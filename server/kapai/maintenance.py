from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field, StringConstraints, field_validator

from kapai.admin import audit, require_admin, utc_iso
from kapai.db import execute, one
from kapai.runtime import engine

router = APIRouter()
LIMIT = 20
Nickname = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]


class Change(BaseModel):
    revision: str = Field(pattern=r"^[0-9]{1,20}$")
    expected_nickname: str = Field(max_length=40)
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]


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


@router.get("/admin/data/players")
def list_players(request: Request, q: str = Query("", max_length=100),
                 offset: int = Query(0, ge=0, le=1_000_000)):
    with engine.connect() as db:
        require_admin(db, request)
        rows = execute(db, """
            SELECT user_id, username, nickname, created_at, COUNT(*) OVER () AS total FROM users
            WHERE activated_at IS NOT NULL AND role='player'
              AND (:q='' OR LOCATE(:q,nickname)>0 OR LOCATE(:q,username)>0 OR LOCATE(:q,user_id)>0)
            ORDER BY created_at DESC, user_id DESC LIMIT :limit OFFSET :offset
        """, q=q.strip(), limit=LIMIT + 1, offset=offset).mappings().all()
    return {"items": [dict(user_id=r["user_id"], username=r["username"], nickname=r["nickname"],
                            created_at=utc_iso(r["created_at"])) for r in rows[:LIMIT]],
            "total": rows[0]["total"] if rows else 0, "next_offset": offset + LIMIT if len(rows) > LIMIT else None}


def player(db, user_id, *, lock=False):
    item = one(db, """
        SELECT user_id, username, nickname, created_at FROM users
        WHERE role='player' AND activated_at IS NOT NULL AND user_id=:id
    """ + (" FOR UPDATE" if lock else ""), id=user_id)
    if item is None:
        raise HTTPException(404, "maintenance_player_missing")
    return dict(item, created_at=utc_iso(item["created_at"]))


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
    return dict(item, revision=revision(entries), can_restore=bool(entries and item["nickname"] == entries[0]["new_nickname"]),
                history=[dict(row, change_id=str(row["change_id"]), changed_at=utc_iso(row["changed_at"])) for row in entries])


def update_name(db, request, user_id, data, mode):
    actor = require_admin(db, request)
    item = player(db, user_id, lock=True)
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
