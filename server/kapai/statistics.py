from datetime import date, datetime, time, timedelta, timezone
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import AwareDatetime, BaseModel, Field, StringConstraints

from kapai.admin import audit, require_admin, utc_iso
from kapai.db import execute, one
from kapai.matches import IDENTIFIER
from kapai.runtime import engine

router = APIRouter()
LIMIT = 20
RecordSource = Literal["", "automatic", "adjusted", "manual"]
RecordState = Literal["included", "excluded", "all"]
BEIJING = timezone(timedelta(hours=8))
Reason = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]

# Analytics overlay only. A manual row counts as one run, never as a distinct player.
# Null override fields follow the real milestone/metadata; exclusions never update the game tables.
PROJECTION = """
    SELECT m.match_id AS record_id, p.user_id,
           COALESCE(a.started_at,m.started_at) AS started_at,
           COALESCE(a.game_version,m.game_version) AS game_version,
           COALESCE(a.character_id,p.character_id) AS character_id,
           COALESCE(a.difficulty,p.difficulty) AS difficulty,
           COALESCE(a.first_battle,m.first_battle_at IS NOT NULL) AS first_battle,
           COALESCE(a.finished,m.status='finished') AS finished,
           COALESCE(a.excluded,0) AS excluded, COALESCE(a.revision,0) AS revision,
           COALESCE(a.reason,'') AS reason,
           IF(a.started_at IS NOT NULL OR a.game_version IS NOT NULL OR a.character_id IS NOT NULL
              OR a.difficulty IS NOT NULL OR a.first_battle IS NOT NULL OR a.finished IS NOT NULL,
              'adjusted','automatic') AS source,
           u.nickname, u.username
    FROM matches m JOIN match_players p ON m.match_id=p.match_id
    JOIN users u ON u.user_id=p.user_id
    LEFT JOIN stats_adjustments a ON a.match_id=m.match_id
    WHERE m.mode='solo' AND m.source='client_reported' AND p.seat_no=1 {auto}
    UNION ALL
    SELECT a.record_id, NULL, a.started_at, a.game_version, a.character_id, a.difficulty,
           a.first_battle, a.finished, a.excluded, a.revision, a.reason, 'manual', NULL, NULL
    FROM stats_adjustments a WHERE a.match_id IS NULL {manual}
"""
DIMENSIONS = """started_at>=:start AND started_at<:end
    AND (:version='' OR game_version=:version) AND (:character='' OR character_id=:character)
    AND (:difficulty='' OR difficulty=:difficulty)"""
DATE_PROJECTION = PROJECTION.format(
    auto="AND ((a.started_at IS NULL AND m.started_at>=:start AND m.started_at<:end) "
         "OR (a.started_at>=:start AND a.started_at<:end))",
    manual="AND a.started_at>=:start AND a.started_at<:end",
)


def stats_scope(start: date, end: date, version: str = Query("", max_length=80),
                character: str = Query("", max_length=80), difficulty: str = Query("", max_length=20)):
    if not (date(2000, 1, 1) <= start <= end <= date(9998, 12, 31) and (end - start).days <= 366):
        raise HTTPException(422, "invalid_range")
    return dict(start=datetime.combine(start, time()) - timedelta(hours=8),
                end=datetime.combine(end + timedelta(days=1), time()) - timedelta(hours=8),
                version=version.strip(), character=character.strip(), difficulty=difficulty.strip())


@router.get("/admin/stats")
def statistics(request: Request, scope: dict = Depends(stats_scope)):
    with engine.begin() as db:
        actor = require_admin(db, request)
        audit(db, actor, "stats.read")
        return stats_snapshot(db, scope)


def stats_snapshot(db, scope):
    totals = one(db, """
        SELECT (SELECT COUNT(*) FROM users WHERE activated_at IS NOT NULL) AS registered,
        (SELECT COUNT(DISTINCT visitor_id) FROM game_events
         WHERE event_type='menu_opened' AND received_at>=:start AND received_at<:end) AS visitors
    """, **scope)
    groups = execute(db, """
        SELECT game_version, COUNT(DISTINCT user_id) AS accounts, COUNT(*) AS started,
               SUM(first_battle) AS first_battles, SUM(finished) AS finished,
               SUM(source='manual') AS manual
        FROM (""" + DATE_PROJECTION + ") runs WHERE excluded=0 AND " + DIMENSIONS + """
        GROUP BY game_version WITH ROLLUP
    """, **scope).mappings().all()
    return dict(totals, activity=[dict(group) for group in groups])


