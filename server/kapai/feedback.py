import base64
import binascii
import hashlib
from datetime import timezone
from io import BytesIO
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Query, Request, Response
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, Field, StringConstraints
from sqlalchemy.exc import IntegrityError

from kapai.accounts import limited, require, session_user
from kapai.db import execute, one
from kapai.runtime import engine

router = APIRouter()
MAX_IMAGE_BYTES = 2 * 1024 * 1024
MAX_IMAGE_PIXELS = 12_000_000
Category = Literal["bug", "suggestion", "other"]
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


def require_admin(db, request):
    require("ADMIN")
    user = session_user(db, request)
    if user["role"] != "admin":
        raise HTTPException(403, "admin_required")
    return user["user_id"]


def public_feedback(row):
    return dict(row, created_at=row["created_at"].replace(tzinfo=timezone.utc).isoformat())


@router.get("/admin/feedback")
def list_feedback(request: Request, category: Category | None = None, offset: int = Query(0, ge=0)):
    limit = 20
    with engine.connect() as db:
        require_admin(db, request)
        rows = execute(db, """
            SELECT f.feedback_id, f.category, f.title, f.created_at, u.nickname,
                (SELECT COUNT(*) FROM feedback_screenshots s WHERE s.feedback_id=f.feedback_id) AS screenshot_count
            FROM player_feedback f JOIN users u ON f.user_id=u.user_id
            WHERE (:category IS NULL OR f.category=:category)
            ORDER BY f.created_at DESC, f.feedback_id DESC LIMIT :limit OFFSET :offset
        """, category=category, limit=limit + 1, offset=offset).mappings().all()
    return {"items": [public_feedback(row) for row in rows[:limit]],
            "next_offset": offset + limit if len(rows) > limit else None}


@router.get("/admin/feedback/{feedback_id}")
def read_feedback(feedback_id: UUID, request: Request):
    with engine.begin() as db:
        admin_id = require_admin(db, request)
        row = one(db, """
            SELECT f.feedback_id, f.category, f.title, f.description, f.build_version, f.created_at,
                u.nickname, u.username
            FROM player_feedback f JOIN users u ON f.user_id=u.user_id WHERE f.feedback_id=:feedback
        """, feedback=str(feedback_id))
        if row is None:
            raise HTTPException(404, "feedback_not_found")
        screenshots = execute(db, """
            SELECT position, width, height FROM feedback_screenshots
            WHERE feedback_id=:feedback ORDER BY position
        """, feedback=str(feedback_id)).mappings().all()
        execute(db, """
            INSERT INTO admin_audit_log (actor_id, operation, object_id, result, request_id)
            VALUES (:admin, 'feedback.read', :feedback, 'ok', :request)
        """, admin=admin_id, feedback=str(feedback_id), request=str(uuid4()))
    return dict(public_feedback(row), screenshots=[dict(image) for image in screenshots])


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
