"""Exercise the existing timestamp player plus real V7/V8 version switching."""
from pathlib import Path
import hashlib
import json

from playwright.sync_api import sync_playwright
import verify_actor_party_review as base

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-proportions-20261115"


def main():
    base.EV = EV
    base.OUT = EV / "review-browser"
    base.URL = (EV / "review/index.html").as_uri()
    base.main()
    checks, errors = {}, []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="msedge", headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 1100}, reduced_motion="no-preference")
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("requestfailed", lambda request: errors.append(request.url))
        page.goto(base.URL)
        page.wait_for_function("ready && !busy")
        checks["default_is_corrected_v8"] = page.locator("#version").input_value() == "v8"
        checks["three_equal_scale_comparisons_exist"] = page.locator("#comparison figure").count() == 3
        for version, folder in (("v7", "actor-party-20261115"), ("v8", "actor-proportions-20261115")):
            page.locator("#version").select_option(version)
            page.wait_for_function("([v])=>ready && !busy && version===v", arg=[version])
            for role in ("P02", "P03", "P04"):
                page.locator("#character").select_option(role)
                page.wait_for_function("([r])=>ready && !busy && document.getElementById('actor-canvas').dataset.role===r", arg=[role])
                frame_url = page.evaluate("new URL(document.getElementById('actor-canvas').dataset.frame, location.href).href")
                checks[f"{version}_{role}_canvas_uses_correct_run"] = folder in frame_url
                checks[f"{version}_{role}_launcher_selects_exact_version"] = ("-Version " + version.upper()) in page.locator("#launch-command").inner_text()
            checks[version + "_roster_uses_selected_version"] = all(folder in value for value in page.locator(".character-card img").evaluate_all("els=>els.map(e=>e.src)"))
            if version == "v8":
                page.locator("#characters").scroll_into_view_if_needed()
                page.screenshot(path=str(base.OUT / "corrected-lineup-1440.png"))
        page.locator("#motion").scroll_into_view_if_needed()
        page.locator("#reduce-motion").check()
        for version in ("v7", "v8", "v7", "v8"):
            page.locator("#version").select_option(version)
        page.locator("#character").select_option("P03")
        page.wait_for_function("ready && !busy && reduced && document.getElementById('actor-canvas').dataset.role==='P03'")
        current = page.locator("#actor-canvas").get_attribute("data-frame")
        frame_url = page.evaluate("new URL(document.getElementById('actor-canvas').dataset.frame, location.href).href")
        checks["rapid_version_changes_drop_stale_frames"] = "actor-proportions-20261115/p03-final" in frame_url
        checks["version_switch_preserves_reduced_motion"] = current.endswith("anatomy-full-neutral.png") and page.locator("#play").is_disabled()
        page.screenshot(path=str(base.OUT / "p03-corrected-neck-1440.png"))
        page.locator("#comparison").scroll_into_view_if_needed()
        page.wait_for_function("Array.from(document.querySelectorAll('#comparison img')).every(i=>i.complete && i.naturalWidth===1200 && i.naturalHeight===780)")
        checks["comparisons_render_exact_full_canvas_size"] = True
        page.screenshot(path=str(base.OUT / "before-after-1440.png"))
        browser.close()
    path = base.OUT / "report.json"
    report = json.loads(path.read_text(encoding="utf-8"))
    report["checks"].update(checks)
    report["errors"].extend(errors)
    report["passed"] = report["passed"] and all(checks.values()) and not errors
    paths = [ROOT / p for p in ("tools/build_actor_proportions_review.py", "tools/verify_actor_proportions_review.py")]
    report["inputs"].update({p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]), "failures": [k for k, ok in report["checks"].items() if not ok], "errors": report["errors"]}, ensure_ascii=False))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
