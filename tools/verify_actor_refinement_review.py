"""Exercise the offline review with actual isolated Chromium controls."""
from pathlib import Path
import json
import time

from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/actor-rig-refinement-20261115/review-browser"
URL = (OUT.parent / "review/index.html").as_uri()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = {"errors": [], "failed_requests": [], "layouts": [], "checks": {}, "playback": {}}
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="msedge", headless=True)
        context = browser.new_context(viewport={"width": 1440, "height": 1150})
        page = context.new_page()
        page.on("pageerror", lambda error: report["errors"].append(str(error)))
        page.on("requestfailed", lambda request: report["failed_requests"].append({"url": request.url, "failure": request.failure}))
        page.goto(URL)
        page.wait_for_function("ready === true")

        def pause():
            if page.evaluate("playing"):
                page.locator("#play").click()

        pause()
        for width, height in [(1440, 1150), (640, 1050)]:
            page.set_viewport_size({"width": width, "height": height})
            page.screenshot(path=str(OUT / f"layout-{width}.png"), full_page=False)
            report["layouts"].append(page.evaluate("""() => ({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,
                controls:[...document.querySelectorAll('button,select')].map(e=>({id:e.id,width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height}))})"""))
        report["checks"]["layouts_no_horizontal_overflow"] = all(r["scrollWidth"] <= r["width"] for r in report["layouts"])
        report["checks"]["buttons_and_selects_at_least_44px"] = all(c["height"] >= 44 for r in report["layouts"] for c in r["controls"])
        page.set_viewport_size({"width": 1440, "height": 1150})
        names = page.locator("#sequence option").evaluate_all("els=>els.map(e=>e.value)")
        for name in names:
            page.locator("#sequence").select_option(name)
            page.wait_for_function("ready === true && current === " + json.dumps(name))
            report["checks"]["sequence_" + name] = page.evaluate("data[current].before.length > 0 && data[current].after.length > 0")
        for mode, dims in [("hero", [320, 355]), ("enemy", [320, 355]), ("stage", [1190, 390]), ("close", [600, 355])]:
            page.locator("#crop").select_option(mode)
            page.wait_for_function("document.getElementById('after').width === " + str(dims[0]))
            report["checks"]["crop_" + mode] = page.locator("#after").evaluate("e=>[e.width,e.height]") == dims
        page.locator("#sequence").select_option("idle")
        page.wait_for_function("ready === true && current === 'idle'")
        for speed, expected in [("1", 450), ("0.25", 112.5)]:
            page.locator("#speed").select_option(speed)
            page.locator("#replay").click()
            initial = page.evaluate("({ms,now:performance.now()})")
            page.wait_for_timeout(450)
            final = page.evaluate("({ms,now:performance.now()})")
            elapsed = final["ms"] - initial["ms"]
            real = final["now"] - initial["now"]
            report["playback"][speed] = {"captured_ms_advanced": elapsed, "wall_ms": real}
            report["checks"]["timestamp_rate_" + speed] = abs(elapsed - real * float(speed)) < 90
            pause()
        stopped = page.evaluate("ms")
        page.wait_for_timeout(300)
        report["checks"]["pause_has_no_time_drift"] = page.evaluate("ms") == stopped
        seek = page.locator("#seek")
        seek.focus()
        seek.press("End")
        report["checks"]["keyboard_seek_end_exact"] = page.evaluate("ms === length() && !playing")
        seek.press("Home")
        report["checks"]["keyboard_seek_home_exact"] = page.evaluate("ms === 0 && !playing")
        page.locator("#play").focus()
        page.keyboard.press("Space")
        report["checks"]["keyboard_play_button"] = page.evaluate("playing")
        pause()
        # Observe a real command at successive rendered moments, not a CSS mock.
        page.locator("#sequence").select_option("command-02")
        page.wait_for_function("ready === true && current === 'command-02'")
        page.locator("#speed").select_option("1")
        page.locator("#crop").select_option("stage")
        page.locator("#replay").click()
        samples = []
        for ordinal in range(7):
            page.wait_for_timeout(140)
            state = page.evaluate("({ms,before:document.getElementById('before-label').textContent,after:document.getElementById('after-label').textContent})")
            image_path = OUT / f"observed-command-02-{ordinal:02}.png"
            page.locator("#after").screenshot(path=str(image_path))
            samples.append({"image": image_path.name, **state})
        pause()
        report["observed_continuous_command"] = samples
        page.locator("#crop").select_option("hero")
        page.screenshot(path=str(OUT / "hero-comparison.png"), full_page=False)
        reduced = browser.new_context(viewport={"width": 1280, "height": 900}, reduced_motion="reduce")
        rp = reduced.new_page()
        rp.goto(URL)
        rp.wait_for_function("ready === true")
        report["checks"]["reduced_motion_starts_paused"] = rp.evaluate("!playing")
        reduced.close()
        context.close()
        browser.close()
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 17)
    sheet = Image.new("RGB", (1200, 4 * 232), "#162a33")
    for i, sample in enumerate(samples):
        im = Image.open(OUT / sample["image"]).convert("RGB")
        im.thumbnail((580, 191))
        x, y = (i % 2) * 600 + 8, (i // 2) * 232 + 28
        sheet.paste(im, (x, y))
        ImageDraw.Draw(sheet).text((x, y - 24), f"浏览器连续播放 · {sample['ms']:.0f} ms", font=font, fill="white")
    sheet.save(OUT / "observed-command-02-strip.jpg", quality=94)
    report["passed"] = all(report["checks"].values()) and not report["errors"] and not report["failed_requests"]
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "checks": report["checks"], "errors": report["errors"], "failed_requests": report["failed_requests"]}, ensure_ascii=False))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
