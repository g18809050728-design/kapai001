"""Bind the composition review to actual runs and the current source bytes."""
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
OUT = ROOT / "artifacts/verification/map-composition-feedback-20261114"
PREVIOUS = ROOT / "artifacts/verification/map-material-feedback-20261114"
RUNS = ROOT / "artifacts/verification/four-year-20261104"
FINAL = {"ui": "map-composition-full-ui-final-20261114", "visual": "map-composition-visual-final-20261114", "import": "map-composition-import-final-20261114"}
NATIVE = ROOT / "artifacts/verification/map-card-feedback-20261114/map-composition-feedback-final-20261114"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return path.relative_to(ROOT).as_posix()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def review():
    target = OUT / "review"
    target.mkdir(exist_ok=True)
    pictures = sorted((OUT / "screens-final").glob("*.png")) + sorted((OUT / "screens-dense-final").glob("*.png"))
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 25)
    for width, scale in [(1280, 100), (960, 150)]:
        name = f"map-bar-{width}-{scale}.png"
        paths = [PREVIOUS / "screens-final" / name, OUT / "screens-final" / name]
        board = Image.new("RGB", (width * 2, (800 if width == 1280 else 600) + 54), "#1e2b31")
        draw = ImageDraw.Draw(board)
        for index, path in enumerate(paths):
            with Image.open(path) as source:
                board.paste(source.convert("RGB"), (index * width, 54))
            draw.text((20 + index * width, 10), "修改前：规则直列 / 侧廊折返" if index == 0 else "本轮：同源校园符号 / 错落节点 / 连续曲线", font=font, fill="#eadbc0")
        board.save(target / f"comparison-{width}-{scale}.png")
    contact_font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 17)
    for start in range(0, len(pictures), 6):
        board = Image.new("RGB", (1240, 1320), "#1e2b31")
        draw = ImageDraw.Draw(board)
        for index, path in enumerate(pictures[start:start+6]):
            with Image.open(path) as source:
                bitmap = source.convert("RGB")
            bitmap.thumbnail((600, 390))
            x, y = 10 + index % 2 * 620, 10 + index // 2 * 440
            board.paste(bitmap, (x + (600 - bitmap.width) // 2, y))
            draw.text((x, y + 396), path.name, font=contact_font, fill="#eadbc0")
        board.save(target / f"contact-{start//6+1:02d}.jpg", quality=95)

    def cards(paths):
        figures = []
        for path in paths:
            uri = html.escape(quote(os.path.relpath(path, target).replace(os.sep, "/"), safe="/"))
            label = html.escape(path.name)
            figures.append(f'<figure><a href="{uri}"><img src="{uri}" loading="lazy" alt="{label}"></a><figcaption>{label}</figcaption></figure>')
        return '<div class="grid">' + "\n".join(figures) + '</div>'

    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>地图图标与路线 · 实渲前后对照</title><style>
body{max-width:1560px;margin:auto;padding:24px;background:#1e2b31;color:#eadbc0;font:16px/1.65 system-ui,sans-serif}a{color:#e4c180}h1{font-size:27px}h2{margin-top:36px;font-size:21px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}figure{margin:0;padding:10px;background:#28383e}img{display:block;width:100%;height:auto}figcaption{overflow-wrap:anywhere}.comparison img{margin:16px 0}@media(max-width:800px){.grid{grid-template-columns:1fr}body{padding:12px}}</style>
<h1>地图图标与路线的整体构图 · 2026-11-14</h1>
<p>本轮纠正“加纸张纹理就算美化”的误读。重画同源校园符号，统一光学大小与笔画；节点按冻结拓扑稳定错落，实际路径为连续曲线，文字处留出短空白；减少重复圆圈、叉号和预览短弧，让当前与预选成为视觉重点。</p>
<p>以下均为Godot实际渲染。尺寸1280×800 / 960×600，字号100 / 125 / 150%。第四学年使用生产生成器与受控已走路径，未冒充自然通关。官方材料仅为已归档的开发截图和宣传连续帧；没有宣称最新构建。AI观察和自动检查不代替用户审美签收。</p>
<div class="comparison"><h2>修改前 / 本轮</h2><a href="comparison-1280-100.png"><img src="comparison-1280-100.png" alt="1280前后对照"></a><a href="comparison-960-150.png"><img src="comparison-960-150.png" alt="960大字号前后对照"></a></div>'''
    page += '<h2>官方构图参考</h2>' + cards([ROOT / "ui-plan/references/slay-the-spire-2" / name for name in ["map_qol.jpg", "map-rest-sequence.jpg"]])
    for title, prefix in [("导航地图与全图", ("map-bar", "map-overview")), ("大四密集路线", ("year-four",)), ("房间只读全图", ("club-map",)), ("菜单与其余页面回归", ("battle-", "club-bar", "club-menu", "map-menu"))]:
        page += '<h2>' + title + '</h2>' + cards([path for path in pictures if path.name.startswith(prefix)])
    (target / "index.html").write_text(page, encoding="utf-8")
    missing = [uri for uri in re.findall(r'(?:href|src)="([^"]+)"', page) if not (target / unquote(uri)).resolve().is_file()]
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
        mismatches = [path for path, sha in recorded.items() if not (ROOT / path).is_file() or digest(ROOT / path) != sha]
        check(key + "_recorded_inputs_current", not mismatches, mismatches)
    native = read(NATIVE / "result.json")
    check("native_actual_input", len(native["cases"]) == 36 and not native["failures"] and native["engine_exit_code"] == 0 and native["engine_errors"] == 0)
    check("native_inputs_current", all((ROOT / p).is_file() and digest(ROOT / p) == sha for p, sha in read(NATIVE / "input_hashes.json").items()))
    navigation = read(OUT / "screens-final/checks.json")
    dense = read(OUT / "screens-dense-final/capture.json")
    check("navigation_actual_checks", not navigation["failures"], navigation["checks"])
    check("dense_actual_render", dense["nodes"] >= 40 and dense["view_unchanged"] and len(dense["captures"]) == 12)
    check("sixty_final_screens", len(pictures) == 60 and len(navigation["captures"]) == 48)
    for path in pictures:
        width = int(path.stem.split("-")[-2])
        with Image.open(path) as bitmap:
            check("dimensions_" + path.name, bitmap.size == (width, 800 if width == 1280 else 600))
    frozen = [path for path in before if path.startswith(("docs/提交文档_20261114/", "output/文档提交_20261114/")) or path == "output/交大四年_DDL战争_文档提交包_20261114.zip"]
    check("frozen_package_bytes", all((ROOT / p).is_file() and digest(ROOT / p) == before[p] for p in frozen), len(frozen))
    for prefix in ["data/", "assets/", "src/app/", "src/battle/", "src/common/", "src/content/", "src/run/", "src/storage/"]:
        changed = [path for path, sha in before.items() if path.startswith(prefix) and (not (ROOT / path).is_file() or digest(ROOT / path) != sha)]
        check("existing_bytes_unchanged_" + prefix, not changed, changed)
    added_assets = [relative(p) for p in (ROOT / "assets").rglob("*") if p.is_file() and relative(p) not in before]
    check("new_assets_only_original_glyphs", all(p.startswith("assets/ui/map/glyphs/") for p in added_assets), added_assets)
    origin = read(ROOT / "assets/ui/map/glyphs/source.json")
    check("original_glyph_hashes", len(origin["glyphs"]) == 13 and not origin["external_images"] and not origin["game_rng_used"] and all(digest(ROOT / "assets/ui/map/glyphs" / item["file"]) == item["sha256"] for item in origin["glyphs"].values()))
    for path in ["src/ui/card_face_view.gd", "src/ui/card_display_model.gd", "src/ui/ui_labels.json", "src/ui/battle_screen.gd", "src/ui/map_paper.gd", "src/ui/run_toolbar.gd", "project.godot"]:
        check("preserved_" + path, digest(ROOT / path) == before[path])
    check("review_links", not read(OUT / "gallery-links.json")["missing"])
    visual = read(OUT / "visual-review.json")
    check("actual_visual_observation", visual.get("reviewed_screens") == 60 and visual.get("human_accepted") is False)
    state_path = ROOT / "docs/baselines/current-state.json"
    state = read(state_path)
    state["evidence"].update({"current_ui": relative(RUNS / FINAL["ui"] / "summary.json"), "current_visual": relative(RUNS / FINAL["visual"] / "summary.json"), "current_import": relative(RUNS / FINAL["import"] / "summary.json"),
        "map_composition_native": relative(NATIVE / "result.json"), "map_composition_consistency": relative(OUT / "consistency.json"), "map_composition_review": relative(OUT / "review/index.html")})
    sources = set(state["source_sha256"])
    sources.update(relative(path) for folder in ["src", "tests"] for path in (ROOT / folder).rglob("*.gd"))
    sources.update(relative(path) for path in (ROOT / "assets/ui/map/glyphs").glob("*") if path.suffix in [".svg", ".json"])
    sources.update(["tools/prepare_map_composition_feedback.py", "tools/build_map_glyphs.py", "tools/record_map_composition_feedback.py", "tools/verify_map_composition.gd", "docs/plans/2026-11-14-map-composition-feedback-design.md", "docs/地图整体构图修正_20261114.md"])
    state["source_sha256"] = {path: digest(ROOT / path) for path in sorted(sources)}
    state["map_composition"] = {"scope": "same optical/stroke system for original campus glyphs, stable organic layer drift, continuous actual edges with caption clearance", "character_art": "paused", "human_visual_acceptance": "pending"}
    write(state_path, state)
    check("snapshot_source_hashes", all(digest(ROOT / path) == sha for path, sha in state["source_sha256"].items()))
    report = {"utc": datetime.now(timezone.utc).isoformat(), "checks": checks, "failures": [row for row in checks if not row["passed"]], "source_hashes": len(sources), "screens": len(pictures), "scope": "This batch's observed implementation; not whole G0/G6/G8 or human aesthetic approval"}
    write(OUT / "consistency.json", report)
    print(json.dumps({"checks": len(checks), "failures": report["failures"], "sources": len(sources), "screens": len(pictures)}, ensure_ascii=False))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
