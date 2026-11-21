import json
from datetime import date, datetime, time, timedelta
from typing import Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError

from kapai.accounts import limited, require, session_user
from kapai.db import execute, one
from kapai.runtime import engine

router = APIRouter()
Difficulty = Literal["relaxed", "normal", "hard"]
IDENTIFIER = r"^[a-zA-Z0-9_.:-]+$"


class Run(BaseModel):
    run_id: str = Field(max_length=80, pattern=IDENTIFIER)
    character_id: Literal["P01", "P02", "P03", "P04"]
    difficulty: Difficulty
    manifest_id: str = Field(max_length=80, pattern=IDENTIFIER)
    game_version: str = Field(max_length=80, pattern=IDENTIFIER)


class Summary(BaseModel):
    result: Literal["won", "lost", "abandoned"]
    term: int = Field(ge=1, le=4)
    reason: str = Field(default="", max_length=80)
    ending_id: str = Field(default="", max_length=80)


class Event(BaseModel):
    event_id: UUID
    event_type: Literal["menu_opened", "first_battle_completed"]
    visitor_id: UUID | None = None
    match_id: UUID | None = None
    result: Literal["won", "lost"] | None = None


def player_match(db, user, *, match_id=None, run_id=None, lock=False):
    condition = "m.match_id=:value" if match_id is not None else "p.client_run_id=:value"
    locking = " FOR UPDATE" if lock else ""
    match = one(db, """
        SELECT m.match_id,m.status,m.game_version,m.manifest_id,p.character_id,p.difficulty,p.result
        FROM matches m JOIN match_players p ON m.match_id=p.match_id
        WHERE m.mode='solo' AND p.user_id=:user AND """ + condition + locking,
        user=user, value=match_id or run_id)
    if not match and match_id is not None:
        raise HTTPException(404, "match_missing")
    return match


def write_event(db, kind, *, user=None, visitor=None, match=None, event_id=None, data=None):
    execute(db, """
        INSERT INTO game_events (event_id,event_type,user_id,visitor_id,match_id,data)
        VALUES (:id,:kind,:user,:visitor,:match,:data)
        ON DUPLICATE KEY UPDATE event_id=event_id
    """, id=event_id or str(uuid4()), kind=kind, user=user, visitor=visitor, match=match, data=json.dumps(data))


@router.post("/matches/start")
def start(run: Run, request: Request):
    with engine.begin() as db:
        user = session_user(db, request)["user_id"]
        existing = player_match(db, user, run_id=run.run_id)
    if not existing:
        try:
            with engine.begin() as db:
                match_id = str(uuid4())
                execute(db, "INSERT INTO matches (match_id,game_version,manifest_id) VALUES (:id,:version,:manifest)",
                        id=match_id, version=run.game_version, manifest=run.manifest_id)
                execute(db, """
                    INSERT INTO match_players (match_id,user_id,seat_no,client_run_id,character_id,difficulty)
                    VALUES (:id,:user,1,:run,:character,:difficulty)
                """, id=match_id, user=user, run=run.run_id, character=run.character_id, difficulty=run.difficulty)
                write_event(db, "run_started", user=user, match=match_id)
            return {"match_id": match_id}
        except IntegrityError as error:
            if error.orig.args[0] != 1062:
                raise
            with engine.connect() as db:
                existing = player_match(db, user, run_id=run.run_id)
    if not existing or any(existing[key] != getattr(run, key) for key in ("manifest_id", "character_id", "difficulty")):
        raise HTTPException(409, "match_conflict")
    return {"match_id": existing["match_id"]}


@router.post("/matches/{match_id}/finish")
def finish(match_id: UUID, summary: Summary, request: Request):
    result = summary.model_dump()
    with engine.begin() as db:
        user = session_user(db, request)["user_id"]
        match = player_match(db, user, match_id=str(match_id), lock=True)
        if match["result"] is not None:
            if json.loads(match["result"]) != result:
                raise HTTPException(409, "result_conflict")
            return {}
        execute(db, "UPDATE matches SET status=:status,finished_at=UTC_TIMESTAMP(6) WHERE match_id=:id",
                id=str(match_id), status="abandoned" if summary.result == "abandoned" else "finished")
        execute(db, "UPDATE match_players SET result=:result WHERE match_id=:id AND user_id=:user",
                result=json.dumps(result), id=str(match_id), user=user)
        write_event(db, "run_finished", user=user, match=str(match_id))
    return {}


@router.get("/me/matches")
def history(request: Request, offset: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=50)):
    with engine.connect() as db:
        user = session_user(db, request)["user_id"]
        rows = execute(db, """
            SELECT m.match_id,m.mode,m.source,m.status,m.started_at,m.finished_at,p.character_id,p.difficulty,p.result
            FROM matches m JOIN match_players p ON m.match_id=p.match_id
            WHERE p.user_id=:user ORDER BY m.started_at DESC,m.match_id LIMIT :limit OFFSET :offset
        """, user=user, limit=limit + 1, offset=offset).mappings().all()
    entries = [dict(row, result=json.loads(row["result"]) if row["result"] else None) for row in rows[:limit]]
    return {"items": entries, "next_offset": offset + limit if len(rows) > limit else None}


