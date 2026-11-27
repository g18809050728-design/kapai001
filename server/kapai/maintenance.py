from datetime import date, datetime, time, timedelta
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field, StringConstraints, field_validator

from kapai.admin import audit, require_admin, utc_iso
from kapai.db import execute, one
from kapai.matches import match_history
from kapai.runtime import engine

router = APIRouter()
LIMIT = 20
Nickname = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]
Reason = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
Role = Literal["", "player", "admin"]
UserSort = Literal["created_newest", "created_oldest", "login_newest", "login_oldest"]
USER_ORDER = {
    "created_newest": "created_at DESC, user_id DESC",
    "created_oldest": "created_at ASC, user_id ASC",
    "login_newest": "last_login_at DESC, user_id DESC",
    "login_oldest": "last_login_at IS NULL, last_login_at ASC, user_id ASC",
}
USER_FIELDS = """u.user_id, u.username, u.nickname, u.role, u.created_at, u.last_login_at,
    (SELECT COUNT(*) FROM match_players p WHERE p.user_id=u.user_id) AS match_count"""
ROLE_ACTIONS = "'data.player.role.promote','admin-create','admin-revoke'"


class Change(BaseModel):
    revision: str = Field(pattern=r"^[0-9]{1,20}$")
    expected_nickname: str = Field(max_length=40)
    reason: Reason


class Rename(Change):
    nickname: Nickname

    @field_validator("nickname")
    @classmethod
    def validate_name(cls, name):
        # No control characters, surrogate characters or directional formatting controls.
        if any(ord(c) < 32 or 127 <= ord(c) <= 159 or 0xD800 <= ord(c) <= 0xDFFF
               or 0x202A <= ord(c) <= 0x202E or 0x2066 <= ord(c) <= 0x2069 for c in name):
            raise ValueError("unsupported display-name character")
        return name


class Promote(BaseModel):
    reason: Reason


def date_bounds(start, end):
    if any(day and not date(2000, 1, 1) <= day <= date(9998, 12, 31) for day in (start, end)):
        raise HTTPException(422, "invalid_range")
    if start and end and start > end:
        raise HTTPException(422, "invalid_range")
    return (
        datetime.combine(start, time()) - timedelta(hours=8) if start else None,
        datetime.combine(end, time()) + timedelta(hours=16) if end else None,
    )


def directory_entry(row):
    return {key: utc_iso(value) if key in {"created_at", "last_login_at"} else value
            for key, value in row.items() if key != "total"}


@router.get("/admin/data/players")
def list_players(request: Request, q: str = Query("", max_length=100),
                 role: Role = "", sort: UserSort = "created_newest",
                 created_from: date | None = None, created_to: date | None = None,
                 login_from: date | None = None, login_to: date | None = None,
                 offset: int = Query(0, ge=0, le=1_000_000)):
    created_start, created_end = date_bounds(created_from, created_to)
    login_start, login_end = date_bounds(login_from, login_to)
    with engine.connect() as db:
        require_admin(db, request)
        rows = execute(db, f"""
            SELECT {USER_FIELDS}, COUNT(*) OVER () AS total FROM users u
            WHERE activated_at IS NOT NULL AND (:role='' OR role=:role)
              AND (:q='' OR LOCATE(:q,nickname)>0 OR LOCATE(:q,username)>0 OR LOCATE(:q,user_id)>0)
              AND (:created_start IS NULL OR created_at>=:created_start)
              AND (:created_end IS NULL OR created_at<:created_end)
              AND (:login_start IS NULL OR last_login_at>=:login_start)
              AND (:login_end IS NULL OR last_login_at<:login_end)
            ORDER BY {USER_ORDER[sort]} LIMIT :limit OFFSET :offset
        """, q=q.strip(), role=role, created_start=created_start, created_end=created_end, login_start=login_start,
            login_end=login_end, limit=LIMIT + 1, offset=offset).mappings().all()
    return {"items": [directory_entry(row) for row in rows[:LIMIT]],
            "total": rows[0]["total"] if rows else 0, "next_offset": offset + LIMIT if len(rows) > LIMIT else None}


def player(db, user_id, *, lock=False):
    item = one(db, f"""
        SELECT {USER_FIELDS} FROM users u WHERE u.activated_at IS NOT NULL AND u.user_id=:id
    """ + (" FOR UPDATE" if lock else ""), id=user_id)
    if item is None:
        raise HTTPException(404, "maintenance_player_missing")
    return directory_entry(item)


