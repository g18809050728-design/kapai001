"""Build the map review and bind this batch's actual checks to current source bytes."""
from datetime import datetime, timezone
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
from urllib.parse import quote, unquote

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/map-material-feedback-20261114"
RUNS = ROOT / "artifacts/verification/four-year-20261104"
FINAL = {"ui": "map-material-full-ui-final-20261114", "visual": "map-material-visual-final-20261114", "import": "map-material-import-final-20261114"}
NATIVE = ROOT / "artifacts/verification/map-card-feedback-20261114/map-material-feedback-final-20261114"
FROZEN = "output/交大四年_DDL战争_文档提交包_20261114.zip"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def relative(path):
    return path.relative_to(ROOT).as_posix()


def review():
    target = OUT / "review"
    target.mkdir(exist_ok=True)
    pictures = sorted((OUT / "screens-final").glob("*.png")) + sorted((OUT / "screens-dense-final").glob("*.png"))
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 17)
    for start in range(0, len(pictures), 6):
        sheet = Image.new("RGB", (1240, 1320), "#171e23")
        painter = ImageDraw.Draw(sheet)
        for index, path in enumerate(pictures[start:start+6]):
            with Image.open(path) as source:
                bitmap = source.convert("RGB")
            bitmap.thumbnail((600, 390))
            x, y = 10 + index % 2 * 620, 10 + index // 2 * 440
            sheet.paste(bitmap, (x + (600 - bitmap.width) // 2, y))
            painter.text((x, y + 396), path.name, font=font, fill="#ead8b4")
        sheet.save(target / f"contact-{start//6+1:02d}.jpg", quality=94)

    def cards(paths):
        result = []
        for path in paths:
            address = html.escape(quote(os.path.relpath(path, target).replace(os.sep, "/"), safe="/"))
            label = html.escape(path.name)
            result.append(f'<figure><a href="{address}"><img loading="lazy" src="{address}" alt="{label}"></a><figcaption>{label}</figcaption></figure>')
        return '<div class="grid">' + "\n".join(result) + '</div>'

    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>地图材质 · 实渲对照</title><style>
body{max-width:1500px;margin:auto;padding:24px;background:#171e23;color:#eadbc1;font:16px/1.6 system-ui,sans-serif}a{color:#e9c783}h1{font-size:26px}h2{margin-top:36px;font-size:21px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}figure{margin:0;padding:10px;background:#24333b;border:1px solid #877453}img{display:block;max-width:100%;height:auto;margin:auto}figcaption{overflow-wrap:anywhere;margin-top:8px}nav{display:flex;flex-wrap:wrap;gap:20px}@media(max-width:800px){body{padding:14px}.grid{grid-template-columns:1fr}}
</style><h1>地图纸面、墨印与情境导航 · 2026-11-14</h1>
<p>原创纤维纸张、折痕、不齐边缘和墨印节点；虚线连接未来路线，实线记录已走路线，朱线预览后续三层。地图页仅牌组/菜单，M切换本页概览；房间和战斗保留只读地图。</p>
<p>Godot真实渲染：1280×800 / 960×600，100 / 125 / 150%字号。后期图使用生产生成器的第四学年受控视图，未冒充自然通关。官方归档为注明日期的开发/宣传材料，未声称最新构建。人物继续暂停；AI看图不是用户审美或整版验收。</p>
<nav><a href="#official">官方材料</a><a href="#before">修改前</a><a href="#map">当前地图</a><a href="#dense">第四学年</a><a href="#roommap">房间只读全图</a><a href="#navigation">菜单及其他页面</a></nav>'''
    page += '<h2 id="official">官方地图归档</h2>' + cards([ROOT / "ui-plan/references/slay-the-spire-2" / name for name in ["map_qol.jpg", "map-rest-sequence.jpg"]])
    page += '<h2 id="before">本批修改前</h2>' + cards([ROOT / "artifacts/verification/ui-navigation-feedback-20261114/screens-current" / name for name in ["map-bar-1280-100.png", "map-bar-960-150.png"]])
    groups = [("map", "当前地图与概览", lambda p: p.name.startswith(("map-bar", "map-overview"))),
              ("dense", "第四学年密集路线", lambda p: p.name.startswith("year-four")),
              ("roommap", "房间中的只读地图", lambda p: p.name.startswith("club-map")),
              ("navigation", "菜单与其他页面回归", lambda p: p.name.startswith(("battle-", "club-bar", "club-menu", "map-menu")))]
    for anchor, caption, predicate in groups:
        page += f'<h2 id="{anchor}">{caption}</h2>' + cards([p for p in pictures if predicate(p)])
    (target / "index.html").write_text(page, encoding="utf-8")
    missing = [a for a in re.findall(r'(?:href|src)="([^"]+)"', page) if not a.startswith("#") and not (target / unquote(a)).resolve().is_file()]
    write(OUT / "gallery-links.json", {"missing": missing, "screens": len(pictures)})
    return pictures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--review-only", action="store_true")
    args = parser.parse_args()
    pictures = review()
    if args.review_only:
        print(json.dumps({"screens": len(pictures), "review": relative(OUT / "review/index.html")}))
        return 0
    checks = []

    def check(name, passed, details=None):
        checks.append({"name": name, "passed": bool(passed), "details": details})

    before = read(OUT / "before.json")["files"]
    for key, run in FINAL.items():
        summary = read(RUNS / run / "summary.json")
        check(key + "_actual_exit_and_errors", all(row["exit_code"] == 0 and row["engine_errors"] == 0 for row in summary), summary)
        recorded = read(RUNS / run / "input_hashes.json")
        mismatches = [p for p, h in recorded.items() if not (ROOT / p).is_file() or digest(ROOT / p) != h]
        check(key + "_recorded_inputs_current", not mismatches, mismatches)
    native = read(NATIVE / "result.json")
    check("native_36_cases", len(native["cases"]) == 36 and not native["failures"] and native["engine_exit_code"] == 0 and native["engine_errors"] == 0)
    native_inputs = read(NATIVE / "input_hashes.json")
    check("native_inputs_current", all((ROOT / p).is_file() and digest(ROOT / p) == h for p, h in native_inputs.items()))
    captures = read(OUT / "screens-final/checks.json")
    check("navigation_visual_checks", not captures["failures"], {"checks": captures["checks"], "failures": captures["failures"]})
    dense = read(OUT / "screens-dense-final/capture.json")
    check("dense_year_four_render", dense["nodes"] >= 40 and dense["view_unchanged"] and len(dense["captures"]) == 12)
    check("60_actual_screens", len(pictures) == 60 and len(captures["captures"]) == 48)
    for path in pictures:
        width = int(path.stem.split("-")[-2])
        with Image.open(path) as bitmap:
            check("dimensions_" + path.name, bitmap.size == (width, 800 if width == 1280 else 600))
    frozen = [p for p in before if p.startswith(("docs/提交文档_20261114/", "output/文档提交_20261114/")) or p == FROZEN]
    check("frozen_package_bytes", all((ROOT / p).is_file() and digest(ROOT / p) == before[p] for p in frozen), len(frozen))
    for prefix in ["data/", "assets/", "src/app/", "src/battle/", "src/common/", "src/content/", "src/run/", "src/storage/"]:
        changed = [p for p, h in before.items() if p.startswith(prefix) and (not (ROOT / p).is_file() or digest(ROOT / p) != h)]
        check("existing_bytes_unchanged_" + prefix, not changed, changed)
    added_art = [relative(p) for p in (ROOT / "assets").rglob("*") if p.is_file() and relative(p) not in before]
    check("new_assets_only_original_paper", all(p.startswith("assets/ui/map/") for p in added_art), added_art)
    paper = read(ROOT / "assets/ui/map/source.json")
    check("original_paper_hash_and_dimensions", digest(ROOT / "assets/ui/map" / paper["asset"]) == paper["sha256"] and paper["dimensions"] == [1024, 2048] and not paper["external_images"] and not paper["game_rng_used"])
    for path in ["src/ui/card_face_view.gd", "src/ui/card_display_model.gd", "src/ui/ui_labels.json", "src/ui/route_overlay.gd", "src/ui/battle_screen.gd"]:
        check("preserved_" + path, digest(ROOT / path) == before[path])
    check("review_links", not read(OUT / "gallery-links.json")["missing"])
    visual = read(OUT / "visual-review.json")
    check("actual_visual_review", visual.get("reviewed_screens") == 60 and visual.get("human_accepted") is False)
    state_path = ROOT / "docs/baselines/current-state.json"
    state = read(state_path)
    state["evidence"].update({"current_ui": relative(RUNS / FINAL["ui"] / "summary.json"), "current_visual": relative(RUNS / FINAL["visual"] / "summary.json"), "current_import": relative(RUNS / FINAL["import"] / "summary.json"),
        "map_material_checks": relative(OUT / "screens-final/checks.json"), "map_material_native": relative(NATIVE / "result.json"), "map_material_consistency": relative(OUT / "consistency.json"), "map_material_review": relative(OUT / "review/index.html")})
    sources = set(state["source_sha256"])
    sources.update(relative(p) for folder in ["src", "tests"] for p in (ROOT / folder).rglob("*.gd"))
    sources.update(["tools/prepare_map_material_feedback.py", "tools/build_map_paper.py", "tools/capture_map_material.gd", "tools/record_map_material_feedback.py", "assets/ui/map/parchment-fiber-v1.png", "assets/ui/map/source.json",
        "docs/plans/2026-11-14-map-material-feedback-design.md", "docs/地图质感与冗余入口修正_20261114.md"])
    state["source_sha256"] = {p: digest(ROOT / p) for p in sorted(sources)}
    state["ui_navigation"]["toolbar"] = "shared physical targets; map page deck/settings only, M toggles existing overview; other rooms and battle retain read-only map"
    state["map_material"] = {"paper": "assets/ui/map/parchment-fiber-v1.png", "origin": "original procedural texture and ink silhouettes", "character_art": "paused", "human_visual_acceptance": "pending"}
    write(state_path, state)
    check("snapshot_source_hashes", all(digest(ROOT / p) == h for p, h in state["source_sha256"].items()))
    report = {"utc": datetime.now(timezone.utc).isoformat(), "checks": checks, "failures": [c for c in checks if not c["passed"]], "source_hashes": len(state["source_sha256"]), "screen_count": len(pictures), "scope": "Observed implementation evidence; not whole G0/G6/G8 or human visual acceptance"}
    write(OUT / "consistency.json", report)
    print(json.dumps({"checks": len(checks), "failures": report["failures"], "screens": len(pictures), "visual_checks": captures["checks"], "snapshot_sources": len(state["source_sha256"])}, ensure_ascii=False))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
