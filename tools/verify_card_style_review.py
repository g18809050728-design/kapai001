"""Inspect the local card-art comparison in an isolated, temporary Edge session."""
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import time

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "artifacts/verification/card-style-20261115"
REVIEW = EVIDENCE / "review/index.html"
REPORT = EVIDENCE / "browser-check-01.json"


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = set()

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("href", "src", "data-old", "data-new", "data-game") and value:
                self.links.add(value)


def main():
    if REPORT.exists():
        raise SystemExit("Use a fresh evidence name; previous results are retained")
    report = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "Local review page only; isolated Edge; no personal browser or player saves",
        "review_sha256": hashlib.sha256(REVIEW.read_bytes()).hexdigest(),
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "checks": 0, "errors": [], "console_errors": [], "screenshots": [],
        "filter_counts": {}, "decoded_card_ids": [],
    }
    start = time.perf_counter()

    def check(value, message):
        report["checks"] += 1
        if not value:
            raise AssertionError(message)

    def ready(img):
        img.scroll_into_view_if_needed()
        for attempt in range(50):
            if img.evaluate("i => i.complete && i.naturalWidth > 0 && i.naturalHeight > 0"):
                return True
            img.page.wait_for_timeout(50)
        return False

    try:
        links = Links()
        links.feed(REVIEW.read_text(encoding="utf-8"))
        for ref in sorted(links.links):
            check((REVIEW.parent / ref).resolve().is_file(), "Missing local asset/link: " + ref)
        report["local_links"] = len(links.links)
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="msedge", headless=True)
            report["browser_version"] = browser.version
            context = browser.new_context(viewport={"width": 1280, "height": 800}, device_scale_factor=1)
            page = context.new_page()
            page.on("pageerror", lambda error: report["console_errors"].append(str(error)))
            page.on("console", lambda message: report["console_errors"].append(message.text) if message.type == "error" else None)
            page.goto(REVIEW.as_uri(), wait_until="load")
            check(page.locator("article").count() == 174, "Expected all 174 cards")
            check(page.locator("#count").inner_text() == "174 张", "Initial visible count")
            all_cards = page.locator("article")
            for index in range(174):
                card = all_cards.nth(index)
                check(ready(card.locator(".art img")), "Browser cannot decode card " + str(index))
                report["decoded_card_ids"].append(card.locator("small").inner_text())
            check(len(set(report["decoded_card_ids"])) == 174, "Duplicate review card IDs")
            for dimensions in [(1280, 800), (960, 600)]:
                page.set_viewport_size({"width": dimensions[0], "height": dimensions[1]})
                for label, owner, count in [
                    ("林序 · 调试实践", "P01", 40),
                    ("许知微 · 论文研究", "P02", 42),
                    ("沈见章 · 证据追问", "P03", 40),
                    ("唐以宁 · 小组协作", "P04", 40),
                    ("公共", "C", 12),
                ]:
                    page.get_by_role("button", name=label, exact=True).click()
                    page.keyboard.press("Control+Home")
                    cards = page.locator("article:not(.hidden)")
                    check(cards.count() == count, f"{dimensions} {owner} count")
                    check(page.locator("#count").inner_text() == f"{count} 张", "Visible count label")
                    check(cards.evaluate_all("els => els.every(a => a.dataset.owner === '" + owner + "')"), "Filter identity")
                    report["filter_counts"][owner] = count
                    check(ready(cards.first.locator(".art img")), "Filtered first art loads")
                page.get_by_role("button", name="全部", exact=True).click()
                search = page.get_by_placeholder("搜索牌名 / ID")
                search.fill("橡皮鸭讲解")
                page.keyboard.press("Control+Home")
                cards = page.locator("article:not(.hidden)")
                check(cards.count() == 1 and cards.first.locator("small").inner_text() == "R3-P01-12", "Search by card name")
                art = cards.first.locator(".art img")
                for label, attribute in [("改前", "data-old"), ("新插画", "data-new"), ("游戏卡面", "data-game")]:
                    cards.first.get_by_role("button", name=label, exact=True).click()
                    check(art.get_attribute("src") == art.get_attribute(attribute), "Switch " + label)
                    check(ready(art), "Decode " + label)
                art.click()
                check(page.locator("dialog[open]").count() == 1, "Zoom opens")
                check(ready(page.locator("dialog img")), "Zoom art loads")
                screenshot = f"review-zoom-{dimensions[0]}.png"
                page.screenshot(path=str(EVIDENCE / screenshot))
                report["screenshots"].append(screenshot)
                page.get_by_role("button", name="关闭", exact=True).click()
                check(page.locator("dialog[open]").count() == 0, "Zoom closes")
                search.fill("r3-p03-40")
                check(page.locator("article:not(.hidden)").count() == 1, "Search by case-insensitive ID")
                search.fill("不存在的卡牌12345")
                check(page.locator("#count").inner_text() == "0 张", "Empty search result")
                search.fill("")
                page.get_by_role("button", name="全部", exact=True).click()
                page.keyboard.press("Control+Home")
                check(page.locator("article:not(.hidden)").count() == 174, "Reset to all")
                check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"), "No horizontal overflow")
                check(page.locator("nav button").evaluate_all("els => els.every(b => b.getBoundingClientRect().height >= 44)"), "Main filter targets >=44px")
                screenshot = f"review-{dimensions[0]}.png"
                page.screenshot(path=str(EVIDENCE / screenshot))
                report["screenshots"].append(screenshot)
            check(not report["console_errors"], "Browser errors")
            context.close()
            browser.close()
    except Exception as error:
        report["errors"].append(repr(error))
    report["seconds"] = time.perf_counter() - start
    report["ok"] = not report["errors"] and not report["console_errors"]
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "decoded_card_ids"}, ensure_ascii=False))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
