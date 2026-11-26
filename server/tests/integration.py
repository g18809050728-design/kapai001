"""Run on the isolated development MySQL schema with the application credentials."""

import base64
import hashlib
import io
import json
import os
import tempfile
from datetime import datetime, timezone, timedelta
from pathlib import Path
from contextlib import redirect_stdout
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy.exc import OperationalError

assert os.environ["KAPAI_DB_NAME"] == "kapai_dev"
origin = "https://accounts.test"
with tempfile.TemporaryDirectory() as mailbox:
    os.environ.update(KAPAI_ORIGIN=origin, KAPAI_ACCOUNTS="1", KAPAI_ADMIN="1",
                      KAPAI_REGISTRATION="1", KAPAI_CLOUD="1", KAPAI_MAIL_SPOOL=mailbox)
    from kapai import saves
    from kapai.accounts import issue_token, password_hasher
    from kapai.db import execute, one
    from kapai.main import api, engine

    def client():
        return TestClient(api, base_url=origin, headers={"Origin": origin})

    def check(response, status=200):
        assert response.status_code == status, (response.status_code, response.json(), status)
        return response.json()

    def newest_mail(email, kind):
        files = [file for file in Path(mailbox).iterdir() if file.read_text().startswith(email + "\n")]
        return max(files, key=lambda file: file.stat().st_mtime_ns).read_text().strip().split(f"account-{kind}=")[-1]

    seed = uuid4().hex
    username = "test_" + seed[:16]
    legacy_email = seed + "-old@example.org"
    legacy_id = str(uuid4())
    legacy_username = "old_" + seed[:16]
    admin_email = seed + "-admin@example.org"
    password = "integration-passphrase"
    register = client()
    check(register.get("/internal/ready"))
    check(register.post("/auth-placeholder", json={}), 404)
    check(register.get("/api/v1/features"))
    with patch.dict(os.environ, {"KAPAI_TEAM_TOOLS": "1"}):
        assert "team_tools" not in check(register.get("/api/v1/features"))
    route = "/api/v1"
    signup = {"username": username, "password": password}
    check(register.post(route + "/auth/register", json={"username": username}), 422)
    check(register.post(route + "/auth/register", json={**signup, "username": "invalid username"}), 422)
    with patch("kapai.accounts.mail_spool", None):
        assert check(register.get(route + "/features"))["registration"]
        auth = register.post(route + "/auth/register", json=signup)
    user_id = check(auth, 201)["user_id"]
    assert check(register.get(route + "/auth/session"))["user"]["user_id"] == user_id
    assert not list(Path(mailbox).iterdir())
    with engine.connect() as db:
        account = one(db, "SELECT email,verified_at,activated_at FROM users WHERE user_id=:user", user=user_id)
        assert account["email"] is None and account["verified_at"] is None and account["activated_at"]
    check(register.post(route + "/auth/register", json={
        **signup, "username": username.upper(),
    }), 409)
    auth = register.post(route + "/auth/login", json={"identifier": username.upper(), "password": password})
    assert check(auth)["user_id"] == user_id and check(auth)["username"] == username
    check(register.post(route + "/auth/login", json={"identifier": username, "password": "wrong"}), 401)
    assert all(flag in auth.headers["set-cookie"].lower() for flag in ["secure", "httponly", "samesite=lax"])
    check(register.get(route + "/me", headers={"X-Kapai-Account": str(uuid4())}), 401)
    check(register.post(route + "/auth/logout", headers={"Origin": "https://unrelated.test"}, json={}), 403)
    print("AUTH-01 SMTP-free signup, automatic confirmed session, username uniqueness, cookie and CSRF passed")

    with engine.begin() as db:
        execute(db, "INSERT INTO users (user_id,email,nickname,password_hash) VALUES (:user,:email,'old',:password)",
                user=legacy_id, email=legacy_email, password=password_hasher.hash("unused"))
        legacy_token = issue_token(db, legacy_id, "verify", timedelta(hours=2))
    legacy = client()
    assert check(legacy.post(route + "/auth/verify", json={
        "token": legacy_token,
    }), 409)["detail"] == "password_setup_required"
    check(legacy.post(route + "/auth/verify", json={"token": legacy_token, "password": password}))
    assert check(legacy.post(route + "/auth/login", json={"email": legacy_email.upper(), "password": password}))["username"] is None
    check(legacy.post(route + "/me/username", json={"username": username}), 409)
    assert check(legacy.post(route + "/me/username", json={"username": legacy_username}))["user_id"] == legacy_id
    assert check(legacy.get(route + "/auth/session"))["user"]["username"] == legacy_username
    check(legacy.post(route + "/me/username", json={"username": "second_name"}), 409)
    assert check(client().post(route + "/auth/login", json={
        "identifier": legacy_username, "password": password,
    }))["user_id"] == legacy_id
    check(legacy.post(route + "/auth/forgot", json={"email": legacy_email}), 202)
    reset = newest_mail(legacy_email, "reset")
    new_password = password + "-reset"
    check(client().post(route + "/auth/reset", json={"token": reset, "password": new_password}))
    check(legacy.get(route + "/me"), 401)
    check(legacy.post(route + "/auth/login", json={"identifier": legacy_username, "password": new_password}))
    check(legacy.request("DELETE", route + "/me", json={"password": new_password}))
    print("AUTH-01 legacy invitation, email login, single username claim, password reset and session revocation passed")

    run = {"run_id": "run_" + seed, "manifest_id": "campus_four_year_relics", "game_version": "campus_four_year_relics.v2",
           "character_id": "P01", "difficulty": "normal"}
    match = check(register.post(route + "/matches/start", json=run))["match_id"]
    assert check(register.post(route + "/matches/start", json=run))["match_id"] == match
    battle = {"event_id": str(uuid4()), "match_id": match, "result": "lost", "event_type": "first_battle_completed"}
    check(register.post(route + "/events", json=battle))
    check(register.post(route + "/events", json={**battle, "event_id": str(uuid4())}))
    finish = route + "/matches/" + match + "/finish"
    result = {"result": "lost", "term": 1, "reason": "deadline"}
    check(register.post(finish, json=result))
    check(register.post(finish, json=result))
    check(register.post(finish, json={**result, "term": 2}), 409)
    check(client().post(finish, json=result), 401)
    assert check(register.get(route + "/me/matches"))["items"][0]["result"]["term"] == 1
    visitor = str(uuid4())
    for _ in range(2):
        check(client().post(route + "/events", json={
            "event_type": "menu_opened", "visitor_id": visitor, "event_id": str(uuid4()),
        }))
    imported = {"summary": result, **run, "run_id": run["run_id"] + "_old"}
    check(register.post(route + "/me/matches/import", json=[imported]))
    check(register.post(route + "/me/matches/import", json=[imported]))
    assert len(check(register.get(route + "/me/matches"))["items"]) == 2
    print("AUTH-01 duplicates, terminal conflict, unauthorized write, history and import passed")

    second = client()
    check(second.post(route + "/auth/login", json={"identifier": username, "password": password}))

    local_date = (datetime.now(timezone.utc) + timedelta(hours=8)).date().isoformat()
    stats = route + "/admin/stats?start=" + local_date + "&end=" + local_date
    check(register.get(stats), 403)
    administrator = client()
    from kapai import manage
    admin_username = "admin_" + seed[:16]
    console_output = io.StringIO()
    with patch("sys.argv", ["manage", "admin-create", admin_email, "--username", admin_username]), \
            patch.object(manage, "getpass", return_value=password), redirect_stdout(console_output):
        manage.main()
    assert "Administrator created" in console_output.getvalue()
    with engine.connect() as db:
        admin_record = one(db, "SELECT user_id,totp_secret FROM users WHERE email=:email", email=admin_email)
        administrator_id = admin_record["user_id"]
        assert admin_record["totp_secret"] is None
    auth_fields = {"email": admin_email, "password": password}
    check(administrator.post(route + "/auth/login", json={**auth_fields, "password": "incorrect"}), 401)
    assert check(administrator.post(route + "/auth/login", json=auth_fields))["role"] == "admin"
    assert check(administrator.get(route + "/auth/session"))["user"]["role"] == "admin"
    with engine.connect() as db:
        assert not one(db, "SELECT mfa FROM auth_sessions WHERE user_id=:user", user=administrator_id)["mfa"]
    summary = check(administrator.get(stats + "&version=campus_four_year_relics.v2"))
    assert summary["visitors"] >= 1
    assert any(item["started"] >= 1 and item["first_battles"] >= 1 and item["finished"] >= 1 for item in summary["activity"])
    with engine.begin() as db:
        assert one(db, "SELECT operation FROM admin_audit_log WHERE actor_id=:user", user=administrator_id)["operation"] == "stats.read"
        execute(db, "UPDATE users SET totp_secret='LEGACYCONFIGUREDSECRET',last_totp_step=999999999 WHERE user_id=:user",
                user=administrator_id)
        execute(db, "UPDATE auth_sessions SET mfa=TRUE WHERE user_id=:user", user=administrator_id)
    assert check(administrator.get(route + "/me"))["role"] == "admin"
    check(administrator.get(stats))
    assert check(administrator.post(route + "/auth/login", json={
        "identifier": admin_username, "password": password,
    }))["role"] == "admin"
    check(administrator.get(stats))

    feedback = route + "/feedback"
    inbox = route + "/admin/feedback"
    image_buffer = io.BytesIO()
    Image.new("RGB", (128, 72), "steelblue").save(image_buffer, "PNG")
    encoded = base64.b64encode(image_buffer.getvalue()).decode()
    report = {"submission_id": str(uuid4()), "category": "bug", "title": "  <b>提交后卡住</b>  ",
              "description": "第一步\n第二步 <tag>", "build_version": "integration", "screenshots": [encoded]}
    check(client().post(feedback, json=report), 401)
    check(register.post(feedback, headers={"Origin": "https://unrelated.test"}, json=report), 403)
    check(register.post(feedback, json={**report, "screenshots": [encoded] * 4}), 422)
    check(register.post(feedback, json={**report, "description": "   "}), 422)
    assert check(register.post(feedback, json={**report, "screenshots": ["bGF0ZQ=="]}), 422)["detail"] == "screenshot_invalid"
    receipt = check(register.post(feedback, json=report), 201)
    assert check(register.post(feedback, json=report), 201) == receipt
    check(register.post(feedback, json={**report, "title": "内容已变更"}), 409)
    suggestion = {**report, "submission_id": str(uuid4()), "category": "suggestion", "screenshots": []}
    suggestion_id = check(register.post(feedback, json=suggestion), 201)["feedback_id"]
    detail = inbox + "/" + receipt["feedback_id"]
    attachment = detail + "/screenshots/1"
    for path in (inbox, detail, attachment):
        check(client().get(path), 401)
        check(register.get(path), 403)
    page = check(administrator.get(inbox + "?category=bug"))
    assert page["items"][0]["feedback_id"] == receipt["feedback_id"]
    assert page["items"][0]["screenshot_count"] == 1
    item = check(administrator.get(detail))
    assert item["title"] == report["title"].strip() and item["description"] == report["description"]
    assert item["username"] == username and item["build_version"] == "integration"
    assert item["screenshots"] == [{"position": 1, "width": 128, "height": 72}]
    assert check(administrator.get(inbox + "/" + suggestion_id))["screenshots"] == []
    assert check(administrator.get(inbox + "?category=suggestion"))["items"][0]["feedback_id"] == suggestion_id
    response = administrator.get(attachment)
    assert response.status_code == 200 and response.headers["content-type"] == "image/webp"
    assert response.headers["cache-control"] == "no-store" and response.headers["x-content-type-options"] == "nosniff"
    with Image.open(io.BytesIO(response.content)) as screenshot:
        assert screenshot.format == "WEBP" and screenshot.size == (128, 72)
    check(administrator.get(detail + "/screenshots/2"), 404)

    with engine.begin() as db:
        execute(db, "UPDATE users SET role='player' WHERE user_id=:user", user=administrator_id)
    assert check(administrator.get(route + "/auth/session"))["user"]["role"] == "player"
    check(administrator.get(stats), 403)
    for path in (inbox, detail, attachment):
        check(administrator.get(path), 403)
    assert check(administrator.get(route + "/me/matches"))["items"] == []
    print("ADMIN-01 CLI creation, password-only admin login, legacy MFA compatibility, statistics and live role changes passed")

    def snapshot(revision):
        document = {"schema_version": 1, "content_version": run["game_version"], "content_hash": "a" * 64,
                    "manifest_id": run["manifest_id"], "run_id": run["run_id"], "revision": revision,
                    "random_state": {}, "payload": {"run": {"run_id": run["run_id"]}, "battle": None,
                    "terminal_summary": None, "profile_merge_pending": False, "event_log": []}}
        encoded = json.dumps(document, sort_keys=True, separators=(",", ":"))
        document["checksum"] = hashlib.sha256(encoded.encode()).hexdigest()
        return json.dumps(document, sort_keys=True, separators=(",", ":"))

    slot = route + "/me/saves/current_run"
    request = {"expected_cloud_revision": 0, "request_id": str(uuid4()), "snapshot": snapshot(15)}
    assert check(register.get(slot))["cloud_revision"] == 0
    assert check(register.put(slot, json=request))["cloud_revision"] == 1
    assert check(register.put(slot, json=request))["cloud_revision"] == 1
    assert check(second.get(slot))["snapshot"] == request["snapshot"]
    stale = {"expected_cloud_revision": 0, "request_id": str(uuid4()), "snapshot": snapshot(16)}
    assert check(second.put(slot, json=stale), 409)["current"]["cloud_revision"] == 1
    stale["expected_cloud_revision"] = 1
    assert check(second.put(slot, json=stale))["cloud_revision"] == 2
    assert check(register.get(slot + "?previous=true"))["snapshot"] == request["snapshot"]
    check(register.put(slot, json={**stale, "snapshot": stale["snapshot"].replace('"revision":16', '"revision":17')}), 422)
    assert check(administrator.get(slot))["cloud_revision"] == 0
    execute_save = saves.execute

    def fail_publish(db, statement, **params):
        if "UPDATE save_slots" in statement:
            raise OperationalError("update", {}, Exception("simulated write failure"))
        return execute_save(db, statement, **params)

    failed = {"expected_cloud_revision": 2, "request_id": str(uuid4()), "snapshot": snapshot(17)}
    with patch.object(saves, "execute", side_effect=fail_publish):
        check(register.put(slot, json=failed), 503)
    assert check(register.get(slot))["cloud_revision"] == 2
    assert check(register.get(slot + "?previous=true"))["cloud_revision"] == 1
    assert check(register.put(slot, json=failed))["cloud_revision"] == 3
    check(register.request("DELETE", route + "/me", json={"password": password}))
    check(second.get(slot), 401)
    with engine.begin() as db:
        assert not one(db, "SELECT * FROM save_slots WHERE user_id=:user", user=user_id)
        assert not one(db, "SELECT * FROM matches WHERE match_id=:match", match=match)
        assert not one(db, "SELECT feedback_id FROM player_feedback WHERE user_id=:user", user=user_id)
        assert not one(db, "SELECT feedback_id FROM feedback_screenshots WHERE feedback_id=:id", id=receipt["feedback_id"])
        execute(db, "DELETE FROM game_events WHERE visitor_id=:visitor", visitor=visitor)
        execute(db, "DELETE FROM admin_audit_log WHERE actor_id=:user", user=administrator_id)
        execute(db, "DELETE FROM users WHERE user_id=:user", user=administrator_id)
    print("SYNC-01 round-trip bytes, revision conflicts, idempotency, backup, transactional write failure and deletion passed")
    print("FEEDBACK-01 text and screenshot submission, filters, retries, private image, live role and deletion passed")
