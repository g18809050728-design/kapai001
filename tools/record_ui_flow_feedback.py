"""Record this batch's real evidence and refresh the observed implementation snapshot.

This never runs or modifies the game, player saves, frozen documents, or test logs.
It only writes this batch's derived review files and docs/baselines/current-state.json.
"""
from __future__ import annotations

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
OUT = ROOT / "artifacts/verification/ui-flow-feedback-20261114"
RUNS = ROOT / "artifacts/verification/four-year-20261104"
FINAL = {
    "rules": "ui-flow-feedback-full-rules-20261114",
    "ui": "ui-flow-feedback-full-ui-final-20261114",
    "visual": "ui-flow-feedback-visual-final-20261114",
    "import": "ui-flow-feedback-import-final-20261114",
    "content": "ui-flow-feedback-content-final-20261114",
}
FROZEN_DIRS = ("docs/提交文档_20261114/", "output/文档提交_20261114/")
FROZEN_ZIP = "output/交大四年_DDL战争_文档提交包_20261114.zip"
FROZEN_HASH = "8aa7e77e5bb5824ce0db428815695c8b822089a28b4b13534a8b8e983b10d232"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def hyperlink(path: Path, parent: Path) -> str:
    return html.escape(quote(os.path.relpath(path, parent).replace(os.sep, "/"), safe="/"))


