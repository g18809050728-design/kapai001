import hashlib
import json
import re
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from kapai.accounts import require, session_user
from kapai.db import execute, one
from kapai.runtime import engine

router = APIRouter()
Slot = Literal["current_run", "profile"]
HEX = re.compile(r"^[0-9a-f]{64}$")
MANIFESTS = {"campus_mvp", "campus_v3", "campus_four_year", "campus_four_year_relics"}
CHECKSUM_FIELD = re.compile(rb'^\{"checksum":"([0-9a-f]{64})",')
RUN_ID = re.compile(r"^[a-zA-Z0-9_.:-]{1,80}$")
LIMIT = 4 * 1024 * 1024


class Upload(BaseModel):
    expected_cloud_revision: int = Field(ge=0, le=2**53-1)
    request_id: UUID
    snapshot: str = Field(max_length=LIMIT)


def strict_object(pairs):
    fields = dict(pairs)
    if len(fields) != len(pairs):
        raise ValueError("duplicate fields")
    return fields


def invalid_constant(_value):
    raise ValueError("non-finite value")


def checked_snapshot(slot, snapshot):
    try:
        raw = snapshot.encode("utf-8")
        if len(raw) > LIMIT:
            raise HTTPException(413, "snapshot_too_large")
        data = json.loads(snapshot, object_pairs_hook=strict_object, parse_constant=invalid_constant)
    except (ValueError, RecursionError):
        raise HTTPException(422, "snapshot_invalid") from None
    fields = {"checksum", "schema_version", "content_version", "content_hash", "manifest_id",
              "run_id", "revision", "random_state", "payload"}
    if not isinstance(data, dict) or set(data) != fields or type(data["schema_version"]) is not int:
        raise HTTPException(422, "snapshot_invalid")
    if data["schema_version"] != 1:
        raise HTTPException(422, "snapshot_version_unsupported")
    if any(not isinstance(data[key], str) or len(data[key]) > 80
           for key in ("content_version", "content_hash", "manifest_id", "checksum")):
        raise HTTPException(422, "snapshot_invalid")
    checksum = CHECKSUM_FIELD.match(raw)
    if not checksum or hashlib.sha256(b"{" + raw[checksum.end():]).hexdigest() != data["checksum"]:
        raise HTTPException(422, "snapshot_checksum")
    payload = data["payload"]
    if not isinstance(payload, dict):
        raise HTTPException(422, "snapshot_invalid")
    if slot == "profile":
        if data["manifest_id"] != "profile" or any(data[key] is not None for key in ("run_id", "revision", "random_state")):
            raise HTTPException(422, "snapshot_slot")
        if not isinstance(payload.get("summaries_by_run_id"), dict):
            raise HTTPException(422, "snapshot_invalid")
    else:
        if (not isinstance(data["run_id"], str) or not RUN_ID.fullmatch(data["run_id"])
            or type(data["revision"]) is not int or not 0 <= data["revision"] <= 2**53-1
            or not HEX.fullmatch(data["content_hash"]) or not isinstance(data["random_state"], dict)
            or data["manifest_id"] not in MANIFESTS or not data["content_version"]
            or not isinstance(payload.get("run"), dict) or payload["run"].get("run_id") != data["run_id"]
            or set(payload) != {"run", "battle", "terminal_summary", "profile_merge_pending", "event_log"}):
            raise HTTPException(422, "snapshot_invalid")
        battle = payload["battle"]
        if battle is not None and (not isinstance(battle, dict) or battle.get("resolution") is not None):
            raise HTTPException(422, "snapshot_unstable")
    return raw, data


def latest(db, user_id, slot, *, previous=False):
    columns = """v.cloud_revision,v.run_id,v.run_revision,v.manifest_id,v.saved_at,v.checksum,v.snapshot"""
    return one(db, f"""
        SELECT {columns} FROM save_slots s JOIN save_versions v
        ON s.user_id=v.user_id AND s.slot_key=v.slot_key
        AND v.cloud_revision+:previous=s.cloud_revision
        WHERE s.user_id=:user AND s.slot_key=:slot
    """, user=user_id, slot=slot, previous=int(previous))


def version_data(version, with_data=False):
    if not version:
        return {"cloud_revision": 0, "snapshot": None}
    result = {key: value for key, value in version.items() if key != "snapshot"}
    result["saved_at"] = version["saved_at"].isoformat() + "Z"
    if with_data:
        result["snapshot"] = version["snapshot"].decode()
    return result


@router.get("/me/saves/{slot}")
def get_save(slot: Slot, request: Request, previous: bool = False):
    require("CLOUD")
    with engine.connect() as db:
        user = session_user(db, request)["user_id"]
        return version_data(latest(db, user, slot, previous=previous), with_data=True)


@router.put("/me/saves/{slot}")
def put_save(slot: Slot, data: Upload, request: Request):
    require("CLOUD")
    with engine.begin() as db:
        user = session_user(db, request)["user_id"]
        raw, snapshot = checked_snapshot(slot, data.snapshot)
        values = dict(user=user, slot=slot, request=str(data.request_id), checksum=snapshot["checksum"])
        execute(db, """
            INSERT INTO save_slots (user_id,slot_key) VALUES (:user,:slot)
            ON DUPLICATE KEY UPDATE cloud_revision=cloud_revision
        """, **values)
        current = one(db, """
            SELECT cloud_revision FROM save_slots WHERE user_id=:user AND slot_key=:slot FOR UPDATE
        """, **values)["cloud_revision"]
        receipt = one(db, """
            SELECT cloud_revision,checksum FROM save_receipts
            WHERE user_id=:user AND slot_key=:slot AND request_id=:request
        """, **values)
        if receipt:
            if receipt["checksum"] != snapshot["checksum"]:
                raise HTTPException(409, "request_conflict")
            return {"cloud_revision": receipt["cloud_revision"], "checksum": snapshot["checksum"]}
        if current != data.expected_cloud_revision:
            return JSONResponse({"detail": "save_conflict", "current": version_data(latest(db, user, slot))}, status_code=409)
        revision = current + 1
        execute(db, """
            INSERT INTO save_versions (user_id,slot_key,cloud_revision,request_id,run_id,run_revision,
                                       schema_version,content_version,content_hash,manifest_id,checksum,snapshot)
            VALUES (:user,:slot,:cloud,:request,:run_id,:revision,:schema_version,:content_version,
                    :content_hash,:manifest_id,:checksum,:raw)
        """, **(snapshot | values), cloud=revision, raw=raw)
        execute(db, "UPDATE save_slots SET cloud_revision=:cloud WHERE user_id=:user AND slot_key=:slot",
                **values, cloud=revision)
        execute(db, """INSERT INTO save_receipts (user_id,slot_key,request_id,cloud_revision,checksum)
                    VALUES (:user,:slot,:request,:cloud,:checksum)""",
                **values, cloud=revision)
        execute(db, "DELETE FROM save_versions WHERE user_id=:user AND slot_key=:slot AND cloud_revision<:old",
                **values, old=revision-1)
    return {"cloud_revision": revision, "checksum": snapshot["checksum"]}
