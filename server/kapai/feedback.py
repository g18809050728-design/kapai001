import base64
import binascii
import hashlib
from io import BytesIO
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Query, Request, Response
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, Field, StringConstraints
from sqlalchemy.exc import IntegrityError

from kapai.accounts import limited, require, session_user
from kapai.admin import audit, require_admin, utc_iso
from kapai.db import execute, one
from kapai.runtime import engine

router = APIRouter()
MAX_IMAGE_BYTES = 2 * 1024 * 1024
MAX_IMAGE_PIXELS = 12_000_000
Category = Literal["bug", "suggestion", "other"]
FeedbackState = Literal["new", "reviewing", "resolved", "archived"]
FeedbackFilter = FeedbackState | Literal["active", "all"]
EncodedImage = Annotated[str, StringConstraints(min_length=4, max_length=4 * ((MAX_IMAGE_BYTES + 2) // 3))]


class Submission(BaseModel):
    submission_id: UUID
    category: Category
    title: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
    description: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=3000)]
    build_version: str = Field(default="", max_length=80)
    screenshots: list[EncodedImage] = Field(default_factory=list, max_length=3)


def decode_screenshot(encoded):
    try:
        original = base64.b64decode(encoded, validate=True)
        if len(original) > MAX_IMAGE_BYTES:
            raise HTTPException(422, "screenshot_too_large")
        with Image.open(BytesIO(original), formats=("PNG", "JPEG", "WEBP")) as image:
            width, height = image.size
            if max(width, height) > 8192 or width * height > MAX_IMAGE_PIXELS:
                raise HTTPException(422, "screenshot_dimensions")
            if getattr(image, "n_frames", 1) != 1:
                raise HTTPException(422, "screenshot_invalid")
            corrected = ImageOps.exif_transpose(image)
            mode = "RGBA" if "A" in corrected.getbands() or "transparency" in corrected.info else "RGB"
            pixels = corrected.convert(mode)
            # Re-encode pixels only, including when the source is already WebP.
            output = BytesIO()
            pixels.save(output, "WEBP", quality=90)
            if output.tell() > MAX_IMAGE_BYTES:
                raise HTTPException(422, "screenshot_too_large")
            return pixels.width, pixels.height, output.getvalue()
    except Image.DecompressionBombError:
        raise HTTPException(422, "screenshot_dimensions") from None
    except (binascii.Error, UnidentifiedImageError, OSError, ValueError, SyntaxError):
        raise HTTPException(422, "screenshot_invalid") from None


def existing_submission(db, user_id, submission_id, payload_hash):
    row = one(db, """
        SELECT feedback_id, payload_hash FROM player_feedback
        WHERE user_id=:user AND submission_id=:submission
    """, user=user_id, submission=submission_id)
    if row and row["payload_hash"] != payload_hash:
        raise HTTPException(409, "feedback_conflict")
    return {"feedback_id": row["feedback_id"]} if row else None


@router.post("/feedback", status_code=201)
def submit_feedback(data: Submission, request: Request):
    require()
    submission_id = str(data.submission_id)
    with engine.connect() as db:
        user_id = session_user(db, request)["user_id"]
        payload_hash = hashlib.sha256(data.model_dump_json().encode()).hexdigest()
        receipt = existing_submission(db, user_id, submission_id, payload_hash)
    if receipt:
        return receipt
    limited(request, "feedback", user_id, attempts=5)
    screenshots = [decode_screenshot(value) for value in data.screenshots]
    feedback_id = str(uuid4())
    try:
        with engine.begin() as db:
            session_user(db, request)
            execute(db, """
                INSERT INTO player_feedback
                    (feedback_id, user_id, submission_id, payload_hash, category, title, description, build_version)
                VALUES (:feedback, :user, :submission, :hash, :category, :title, :description, :version)
            """, feedback=feedback_id, user=user_id, submission=submission_id, hash=payload_hash,
                category=data.category, title=data.title, description=data.description, version=data.build_version)
            for position, (width, height, image) in enumerate(screenshots, 1):
                execute(db, """
                    INSERT INTO feedback_screenshots (feedback_id, position, width, height, image)
                    VALUES (:feedback, :position, :width, :height, :image)
                """, feedback=feedback_id, position=position, width=width, height=height, image=image)
    except IntegrityError as error:
        if error.orig.args[0] != 1062:
            raise
        with engine.connect() as db:
            if receipt := existing_submission(db, user_id, submission_id, payload_hash):
                return receipt
        raise
    return {"feedback_id": feedback_id}


class FeedbackTriage(BaseModel):
    status: FeedbackState
    note: str = Field(default="", max_length=1600)
    updated_at: str | None = Field(default=None, max_length=40)


def public_feedback(row):
    return dict(row, created_at=utc_iso(row["created_at"]), updated_at=utc_iso(row["updated_at"]))


def feedback_rows(db, category, q, state, sort, limit, offset=0):
    direction = "DESC" if sort == "newest" else "ASC"
    return execute(db, """
        SELECT f.feedback_id, f.category, f.title, f.created_at, u.nickname, f.build_version,
            COALESCE(t.status,'new') AS status, t.updated_at, f.description, COALESCE(t.note,'') AS note,
            (SELECT COUNT(*) FROM feedback_screenshots s WHERE s.feedback_id=f.feedback_id) AS screenshot_count,
            COUNT(*) OVER () AS total
        FROM player_feedback f JOIN users u ON f.user_id=u.user_id
        LEFT JOIN feedback_triage t ON t.feedback_id=f.feedback_id
        WHERE (:category IS NULL OR f.category=:category)
          AND (:state='all' OR (:state='active' AND COALESCE(t.status,'new') IN ('new','reviewing'))
               OR COALESCE(t.status,'new')=:state)
          AND (:q='' OR LOCATE(:q, f.title)>0 OR LOCATE(:q, f.description)>0 OR LOCATE(:q, u.nickname)>0
               OR LOCATE(:q, u.username)>0 OR LOCATE(:q, f.feedback_id)>0 OR LOCATE(:q, f.build_version)>0)
        ORDER BY f.created_at """ + direction + ", f.feedback_id " + direction + " LIMIT :limit OFFSET :offset",
        category=category, q=q.strip(), state=state, limit=limit, offset=offset).mappings().all()


@router.get("/admin/feedback")
def list_feedback(request: Request, category: Category | None = None, offset: int = Query(0, ge=0, le=1_000_000),
                  q: str = Query("", max_length=100), state: FeedbackFilter = "all",
                  sort: Literal["newest", "oldest"] = "newest"):
    limit = 20
    with engine.connect() as db:
        require_admin(db, request)
        rows = feedback_rows(db, category, q, state, sort, limit + 1, offset)
    return {"items": [public_feedback({k: v for k, v in row.items() if k not in {"total", "description", "note"}}) for row in rows[:limit]],
            "total": rows[0]["total"] if rows else 0, "next_offset": offset + limit if len(rows) > limit else None}


@router.get("/admin/feedback/{feedback_id}")
def read_feedback(feedback_id: UUID, request: Request):
    with engine.begin() as db:
        admin_id = require_admin(db, request)
        row = one(db, """
            SELECT f.feedback_id, f.category, f.title, f.description, f.build_version, f.created_at,
                u.nickname, u.username, COALESCE(t.status,'new') AS status, COALESCE(t.note,'') AS note, t.updated_at
            FROM player_feedback f JOIN users u ON f.user_id=u.user_id
            LEFT JOIN feedback_triage t ON t.feedback_id=f.feedback_id WHERE f.feedback_id=:feedback
        """, feedback=str(feedback_id))
        if row is None:
            raise HTTPException(404, "feedback_not_found")
        screenshots = execute(db, """
            SELECT position, width, height FROM feedback_screenshots
            WHERE feedback_id=:feedback ORDER BY position
        """, feedback=str(feedback_id)).mappings().all()
        audit(db, admin_id, "feedback.read", str(feedback_id))
    return dict(public_feedback(row), screenshots=[dict(image) for image in screenshots])


@router.patch("/admin/feedback/{feedback_id}")
def triage_feedback(feedback_id: UUID, data: FeedbackTriage, request: Request):
    feedback_id = str(feedback_id)
    with engine.begin() as db:
        admin_id = require_admin(db, request)
        if not one(db, "SELECT feedback_id FROM player_feedback WHERE feedback_id=:id FOR UPDATE", id=feedback_id):
            raise HTTPException(404, "feedback_not_found")
        current = one(db, "SELECT updated_at FROM feedback_triage WHERE feedback_id=:id FOR UPDATE", id=feedback_id)
        if data.updated_at != (utc_iso(current["updated_at"]) if current else None):
            raise HTTPException(409, "feedback_changed")
        execute(db, """
            INSERT INTO feedback_triage (feedback_id,status,note,updated_at) VALUES (:id,:status,:note,UTC_TIMESTAMP(6))
            ON DUPLICATE KEY UPDATE status=:status,note=:note,updated_at=UTC_TIMESTAMP(6)
        """, id=feedback_id, status=data.status, note=data.note.strip())
        audit(db, admin_id, "feedback.triage", feedback_id)
        row = one(db, "SELECT status,note,updated_at FROM feedback_triage WHERE feedback_id=:id", id=feedback_id)
    return dict(row, updated_at=utc_iso(row["updated_at"]))


@router.get("/admin/feedback/{feedback_id}/screenshots/{position}")
def read_screenshot(feedback_id: UUID, position: int, request: Request):
    with engine.connect() as db:
        require_admin(db, request)
        row = one(db, """
            SELECT image FROM feedback_screenshots WHERE feedback_id=:feedback AND position=:position
        """, feedback=str(feedback_id), position=position)
    if row is None:
        raise HTTPException(404, "feedback_not_found")
    return Response(row["image"], media_type="image/webp",
                    headers={"X-Content-Type-Options": "nosniff", "Cross-Origin-Resource-Policy": "same-origin"})
