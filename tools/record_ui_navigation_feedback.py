"""Build this batch's review and verify actual evidence; never changes game data."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import html
import json
import os
from pathlib import Path
import re
from urllib.parse import quote, unquote

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/ui-navigation-feedback-20261114"
RUNS = ROOT / "artifacts/verification/four-year-20261104"
FINAL = {
    "ui": "ui-navigation-full-ui-accepted-20261114",
    "visual": "ui-navigation-visual-current-20261114",
    "import": "ui-navigation-import-final-20261114",
}
NATIVE = ROOT / "artifacts/verification/map-card-feedback-20261114/ui-navigation-feedback-final-20261114"
SCREENS = OUT / "screens-current"
FROZEN = "output/交大四年_DDL战争_文档提交包_20261114.zip"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def relative(path):
    return path.relative_to(ROOT).as_posix()


def build_review():
    review = OUT / "review"
    review.mkdir(exist_ok=True)
    pictures = sorted(SCREENS.glob("*.png"))
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 17)
    for start in range(0, len(pictures), 6):
        canvas = Image.new("RGB", (1240, 1320), "#171e23")
        painter = ImageDraw.Draw(canvas)
        for number, path in enumerate(pictures[start:start + 6]):
            with Image.open(path) as source:
                bitmap = source.convert("RGB")
            bitmap.thumbnail((600, 390))
            x, y = 10 + number % 2 * 620, 10 + number // 2 * 440
            canvas.paste(bitmap, (x + (600 - bitmap.width) // 2, y))
            painter.text((x, y + 396), path.name, font=font, fill="#ead8b4")
        canvas.save(review / f"contact-{start // 6 + 1:02d}.jpg", quality=94)

    def cards(paths):
        rows = []
        for path in paths:
            address = html.escape(quote(os.path.relpath(path, review).replace(os.sep, "/"), safe="/"))
            label = html.escape(path.name)
            rows.append(f'<figure><a href="{address}"><img loading="lazy" src="{address}" alt="{label}"></a><figcaption>{label}</figcaption></figure>')
        return '<div class="grid">' + "\n".join(rows) + "</div>"

    references = [ROOT / "ui-plan/references/slay-the-spire-2" / p for p in ["topbar_qol.jpg", "map_qol.jpg"]]
    previous = [ROOT / "artifacts/verification/ui-flow-feedback-20261114/screens-final" / p for p in ["toolbar-1280-100.png", "toolbar-960-150.png"]]
    text = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>地图再次点击与顶栏 · 实渲对照</title><style>
body{margin:0 auto;max-width:1500px;padding:24px;background:#171e23;color:#eadbc1;font:16px/1.6 system-ui,sans-serif}a{color:#e9c783}h1{font-size:26px}h2{margin-top:36px;font-size:21px}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}figure{margin:0;padding:10px;background:#24333b;border:1px solid #877453;border-radius:5px}img{display:block;max-width:100%;height:auto;margin:auto}figcaption{overflow-wrap:anywhere;margin-top:8px}nav{display:flex;flex-wrap:wrap;gap:20px}@media(max-width:800px){body{padding:14px}.grid{grid-template-columns:1fr}}
</style><h1>地图再次点击与顶栏深化 · 2026-11-14</h1>
<p>Godot真实渲染：1280×800 / 960×600，100 / 125 / 150%字号，战斗、地图与受控社团房间。右侧地图/牌组/齿轮三入口；菜单分组、滚动与固定关闭。点击图片查看原图。</p>
<p>地图首次预选、慢速再次点击进入；全图浮层只读。官方图为此前归档的开发材料，并非最新版规格。人物继续暂停；本页是实现及AI观察证据，不是用户最终审美或整版验收。</p>
<nav><a href="#reference">官方归档</a><a href="#before">上批顶栏</a><a href="#battle">当前战斗</a><a href="#map">当前地图</a><a href="#club">当前社团</a></nav>'''
    text += '<h2 id="reference">官方归档：导航结构与地图</h2>' + cards(references)
    text += '<h2 id="before">上批顶栏</h2>' + cards(previous)
    for prefix, title in [("battle", "战斗"), ("map", "地图"), ("club", "社团房间")]:
        text += f'<h2 id="{prefix}">{title} · 顶栏与菜单</h2>' + cards([p for p in pictures if p.name.startswith(prefix + "-")])
    (review / "index.html").write_text(text, encoding="utf-8")
    missing = []
    for address in re.findall(r'(?:href|src)="([^"]+)"', text):
        if not address.startswith("#") and not (review / unquote(address)).resolve().is_file():
            missing.append(address)
    write(OUT / "gallery-links.json", {"local_references": len(re.findall(r'(?:href|src)="([^"]+)"', text)), "missing": missing})
    return pictures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--review-only", action="store_true")
    args = parser.parse_args()
    pictures = build_review()
    if args.review_only:
        print(json.dumps({"screens": len(pictures), "review": relative(OUT / "review/index.html")}))
        return 0
    checks = []

    def check(name, passed, details=None):
        checks.append({"name": name, "passed": bool(passed), "details": details})

    before = read(OUT / "before.json")["files"]
    for key, run in FINAL.items():
        summary = read(RUNS / run / "summary.json")
        check(key + "_actual_exit_and_errors", all(r["exit_code"] == 0 and r["engine_errors"] == 0 for r in summary), summary)
        recorded = read(RUNS / run / "input_hashes.json")
        mismatches = [p for p, h in recorded.items() if not (ROOT / p).is_file() or digest(ROOT / p) != h]
        check(key + "_recorded_inputs_still_current", not mismatches, mismatches)
    native = read(NATIVE / "result.json")
    check("native_36_cases_actual_exit_and_errors", len(native["cases"]) == 36 and not native["failures"] and native["engine_exit_code"] == 0 and native["engine_errors"] == 0)
    native_inputs = read(NATIVE / "input_hashes.json")
    check("native_recorded_inputs_still_current", all((ROOT / p).is_file() and digest(ROOT / p) == h for p, h in native_inputs.items()))
    captures = read(SCREENS / "checks.json")
    check("navigation_visual_checks", not captures["failures"] and captures["checks"] > 450, {"checks": captures["checks"], "failures": captures["failures"]})
    check("36_actual_screens", len(pictures) == 36 and len(captures["captures"]) == 36)
    for path in pictures:
        width = int(path.stem.split("-")[-2])
        with Image.open(path) as bitmap:
            check("dimensions_" + path.name, bitmap.size == (width, 800 if width == 1280 else 600))
    frozen = [p for p in before if p.startswith(("docs/提交文档_20261114/", "output/文档提交_20261114/")) or p == FROZEN]
    check("frozen_package_bytes_preserved", all((ROOT / p).is_file() and digest(ROOT / p) == before[p] for p in frozen), len(frozen))
    check("frozen_zip_known_sha256", digest(ROOT / FROZEN) == "8aa7e77e5bb5824ce0db428815695c8b822089a28b4b13534a8b8e983b10d232")
    for prefix in ["data/", "assets/", "src/app/", "src/battle/", "src/common/", "src/content/", "src/run/", "src/storage/"]:
        changed = [p for p, h in before.items() if p.startswith(prefix) and (not (ROOT / p).is_file() or digest(ROOT / p) != h)]
        check("unchanged_" + prefix, not changed, changed)
    for path in ["src/ui/card_face_view.gd", "src/ui/card_display_model.gd", "src/ui/ui_labels.json", "src/ui/route_overlay.gd"]:
        check("preserved_" + path, digest(ROOT / path) == before[path])
    links = read(OUT / "gallery-links.json")
    check("review_links_exist", not links["missing"], links)
    visual = read(OUT / "visual-review.json")
    check("actual_visual_review_recorded", visual.get("reviewed_all_36") is True and visual.get("human_accepted") is False)
    state_path = ROOT / "docs/baselines/current-state.json"
    state = read(state_path)
    state["project_date"] = "2026-11-14"
    state["evidence"].update({"current_ui": relative(RUNS / FINAL["ui"] / "summary.json"), "current_visual": relative(RUNS / FINAL["visual"] / "summary.json"), "current_import": relative(RUNS / FINAL["import"] / "summary.json"), "ui_navigation_checks": relative(SCREENS / "checks.json"), "ui_navigation_native": relative(NATIVE / "result.json"), "ui_navigation_consistency": relative(OUT / "consistency.json")})
    sources = set(state["source_sha256"])
    sources.update(relative(p) for folder in ["src", "tests"] for p in (ROOT / folder).rglob("*.gd"))
    sources.update(["tools/prepare_ui_navigation_feedback.py", "tools/record_ui_navigation_feedback.py", "tools/verify_ui_navigation.gd", "docs/plans/2026-11-14-ui-navigation-feedback-design.md", "docs/地图再次点击与顶栏深化_20261114.md"])
    state["source_sha256"] = {p: digest(ROOT / p) for p in sorted(sources)}
    state["ui_navigation"] = {"map_click": "first click preview; repeat selected reachable node enters once without OS timing; full-map overlay read-only", "toolbar": "shared physical 64x56 main targets; map/deck/settings; grouped menu, focus/input isolation", "character_art": "paused", "human_visual_acceptance": "pending"}
    write(state_path, state)
    check("snapshot_source_hashes_current", all(digest(ROOT / p) == h for p, h in state["source_sha256"].items()))
    report = {"utc": datetime.now(timezone.utc).isoformat(), "checks": checks, "failures": [c for c in checks if not c["passed"]], "source_hashes": len(state["source_sha256"]), "screen_count": len(pictures), "scope": "Observed implementation evidence; not whole G0/G6/G8 or human visual acceptance"}
    write(OUT / "consistency.json", report)
    print(json.dumps({"checks": len(checks), "failures": report["failures"], "screens": len(pictures), "visual_checks": captures["checks"], "snapshot_sources": len(state["source_sha256"])}, ensure_ascii=False))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
