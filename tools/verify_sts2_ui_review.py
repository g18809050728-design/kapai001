"""Check the offline comparison using the locally installed Python Playwright."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import sys

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/sts2-ui-rebuild-20261114"
PAGE = ROOT / "output/sts2-ui-rebuild-20261114/preview.html"


def main():
    checks, errors = [], []
    result = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "command": [sys.executable, "tools/verify_sts2_ui_review.py"],
        "python": sys.version,
        "os": platform.platform(),
        "page_sha256": hashlib.sha256(PAGE.read_bytes()).hexdigest(),
        "checks": checks,
        "errors": errors,
    }

    def check(condition, name):
        checks.append({"name": name, "passed": bool(condition)})

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            result["browser"] = browser.version
            page = browser.new_page(viewport={"width": 1440, "height": 1100})
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(PAGE.as_uri())
            options = page.locator("#screen option").evaluate_all("nodes => nodes.map(n => n.value)")
            result["screen_count"] = len(options)
            check(len(options) == 74, "all 74 real captures are selectable")
            for value in options:
                page.select_option("#screen", value)
                page.wait_for_function("() => [...document.images].every(i => i.complete && i.naturalWidth > 0)")
                check(page.locator("#actual-label").text_content() == value, f"screen label {value}")
                images = page.locator("img").evaluate_all("nodes => nodes.map(n => ({width:n.naturalWidth, alt:n.alt}))")
                check(all(i["width"] > 0 and len(i["alt"]) > 3 for i in images), f"images and labels {value}")
                check(page.locator("#full").get_attribute("href") == page.locator("#actual").get_attribute("src"), f"original image link {value}")
            page.select_option("#screen", "battle-1280")
            page.get_by_role("button", name="960 × 600").click()
            check(page.locator("#screen").input_value() == "battle-960", "960 size selects corresponding game capture")
            check(page.locator('[data-width="960"]').get_attribute("aria-pressed") == "true", "size has accessible selected state")
            page.get_by_role("button", name="1280 × 800").click()
            check(page.locator("#screen").input_value() == "battle-1280", "1280 size selects corresponding game capture")
            page.wait_for_function("() => [...document.images].every(i => i.complete && i.naturalWidth > 0)")
            page.screenshot(path=str(OUT / "review-desktop.png"), full_page=True)
            page.set_viewport_size({"width": 390, "height": 844})
            check(page.evaluate("document.documentElement.scrollWidth <= innerWidth"), "390px page has no horizontal overflow")
            page.screenshot(path=str(OUT / "review-mobile.png"), full_page=True)
            page.locator("#screen").focus()
            page.keyboard.press("ArrowDown")
            check(page.locator("#screen").evaluate("n => n === document.activeElement"), "keyboard selection retains focus")
            check(not errors, "no browser script errors")
            browser.close()
    except Exception as error:
        errors.append(f"{type(error).__name__}: {error}")
    result["passed"] = bool(checks) and all(c["passed"] for c in checks) and not errors
    result["exit_code"] = 0 if result["passed"] else 1
    (OUT / "review-browser-checks.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"checks": len(checks), "passed": result["passed"], "errors": errors}, ensure_ascii=False))
    return result["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