@router.post("/events")
def record(data: Event, request: Request):
    require()
    if data.event_type == "menu_opened":
        if not data.visitor_id or data.match_id or data.result:
            raise HTTPException(422, "invalid_input")
        limited(request, "visitor", str(data.visitor_id), attempts=60)
        with engine.begin() as db:
            write_event(db, data.event_type, visitor=str(data.visitor_id), event_id=str(data.event_id))
        return {}
    if not data.match_id or not data.result or data.visitor_id:
        raise HTTPException(422, "invalid_input")
    with engine.begin() as db:
        user = session_user(db, request)["user_id"]
        player_match(db, user, match_id=str(data.match_id))
        write_event(db, data.event_type, user=user, match=str(data.match_id),
                    event_id=str(data.event_id), data={"result": data.result})
        execute(db, """
            UPDATE matches SET first_battle_at=UTC_TIMESTAMP(6)
             WHERE match_id=:match AND first_battle_at IS NULL
        """, match=str(data.match_id))
    return {}


@router.get("/admin/stats")
def statistics(request: Request, start: date, end: date, version: str = Query("", max_length=80),
               character: str = Query("", max_length=80), difficulty: str = Query("", max_length=20)):
    require("ADMIN")
    if not 0 <= (end - start).days <= 366:
        raise HTTPException(422, "invalid_range")
    # Dates are inclusive Beijing calendar days.
    scope = dict(start=datetime.combine(start, time()) - timedelta(hours=8),
                 end=datetime.combine(end + timedelta(days=1), time()) - timedelta(hours=8),
                 version=version, character=character, difficulty=difficulty)
    with engine.begin() as db:
        user = session_user(db, request)
        if user["role"] != "admin":
            raise HTTPException(403, "admin_required")
        execute(db, """
            INSERT INTO admin_audit_log (actor_id,operation,result,request_id)
            VALUES (:user,'stats.read','ok',:request)
        """, user=user["user_id"], request=str(uuid4()))
        totals = one(db, """
            SELECT (SELECT COUNT(*) FROM users WHERE activated_at IS NOT NULL) AS registered,
            (SELECT COUNT(DISTINCT visitor_id) FROM game_events
             WHERE event_type='menu_opened' AND received_at>=:start AND received_at<:end) AS visitors
        """, **scope)
        groups = execute(db, """
            SELECT m.game_version, COUNT(DISTINCT p.user_id) AS accounts,
                COUNT(*) AS started, COALESCE(SUM(m.first_battle_at IS NOT NULL),0) AS first_battles,
                COALESCE(SUM(m.status='finished'),0) AS finished
            FROM matches m JOIN match_players p ON p.match_id=m.match_id
            WHERE m.mode='solo' AND m.source='client_reported'
            AND m.started_at>=:start AND m.started_at<:end
            AND (:version='' OR m.game_version=:version) AND (:character='' OR p.character_id=:character)
            AND (:difficulty='' OR p.difficulty=:difficulty)
            GROUP BY m.game_version WITH ROLLUP
        """, **scope).mappings().all()
    return {"registered": totals["registered"], "visitors": totals["visitors"],
            "activity": [dict(group) for group in groups]}


class ImportedRun(Run):
    summary: Summary


@router.post("/me/matches/import")
def import_history(data: list[ImportedRun], request: Request):
    if len(data) > 50:
        raise HTTPException(422, "too_many_entries")
    with engine.begin() as db:
        user = session_user(db, request)["user_id"]
        # Serialize imports for a user. Normal starts concurrently retry their unique key.
        one(db, "SELECT user_id FROM users WHERE user_id=:user FOR UPDATE", user=user)
        for run in data:
            existing = player_match(db, user, run_id=run.run_id)
            if existing:
                if existing["result"] and json.loads(existing["result"]) != run.summary.model_dump():
                    raise HTTPException(409, "result_conflict")
                continue
            match = str(uuid4())
            execute(db, """
                INSERT INTO matches (match_id,source,status,game_version,manifest_id,finished_at)
                VALUES (:match,'imported','finished',:version,:manifest,UTC_TIMESTAMP(6))
            """, match=match, version=run.game_version, manifest=run.manifest_id)
            execute(db, """
                INSERT INTO match_players (match_id,user_id,seat_no,client_run_id,character_id,difficulty,result)
                VALUES (:match,:user,1,:run,:character,:difficulty,:result)
            """, match=match, user=user, run=run.run_id, character=run.character_id,
                difficulty=run.difficulty, result=run.summary.model_dump_json())
    return {}
