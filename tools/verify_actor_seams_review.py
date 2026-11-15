"""Exercise the isolated offline v5/v6 review and inspect repaired details."""
from pathlib import Path
import json

from playwright.sync_api import sync_playwright
import verify_actor_refinement_review as shared

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/actor-seams-20261115/review-browser"
shared.OUT = OUT
shared.URL = (OUT.parent / "review/index.html").as_uri()


def main():
    shared.main()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="msedge", headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 1150})
        page.goto(shared.URL)
        page.wait_for_function("ready === true")
        checks = {"default_crop_fullbody": page.locator("#crop").input_value() == "hero",
                  "local_repairs_first": page.locator("#shoulder").bounding_box()["y"] < page.locator("#viewer").bounding_box()["y"],
                  "four_large_engine_images": page.locator(".portrait-grid img").count() == 4,
                  "all_visible_stills_loaded": page.locator("#shoulder img").evaluate_all("els=>els.every(e=>e.complete&&e.naturalWidth>0)")}
        page.screenshot(path=str(OUT / "repairs-first-1440.png"), full_page=False)
        page.locator("#contacts").scroll_into_view_if_needed()
        page.screenshot(path=str(OUT / "contacts-1440.png"), full_page=False)
        page.set_viewport_size({"width": 640, "height": 1050})
        page.locator("#shoulder").scroll_into_view_if_needed()
        page.screenshot(path=str(OUT / "repairs-first-640.png"), full_page=False)
        checks["small_layout_no_overflow"] = page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        browser.close()
    report = json.loads((OUT / "report.json").read_text(encoding="utf-8"))
    report["checks"].update(checks)
    report["passed"] = report["passed"] and all(checks.values())
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"detail_checks": checks, "passed": report["passed"]}))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