def build_review(capture):
    review = OUT / "review-final"
    review.mkdir(exist_ok=True)
    pictures = sorted((OUT / "screens-final").glob("*.png"))
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 17)
    for start in range(0, len(pictures), 6):
        canvas = Image.new("RGB", (1240, 1350), "#171e23")
        painter = ImageDraw.Draw(canvas)
        for number, path in enumerate(pictures[start:start + 6]):
            with Image.open(path) as source:
                image = source.convert("RGB")
            image.thumbnail((600, 412))
            x, y = 10 + number % 2 * 620, 10 + number // 2 * 450
            canvas.paste(image, (x + (600 - image.width) // 2, y))
            painter.text((x, y + 416), path.name, fill="#f3dec0", font=font)
        canvas.save(review / f"contact-{start // 6 + 1:02d}.jpg", quality=92)

    references = [ROOT / "ui-plan/references/slay-the-spire-2" / name for name in
                  ["map_qol.jpg", "topbar_qol.jpg", "event2.jpg", "screenshots-contact.jpg"]]
    before = [ROOT / "image copy 4.png"] + [
        ROOT / "artifacts/verification/ui-beauty-usability-20261114/screens-accepted" / name
        for name in ["setup-text150-960.png", "battle-map-960.png", "production-event-960.png"]
    ]

    def cards(paths):
        result = []
        for path in paths:
            assert path.is_file(), path
            address = hyperlink(path, review)
            label = html.escape(path.name)
            result.append(f'<figure><a href="{address}"><img loading="lazy" src="{address}" alt="{label}"></a><figcaption>{label}</figcaption></figure>')
        return '<div class="grid">' + "\n".join(result) + "</div>"

    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>创建、地图与操作体验 · 实渲核对</title><style>
body{margin:0 auto;max-width:1500px;padding:24px;background:#171e23;color:#eadbc1;font:16px/1.6 system-ui,sans-serif}
a{color:#e9c783}h1{font-size:26px}h2{margin-top:36px;font-size:21px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}
figure{margin:0;padding:10px;background:#24333b;border:1px solid #877453;border-radius:5px}img{display:block;max-width:100%;height:auto;margin:auto}figcaption{overflow-wrap:anywhere;margin-top:8px}
nav{display:flex;flex-wrap:wrap;gap:20px}p{max-width:1000px}@media(max-width:800px){body{padding:14px}.grid{grid-template-columns:1fr}}
</style><h1>创建、地图与操作体验 · 2026-11-14</h1>
<p>最终44张Godot实渲：1280×800 / 960×600，100 / 125 / 150%字号；1017项定向检查通过。点击图片查看原图。人物继续暂停；这里是本批实现和AI视觉核对，不代表最终审美、平衡或整版验收。</p>
<nav><a href="#final">本批实渲</a><a href="#reference">官方归档</a><a href="#before">历史同类画面</a><a href="../README.md">原始证据</a></nav>
<h2 id="final">本批实渲</h2>'''
    page += cards(pictures)
    page += '<h2 id="reference">已归档官方参考</h2><p>归档来源与日期见参考目录；包括开发中资料与官方商店画面，不称为最新构建规范。地图纸面/路线与侧栏、窄顶栏、选角与事件左右构图用于本批对照。</p>'
    page += cards(references)
    page += '<h2 id="before">历史同类画面及用户原截图</h2><p>用于比较高级设置位置、顶栏图标、旧地图面板与事件表现；历史种子/状态不同，不用于规则或像素差分。</p>'
    page += cards(before)
    page += '</html>'
    (review / "index.html").write_text(page, encoding="utf-8")
    observed = {
        "date": "2026-11-14", "reviewer": "AI visual inspection", "human_acceptance": False,
        "reviewed_screens": {rel(p): digest(p) for p in pictures},
        "official_reference_sha256": {rel(p): digest(p) for p in references},
        "historical_comparisons": {rel(p): digest(p) for p in before},
        "observations": [
            "8张接触表中的44张最终图已查看，另放大检查种子、地图、顶栏、待选和付费服务。",
            "创建主要操作固定可达，独立种子弹层在960/150%中完整显示。",
            "完整地图包含本学年所有节点/连线和侧方摘要，关闭回到原页面。",
            "校园服务有已有插画、真实标题和选项说明，付费目标阶段使用固定最终确认。",
            "大字号长说明/牌组采用滚动，保留原卡牌类型费用图案。",
        ],
        "remaining": [
            "人物造型及资源工作暂停；没有用户最终审美签收。",
            "服务图复用卡图/背景，未制作全部专属全景或连续演出。",
            "本作线条图标与二代仍有绘画细节差异；没有宣称逐像素相同。",
            "难度参数未作真人平衡、自然四年、性能或发行验收。",
        ],
    }
    write(OUT / "visual-review.json", observed)
    return pictures


def refresh_snapshot(catalog):
    path = ROOT / "docs/baselines/current-state.json"
    state = read(path)
    state["project_date"] = "2026-11-14"
    state["manifest"].update(id=catalog["id"], content_version=catalog["version"], content_hash=catalog["hash"])
    state["manifest"]["sha256"] = digest(ROOT / state["manifest"]["path"])
    for kind, record in state["definitions"].items():
        record.update(sha256=digest(ROOT / record["path"]),
                      enabled_ids=catalog["enabled"][kind], enabled_count=len(catalog["enabled"][kind]),
                      definition_count_in_file=len(read(ROOT / record["path"])))
    state["enabled_definition_count"] = sum(len(ids) for ids in catalog["enabled"].values())
    state["annual_maps"].update(map_version=3, supported_map_versions=[1, 2, 3],
        legacy_algorithm="annual_map_generator_v1.gd and annual_map_generator_v2.gd; original algorithms and later-year seeds retained",
        minimum_fork_category_differences=2, maximum_first_fork_difference_distance=3)
    rules = read(ROOT / "data/four_year/definitions/rulesets.json")[0]
    state["difficulty"] = {"default": "normal", "profiles": rules["difficulty_overrides"],
        "pressure_rounding": "ceil after complete dynamic modifiers, then original status reductions", "balance_acceptance": "pending"}
    state["evidence"].update(
        current_import=rel(RUNS / FINAL["import"] / "summary.json"),
        current_regression=rel(RUNS / FINAL["rules"] / "summary.json"),
        current_ui=rel(RUNS / FINAL["ui"] / "summary.json"),
        current_visual=rel(RUNS / FINAL["visual"] / "summary.json"),
        current_content=rel(RUNS / FINAL["content"] / "summary.json"),
        ui_flow_checks=rel(OUT / "screens-final/checks.json"),
        ui_flow_consistency=rel(OUT / "consistency.json"),
        ui_flow_native="artifacts/verification/map-card-feedback-20261114/ui-flow-feedback-20261114/result.json")
    sources = set(state["source_sha256"])
    sources.update(rel(p) for p in (ROOT / "src").rglob("*.gd"))
    sources.update(["AGENTS.md", "agent.md", "ui-plan/README.md", "docs/baselines/README.md",
        "docs/创建地图与操作体验修正_20261114.md", "docs/plans/2026-11-14-ui-flow-feedback-design.md",
        "动作或者图片描述/整体表现重制需求_20261113.md", "动作或者图片描述/逐年随机地图需求_20261113.md",
        "docs/界面层契约.md", "docs/战斗模块契约.md", "docs/接口文档.md", "docs/G6资源准备执行记录.md",
        "tests/suites/test_annual_map_generator_v3.gd", "tests/suites/test_difficulty.gd", "tests/suites/test_ui_flow_revision.gd",
        "tools/verify_ui_flow_rules.gd", "tools/verify_ui_flow_revision.gd", "tools/verify_four_year.py", "tools/record_ui_flow_feedback.py"])
    state["source_sha256"] = {name: digest(ROOT / name) for name in sorted(sources)}
    write(path, state)
    return state


def main():
    original = read(OUT / "before.json")
    before = original["files"]
    checks = []

    def check(name, passed, details=None):
        checks.append({"name": name, "passed": bool(passed), "details": details})

    summaries = {}
    for label, folder in FINAL.items():
        summaries[label] = read(RUNS / folder / "summary.json")
        check(f"{label}_exit_and_engine_errors", all(r["exit_code"] == 0 and r["engine_errors"] == 0 for r in summaries[label]))
    text = (RUNS / FINAL["content"] / "capture_map_content_baseline.stdout.txt").read_text(encoding="utf-8")
    catalog = json.loads(next(line.split("=", 1)[1] for line in text.splitlines() if line.startswith("FOUR_YEAR_CONTENT_BASELINE=")))
    check("catalog_loaded_with_346_enabled_definitions", sum(len(v) for v in catalog["enabled"].values()) == 346)
    capture = read(OUT / "screens-final/checks.json")
    pictures = build_review(capture)
    check("targeted_visual_checks", capture["checks"] == 1017 and not capture["failures"], capture["checks"])
    check("44_exact_captures", len(pictures) == 44 and {p.stem for p in pictures} == set(capture["captures"]))
    for path in pictures:
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            expected = (960, 600) if "-960-" in path.name else (1280, 800)
            check("capture_dimensions:" + path.name, image.size == expected)
    native_path = ROOT / "artifacts/verification/map-card-feedback-20261114/ui-flow-feedback-20261114/result.json"
    native = read(native_path)
    check("16_native_mouse_cases", len(native["cases"]) == 16 and not native["failures"] and native["engine_errors"] == 0 and native["engine_exit_code"] == 0)
    for folder in FROZEN_DIRS:
        registered = {p: h for p, h in before.items() if p.startswith(folder)}
        current = {rel(p): digest(p) for p in (ROOT / folder).rglob("*") if p.is_file()}
        check("frozen_directory_unchanged:" + folder, bool(registered) and registered == current, len(registered))
    check("frozen_zip_exact_sha256", digest(ROOT / FROZEN_ZIP) == FROZEN_HASH == before[FROZEN_ZIP], FROZEN_HASH)
    assets = {p: h for p, h in before.items() if p.startswith("assets/")}
    current_assets = {rel(p): digest(p) for p in (ROOT / "assets").rglob("*") if p.is_file()}
    check("all_registered_assets_unchanged_no_additions", assets == current_assets, len(assets))
    for name in ["src/ui/card_face_view.gd", "src/ui/card_display_model.gd", "src/ui/ui_labels.json", "src/run/annual_map_generator_v1.gd", "docs/baselines/g0.json"]:
        check("preserved:" + name, digest(ROOT / name) == before[name])
    retained = (ROOT / "src/run/annual_map_generator_v2.gd").read_bytes().replace(b"class_name AnnualMapGeneratorV2", b"class_name AnnualMapGenerator", 1)
    check("v2_exact_original_bytes_except_class_name", hashlib.sha256(retained).hexdigest() == before["src/run/annual_map_generator.gd"])

    current_inputs = {rel(p): digest(p) for folder in ["src", "tests", "data"] for p in (ROOT / folder).rglob("*") if p.is_file()}
    current_inputs.update({name: digest(ROOT / name) for name in ["project.godot", "tools/build_four_year_content.py"]})
    final_input_differences = {}
    for label, folder in FINAL.items():
        tested = read(RUNS / folder / "input_hashes.json")
        differences = sorted(name for name in set(tested) | set(current_inputs) if tested.get(name) != current_inputs.get(name))
        final_input_differences[label] = differences
        behavioral = [name for name in differences if not name.endswith(".uid")]
        if label == "rules":
            allowed = {"src/ui/experience_page.gd", "tests/suites/test_ui_flow_revision.gd"}
            check("rules_production_and_rule_tests_match_final_inputs", set(behavioral) <= allowed, behavioral)
        else:
            check(label + "_behavioral_inputs_match_final", not behavioral, behavioral)
    native_tested = read(native_path.parent / "input_hashes.json")
    check("native_production_inputs_match_final", all(digest(ROOT / name) == value for name, value in native_tested.items() if name.startswith(("src/", "data/")) and not name.endswith(".uid")))
    requirements = (ROOT / "动作或者图片描述/整体表现重制需求_20261113.md").read_text(encoding="utf-8")
    ids = re.findall(r"^\| (UIR-\d{3}) \|", requirements, re.MULTILINE)
    check("unique_UIR_001_to_067", len(ids) == len(set(ids)) == 67 and set(ids) == {f"UIR-{i:03d}" for i in range(1, 68)})
    state = refresh_snapshot(catalog)
    check("snapshot_source_and_definition_hashes_current", all(digest(ROOT / name) == value for name, value in state["source_sha256"].items()) and all(digest(ROOT / entry["path"]) == entry["sha256"] for entry in state["definitions"].values()))
    check("snapshot_observed_only", not state["g0_whole_version_accepted"] and not state["g8_whole_version_accepted"])
    missing_links = []
    for source in [ROOT / "docs/创建地图与操作体验修正_20261114.md", OUT / "README.md"]:
        for target in re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", source.read_text(encoding="utf-8")):
            clean = unquote(target.split("#", 1)[0].strip("<>"))
            if not clean or re.match(r"^[a-z]+:", clean):
                continue
            actual = (source.parent / clean).resolve()
            if actual != OUT / "consistency.json" and not actual.exists():
                missing_links.append({"source": rel(source), "target": target})
    check("new_evidence_document_links_exist", not missing_links, missing_links)
    history = []
    for folder in sorted(RUNS.glob("ui-flow-feedback-*")):
        if (folder / "summary.json").exists():
            history.append({"path": rel(folder / "summary.json"), "results": read(folder / "summary.json")})
        else:
            history.append({"path": rel(folder), "summary": "not finalized; raw outputs retained"})
    changed = sorted(name for name, value in before.items() if not (ROOT / name).is_file() or digest(ROOT / name) != value)
    watched = ["src", "data", "tests", "tools", "assets", "ui-plan", "动作或者图片描述", "docs"]
    now = {rel(p): digest(p) for folder in watched for p in (ROOT / folder).rglob("*") if p.is_file()}
    report = {
        "date": "2026-11-14", "recorded_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "Observed implementation evidence, not full G0/G6/G8 or human/balance acceptance",
        "before": {"utc": original["utc"], "count": len(before), "note": "After initial plan/design/contract additions, before rule and UI source changes"},
        "content_hash": catalog["hash"], "checks": checks,
        "failures": [item["name"] for item in checks if not item["passed"]],
        "modified_since_snapshot": changed, "new_since_snapshot": {name: value for name, value in now.items() if name not in before},
        "test_input_differences": final_input_differences, "final_runs": summaries,
        "history_including_failed_runs": history,
        "derived_files": {"tool_sha256": digest(Path(__file__)), "snapshot_sha256": digest(ROOT / "docs/baselines/current-state.json")},
    }
    write(OUT / "consistency.json", report)
    print(json.dumps({"checks": len(checks), "failures": report["failures"], "content_hash": catalog["hash"], "snapshot_files": len(state["source_sha256"]), "screens": len(pictures)}, ensure_ascii=False))
    return int(bool(report["failures"]))


if __name__ == "__main__":
    raise SystemExit(main())
