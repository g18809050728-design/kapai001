"""Exercise the offline motion comparison in a real isolated Edge browser."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-motion-20261115"
OUT = EV / "review-browser-final"
URL = (EV / "review/index.html").as_uri()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    checks, errors, failed = {}, [], []
    started = datetime.now(timezone.utc).isoformat()

    def check(name, value):
        checks[name] = bool(value)

    def ready(page, role=None):
        page.wait_for_function("r=>ready&&!busy&&(!r||document.getElementById('actor-canvas').dataset.role===r)", arg=role)

    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="msedge", headless=True)
        context = browser.new_context(viewport={"width": 1440, "height": 1100}, reduced_motion="no-preference")
        page = context.new_page()
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.on("requestfailed", lambda r: failed.append({"url": r.url, "reason": r.failure}))
        page.goto(URL)
        ready(page, "P04")
        check("default_P04_V11", page.locator("#version").input_value() == "v11" and page.locator("#character").input_value() == "P04")
        check("two_actual_motion_comparisons", page.locator("#comparison figure").count() == 2)
        page.locator("#comparison").scroll_into_view_if_needed()
        page.wait_for_function("Array.from(document.querySelectorAll('#comparison img')).every(i=>i.complete&&i.naturalWidth===1200&&i.naturalHeight===780)")
        check("comparison_images_decoded", True)
        page.screenshot(path=str(OUT / "p04-action-comparison-1440.png"))
        check("all_three_selected_figures_exist", page.locator(".character-card img").count() == 3 and page.locator(".character-card img").evaluate_all("els=>els.every(e=>e.complete&&e.naturalWidth===1200&&e.naturalHeight===1400)"))

        page.locator("#motion").scroll_into_view_if_needed()
        page.locator("#play").click()
        page.wait_for_function("!playing")
        before = page.evaluate("ms")
        page.wait_for_timeout(180)
        check("pause_retains_actual_frame_time", before == page.evaluate("ms"))
        page.locator("#play").click()
        page.wait_for_timeout(250)
        check("play_advances_timestamp_clock", page.evaluate("ms") > before + 120)
        page.locator("#play").click()
        page.locator("#sequence").select_option("fullbody-action-x1")
        ready(page)
        page.locator("#speed").select_option("0.25")
        page.locator("#replay").click()
        start = page.evaluate("ms")
        page.wait_for_timeout(500)
        check("quarter_speed_uses_recorded_timestamps", 50 < page.evaluate("ms") - start < 240)
        page.locator("#reduce-motion").check()
        ready(page)
        check("reduced_motion_freezes_neutral_and_disables_playback", page.locator("#actor-canvas").get_attribute("data-frame").endswith("anatomy-full-neutral.png") and page.locator("#play").is_disabled() and page.locator("#seek").is_disabled())
        for version in ("v11", "v8"):
            page.locator("#version").select_option(version)
            for role in ("P04", "P03", "P02"):
                page.locator("#character").select_option(role)
                ready(page, role)
                frame = page.evaluate("new URL(document.getElementById('actor-canvas').dataset.frame,location.href).href")
                family = ("actor-motion-20261115/p04-final-02" if version == "v11" else "actor-proportions-20261115/p04-final") if role == "P04" else "actor-rebuild-20261115/p03-final" if role == "P03" else "actor-proportions-20261115/p02-final"
                launcher = version.upper() if role == "P04" else "V10" if role == "P03" else "V8"
                check(f"{version}_{role}_exact_capture_source", family in frame)
                check(f"{version}_{role}_correct_launch_version", f"-Character {role} -Version {launcher}" in page.locator("#launch-command").inner_text())
                check(f"{version}_{role}_selection_visible", page.locator(f'.character-card[data-role="{role}"]').get_attribute("aria-pressed") == "true")
                check(f"{version}_{role}_four_poses_and_battle_images", page.locator("#pose-gallery img").count() == 4 and page.locator("#battle-gallery img").count() == 4)
                check(f"{version}_{role}_reduced_motion_preserved", page.locator("#play").is_disabled() and frame.endswith("anatomy-full-neutral.png"))
        for version in ("v11", "v8", "v11"):
            page.locator("#version").select_option(version)
        page.locator("#character").select_option("P04")
        ready(page, "P04")
        check("rapid_switch_discards_old_frames", "actor-motion-20261115/p04-final-02" in page.evaluate("new URL(document.getElementById('actor-canvas').dataset.frame,location.href).href"))
        page.locator("#reduce-motion").uncheck()
        ready(page)
        check("motion_restores_without_autoplay", not page.evaluate("playing") and not page.locator("#play").is_disabled())
        for sequence in ("fullbody-action-x4", "fullbody-action-x1", "fullbody-hit-x1", "command-00"):
            page.locator("#sequence").select_option(sequence)
            ready(page)
            page.locator("#seek").focus()
            page.locator("#seek").press("End")
            page.wait_for_function("!busy")
            check(sequence + "_keyboard_seek_renders_frame", bool(page.locator("#actor-canvas").get_attribute("data-frame")) and page.locator("#seek").input_value() == page.locator("#seek").get_attribute("max"))
        page.locator("#sequence").select_option("fullbody-action-x1")
        ready(page)
        page.locator("#seek").fill("760")
        page.wait_for_function("!busy")
        page.screenshot(path=str(OUT / "p04-viewer-1440.png"))
        for width in (1440, 960, 640, 390):
            page.set_viewport_size({"width": width, "height": 1000})
            page.wait_for_timeout(160)
            check(f"width_{width}_no_overflow", page.evaluate("document.documentElement.scrollWidth<=innerWidth"))
            check(f"width_{width}_main_controls_44px", page.locator("button,select").evaluate_all("els=>els.filter(e=>e.getClientRects().length).every(e=>e.getBoundingClientRect().height>=44)"))
            if width in (960, 390):
                page.screenshot(path=str(OUT / f"p04-viewer-{width}.png"))
        reduced = browser.new_page(viewport={"width": 960, "height": 800}, reduced_motion="reduce")
        reduced.goto(URL)
        ready(reduced, "P04")
        check("OS_reduced_motion_is_static_on_first_load", reduced.locator("#reduce-motion").is_checked() and reduced.locator("#play").is_disabled())
        browser_version = browser.version
        browser.close()
    inputs = [ROOT / "tools" / n for n in ("actor_party_review.html", "build_actor_motion_review.py", "verify_actor_motion_review.py", "build_actor_proportions_review.py")]
    inputs += [EV / "review/index.html", EV / "review/manifest.json"]
    report = {"passed": all(checks.values()) and not errors and not failed, "started_utc": started,
              "browser": browser_version, "url": URL, "checks": checks, "errors": errors, "failed_requests": failed,
              "inputs": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}}
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "failures": [k for k, v in checks.items() if not v], "errors": errors, "failed_requests": failed}, ensure_ascii=False))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
