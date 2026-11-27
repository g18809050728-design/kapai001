"""Browser checks for the real accounts.js and isolated MySQL-backed workbench.

The QA origin must use a disposable database; supply a QA admin via environment.
"""
import io
import os
from zipfile import ZipFile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit
from uuid import uuid4

from PIL import Image
from playwright.sync_api import expect, sync_playwright

ORIGIN = os.environ["KAPAI_WORKSPACE_QA_ORIGIN"]
assert urlsplit(ORIGIN).hostname in {"localhost", "127.0.0.1"}
QA_TLS = urlsplit(ORIGIN).scheme == "https"
EXTENDED = os.environ.get("KAPAI_WORKSPACE_VERIFY_EXPORTS") == "1"
EVIDENCE = "admin-data-20261127" if EXTENDED else "admin-workspace-20261127"
OUT = Path(os.environ.get("KAPAI_WORKSPACE_QA_OUTPUT")
           or Path(__file__).resolve().parents[1] / "artifacts/verification" / EVIDENCE)
OUT.mkdir(parents=True, exist_ok=True)


def open_section(page, key, panel):
    page.evaluate("key => window.kapaiAccounts.openSection(key)", key)
    expect(page.locator(f'#account-panel[open][data-panel="{panel}"]')).to_be_visible()


def setup_page(context):
    page = context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda event: errors.append(f"{event.location.get('url', '')}: {event.text}") if event.type == "error" else None)
    page.route("**/pack-loader.js", lambda route: route.fulfill(
        content_type="text/javascript", body="const KapaiWebPack = {start: async () => {}};"))
    page.goto(ORIGIN)
    page.locator("#status").wait_for(state="detached", timeout=120_000)
    page.evaluate("""() => window.kapaiAccounts.connectGame((method, ...args) => {
        if (method === 'menu') window.menu = args;
        window.kapaiAccounts.reply(true);
    })""")
    return page, errors


def login(context, data, path):
    response = context.request.post(ORIGIN + "/api/v1/auth/" + path, data=data, headers={"Origin": ORIGIN})
    assert response.ok, response.text()


def get_button(page, title):
    return page.get_by_role("button", name=title, exact=True)


def assert_download(page, kind, sheet_name, needle=""):
    with page.expect_download() as info:
        get_button(page, "导出 XLSX").click()
    download = info.value
    assert download.suggested_filename.startswith(f"kapai-{kind}-") and download.suggested_filename.endswith(".xlsx")
    download.save_as(OUT / (kind + "-example.xlsx"))
    with ZipFile(download.path()) as book:
        assert book.testzip() is None
        assert sheet_name in book.read("xl/workbook.xml").decode()
        if needle:
            assert needle in book.read("xl/sharedStrings.xml").decode()


def inspect_layout(page):
    checks = page.locator('#account-panel .account-content').evaluate("""e => ({
      overflow: e.scrollWidth > e.clientWidth + 1,
      small: [...e.querySelectorAll('button,select')].filter(x=>x.getClientRects().length && x.getBoundingClientRect().height < 44).map(x=>x.textContent)
    })""")
    assert not checks["small"] and not checks["overflow"], checks