def public_record(row):
    return dict(row, started_at=utc_iso(row["started_at"]), first_battle=bool(row["first_battle"]),
                finished=bool(row["finished"]), excluded=bool(row["excluded"]))


def record_rows(db, scope, q, source, state, sort, limit, offset=0):
    direction = "DESC" if sort == "newest" else "ASC"
    return execute(db, """
        SELECT runs.*, COUNT(*) OVER () AS total FROM (""" + DATE_PROJECTION + ") runs WHERE " + DIMENSIONS + """
          AND (:source='' OR source=:source)
          AND (:state='all' OR excluded=(:state='excluded'))
          AND (:q='' OR LOCATE(:q, record_id)>0 OR LOCATE(:q, game_version)>0
               OR LOCATE(:q, nickname)>0 OR LOCATE(:q, username)>0 OR LOCATE(:q, reason)>0)
        ORDER BY started_at """ + direction + ", record_id " + direction + " LIMIT :limit OFFSET :offset",
        **scope, q=q.strip(), source=source, state=state, limit=limit, offset=offset).mappings().all()


@router.get("/admin/stats/records")
def list_records(request: Request, scope: dict = Depends(stats_scope), q: str = Query("", max_length=100),
                 source: RecordSource = "",
                 state: RecordState = "included",
                 sort: Literal["newest", "oldest"] = "newest", offset: int = Query(0, ge=0, le=1_000_000)):
    with engine.connect() as db:
        require_admin(db, request)
        rows = record_rows(db, scope, q, source, state, sort, LIMIT + 1, offset)
    return {"items": [public_record({k: v for k, v in row.items() if k not in {"total", "user_id"}})
                      for row in rows[:LIMIT]], "total": rows[0]["total"] if rows else 0,
            "next_offset": offset + LIMIT if len(rows) > LIMIT else None}


def record_by_id(db, record_id):
    row = one(db, "SELECT * FROM (" + PROJECTION.format(auto="AND m.match_id=:id", manual="AND a.record_id=:id")
              + ") runs", id=record_id)
    if row is None:
        raise HTTPException(404, "stats_record_not_found")
    return public_record({k: v for k, v in row.items() if k != "user_id"})


@router.get("/admin/stats/records/{record_id}")
def read_record(record_id: UUID, request: Request):
    with engine.begin() as db:
        actor = require_admin(db, request)
        item = record_by_id(db, str(record_id))
        audit(db, actor, "stats.record.read", str(record_id))
    return item


class RecordValues(BaseModel):
    started_at: AwareDatetime
    game_version: str = Field(min_length=1, max_length=80, pattern=IDENTIFIER)
    character_id: str = Field(min_length=1, max_length=80, pattern=IDENTIFIER)
    difficulty: str = Field(min_length=1, max_length=20, pattern=IDENTIFIER)
    first_battle: bool
    finished: bool
    reason: Reason

    def columns(self):
        if not 2000 <= self.started_at.year <= 9997:
            raise HTTPException(422, "invalid_range")
        return dict(self.model_dump(exclude={"revision"}),
                    started_at=self.started_at.astimezone(timezone.utc).replace(tzinfo=None))


class RecordEdit(RecordValues):
    revision: int = Field(ge=0)


class StateChange(BaseModel):
    revision: int = Field(ge=0)
    reason: Reason


@router.post("/admin/stats/records", status_code=201)
def create_record(data: RecordValues, request: Request):
    record_id = str(uuid4())
    with engine.begin() as db:
        actor = require_admin(db, request)
        execute(db, """
            INSERT INTO stats_adjustments (record_id,started_at,game_version,character_id,difficulty,first_battle,finished,reason)
            VALUES (:id,:started_at,:game_version,:character_id,:difficulty,:first_battle,:finished,:reason)
        """, id=record_id, **data.columns())
        audit(db, actor, "stats.record.create", record_id)
        return record_by_id(db, record_id)


