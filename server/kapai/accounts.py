import hashlib
import os
import re
import secrets
import smtplib
import ssl
import time
import unicodedata
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from pathlib import Path
from uuid import uuid4

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from email_validator import EmailNotValidError, validate_email
from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import AliasChoices, BaseModel, Field
from sqlalchemy.exc import IntegrityError

from kapai.db import execute, one
from kapai.runtime import ORIGIN, enabled, engine

router = APIRouter()
COOKIE = "__Host-kapai_session"
SESSION_AGE = 7 * 86400
password_hasher = PasswordHasher()
dummy_hash = password_hasher.hash(secrets.token_hex())
mail_spool = os.getenv("KAPAI_MAIL_SPOOL")


def utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def normalize_email(value):
    try:
        normalized = validate_email(value, check_deliverability=False).normalized
    except EmailNotValidError:
        raise HTTPException(422, "email_invalid") from None
    return unicodedata.normalize("NFC", normalized.casefold())


def normalize_username(value):
    value = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_]{2,23}", value):
        raise HTTPException(422, "username_invalid")
    return value.lower()


def public_user(row):
    return {field: row[field] for field in ("user_id", "username", "nickname", "role")}


def session_user(db, request, required=True):
    token = request.cookies.get(COOKIE)
    row = None
    if enabled("ACCOUNTS") and token:
        row = one(db, """
            SELECT u.user_id,u.username,u.email,u.nickname,u.role FROM users u JOIN auth_sessions s
            ON u.user_id=s.user_id WHERE s.token_hash=:token AND s.expires_at>UTC_TIMESTAMP(6)
            AND u.activated_at IS NOT NULL
        """, token=digest(token))
    claimed = request.headers.get("x-kapai-account")
    if claimed and (row is None or row["user_id"] != claimed):
        raise HTTPException(401, "account_changed")
    if required and row is None:
        raise HTTPException(401, "login_required")
    return row


def limited(request, name, identity, attempts=12):
    client = request.client.host if request.client else "unavailable"
    buckets = [(digest(f"{name}:address:{client}"), attempts * 3)]
    if identity:
        buckets.append((digest(f"{name}:identity:{identity}"), attempts))
    window = int(time.time()) // 900
    blocked = False
    with engine.begin() as db:
        for bucket, budget in buckets:
            execute(db, """
                INSERT INTO rate_limits VALUES (:bucket,:window,1)
                ON DUPLICATE KEY UPDATE attempts=attempts+1
            """, bucket=bucket, window=window)
            count = one(db, "SELECT attempts FROM rate_limits WHERE bucket=:bucket AND window_start=:window",
                        bucket=bucket, window=window)["attempts"]
            blocked = blocked or count > budget
    if blocked:
        raise HTTPException(429, "rate_limited", headers={"Retry-After": "900"})


def issue_token(db, user, kind, lifetime):
    token = secrets.token_urlsafe(32)
    execute(db, "DELETE FROM auth_tokens WHERE user_id=:user AND kind=:kind", user=user, kind=kind)
    execute(db, "INSERT INTO auth_tokens VALUES (:token,:user,:kind,:expires)",
            token=digest(token), user=user, kind=kind, expires=utcnow() + lifetime)
    return token


def mail_available():
    return bool(mail_spool or os.getenv("KAPAI_SMTP_HOST") and os.getenv("KAPAI_MAIL_FROM"))


def send_link(email, kind, token):
    link = f"{ORIGIN}/#account-{kind}={token}"
    if mail_spool:
        path = Path(mail_spool) / f"{uuid4()}.mail"
        with os.fdopen(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "w") as message:
            message.write(f"{email}\n{link}\n")
        return
    msg = EmailMessage()
    msg["To"] = email
    msg["From"] = os.environ["KAPAI_MAIL_FROM"]
    msg["Subject"] = "交大四年：DDL战争 · 账号验证" if kind == "verify" else "交大四年：DDL战争 · 重置密码"
    msg.set_content(f"请打开链接继续。\n\n{link}\n\n如果这不是你发起的操作，请忽略此邮件。")
    try:
        with smtplib.SMTP(os.environ["KAPAI_SMTP_HOST"], int(os.getenv("KAPAI_SMTP_PORT", "587")), timeout=10) as smtp:
            smtp.starttls(context=ssl.create_default_context())
            if user := os.getenv("KAPAI_SMTP_USER"):
                smtp.login(user, os.environ["KAPAI_SMTP_PASSWORD"])
            smtp.send_message(msg)
    except (OSError, smtplib.SMTPException):
        raise HTTPException(503, "mail_unavailable") from None


