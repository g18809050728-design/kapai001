from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import OperationalError, ProgrammingError

from kapai import accounts, exports, feedback, maintenance, matches, saves, statistics
from kapai.db import one
from kapai.runtime import ORIGIN, engine

api = FastAPI(openapi_url=None, docs_url=None, redoc_url=None)


@api.middleware("http")
async def protect_api(request: Request, call_next):
    if request.url.path.startswith("/api/v1"):
        if request.method not in {"GET", "HEAD"}:
            if request.headers.get("origin") != ORIGIN:
                return JSONResponse({"detail": "origin_rejected"}, status_code=403)
            if request.headers.get("content-type", "").split(";")[0] != "application/json":
                return JSONResponse({"detail": "json_required"}, status_code=415)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response
    return await call_next(request)


@api.exception_handler(RequestValidationError)
async def invalid_request(_request, _error):
    return JSONResponse({"detail": "invalid_input"}, status_code=422)


@api.exception_handler(OperationalError)
async def database_unavailable(_request, _error):
    return JSONResponse({"detail": "database_unavailable"}, status_code=503)


@api.get("/internal/live")
def live():
    return {"status": "ok"}


@api.get("/internal/ready")
def ready():
    try:
        with engine.connect() as db:
            row = one(db, "SELECT version_num FROM alembic_version")
    except ProgrammingError as error:
        if error.orig.args[0] != 1146:
            raise
        raise HTTPException(503, "database_not_migrated") from None
    if row is None or row["version_num"] != "0009_match_details":
        raise HTTPException(503, "database_not_migrated")
    return {"status": "ok", "migration": row["version_num"]}




for module in (accounts, exports, feedback, maintenance, matches, saves, statistics):
    api.include_router(module.router, prefix="/api/v1")