def role_events(db, target=None, offset=0):
    rows = execute(db, f"""
        SELECT l.operation, l.created_at, l.reason, l.actor_id, a.nickname AS actor_nickname,
               l.object_id AS user_id, u.nickname AS user_nickname
        FROM admin_audit_log l LEFT JOIN users a ON a.user_id=l.actor_id LEFT JOIN users u ON u.user_id=l.object_id
        WHERE l.operation IN ({ROLE_ACTIONS}) AND (:target IS NULL OR l.object_id=:target)
        ORDER BY l.audit_id DESC LIMIT :limit OFFSET :offset
    """, target=target, limit=LIMIT + 1, offset=offset).mappings().all()
    return {"items": [dict(row, created_at=utc_iso(row["created_at"])) for row in rows[:LIMIT]],
            "next_offset": offset + LIMIT if len(rows) > LIMIT else None}


@router.get("/admin/data/role-events")
def list_role_events(request: Request, user_id: UUID | None = None, offset: int = Query(0, ge=0, le=1_000_000)):
    with engine.connect() as db:
        require_admin(db, request)
        return role_events(db, str(user_id) if user_id else None, offset)


@router.get("/admin/data/players/{user_id}/matches")
def player_matches(user_id: UUID, request: Request, offset: int = Query(0, ge=0, le=1_000_000)):
    with engine.connect() as db:
        require_admin(db, request)
        player(db, str(user_id))
        page = match_history(db, str(user_id), LIMIT, offset)
    for item in page["items"]:
        for key in ("started_at", "first_battle_at", "finished_at"):
            item[key] = utc_iso(item[key])
    return page


def history(db, user_id, *, lock=False, limit=10):
    return execute(db, """
        SELECT change_id,old_nickname,new_nickname,reason,changed_at
        FROM admin_nickname_changes WHERE user_id=:id ORDER BY change_id DESC LIMIT :limit
    """ + (" FOR UPDATE" if lock else ""), id=user_id, limit=limit).mappings().all()


def revision(entries):
    return str(entries[0]["change_id"]) if entries else "0"


@router.get("/admin/data/players/{user_id}")
def get_player(user_id: UUID, request: Request):
    with engine.connect() as db:
        require_admin(db, request)
        item = player(db, str(user_id))
        entries = history(db, str(user_id))
    return dict(item, revision=revision(entries),
                can_restore=bool(item["role"] == "player" and entries and item["nickname"] == entries[0]["new_nickname"]),
                history=[dict(row, change_id=str(row["change_id"]), changed_at=utc_iso(row["changed_at"])) for row in entries])


@router.post("/admin/data/players/{user_id}/promote")
def promote_player(user_id: UUID, data: Promote, request: Request):
    target = str(user_id)
    with engine.begin() as db:
        actor = require_admin(db, request)
        # Recheck the grantor while holding its row lock, including concurrent CLI revocation.
        if not one(db, "SELECT user_id FROM users WHERE user_id=:id AND role='admin' FOR UPDATE", id=actor):
            raise HTTPException(403, "admin_required")
        item = player(db, target, lock=True)
        if item["role"] != "player":
            raise HTTPException(409, "maintenance_role_changed")
        execute(db, "UPDATE users SET role='admin' WHERE user_id=:id", id=target)
        execute(db, "DELETE FROM auth_sessions WHERE user_id=:id", id=target)
        audit(db, actor, "data.player.role.promote", target, reason=data.reason)
    return {"role": "admin"}


def update_name(db, request, user_id, data, mode):
    actor = require_admin(db, request)
    item = player(db, user_id, lock=True)
    if item["role"] != "player":
        raise HTTPException(404, "maintenance_player_missing")
    entries = history(db, user_id, lock=True, limit=1)
    if data.revision != revision(entries) or data.expected_nickname != item["nickname"]:
        raise HTTPException(409, "maintenance_player_changed")
    if mode == "restore":
        if not entries or item["nickname"] != entries[0]["new_nickname"]:
            raise HTTPException(409, "maintenance_player_changed")
        nickname = entries[0]["old_nickname"]
    else:
        nickname = data.nickname
    if nickname == item["nickname"]:
        raise HTTPException(422, "maintenance_nickname_unchanged")
    execute(db, "UPDATE users SET nickname=:nickname WHERE user_id=:id", nickname=nickname, id=user_id)
    execute(db, """
        INSERT INTO admin_nickname_changes (user_id,old_nickname,new_nickname,reason)
        VALUES (:id,:old,:new,:reason)
    """, id=user_id, old=item["nickname"], new=nickname, reason=data.reason)
    audit(db, actor, "data.player.nickname." + mode, user_id)
    return {"nickname": nickname}


@router.patch("/admin/data/players/{user_id}/nickname")
def rename_player(user_id: UUID, data: Rename, request: Request):
    with engine.begin() as db:
        return update_name(db, request, str(user_id), data, "update")


@router.post("/admin/data/players/{user_id}/nickname/restore")
def restore_player(user_id: UUID, data: Change, request: Request):
    with engine.begin() as db:
        return update_name(db, request, str(user_id), data, "restore")
