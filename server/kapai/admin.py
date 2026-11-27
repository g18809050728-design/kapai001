from datetime import timezone
from uuid import uuid4

from fastapi import HTTPException

from kapai.accounts import require, session_user
from kapai.db import execute


def require_admin(db, request):
    require("ADMIN")
    user = session_user(db, request)
    if user["role"] != "admin":
        raise HTTPException(403, "admin_required")
    return user["user_id"]


def audit(db, actor, operation, object_id=None):
    execute(db, """
        INSERT INTO admin_audit_log (actor_id, operation, object_id, result, request_id)
        VALUES (:actor, :operation, :object, 'ok', :request)
    """, actor=actor, operation=operation, object=object_id, request=str(uuid4()))


def utc_iso(value):
    return value.replace(tzinfo=timezone.utc).isoformat() if value is not None else None