def require(feature="ACCOUNTS"):
    if not enabled("ACCOUNTS") or not enabled(feature):
        raise HTTPException(404, "feature_disabled")


class Email(BaseModel):
    email: str = Field(min_length=3, max_length=254)


class Login(BaseModel):
    identifier: str = Field(min_length=3, max_length=254, validation_alias=AliasChoices("identifier", "email"))
    password: str = Field(min_length=1, max_length=128)


class Registration(BaseModel):
    username: str = Field(min_length=3, max_length=24)
    password: str = Field(min_length=12, max_length=128)


class Username(BaseModel):
    username: str = Field(min_length=3, max_length=24)


class Token(BaseModel):
    token: str = Field(min_length=30, max_length=100)


class Reset(Token):
    password: str = Field(min_length=12, max_length=128)


class Verification(Token):
    password: str | None = Field(default=None, min_length=12, max_length=128)


class Deletion(BaseModel):
    password: str = Field(min_length=1, max_length=128)


@router.get("/features")
def features():
    return {
        "accounts": enabled("ACCOUNTS"),
        "registration": enabled("ACCOUNTS") and enabled("REGISTRATION"),
        "reset": enabled("ACCOUNTS") and mail_available(),
        "cloud": enabled("ACCOUNTS") and enabled("CLOUD"),
        "admin": enabled("ACCOUNTS") and enabled("ADMIN"),
    }


@router.post("/auth/register", status_code=201)
def register(data: Registration, request: Request, response: Response):
    require("REGISTRATION")
    username = normalize_username(data.username)
    limited(request, "register", username, attempts=4)
    password = password_hasher.hash(data.password)
    user = str(uuid4())
    try:
        with engine.begin() as db:
            execute(db, """
                INSERT INTO users (user_id,username,nickname,password_hash,activated_at)
                VALUES (:user,:username,:username,:password,UTC_TIMESTAMP(6))
            """, user=user, username=username, password=password)
            token = create_session(db, request, user)
    except IntegrityError as error:
        if error.orig.args[0] == 1062 and "users_username_unique" in str(error.orig):
            raise HTTPException(409, "username_taken") from None
        raise
    set_session_cookie(response, token)
    return {"user_id": user, "username": username, "nickname": username, "role": "player"}


@router.post("/auth/verify")
def verify(data: Verification, request: Request):
    require()
    limited(request, "verify", None)
    with engine.begin() as db:
        token_hash = digest(data.token)
        row = one(db, """
            SELECT u.user_id,u.username FROM users u WHERE u.activated_at IS NULL AND u.user_id=(
                SELECT user_id FROM auth_tokens WHERE token_hash=:token AND kind='verify'
                AND expires_at>UTC_TIMESTAMP(6)
            ) FOR UPDATE
        """, token=token_hash)
        if not row:
            raise HTTPException(400, "invalid_token")
        token = one(db, """
            SELECT token_hash FROM auth_tokens WHERE token_hash=:token AND user_id=:user
            AND kind='verify' AND expires_at>UTC_TIMESTAMP(6) FOR UPDATE
        """, token=token_hash, user=row["user_id"])
        if not token:
            raise HTTPException(400, "invalid_token")
        if row["username"] is None:
            if data.password is None:
                raise HTTPException(409, "password_setup_required")
            execute(db, "UPDATE users SET password_hash=:password WHERE user_id=:user",
                    user=row["user_id"], password=password_hasher.hash(data.password))
        execute(db, "UPDATE users SET verified_at=UTC_TIMESTAMP(6),activated_at=UTC_TIMESTAMP(6) WHERE user_id=:user",
                user=row["user_id"])
        execute(db, "DELETE FROM auth_tokens WHERE token_hash=:token", token=token_hash)
    return {}


@router.post("/auth/forgot", status_code=202)
def forgot(data: Email, request: Request):
    require()
    if not mail_available():
        raise HTTPException(503, "mail_unavailable")
    email = normalize_email(data.email)
    limited(request, "forgot", email, attempts=4)
    with engine.begin() as db:
        row = one(db, "SELECT user_id FROM users WHERE email=:email AND verified_at IS NOT NULL FOR UPDATE", email=email)
        if not row:
            return {}
        token = issue_token(db, row["user_id"], "reset", timedelta(minutes=30))
    send_link(email, "reset", token)
    return {}


