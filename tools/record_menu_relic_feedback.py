"""Keep the menu/relic review, actual test results and source hashes together."""
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
OUT = ROOT / "artifacts/verification/menu-relic-feedback-20261114"
RUNS = ROOT / "artifacts/verification/four-year-20261104"
FINAL = {
    "ui": "menu-relic-full-ui-delivery-20261114",
    "visual": "menu-relic-visual-delivery-20261114",
    "import": "menu-relic-import-delivery-20261114",
}
NATIVE = OUT / "native-delivery-retry"
SCREENS = OUT / "screens-delivery"
OWN_SOURCES = [
    "src/ui/reference_overlay.gd", "src/ui/relic_slot_button.gd",
    "src/ui/run_toolbar.gd", "src/ui/nav_icon.gd", "src/ui/ui_page.gd",
    "src/ui/experience_page.gd", "src/ui/battle_screen.gd",
    "src/ui/battle_layout.gd", "src/ui/battle_action_button.gd",
    "src/ui/offer_card.gd", "src/ui/game_shell.gd",
    "src/test/test_room_service.gd", "tests/run_ui_tests.gd",
    "tests/suites/test_ui_menu_relic_revision.gd",
    "tests/suites/test_ui_flow_revision.gd", "tools/verify_ui_menu_relic.gd",
    "tools/capture_reference_native.gd", "tools/verify_reference_native.py",
    "tools/record_menu_relic_feedback.py",
    "docs/plans/2026-11-14-menu-relic-feedback-design.md",
    "docs/菜单与饰品查看优化_20261114.md",
]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def review():
    target = OUT / "review"
    target.mkdir(exist_ok=True)
    pictures = sorted(SCREENS.glob("*.png"))
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 17)
    for start in range(0, len(pictures), 6):
        board = Image.new("RGB", (1240, 1320), "#182a33")
        draw = ImageDraw.Draw(board)
        for index, path in enumerate(pictures[start:start + 6]):
            with Image.open(path) as source:
                bitmap = source.convert("RGB")
            bitmap.thumbnail((600, 390))
            x, y = 10 + index % 2 * 620, 10 + index // 2 * 440
            board.paste(bitmap, (x + (600 - bitmap.width) // 2, y))
            draw.text((x, y + 396), path.name, font=font, fill="#ead9b9")
        board.save(target / f"contact-{start // 6 + 1:02d}.jpg", quality=95)

    title_font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 24)
    for width, scale in [(1280, 100), (960, 150)]:
        name = f"map-menu-{width}-{scale}.png"
        before = ROOT / "artifacts/verification/map-composition-feedback-20261114/screens-final" / name
        after = SCREENS / name
        height = 800 if width == 1280 else 600
        board = Image.new("RGB", (width * 2, height + 50), "#182a33")
        draw = ImageDraw.Draw(board)
        for index, path in enumerate([before, after]):
            with Image.open(path) as source:
                board.paste(source.convert("RGB"), (index * width, 50))
            draw.text((index * width + 15, 8), "修改前" if index == 0 else "本批：真实菜单信息与查阅入口", font=title_font, fill="#ead9b9")
        board.save(target / f"comparison-menu-{width}-{scale}.png")

    def cards(paths):
        figures = []
        for path in paths:
            uri = html.escape(quote(os.path.relpath(path, target).replace(os.sep, "/"), safe="/"))
            label = html.escape(path.name)
            figures.append(f'<figure><a href="{uri}"><img src="{uri}" alt="{label}" loading="lazy"></a><figcaption>{label}</figcaption></figure>')
        return '<div class="grid">' + "\n".join(figures) + '</div>'

    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>菜单与饰品查看 · 实机评审</title><style>
body{max-width:1560px;margin:auto;padding:24px;background:#182a33;color:#ead9b9;font:16px/1.65 system-ui,sans-serif}a{color:#edcb8a}h1{font-size:28px}h2{margin-top:32px;font-size:22px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}figure{margin:0;padding:10px;background:#253a45}img{display:block;width:100%;height:auto}figcaption{overflow-wrap:anywhere}@media(max-width:800px){.grid{grid-template-columns:1fr}body{padding:12px}}</style>
<h1>菜单、规则记录与饰品查看 · 2026-11-14</h1>
<p>地图和战斗共用规则、记录、饰品与冒险信息查阅；菜单直接说明用途与当前状态，设置、保存、返回主页接真实操作。饰品使用实际槽位、原图及完整效果；满槽领取前可以比较旧装备。规则、记录与专注图标统一。</p>
<p>49张Godot实渲覆盖1280×800、960×600及100/125/150%字号。装备和满槽奖励是受控fixture，实际目录效果与生产入口保持；未冒充自然取得或自然四年通关。本批未修改人物；其他并行人物实践独立追踪。自动通过和AI看图不代表用户美术签收。</p>'''
    page += '<h2>菜单修改前后</h2>' + cards(sorted(target.glob("comparison-menu-*.png")))
    page += '<h2>已归档官方参考</h2>' + cards([ROOT / "ui-plan/references/slay-the-spire-2/topbar_qol.jpg"])
    groups = [
        ("地图菜单与操作反馈", ("map-menu-", "map-save-")),
        ("分节规则帮助", ("map-rules-",)),
        ("地图与战斗的装备查看", ("map-relics-", "battle-relics-")),
        ("实际战斗记录与专注", ("battle-log-", "battle-focus-")),
        ("奖励、满槽替换及滚动", ("relic-replacement-",)),
    ]
    for title, prefixes in groups:
        page += '<h2>' + title + '</h2>' + cards([p for p in pictures if p.name.startswith(prefixes)])
    page += '<h2>Windows实际输入样本</h2>' + cards([NATIVE / name for name in ["map-960-150-menu.png", "map-960-150-rules.png", "battle-960-150-relics.png", "battle-960-150-log-search.png"]])
    page += '</html>'
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
        print(json.dumps({"screens": len(pictures), "review": rel(OUT / "review/index.html")}))
        return 0
    checks = []

    def check(name, passed, details=None):
        checks.append({"name": name, "passed": bool(passed), "details": details})

    before = read(OUT / "before.json")["files"]
    for key, run in FINAL.items():
        summary = read(RUNS / run / "summary.json")
        check(key + "_actual_exit_and_errors", all(row["exit_code"] == 0 and row["engine_errors"] == 0 for row in summary), summary)
        inputs = read(RUNS / run / "input_hashes.json")
        mismatches = [p for p, sha in inputs.items() if not (ROOT / p).is_file() or digest(ROOT / p) != sha]
        check(key + "_recorded_inputs_current", not mismatches, mismatches)
    native = read(NATIVE / "result.json")
    check("native_actual_input", len(native["cases"]) == 12 and not native["failures"] and native["exit_code"] == 0 and native["engine_errors"] == 0)
    check("native_unchanged_during_run", not native["changed_during_run"], native["changed_during_run"])
    mismatches = [p for p, sha in read(NATIVE / "input_hashes.json").items() if not (ROOT / p).is_file() or digest(ROOT / p) != sha]
    check("native_recorded_inputs_current", not mismatches, mismatches)
    visual = read(SCREENS / "checks.json")
    check("targeted_actual_checks", visual["checks"] >= 322 and not visual["failures"], visual["checks"])
    check("forty_nine_final_screens", len(pictures) == 49 and len(visual["captures"]) == 49)
    for path in pictures:
        width = int(path.stem.split("-")[-2])
        with Image.open(path) as bitmap:
            check("dimensions_" + path.name, bitmap.size == (width, 800 if width == 1280 else 600))
    frozen = [p for p in before if p.startswith(("docs/提交文档_20261114/", "output/文档提交_20261114/")) or p == "output/交大四年_DDL战争_文档提交包_20261114.zip"]
    check("frozen_package_bytes", all((ROOT / p).is_file() and digest(ROOT / p) == before[p] for p in frozen), len(frozen))
    for prefix in ["data/", "src/app/", "src/battle/", "src/common/", "src/content/", "src/run/", "src/storage/"]:
        changed = [p for p, sha in before.items() if p.startswith(prefix) and p != "src/app/game_session.gd" and (not (ROOT / p).is_file() or digest(ROOT / p) != sha)]
        exclusions = ["src/app/game_session.gd"] if prefix == "src/app/" else []
        check("existing_bytes_unchanged_" + prefix + ("_except_recorded_parallel_source" if exclusions else ""), not changed, {"changed": changed, "parallel_exclusions": exclusions})
    for path in ["src/ui/card_face_view.gd", "src/ui/card_display_model.gd", "src/ui/ui_labels.json", "src/ui/route_canvas.gd", "src/ui/map_node_stamp.gd", "src/ui/map_paper.gd", "src/ui/map_node_glyph.gd", "project.godot"]:
        check("preserved_" + path, digest(ROOT / path) == before[path])
    changed = [p for p, sha in before.items() if not (ROOT / p).is_file() or digest(ROOT / p) != sha]
    # The actor pilot is an independent task in the same workspace. Record its
    # coexistence explicitly instead of claiming those bytes as this batch.
    concurrent = [p for p in changed if p.startswith("src/ui/battle/") or p == "src/app/game_session.gd"]
    check("existing_assets_unchanged", all((ROOT / p).is_file() and digest(ROOT / p) == sha for p, sha in before.items() if p.startswith("assets/")))
    check("review_links", not read(OUT / "gallery-links.json")["missing"])
    observation = read(OUT / "visual-review.json")
    check("actual_visual_observation", observation.get("reviewed_screens") == 49 and observation.get("human_accepted") is False)
    check("diff_whitespace", read(OUT / "diff-check.json")["exit_code"] == 0)
    failures = [row for row in checks if not row["passed"]]
    if not failures:
        path = ROOT / "docs/baselines/current-state.json"
        state = read(path)
        state["evidence"].update({"current_" + key: rel(RUNS / run / "summary.json") for key, run in FINAL.items()})
        state["evidence"].update(menu_relic_native=rel(NATIVE / "result.json"), menu_relic_consistency=rel(OUT / "consistency.json"), menu_relic_review=rel(OUT / "review/index.html"))
        sources = set(state["source_sha256"]) | set(OWN_SOURCES)
        sources.update(rel(p) for folder in ["src", "tests"] for p in (ROOT / folder).rglob("*.gd"))
        state["source_sha256"] = {p: digest(ROOT / p) for p in sorted(sources)}
        state["menu_relic"] = {"requirement": "UIR-068", "stage": "G7 authorized sub-batch", "read_only_reference": ["relics", "rules", "log", "info"], "checks_visual": visual["checks"], "screens": 49, "native_cases": 12, "character_art": "not changed by this batch; independent actor pilot remains separate", "human_visual_acceptance": "pending"}
        write(path, state)
    report = {"utc": datetime.now(timezone.utc).isoformat(), "checks": checks, "failures": failures, "screens": len(pictures), "changed_existing_files": changed, "concurrent_actor_files_not_attributed": concurrent, "shared_ui_files_with_independent_actor_changes": ["src/ui/battle_screen.gd", "src/ui/battle_layout.gd"], "parallel_session_source": {"path": "src/app/game_session.gd", "before_sha256": before["src/app/game_session.gd"], "current_sha256": digest(ROOT / "src/app/game_session.gd"), "scope": "Independent actor practice's read-only effect_sources mapping; preserved and not attributed to this batch"}, "scope": "This batch's observed implementation; not whole G0/G6/G8 or human aesthetic acceptance"}
    write(OUT / "consistency.json", report)
    print(json.dumps({"checks": len(checks), "failures": failures, "screens": len(pictures), "concurrent_actor_files": concurrent}, ensure_ascii=False))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