def lock_record(db, record_id, revision):
    # Serialize changes to an automatic record on its real match, even before any override exists.
    original = one(db, """
        SELECT m.started_at,m.game_version,p.character_id,p.difficulty,
               m.first_battle_at IS NOT NULL AS first_battle,m.status='finished' AS finished
        FROM matches m JOIN match_players p ON p.match_id=m.match_id AND p.seat_no=1
        WHERE m.match_id=:id AND m.mode='solo' AND m.source='client_reported' FOR UPDATE
    """, id=record_id)
    adjustment = one(db, "SELECT * FROM stats_adjustments WHERE record_id=:id FOR UPDATE", id=record_id)
    if not original and not (adjustment and adjustment["match_id"] is None):
        raise HTTPException(404, "stats_record_not_found")
    if (adjustment["revision"] if adjustment else 0) != revision:
        raise HTTPException(409, "stats_record_changed")
    return original, adjustment


@router.patch("/admin/stats/records/{record_id}")
def update_record(record_id: UUID, data: RecordEdit, request: Request):
    record_id = str(record_id)
    with engine.begin() as db:
        actor = require_admin(db, request)
        automatic, adjustment = lock_record(db, record_id, data.revision)
        if adjustment and adjustment["excluded"]:
            raise HTTPException(409, "stats_record_excluded")
        columns = data.columns()
        if automatic:
            # Fields that match the source are still live, e.g. a later real battle completion.
            columns = {key: None if key in automatic and value == automatic[key] else value
                       for key, value in columns.items()}
        execute(db, """
            INSERT INTO stats_adjustments (record_id,match_id,started_at,game_version,character_id,difficulty,
                                           first_battle,finished,reason)
            VALUES (:id,:match,:started_at,:game_version,:character_id,:difficulty,:first_battle,:finished,:reason)
            ON DUPLICATE KEY UPDATE started_at=:started_at,game_version=:game_version,character_id=:character_id,
                difficulty=:difficulty,first_battle=:first_battle,finished=:finished,reason=:reason,revision=revision+1
        """, id=record_id, match=record_id if automatic else None, **columns)
        audit(db, actor, "stats.record.update", record_id)
        return record_by_id(db, record_id)


@router.delete("/admin/stats/records/{record_id}")
def exclude_record(record_id: UUID, data: StateChange, request: Request):
    record_id = str(record_id)
    with engine.begin() as db:
        actor = require_admin(db, request)
        automatic, adjustment = lock_record(db, record_id, data.revision)
        if adjustment and adjustment["excluded"]:
            raise HTTPException(409, "stats_record_excluded")
        execute(db, """
            INSERT INTO stats_adjustments (record_id,match_id,excluded,reason) VALUES (:id,:match,1,:reason)
            ON DUPLICATE KEY UPDATE excluded=1,reason=:reason,revision=revision+1
        """, id=record_id, match=record_id if automatic else None, reason=data.reason)
        audit(db, actor, "stats.record.exclude", record_id)
        return record_by_id(db, record_id)


@router.post("/admin/stats/records/{record_id}/restore")
def restore_record(record_id: UUID, data: StateChange, request: Request):
    record_id = str(record_id)
    with engine.begin() as db:
        actor = require_admin(db, request)
        automatic, adjustment = lock_record(db, record_id, data.revision)
        has_overrides = adjustment and any(adjustment[key] is not None for key in
            ("started_at", "game_version", "character_id", "difficulty", "first_battle", "finished"))
        if not adjustment or not (adjustment["excluded"] or (automatic and has_overrides)):
            raise HTTPException(409, "stats_record_changed")
        clear_overrides = (",started_at=NULL,game_version=NULL,character_id=NULL,difficulty=NULL,"
                           "first_battle=NULL,finished=NULL") if automatic else ""
        execute(db, "UPDATE stats_adjustments SET excluded=0,reason=:reason,revision=revision+1"
                + clear_overrides + " WHERE record_id=:id", id=record_id, reason=data.reason)
        audit(db, actor, "stats.record.restore", record_id)
        return record_by_id(db, record_id)