with sync_playwright() as playwright:
    executable = os.environ.get("KAPAI_WORKSPACE_QA_BROWSER")
    browser = playwright.chromium.launch(executable_path=executable, channel=None if executable else "msedge",
                                         args=["--enable-unsafe-swiftshader", "--js-flags=--liftoff-only --no-wasm-tier-up"])
    prefix = uuid4().hex[:8]
    player = browser.new_context(viewport={"width": 1120, "height": 850}, ignore_https_errors=QA_TLS)
    login(player, {"username": "qa_ws_" + prefix, "nickname": "浏览器验收玩家", "password": "workspace-check-only"}, "register")
    run = player.request.post(ORIGIN + "/api/v1/matches/start", headers={"Origin": ORIGIN}, data={
        "run_id": "qa_" + prefix, "manifest_id": "campus_four_year_relics", "game_version": "qa",
        "character_id": "P01", "difficulty": "normal",
    })
    assert run.ok, run.text()
    match_id = run.json()["match_id"]
    finish = player.request.post(ORIGIN + f"/api/v1/matches/{match_id}/finish", headers={"Origin": ORIGIN},
                                 data={"result": "won", "term": 4})
    assert finish.ok, finish.text()
    page, player_errors = setup_page(player)
    page.wait_for_timeout(350)
    open_section(page, "feedback", "feedback")
    page.locator('[name="title"]').fill("验收：主菜单截图 " + prefix)
    page.locator('[name="description"]').fill("浏览器回归：保存旧截图流转\n第二行正文。")
    image = io.BytesIO()
    Image.new("RGB", (240, 135), "#416262").save(image, "PNG")
    file = {"name": "preview.png", "mimeType": "image/png", "buffer": image.getvalue()}
    page.locator('input[type="file"]').set_input_files([file])
    expect(page.get_by_role("img", name="preview.png")).to_be_visible()
    page.get_by_role("button", name="移除截图 preview.png").click()
    expect(page.get_by_role("img", name="preview.png")).to_have_count(0)
    page.locator('input[type="file"]').set_input_files([file])
    expect(page.get_by_role("img", name="preview.png")).to_be_visible()
    inspect_layout(page)
    page.screenshot(path=OUT / "feedback-compose.png")
    get_button(page, "提交反馈").click()
    expect(page.get_by_role("heading", name="反馈已提交")).to_be_visible()
    expect(page.get_by_text("反馈编号", exact=False)).to_be_visible()
    get_button(page, "返回游戏").click()
    page.evaluate("window.kapaiAccounts.openSection('feedback_admin')")
    expect(page.locator('#account-panel[open]')).to_have_count(0)

    admin = browser.new_context(viewport={"width": 1120, "height": 920}, ignore_https_errors=QA_TLS)
    login(admin, {"identifier": os.environ["KAPAI_WORKSPACE_QA_ADMIN"], "password": os.environ["KAPAI_WORKSPACE_QA_PASSWORD"]}, "login")
    page, admin_errors = setup_page(admin)
    page.wait_for_timeout(350)
    open_section(page, "feedback_admin", "feedback-admin")
    page.get_by_role("searchbox", name="搜索反馈").fill(prefix)
    get_button(page, "搜索").click()
    row = page.get_by_role("button", name=f"验收：主菜单截图 {prefix}", exact=False)
    expect(row).to_be_visible()
    inspect_layout(page)
    page.screenshot(path=OUT / "feedback-inbox.png")
    row.click()
    shot = page.get_by_role("img", name="截图 1（240 × 135）")
    expect(shot).to_be_visible()
    expect(shot).to_have_js_property("naturalWidth", 240)
    page.locator('[name="status"]').select_option("archived")
    page.get_by_label("内部备注（仅管理员可见）").fill("该备注不覆盖原文")
    page.screenshot(path=OUT / "feedback-detail.png")
    get_button(page, "保存处理结果").click()
    expect(page.get_by_text("处理结果已保存。", exact=True)).to_be_visible()
    expect(page.get_by_role("searchbox", name="搜索反馈")).to_have_value(prefix)
    expect(row).to_contain_text("已归档")
    if EXTENDED:
        assert_download(page, "feedback", "玩家反馈", prefix)
    page.keyboard.press("Escape")

    open_section(page, "stats", "admin-data")
    expect(page.get_by_role("heading", name="玩家管理")).to_be_visible()
    expect(page.get_by_role("heading", name="对局漏斗")).to_have_count(0)
    search_player = page.get_by_role("searchbox", name="搜索玩家")
    search_player.fill("qa_ws_" + prefix)
    page.get_by_label("排序").select_option("login_newest")
    page.get_by_text("时间筛选（北京时间）", exact=True).click()
    today = (datetime.now(timezone.utc) + timedelta(hours=8)).date().isoformat()
    for name in ("created_from", "created_to", "login_from", "login_to"):
        page.locator(f'[name="{name}"]').fill(today)
    get_button(page, "查询玩家").click()
    player_row = page.get_by_role("button", name="qa_ws_" + prefix, exact=False)
    expect(player_row).to_contain_text("最后登录")
    expect(player_row).to_contain_text("1 局")
    inspect_layout(page)
    page.screenshot(path=OUT / "player-directory.png")
    page.get_by_text("时间筛选（北京时间）", exact=True).click()
    page.set_viewport_size({"width": 390, "height": 800})
    page.locator("html").evaluate("(e) => e.style.fontSize = '150%'")
    inspect_layout(page)
    page.screenshot(path=OUT / "player-directory-mobile.png")
    page.set_viewport_size({"width": 1120, "height": 920})
    page.locator("html").evaluate("(e) => e.style.removeProperty('font-size')")
    player_row.click()
    expect(page.get_by_role("heading", name="对局记录（1）")).to_be_visible()
    game_row = page.get_by_role("button", name="胜利", exact=False)
    expect(game_row).to_be_visible()
    page.screenshot(path=OUT / "player-profile.png")
    game_row.click()
    expect(page.get_by_text(match_id, exact=True)).to_be_visible()
    page.screenshot(path=OUT / "player-match.png")
    get_button(page, "← 返回玩家资料").click()
    get_button(page, "← 返回玩家管理").click()
    expect(search_player).to_have_value("qa_ws_" + prefix)
    expect(page.get_by_label("排序")).to_have_value("login_newest")
    get_button(page, "活动汇总").click()
    expect(page.get_by_role("heading", name="对局漏斗")).to_be_visible()
    expect(page.get_by_role("heading", name="玩家活动")).to_be_visible()
    expect(page.get_by_role("heading", name="对局结局")).to_be_visible()
    expect(page.get_by_role("table", name="每日事件")).to_be_visible()
    expect(page.get_by_role("columnheader", name="活跃账号")).to_be_visible()
    expect(page.get_by_text("各版本对局", exact=True)).to_have_count(0)
    expect(page.get_by_label("游戏版本")).to_have_count(0)
    inspect_layout(page)
    page.screenshot(path=OUT / "stats-overview.png")
    page.get_by_role("table", name="每日事件").scroll_into_view_if_needed()
    page.screenshot(path=OUT / "stats-daily.png")
    page.get_by_role("heading", name="活动汇总").scroll_into_view_if_needed()
    page.set_viewport_size({"width": 390, "height": 800})
    page.locator("html").evaluate("(e) => e.style.fontSize = '150%'")
    inspect_layout(page)
    page.screenshot(path=OUT / "stats-overview-mobile.png")
    page.set_viewport_size({"width": 1120, "height": 920})
    page.locator("html").evaluate("(e) => e.style.removeProperty('font-size')")
    if EXTENDED:
        assert_download(page, "stats", "每日事件", "活跃账号")
    page.get_by_text("日期与筛选", exact=False).click()
    get_button(page, "近 30 天").click()
    expect(page.get_by_text("至 " + (datetime.now(timezone.utc) + timedelta(hours=8)).date().isoformat() + " · 北京时间", exact=False)).to_be_visible()
    expect(get_button(page, "查询")).to_be_enabled()
    get_button(page, "对局明细").click()
    get_button(page, "＋ 新增统计记录").click()
    expect(page.get_by_label("游戏版本")).to_have_count(0)
    page.get_by_label("首战完成").select_option("1")
    page.get_by_label("操作理由（必填）").fill("浏览器验收补录")
    page.screenshot(path=OUT / "stats-edit.png")
    get_button(page, "新增记录").click()
    expect(page.get_by_text("记录已新增；若不在当前筛选范围内，请调整筛选。", exact=True)).to_be_visible()
    get_button(page, "编辑统计记录").click()
    page.get_by_label("整局结算").select_option("1")
    page.get_by_label("操作理由（必填）").fill("浏览器验收修正")
    get_button(page, "保存修正").click()
    expect(page.get_by_text("统计修正已保存。", exact=True)).to_be_visible()
    get_button(page, "移出统计").click()
    page.get_by_label("操作理由（必填）").fill("浏览器验收移出 " + prefix)
    get_button(page, "确认移出统计").click()
    expect(page.get_by_text("已移出统计。", exact=True)).to_be_visible()
    get_button(page, "← 返回对局明细").click()
    page.get_by_label("统计状态").select_option("excluded")
    page.get_by_label("对局结局").select_option("settled")
    page.get_by_role("searchbox", name="搜索对局明细").fill(prefix)
    get_button(page, "查询").click()
    entry = page.get_by_role("button", name="人工补录", exact=False)
    expect(entry).to_contain_text("已移出")
    expect(entry).to_contain_text("结局未知")
    if EXTENDED:
        assert_download(page, "records", "对局明细", prefix)
        get_button(page, "玩家管理").click()
        page.get_by_role("searchbox", name="搜索玩家").fill("qa_ws_" + prefix)
        get_button(page, "查询玩家").click()
        page.get_by_role("button", name="qa_ws_" + prefix, exact=False).click()
        get_button(page, "修改显示昵称").click()
        page.get_by_label("新显示昵称").fill("验收昵称 " + prefix)
        get_button(page, "下一步").click()
        page.get_by_label("操作原因（必填）").fill("隔离验收真实写入")
        page.screenshot(path=OUT / "nickname-confirmation.png")
        get_button(page, "确认写入数据库").click()
        expect(page.get_by_role("heading", name="验收昵称 " + prefix)).to_be_visible()
        expect(page.get_by_text("显示昵称已写入数据库。", exact=True)).to_be_visible()
        assert player.request.get(ORIGIN + '/api/v1/me').json()['nickname'] == '验收昵称 ' + prefix
        page.screenshot(path=OUT / "nickname-history.png")
        page.get_by_text("昵称修改记录", exact=True).click()
        get_button(page, "撤回上一笔修改").click()
        page.get_by_label("操作原因（必填）").fill("隔离验收撤回")
        get_button(page, "确认撤回").click()
        expect(page.get_by_role("heading", name="qa_ws_" + prefix)).to_be_visible()
        assert player.request.get(ORIGIN + '/api/v1/me').json()['nickname'] == 'qa_ws_' + prefix
        get_button(page, "← 返回玩家管理").click()
        get_button(page, "← 返回活动汇总").click()
        expect(entry).to_contain_text("已移出")
    for width, scale in [(960, 1.25), (390, 1.0), (390, 1.5)]:
        page.set_viewport_size({"width": width, "height": 800})
        page.locator('html').evaluate('(e,scale) => e.style.fontSize = `${scale * 100}%`', scale)
        inspect_layout(page)
        if width == 390 and scale == 1:
            page.screenshot(path=OUT / "stats-records-mobile.png")
    entry.click()
    get_button(page, "恢复计入").click()
    page.get_by_label("操作理由（必填）").fill("浏览器验收恢复")
    get_button(page, "确认恢复计入").click()
    expect(page.get_by_text("已恢复。", exact=True)).to_be_visible()
    page.keyboard.press("Escape")
    page.set_viewport_size({"width": 1120, "height": 920})
    page.locator("html").evaluate("(e) => e.style.removeProperty('font-size')")
    open_section(page, "stats", "admin-data")
    search_player.fill("qa_ws_" + prefix)
    get_button(page, "查询玩家").click()
    player_row.click()
    get_button(page, "升为管理员").click()
    expect(page.get_by_text("普通玩家 → 管理员", exact=True)).to_be_visible()
    page.get_by_label("操作原因（必填）").fill("隔离验收角色提升")
    page.screenshot(path=OUT / "player-role-confirmation.png")
    get_button(page, "确认升为管理员").click()
    expect(page.get_by_text("已升为管理员，重新登录后生效。", exact=True)).to_be_visible()
    assert player.request.get(ORIGIN + "/api/v1/auth/session").json()["user"] is None
    login(player, {"identifier": "qa_ws_" + prefix, "password": "workspace-check-only"}, "login")
    assert player.request.get(ORIGIN + "/api/v1/me").json()["role"] == "admin"
    get_button(page, "权限记录").click()
    expect(page.get_by_text("隔离验收角色提升", exact=True)).to_be_visible()
    page.screenshot(path=OUT / "player-role-events.png")
    get_button(page, "← 返回玩家资料").click()
    get_button(page, "← 返回玩家管理").click()
    get_button(page, "权限记录").click()
    expect(page.get_by_text("隔离验收角色提升", exact=True)).to_be_visible()
    assert not (player_errors + admin_errors), player_errors + admin_errors
    browser.close()
if EXTENDED:
    print("Chromium passed three real XLSX downloads, nickname confirmation, committed write, history and restore.")
print("Chromium passed player directory and matches, date filters, role grants and audit; activity and feedback regression; desktop and mobile.")
