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
from xml.etree import ElementTree as ET
from zipfile import ZipFile

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
        account = one(db, "SELECT email,verified_at,activated_at,last_login_at FROM users WHERE user_id=:user", user=user_id)
        assert account["email"] is None and account["verified_at"] is None and account["activated_at"]
        assert account["last_login_at"] is not None
    check(register.post(route + "/auth/register", json={
        **signup, "username": username.upper(),
    }), 409)
    auth = register.post(route + "/auth/login", json={"identifier": username.upper(), "password": password})
    assert check(auth)["user_id"] == user_id and check(auth)["username"] == username
    with engine.connect() as db:
        success_at = one(db, "SELECT last_login_at FROM users WHERE user_id=:user", user=user_id)["last_login_at"]
    assert success_at > account["last_login_at"]
    check(register.post(route + "/auth/login", json={"identifier": username, "password": "wrong"}), 401)
    check(register.get(route + "/auth/session"))
    with engine.connect() as db:
        assert success_at == one(db, "SELECT last_login_at FROM users WHERE user_id=:user", user=user_id)["last_login_at"]
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
    assert summary["active_players"] >= 1 and summary["new_accounts"] >= 1
    assert summary["runs"]["lost"] >= 1 and summary["runs"]["first_battles"] >= 1
    assert len(summary["activity"]) == 1 and summary["activity"][0]["game_version"] is None
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

    records = route + "/admin/stats/records"
    target = records + "/" + match
    query = stats.split("?", 1)[1]
    # Put the reported milestones around midnight in Beijing. An imported run does not
    # become activity, and a real account/browser seen on both days still counts once.
    historical_query = "start=2024-09-01&end=2024-09-02"
    historical_matches = {}
    for outcome in ("won", "abandoned"):
        record = {**run, "run_id": f"{run['run_id']}_{outcome}", "game_version": f"old-{outcome}"}
        match_id = check(register.post(route + "/matches/start", json=record))["match_id"]
        check(register.post(route + f"/matches/{match_id}/finish", json={"result": outcome, "term": 1}))
        historical_matches[outcome] = match_id
    historical_visitor = str(uuid4())
    with engine.begin() as db:
        previous = one(db, "SELECT activated_at FROM users WHERE user_id=:id", id=user_id)["activated_at"]
        execute(db, "UPDATE users SET activated_at='2024-08-31 16:00:00' WHERE user_id=:id", id=user_id)
        execute(db, """
            UPDATE matches SET started_at='2024-08-31 16:00:00',
                first_battle_at='2024-09-01 16:00:00',finished_at='2024-09-01 16:01:00'
            WHERE match_id=:id
        """, id=historical_matches["won"])
        execute(db, """
            UPDATE matches SET started_at='2024-09-01 16:00:00',finished_at='2024-09-01 16:02:00'
            WHERE match_id=:id OR source='imported' AND match_id IN
                (SELECT match_id FROM match_players WHERE user_id=:user)
        """, id=historical_matches["abandoned"], user=user_id)
        for received in ("2024-08-31 15:59:59", "2024-08-31 16:00:00", "2024-09-01 16:00:00", "2024-09-01 16:01:00"):
            execute(db, """
                INSERT INTO game_events (event_id,event_type,visitor_id,received_at)
                VALUES (:id,'menu_opened',:visitor,:received)
            """, id=str(uuid4()), visitor=historical_visitor, received=received)
    sample = check(administrator.get(route + "/admin/stats?" + historical_query + "&version=old-won"))
    assert (sample["new_accounts"], sample["active_players"], sample["visitors"]) == (1, 1, 1)
    assert sample["runs"] == {"accounts": 1, "started": 2, "first_battles": 1, "finished": 1, "manual": 0,
                              "won": 1, "lost": 0, "abandoned": 1, "settled": 0, "pending": 0}
    assert sample["daily"] == [
        {"day": "2024-09-02", "new_accounts": 0, "visitors": 1, "active_players": 1, "started": 1, "first_battles": 1, "ended": 2},
        {"day": "2024-09-01", "new_accounts": 1, "visitors": 1, "active_players": 1, "started": 1, "first_battles": 0, "ended": 0},
    ]
    cohort = check(administrator.get(route + "/admin/stats?start=2024-09-01&end=2024-09-01"))
    assert cohort["runs"]["finished"] == 1 and cohort["daily"][0]["ended"] == 0
    filtered = check(administrator.get(route + "/admin/stats?" + historical_query + "&character=P04"))
    assert filtered["runs"]["started"] == 0 and filtered["daily"] == sample["daily"]
    page = check(administrator.get(records + "?" + historical_query + "&outcome=abandoned&q=" + username))
    assert [row["record_id"] for row in page["items"]] == [historical_matches["abandoned"]]
    with engine.begin() as db:
        for match_id in historical_matches.values():
            execute(db, "DELETE FROM matches WHERE match_id=:id", id=match_id)
        execute(db, "DELETE FROM game_events WHERE visitor_id=:visitor", visitor=historical_visitor)
        execute(db, "UPDATE users SET activated_at=:activated WHERE user_id=:id", id=user_id, activated=previous)

    manual_version = "manual-" + seed[:12]
    manual_reason = "integration supplement " + seed
    values = {"started_at": local_date + "T12:00:00+08:00",
              "character_id": "P03", "difficulty": "hard", "first_battle": True,
              "finished": False, "reason": manual_reason}
    manual_scope = stats + "&character=P03&difficulty=hard"
    before = check(administrator.get(manual_scope))
    check(client().get(records + "?" + query), 401)
    check(register.get(records + "?" + query), 403)
    check(register.post(records, json=values), 403)
    check(administrator.post(records, json={**values, "reason": "  "}), 422)
    check(administrator.post(records, json={**values, "started_at": local_date + "T12:00:00"}), 422)
    check(administrator.get(records + "?start=2024-02-01&end=2024-01-01"), 422)
    original = check(administrator.get(target))
    assert original["source"] == "automatic" and original["revision"] == 0 and original["finished"]
    created = check(administrator.post(records, json=values), 201)
    manual = records + "/" + created["record_id"]
    assert created["source"] == "manual" and created["started_at"].startswith(local_date + "T04:00")
    page = check(administrator.get(records + "?" + query + "&source=manual&q=" + manual_reason))
    assert page["total"] == 1 and page["items"][0]["record_id"] == created["record_id"]
    assert "user_id" not in page["items"][0]
    summary = check(administrator.get(manual_scope))
    assert summary["runs"]["manual"] == before["runs"]["manual"] + 1
    assert summary["runs"]["accounts"] == before["runs"]["accounts"] and summary["daily"] == before["daily"]
    check(register.patch(target, json={**values, "revision": 0}), 403)
    check(register.request("DELETE", target, json={"revision": 0, "reason": "not authorized"}), 403)
    changed = check(administrator.patch(manual, json={**values, "finished": True, "revision": created["revision"]}))
    assert changed["finished"] and changed["outcome"] == "settled" and changed["revision"] == created["revision"] + 1
    check(administrator.patch(manual, json={**values, "revision": created["revision"]}), 409)
    hidden = check(administrator.request("DELETE", manual, json={"revision": changed["revision"], "reason": "hide sample"}))
    assert hidden["excluded"]
    assert check(administrator.get(records + "?" + query + "&q=" + created["record_id"]))["items"] == []
    assert check(administrator.get(records + "?" + query + "&state=excluded&q=" + created["record_id"]))["total"] == 1
    assert check(administrator.get(manual_scope))["runs"] == before["runs"]
    restored = check(administrator.post(manual + "/restore", json={"revision": hidden["revision"], "reason": "restore sample"}))
    assert not restored["excluded"] and restored["finished"]
    corrected = check(administrator.patch(target, json={**values, "game_version": manual_version, "revision": 0}))
    assert corrected["source"] == "adjusted" and corrected["game_version"] == manual_version and corrected["outcome"] == "pending"
    corrected = check(administrator.patch(target, json={**values, "revision": corrected["revision"]}))
    assert corrected["game_version"] == manual_version
    with engine.connect() as db:
        assert one(db, "SELECT game_version FROM matches WHERE match_id=:id", id=match)["game_version"] == original["game_version"]
    restored = check(administrator.post(target + "/restore", json={"revision": corrected["revision"], "reason": "restore original"}))
    assert restored["source"] == "automatic" and restored["game_version"] == original["game_version"] and restored["finished"]
    assert check(administrator.get(records + "?" + query + "&q=%25"))["items"] == []
    with engine.begin() as db:
        for operation in ("create", "update", "exclude", "restore"):
            assert one(db, "SELECT audit_id FROM admin_audit_log WHERE operation=:op AND object_id=:id",
                       op="stats.record." + operation, id=created["record_id"])
        execute(db, "DELETE FROM stats_adjustments WHERE record_id=:id", id=created["record_id"])
    print("ADMIN-STATS CRUD, permission checks, aggregates, revisions, auditing and original record preservation passed")

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

    assert item["status"] == "new" and item["note"] == "" and item["updated_at"] is None
    assert check(administrator.get(inbox + "?q=%3Ctag%3E&state=active"))["total"] >= 2
    update = {"status": "archived", "note": "internal note", "updated_at": None}
    check(register.patch(detail, json=update), 403)
    triage = check(administrator.patch(detail, json=update))
    assert triage["status"] == "archived" and triage["note"] == "internal note"
    check(administrator.patch(detail, json=update), 409)
    feedback_id = receipt["feedback_id"]
    assert check(administrator.get(inbox + "?state=active&q=" + feedback_id))["items"] == []
    assert check(administrator.get(inbox + "?state=archived&q=" + feedback_id))["total"] == 1
    assert administrator.get(attachment).content == response.content
    assert check(register.post(feedback, json=report), 201) == receipt
    reopened = check(administrator.patch(detail, json={"status": "reviewing", "note": "reopen", "updated_at": triage["updated_at"]}))
    assert reopened["status"] == "reviewing" and check(administrator.get(detail))["description"] == item["description"]
    print("FEEDBACK-TRIAGE list, search, status, compatibility, concurrency and archiving passed")

    data_route = route + "/admin/data/players"
    user_route = data_route + "/" + user_id
    nickname_route = user_route + "/nickname"
    check(client().get(data_route), 401)
    check(register.get(data_route), 403)
    assert [r["user_id"] for r in check(administrator.get(data_route + "?q=" + username))["items"]] == [user_id]
    assert check(administrator.get(data_route + "/" + administrator_id))["role"] == "admin"
    profile = check(administrator.get(user_route))
    assert set(profile) == {"user_id", "username", "nickname", "role", "created_at", "last_login_at",
                            "match_count", "revision", "history", "can_restore"}
    assert profile["last_login_at"] and profile["match_count"] == 2 and profile["role"] == "player"
    check(register.get(user_route + "/matches"), 403)
    actual_matches = check(administrator.get(user_route + "/matches"))["items"]
    assert {r["source"] for r in actual_matches} == {"client_reported", "imported"}
    raw = next(r for r in actual_matches if r["match_id"] == match)
    assert raw["result"] == result | {"ending_id": ""} and raw["first_battle_at"].endswith("+00:00")
    assert check(administrator.get(data_route + "/" + administrator_id + "/matches"))["items"] == []
    check(administrator.get(data_route + "/" + str(uuid4()) + "/matches"), 404)
    control = {"revision": profile["revision"], "expected_nickname": profile["nickname"], "reason": "rename test"}
    # Spreadsheet metacharacters and URLs are valid display data, not workbook markup.
    new_name = "=1+1"
    change = {**control, "nickname": new_name}
    check(register.patch(nickname_route, json=change), 403)
    check(administrator.patch(nickname_route, json={**change, "nickname": "a\x00b"}), 422)
    check(administrator.patch(nickname_route, json={**change, "expected_nickname": "stale"}), 409)
    check(administrator.patch(nickname_route, json=change))
    check(administrator.patch(nickname_route, json=change), 409)
    actual = check(register.get(route + "/me"))
    assert actual["nickname"] == new_name and actual["username"] == username and actual["role"] == "player"
    latest = check(administrator.get(user_route))
    assert latest["history"][0]["old_nickname"] == profile["nickname"] and latest["can_restore"]

    exports = route + "/admin/exports/"
    book_route = exports + "feedback?q=" + feedback_id
    check(client().get(book_route), 401)
    check(register.get(book_route), 403)
    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

    def xlsx(response, sheet_name, sheet_index=1):
        assert response.status_code == 200 and response.headers["content-type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        assert response.headers["cache-control"] == "no-store" and response.headers["content-disposition"].endswith('.xlsx"')
        with ZipFile(io.BytesIO(response.content)) as file:
            assert file.testzip() is None
            names = file.namelist()
            assert not any("/media/" in name or "externalLink" in name for name in names)
            workbook = ET.fromstring(file.read("xl/workbook.xml"))
            sheets = [node.get("name") for node in workbook.findall("x:sheets/x:sheet", ns)]
            assert sheets[sheet_index - 1] == sheet_name
            shared = ET.fromstring(file.read("xl/sharedStrings.xml"))
            strings = ["".join(node.itertext()) for node in shared]
            page = ET.fromstring(file.read(f"xl/worksheets/sheet{sheet_index}.xml"))
            assert page.find(".//x:f", ns) is None and page.find(".//x:hyperlink", ns) is None
            data = []
            for row in page.findall("x:sheetData/x:row", ns):
                cells = {}
                for cell in row:
                    value = cell.find("x:v", ns).text
                    column = cell.get("r").rstrip("0123456789")
                    cells[column] = strings[int(value)] if cell.get("t") == "s" else float(value)
                data.append(cells)
        return data

    # More than a page of records still exports all matching rows.
    with engine.begin() as db:
        for i in range(22):
            execute(db, """
                INSERT INTO player_feedback (feedback_id,user_id,submission_id,payload_hash,category,title,description,build_version)
                VALUES (:id,:user,:submission,'hash','other',:title,'=2+2','archive-integration')
            """, id=str(uuid4()), user=user_id, submission=str(uuid4()), title="bulk-xlsx-" + seed)
    pages = check(administrator.get(inbox + "?q=bulk-xlsx-" + seed))
    assert len(pages["items"]) == 20 and pages["next_offset"] == 20
    feedback_rows = xlsx(administrator.get(book_route), "玩家反馈")
    assert len(feedback_rows) == 2 and feedback_rows[1]["C"] == new_name and feedback_rows[1]["H"] == item["description"] and feedback_rows[1]["J"] == 1
    bulk = xlsx(administrator.get(exports + "feedback?q=bulk-xlsx-" + seed), "玩家反馈")
    assert len(bulk) == 23 and all(row["H"] == "=2+2" for row in bulk[1:])
    with patch("kapai.exports.EXPORT_LIMIT", 20):
        assert check(administrator.get(exports + "feedback?q=bulk-xlsx-" + seed), 422)["detail"] == "export_too_many_rows"
    record_rows = xlsx(administrator.get(exports + "records?" + query + "&outcome=lost&q=" + match), "对局明细")
    assert len(record_rows) == 2 and record_rows[1]["A"] == match and record_rows[1]["C"] == new_name
    assert record_rows[1]["G"] == "失败" and "游戏版本" not in record_rows[0].values()
    report = administrator.get(exports + "stats?" + query)
    overall_rows = xlsx(report, "统计概览")
    assert overall_rows[1]["B"] >= 1 and len(overall_rows) == 15
    daily_rows = xlsx(report, "每日事件", sheet_index=2)
    assert len(daily_rows) == 2 and daily_rows[1]["A"] == local_date and daily_rows[1]["C"] >= 1
    check(administrator.post(nickname_route + "/restore", json={**control, "revision": latest["revision"], "expected_nickname": new_name}))
    assert check(register.get(route + "/me"))["nickname"] == profile["nickname"]
    with engine.connect() as db:
        for operation in ("export.feedback", "export.stats", "export.records", "data.player.nickname.update", "data.player.nickname.restore"):
            assert one(db, "SELECT audit_id FROM admin_audit_log WHERE operation=:op AND actor_id=:admin", op=operation, admin=administrator_id)
    print("ADMIN-DATA nickname DB write, stale/invalid rejection, audit, restore and filtered XLSX workbook content passed")

    directory_seed = "dir_" + seed[:10]
    fixture_ids = [str(uuid4()) for _ in range(4)]
    with engine.begin() as db:
        for index, (created, last_login, active) in enumerate([
            ("2024-10-01 15:59:59", "2024-10-02 16:00:00", True),
            ("2024-10-01 16:00:00", "2024-10-02 15:59:59", True),
            ("2024-10-02 15:59:59", None, True),
            ("2024-10-02 16:00:00", None, False),
        ]):
            execute(db, """
                INSERT INTO users (user_id,username,nickname,password_hash,created_at,activated_at,last_login_at)
                VALUES (:id,:name,:name,:password,:created,:activated,:login)
            """, id=fixture_ids[index], name=f"{directory_seed}_{index}", password=password_hasher.hash(password),
                created=created, activated=created if active else None, login=last_login)
    query_players = data_route + "?q=" + directory_seed

    def account_ids(extra=""):
        return [row["user_id"] for row in check(administrator.get(query_players + extra))["items"]]

    a, b, c, _ = fixture_ids
    assert account_ids() == [c, b, a]
    assert account_ids("&sort=created_oldest") == [a, b, c]
    assert account_ids("&sort=login_newest") == [a, b, c]
    assert account_ids("&sort=login_oldest") == [b, a, c]
    assert account_ids("&created_from=2024-10-02&created_to=2024-10-02") == [c, b]
    assert account_ids("&login_from=2024-10-03&login_to=2024-10-03") == [a]
    assert account_ids("&login_to=2024-10-02") == [b]
    check(administrator.get(query_players + "&login_from=2024-10-03&login_to=2024-10-02"), 422)

    promote_route = data_route + "/" + a + "/promote"
    role_route = route + "/admin/data/role-events"
    role_reason = "Verify role change"
    grantee = client()
    check(grantee.post(route + "/auth/login", json={"identifier": directory_seed + "_0", "password": password}))
    check(client().post(promote_route, json={"reason": role_reason}), 401)
    check(register.post(promote_route, json={"reason": role_reason}), 403)
    check(register.get(role_route), 403)
    check(administrator.post(promote_route, json={"reason": " "}), 422)
    check(administrator.post(data_route + "/" + fixture_ids[3] + "/promote", json={"reason": role_reason}), 404)
    check(administrator.post(data_route + "/" + administrator_id + "/promote", json={"reason": role_reason}), 409)
    assert check(administrator.post(promote_route, json={"reason": role_reason}))["role"] == "admin"
    check(administrator.post(promote_route, json={"reason": role_reason}), 409)
    assert account_ids("&role=admin") == [a] and account_ids("&role=player") == [c, b]
    assert check(grantee.get(route + "/auth/session"))["user"] is None
    check(grantee.get(data_route), 401)
    assert check(grantee.post(route + "/auth/login", json={
        "identifier": directory_seed + "_0", "password": password,
    }))["role"] == "admin"
    events = check(grantee.get(role_route + "?user_id=" + a))["items"]
    assert len(events) == 1
    assert events[0]["operation"] == "data.player.role.promote" and events[0]["actor_id"] == administrator_id
    assert events[0]["reason"] == role_reason and events[0]["user_id"] == a
    assert check(administrator.get(role_route + "?user_id=" + administrator_id))["items"][0]["operation"] == "admin-create"
    with engine.begin() as db:
        execute(db, "DELETE FROM admin_audit_log WHERE object_id=:id", id=a)
        for id_ in fixture_ids:
            execute(db, "DELETE FROM users WHERE user_id=:id", id=id_)
    print("ADMIN-DIRECTORY Beijing date boundaries, login ordering, raw matches, role promotion and audit passed")

    with engine.begin() as db:
        execute(db, "UPDATE users SET role='player' WHERE user_id=:user", user=administrator_id)
    assert check(administrator.get(route + "/auth/session"))["user"]["role"] == "player"
    check(administrator.get(stats), 403)
    check(administrator.get(data_route), 403)
    check(administrator.get(role_route), 403)
    check(administrator.post(promote_route, json={"reason": role_reason}), 403)
    check(administrator.get(records + "?" + query), 403)
    check(administrator.post(records, json=values), 403)
    check(administrator.get(book_route), 403)
    check(administrator.patch(nickname_route, json=change), 403)
    check(administrator.patch(detail, json=update), 403)
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