@router.post("/auth/reset")
def reset(data: Reset, request: Request):
    require()
    limited(request, "reset", None)
    with engine.begin() as db:
        token = one(db, "SELECT user_id FROM auth_tokens WHERE token_hash=:token AND kind='reset' AND expires_at>UTC_TIMESTAMP(6) FOR UPDATE",
                    token=digest(data.token))
        if token is None:
            raise HTTPException(400, "invalid_token")
        user = token["user_id"]
        execute(db, "UPDATE users SET password_hash=:password WHERE user_id=:user", password=password_hasher.hash(data.password), user=user)
        execute(db, "DELETE FROM auth_tokens WHERE user_id=:user", user=user)
        execute(db, "DELETE FROM auth_sessions WHERE user_id=:user", user=user)
    return {}


@router.post("/auth/login")
def login(data: Login, request: Request, response: Response):
    require()
    identifier = data.identifier.strip()
    by_email = "@" in identifier
    column = "email" if by_email else "username"
    identity = normalize_email(identifier) if by_email else normalize_username(identifier)
    limited(request, "login", identity)
    with engine.begin() as db:
        row = one(db, f"""
            SELECT user_id,username,nickname,role,password_hash,activated_at
            FROM users WHERE {column}=:identity FOR UPDATE
        """, identity=identity)
        try:
            password_hasher.verify(row["password_hash"] if row else dummy_hash, data.password)
        except VerifyMismatchError:
            raise HTTPException(401, "invalid_credentials") from None
        if not row:
            raise HTTPException(401, "invalid_credentials")
        if not row["activated_at"]:
            raise HTTPException(403, "email_unverified")
        token = create_session(db, request, row["user_id"])
    set_session_cookie(response, token)
    return public_user(row)


def create_session(db, request, user_id):
    if old := request.cookies.get(COOKIE):
        execute(db, "DELETE FROM auth_sessions WHERE token_hash=:token", token=digest(old))
    token = secrets.token_urlsafe(32)
    execute(db, "INSERT INTO auth_sessions (token_hash,user_id,expires_at) VALUES (:token,:user,:expires)",
            token=digest(token), user=user_id, expires=utcnow() + timedelta(seconds=SESSION_AGE))
    return token


def set_session_cookie(response, token):
    response.set_cookie(COOKIE, token, max_age=SESSION_AGE, httponly=True, secure=True, samesite="lax")


@router.post("/auth/logout")
def logout(request: Request, response: Response):
    require()
    if token := request.cookies.get(COOKIE):
        with engine.begin() as db:
            claimed = request.headers.get("x-kapai-account")
            owner = one(db, "SELECT user_id FROM auth_sessions WHERE token_hash=:token", token=digest(token))
            if claimed and owner and owner["user_id"] != claimed:
                raise HTTPException(401, "account_changed")
            execute(db, "DELETE FROM auth_sessions WHERE token_hash=:token", token=digest(token))
    response.delete_cookie(COOKIE, secure=True, httponly=True, samesite="lax")
    return {}


@router.get("/auth/session")
def probe_session(request: Request):
    with engine.connect() as db:
        row = session_user(db, request, required=False)
    return {"user": public_user(row) if row else None}


@router.get("/me")
def me(request: Request):
    with engine.connect() as db:
        row = session_user(db, request)
    return public_user(row)


@router.post("/me/username")
def claim_username(data: Username, request: Request):
    username = normalize_username(data.username)
    with engine.connect() as db:
        user = session_user(db, request)
    limited(request, "claim_username", user["user_id"])
    try:
        with engine.begin() as db:
            user = session_user(db, request)
            changed = execute(db, """
                UPDATE users SET username=:username WHERE user_id=:user AND username IS NULL
            """, username=username, user=user["user_id"])
            if not changed.rowcount:
                raise HTTPException(409, "username_already_set")
    except IntegrityError as error:
        if error.orig.args[0] != 1062:
            raise
        raise HTTPException(409, "username_taken") from None
    return public_user({**user, "username": username})


@router.delete("/me")
def delete_me(data: Deletion, request: Request, response: Response):
    with engine.begin() as db:
        user = session_user(db, request)
        account = one(db, "SELECT password_hash FROM users WHERE user_id=:user FOR UPDATE", user=user["user_id"])
        try:
            password_hasher.verify(account["password_hash"], data.password)
        except VerifyMismatchError:
            raise HTTPException(401, "invalid_credentials") from None
        execute(db, """
            DELETE m FROM matches m JOIN match_players p ON m.match_id=p.match_id
             WHERE p.user_id=:user AND m.mode='solo'
        """, user=user["user_id"])
        execute(db, "DELETE FROM users WHERE user_id=:user", user=user["user_id"])
    response.delete_cookie(COOKIE, secure=True, httponly=True, samesite="lax")
    return {}
