"""Exercise actual Chromium rendering, offline playback and asynchronous role changes."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-party-20261115"
OUT = EV / "review-browser"
URL = (EV / "review/index.html").as_uri()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    checks, errors, failed = {}, [], []
    started = datetime.now(timezone.utc).isoformat()

    def check(name, value):
        checks[name] = bool(value)

    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="msedge", headless=True)
        context = browser.new_context(viewport={"width": 1440, "height": 1100}, reduced_motion="no-preference")
        page = context.new_page()
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.on("requestfailed", lambda r: failed.append({"url": r.url, "reason": r.failure}))
        page.goto(URL)
        page.wait_for_function("ready && !busy && document.getElementById('actor-canvas').dataset.role === 'P02'")
        check("three_complete_figures_first", page.locator(".character-card img").count() == 3 and page.locator("#characters").bounding_box()["y"] < page.locator("#motion").bounding_box()["y"])
        check("offline_local_images_render", page.locator(".character-card img").evaluate_all("els=>els.every(e=>e.complete && e.naturalWidth===1200 && e.naturalHeight===1400)"))
        page.screenshot(path=str(OUT / "three-characters-1440.png"))
        page.locator("#motion").scroll_into_view_if_needed()
        page.locator("#play").click()
        page.wait_for_function("!playing")
        before = page.evaluate("ms")
        page.wait_for_timeout(250)
        check("pause_stays_at_same_time", page.evaluate("ms") == before)
        page.locator("#play").click()
        page.wait_for_timeout(250)
        check("play_advances_actual_timeline", page.evaluate("ms") > before + 120)
        page.locator("#play").click()
        for role in ["P03", "P04", "P02"]:
            page.locator("#character").select_option(role)
            page.wait_for_function("([r])=>ready && !busy && document.getElementById('actor-canvas').dataset.role===r", arg=[role])
            check(role + "_role_details_and_canvas_agree", role in page.locator("#launch-command").inner_text() and page.locator(f'.character-card[data-role="{role}"]').get_attribute("aria-pressed") == "true")
            check(role + "_four_large_poses_and_four_battle_screens", page.locator("#pose-gallery img").count() == 4 and page.locator("#battle-gallery img").count() == 4)
            for sequence in ["fullbody-action-x4", "fullbody-action-x1", "fullbody-hit-x1", "command-00"]:
                page.locator("#sequence").select_option(sequence)
                page.wait_for_function("([s])=>ready && !busy && document.getElementById('actor-canvas').dataset.sequence===s", arg=[sequence])
                check(role + "_" + sequence + "_real_frames", page.evaluate("loadErrors.length===0 && sequence().frames.length>8"))
            page.locator("#sequence").select_option("fullbody-action-x1")
            page.wait_for_function("ready && !busy")
            seek = page.locator("#seek")
            seek.focus()
            seek.press("End")
            page.wait_for_function("!playing && ms===length() && !busy")
            check(role + "_scrub_uses_last_captured_frame", page.locator("#actor-canvas").get_attribute("data-frame").endswith(page.evaluate("sequence().frames.at(-1).file.split('/').at(-1)")))
            page.locator("#replay").click()
            page.wait_for_timeout(100)
            check(role + "_replay_restarts_near_beginning", page.evaluate("playing && ms<500"))
            page.locator("#play").click()
        # User input only; exercise a fast switch while paused and images load.
        for role in ["P04", "P03", "P02", "P04"]:
            page.locator("#character").select_option(role)
        page.wait_for_function("ready && !busy && document.getElementById('actor-canvas').dataset.role==='P04'")
        page.wait_for_timeout(200)
        check("rapid_role_switch_drops_stale_frames", page.locator("#actor-canvas").get_attribute("data-role") == "P04" and not page.evaluate("playing"))
        page.locator("#sequence").select_option("fullbody-idle-x1")
        page.wait_for_function("ready && !busy")
        page.locator("#speed").select_option("0.25")
        page.locator("#replay").click()
        start = page.evaluate("ms")
        page.wait_for_timeout(500)
        delta = page.evaluate("ms") - start
        check("quarter_speed_changes_viewer_clock", 50 < delta < 240)
        page.locator("#reduce-motion").check()
        page.wait_for_function("ready && !busy && reduced")
        static = page.locator("#actor-canvas").get_attribute("data-frame")
        page.wait_for_timeout(250)
        check("reduced_motion_is_actual_neutral_render", static.endswith("anatomy-full-neutral.png") and page.locator("#actor-canvas").get_attribute("data-frame") == static and not page.evaluate("playing"))
        check("reduced_motion_disables_animation_controls", page.locator("#play").is_disabled() and page.locator("#seek").is_disabled())
        page.locator("#character").select_option("P03")
        page.wait_for_function("ready && !busy && document.getElementById('actor-canvas').dataset.role==='P03'")
        check("reduced_motion_still_allows_role_selection", page.locator("#actor-canvas").get_attribute("data-frame").endswith("p03-final/anatomy-full-neutral.png"))
        page.locator("#reduce-motion").uncheck()
        page.wait_for_function("ready && !busy && !reduced")
        check("motion_restores_without_autoplay", not page.locator("#play").is_disabled() and not page.evaluate("playing"))
        page.locator("#sequence").select_option("fullbody-action-x1")
        page.wait_for_function("ready && !busy")
        page.locator("#seek").focus()
        page.locator("#seek").press("ArrowRight")
        page.screenshot(path=str(OUT / "fullbody-viewer-1440.png"))
        for width in [1440, 960, 640, 390]:
            page.set_viewport_size({"width": width, "height": 1000})
            page.wait_for_timeout(120)
            check(f"responsive_{width}_no_horizontal_overflow", page.evaluate("document.documentElement.scrollWidth<=innerWidth"))
            check(f"responsive_{width}_main_controls_44px", page.locator("button,select").evaluate_all("els=>els.filter(e=>e.getClientRects().length).every(e=>e.getBoundingClientRect().height>=44)"))
            if width in [960, 390]:
                page.screenshot(path=str(OUT / f"viewer-{width}.png"))
        page.set_viewport_size({"width": 1440, "height": 1100})
        page.locator("#character").select_option("P04")
        page.wait_for_function("ready && !busy")
        page.locator("#battle").scroll_into_view_if_needed()
        page.wait_for_function("Array.from(document.querySelectorAll('#battle-gallery img')).slice(0,2).every(i=>i.complete && i.naturalWidth>0)")
        page.screenshot(path=str(OUT / "battle-screens-1440.png"))
        check("all_referenced_capture_files_load", page.evaluate("loadErrors.length===0"))
        reduced_context = browser.new_context(reduced_motion="reduce", viewport={"width": 960, "height": 800})
        reduced_page = reduced_context.new_page()
        reduced_page.goto(URL)
        reduced_page.wait_for_function("ready && !busy && reduced")
        check("system_reduced_motion_defaults_to_static", reduced_page.locator("#reduce-motion").is_checked() and reduced_page.locator("#play").is_disabled() and reduced_page.locator("#actor-canvas").get_attribute("data-frame").endswith("anatomy-full-neutral.png"))
        version = browser.version
        browser.close()
    report = {"passed": all(checks.values()) and not errors and not failed, "started_utc": started, "browser": version, "url": URL, "checks": checks, "errors": errors, "failed_requests": failed,
              "inputs": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT / "tools/actor_party_review.html", ROOT / "tools/build_actor_party_review.py", ROOT / "tools/verify_actor_party_review.py", EV / "review/index.html", EV / "review/manifest.json"]}}
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "failures": [k for k, v in checks.items() if not v], "errors": errors, "failed_requests": failed}, ensure_ascii=False))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
