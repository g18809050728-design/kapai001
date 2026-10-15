"""One-off G6 preparation smoke: real catalog plus temporary synthetic pixels."""
from datetime import datetime, timezone
import csv
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
from tempfile import TemporaryDirectory
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, __version__ as pillow_version

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from slice_g6_atlas import build_plan


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


catalog_path = ROOT / "assets/g6/catalog.json"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
baseline = json.loads((ROOT / "docs/baselines/g0.json").read_text(encoding="utf-8-sig"))
expected = {(kind, item) for kind, ids in baseline["scope"]["enabled_by_kind"].items() for item in ids}
actual = {(item["kind"], item["id"]) for item in catalog["content_coverage"]}
assert actual == expected and len(actual) == len(catalog["content_coverage"]) == 66
assert len(catalog["assets"]) == 46 and len(catalog["batches"]) == 6
assets = {item["id"]: item for item in catalog["assets"]}
assigned = [slot["asset_id"] for batch in catalog["batches"] for slot in batch["slots"]]
assert len(set(assigned)) == len(assigned) == 46 and set(assigned) == set(assets)
assert len({item["requirement_id"] for item in catalog["ui_coverage"]}) == 16
for name, sha in catalog["sources"].items():
    assert digest(ROOT / name) == sha
for asset in assets.values():
    assert asset["selected_file"] is None and asset["selected_version"] is None
with (ROOT / "assets/g6/资源清单.csv").open(encoding="utf-8-sig", newline="") as handle:
    rows = list(csv.DictReader(handle))
assert len(rows) == 46 and {row["asset_id"] for row in rows} == set(assets)
selection = json.loads((ROOT / "assets/g6/selection.json").read_text(encoding="utf-8"))
assert not selection["generation_runs"] and not selection["selections"]
sizes, cli_runs = {}, []
with TemporaryDirectory(prefix="g6-preparation-") as temporary:
    work = Path(temporary)
    for batch in catalog["batches"]:
        ET.parse(ROOT / f"assets/g6/layouts/{batch['id']}.svg")
        sizes[batch["id"]] = {}
        for variant, dimensions in batch["variants"].items():
            _, plan, warnings = build_plan(catalog, batch["id"], variant,
                (dimensions["width"], dimensions["height"]), work / batch["id"] / variant, False)
            assert not warnings and len(plan) == len(batch["slots"])
            sizes[batch["id"]][variant] = sorted({(item["width"], item["height"]) for item in plan})
            prompt = (ROOT / f"assets/g6/prompts/{variant}/{batch['id']}.txt").read_text(encoding="utf-8")
            assert f'{dimensions["width"]}×{dimensions["height"]}' in prompt
            assert f'{batch["columns"]} 列 × {batch["rows"]} 行' in prompt
            assert prompt.count('）：') == len(batch["slots"])
            for slot in batch["slots"]:
                assert f'第{slot["row"] + 1}行第{slot["column"] + 1}列（{slot["asset_id"]}，' in prompt

    # Twelve distinct solid-color cells detect wrong slot order or crop bleeding.
    source = work / "synthetic.png"
    atlas = Image.new("RGB", (3840, 2160))
    draw = ImageDraw.Draw(atlas)
    colors = [(20 + i * 17, 220 - i * 13, 30 + i * 11) for i in range(12)]
    for i, color in enumerate(colors):
        x, y = (i % 4) * 960, (i // 4) * 720
        draw.rectangle((x, y, x + 959, y + 719), fill=color)
    atlas.save(source)
    source_hash = digest(source)
    output = work / "slices"
    command = [sys.executable, str(ROOT / "tools/slice_g6_atlas.py"),
        "--catalog", str(catalog_path), "--batch", "G6-02", "--input", str(source),
        "--output-dir", str(output), "--variant", "high"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8")
    cli_runs.append({"command": command, "exit_code": result.returncode,
                     "stdout": result.stdout, "stderr": result.stderr})
    assert result.returncode == 0, result.stderr
    report = json.loads((output / "slicing.json").read_text(encoding="utf-8"))
    assert report["source_sha256"] == source_hash == digest(source)
    assert report["resource_status"] == "candidate_unreviewed" and not report["background_removed"]
    assert len(report["slices"]) == 12
    hashes = {}
    for i, item in enumerate(report["slices"]):
        path = output / item["output_file"]
        with Image.open(path) as picture:
            assert picture.size == (662, 662) and picture.mode == "RGB"
            assert picture.getextrema() == tuple((c, c) for c in colors[i])
        hashes[item["output_file"]] = digest(path)
        assert hashes[item["output_file"]] == item["sha256"]
    repeated = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8")
    cli_runs.append({"command": command, "exit_code": repeated.returncode,
                     "stdout": repeated.stdout, "stderr": repeated.stderr})
    assert repeated.returncode == 1 and "Refusing to overwrite" in repeated.stderr
    assert all(digest(output / name) == value for name, value in hashes.items())
    assert digest(source) == source_hash

evidence = {
    "status": "passed", "scope": "planning pack and offline slicing only; no generated game art",
    "created_at": datetime.now(timezone.utc).isoformat(),
    "command": [sys.executable, "artifacts/g6-preparation/check_pack.py"],
    "environment": {"python": sys.version, "pillow": pillow_version, "platform": platform.platform()},
    "counts": {"masters": 46, "batches": 6, "frozen_pairs": 66, "ui_requirements": 16, "prompts": 12, "svg_guides": 6},
    "output_sizes": sizes, "synthetic_cli_runs": cli_runs,
    "input_sha256": {name: digest(ROOT / name) for name in [
        "assets/g6/catalog.json", "tools/prepare_g6_pack.py", "tools/slice_g6_atlas.py",
        "artifacts/g6-preparation/check_pack.py", "docs/baselines/g0.json"]},
    "generation_calls_executed": 0,
    "note": "Temporary colored atlas removed after checks; not G6 resource review evidence."
}
(Path(__file__).parent / "pack-check.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("PASS: 46 masters / 6 batches / 66 frozen pairs / 16 UI requirements / 12 prompts / 6 SVG guides")
print("PASS: real-catalog 4K synthetic atlas => 12 correct RGB crops, unchanged source, overwrite rejected")
print("Evidence: artifacts/g6-preparation/pack-check.json; actual generation calls: 0")
