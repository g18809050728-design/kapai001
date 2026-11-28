import json
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field, model_validator
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


ContentId = Annotated[str, Field(max_length=80, pattern=IDENTIFIER)]


class CardRecord(BaseModel):
    definition_id: ContentId
    upgrade_level: int = Field(ge=0, le=99)


class RelicRecord(BaseModel):
    definition_id: ContentId
    slot: int = Field(ge=0, le=31)


class RouteRecord(BaseModel):
    term: int = Field(ge=1, le=8)
    layer: int = Field(ge=1, le=100)
    kind: Literal["normal", "elite", "boss", "event", "shop", "rest"]
    status: Literal["cleared", "battle_won", "battle_lost", "stopped"]
    encounter_id: ContentId | Literal[""] = ""
    event_id: ContentId | Literal[""] = ""


class MatchDetail(BaseModel):
    cards: list[CardRecord] = Field(max_length=1000)
    relics: list[RelicRecord] = Field(max_length=32)
    route: list[RouteRecord] = Field(max_length=512)
    money: int = Field(ge=0, le=2147483647)
    vitality: int = Field(ge=0, le=2147483647)
    max_vitality: int = Field(ge=1, le=2147483647)
    completed_nodes: int | None = Field(default=None, ge=0, le=512)
    settled_battles: int | None = Field(default=None, ge=0, le=512)

    @model_validator(mode="after")
    def validate_resources(self):
        if self.vitality > self.max_vitality:
            raise ValueError("vitality exceeds maximum")
        return self


class Finish(Summary):
    detail: MatchDetail | None = None


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
        SELECT m.match_id,m.status,m.game_version,m.manifest_id,p.character_id,p.difficulty,p.result,p.detail
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
    if not existing or any(existing[key] != getattr(run, key) for key in ("character_id", "difficulty")):
        raise HTTPException(409, "match_conflict")
    manifests = (existing["manifest_id"], run.manifest_id)
    if manifests[0] != manifests[1] and manifests != ("campus_four_year", "campus_four_year_relics"):
        raise HTTPException(409, "match_conflict")
    return {"match_id": existing["match_id"]}


@router.post("/matches/{match_id}/finish")
def finish(match_id: UUID, summary: Finish, request: Request):
    result = summary.model_dump(exclude={"detail"})
    detail = summary.detail.model_dump_json(exclude_none=True) if summary.detail else None
    with engine.begin() as db:
        user = session_user(db, request)["user_id"]
        match = player_match(db, user, match_id=str(match_id), lock=True)
        if match["result"] is not None:
            if json.loads(match["result"]) != result:
                raise HTTPException(409, "result_conflict")
            if match["detail"] is None and detail is not None:
                execute(db, "UPDATE match_players SET detail=:detail WHERE match_id=:id AND user_id=:user",
                        detail=detail, id=str(match_id), user=user)
            return {}
        execute(db, "UPDATE matches SET status=:status,finished_at=UTC_TIMESTAMP(6) WHERE match_id=:id",
                id=str(match_id), status="abandoned" if summary.result == "abandoned" else "finished")
        execute(db, "UPDATE match_players SET result=:result,detail=:detail WHERE match_id=:id AND user_id=:user",
                result=json.dumps(result), detail=detail, id=str(match_id), user=user)
        write_event(db, "run_finished", user=user, match=str(match_id))
    return {}


@router.get("/me/matches")
def history(request: Request, offset: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=50)):
    with engine.connect() as db:
        user = session_user(db, request)["user_id"]
        page = match_history(db, user, limit, offset, include_resources=True)
        if offset == 0:
            totals = one(db, """
                SELECT COUNT(result) AS settled,
                       COALESCE(SUM(JSON_UNQUOTE(JSON_EXTRACT(result, '$.result')) = 'won'), 0) AS wins,
                       COALESCE(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(result, '$.term')) AS UNSIGNED)), 0) AS furthest
                FROM match_players WHERE user_id=:user
            """, user=user)
            page["stats"] = {key: int(value) for key, value in totals.items()}
    for item in page["items"]:
        del item["first_battle_at"]
    return page


@router.get("/me/matches/{match_id}")
def read_match(match_id: UUID, request: Request):
    with engine.connect() as db:
        user = session_user(db, request)["user_id"]
        row = player_match(db, user, match_id=str(match_id))
    return {"detail": json.loads(row["detail"]) if row["detail"] is not None else None}


def match_history(db, user, limit, offset, *, include_resources=False):
    resources = """, JSON_OBJECT('vitality', JSON_EXTRACT(p.detail, '$.vitality'),
                                  'max_vitality', JSON_EXTRACT(p.detail, '$.max_vitality'),
                                  'money', JSON_EXTRACT(p.detail, '$.money')) AS resources""" if include_resources else ""
    rows = execute(db, """
        SELECT m.match_id,m.mode,m.source,m.status,m.started_at,m.first_battle_at,m.finished_at,
               p.character_id,p.difficulty,p.result,p.detail IS NOT NULL AS has_detail
    """ + resources + """
        FROM matches m JOIN match_players p ON m.match_id=p.match_id
        WHERE p.user_id=:user ORDER BY m.started_at DESC,m.match_id LIMIT :limit OFFSET :offset
    """, user=user, limit=limit + 1, offset=offset).mappings().all()
    entries = [dict(row, result=json.loads(row["result"]) if row["result"] else None) for row in rows[:limit]]
    if include_resources:
        for row in entries:
            resources = json.loads(row["resources"])
            row["resources"] = {key: value for key, value in resources.items() if value is not None}
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
