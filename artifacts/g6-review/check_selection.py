"""Verify selected G6 file provenance and mappings without running the game."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


selection = read("assets/g6/selection.json")
catalog = read("assets/g6/catalog.json")
review = read("artifacts/g6-review/review.json")
checks = []


def check(name, condition):
    checks.append({"check": name, "passed": bool(condition)})


selected = {a["asset_id"]: a for a in selection["selections"]}
planned = {a["id"]: a for a in catalog["assets"]}
check("46 unique selected assets equal planned IDs", len(selected) == len(selection["selections"]) == 46 and selected.keys() == planned.keys())
check("6 supplied source atlases", len(selection["generation_runs"]) == 6)
check("catalog hash matches selection", sha("assets/g6/catalog.json") == selection["catalog_sha256"])
check("selection hash matches visual report", sha("assets/g6/selection.json") == review["selection_sha256"])
check("AI review is not labeled human signoff", selection["human_review_status"] == review["human_review_status"] == "not_recorded")
check("external billing is unknown", selection["external_generation_billing_calls"] is None and review["external_paid_calls"] is None)
check("agent generation calls zero", selection["generation_calls_executed"] == review["agent_image_generation_calls"] == 0)

manifests = {}
for run in selection["generation_runs"]:
    batch = run["batch_id"]
    manifest = read(run["slicing_manifest"])
    manifests[batch] = {a["asset_id"]: a for a in manifest["slices"]}
    check(batch + " source hash", sha(run["source_file"]) == run["source_sha256"] == manifest["source_sha256"])
    check(batch + " slicing manifest hash", sha(run["slicing_manifest"]) == run["slicing_manifest_sha256"])
    check(batch + " catalog hash", manifest["catalog_sha256"] == selection["catalog_sha256"])
    with Image.open(ROOT / run["source_file"]) as image:
        check(batch + " source size", list(image.size) == run["actual_size"] == [3840, 2160])

for asset_id, asset in selected.items():
    slice_record = manifests[asset["batch_id"]][asset_id]
    check(asset_id + " candidate hash", sha(asset["candidate_file"]) == asset["candidate_sha256"] == slice_record["sha256"])
    check(asset_id + " selected hash", sha(asset["selected_file"]) == asset["selected_sha256"])
    check(asset_id + " original crop provenance", asset["source_crop_box"] == slice_record["crop_box"])
    check(asset_id + " requirements and content refs", all(asset[key] == planned[asset_id][key] for key in ["requirement_ids", "content_refs"]))
    check(asset_id + " readable review note", len(asset["review_note"]) > 20 and "???" not in asset["review_note"])
    check(asset_id + " visual evidence exists", (ROOT / asset["review_evidence"]).is_file())
    with Image.open(ROOT / asset["selected_file"]) as image:
        check(asset_id + " selected size and mode", list(image.size) == asset["selected_size"] and image.mode == asset["selected_mode"] == "RGB")
        if asset_id in {"K05", "K06"}:
            with Image.open(ROOT / asset["candidate_file"]) as candidate:
                expected = candidate.crop(tuple(asset["derivation"]["candidate_crop_box"]))
                check(asset_id + " exact recorded center crop", expected.size == image.size == (646, 646) and expected.tobytes() == image.tobytes())
        else:
            check(asset_id + " byte-identical copy", asset["selected_sha256"] == asset["candidate_sha256"])

content_expected = {(a["kind"], a["id"]): a for a in catalog["content_coverage"]}
content_actual = {(a["kind"], a["id"]): a for a in selection["content_coverage"]}
check("66 unique frozen content mappings", len(content_actual) == len(selection["content_coverage"]) == 66 and content_actual.keys() == content_expected.keys())
for key, actual in content_actual.items():
    expected = content_expected[key]
    check("content " + "/".join(key), actual["asset_ids"] == expected["asset_ids"] and actual["method"] == expected["method"] and actual.get("selected_files", []) == [selected[asset_id]["selected_file"] for asset_id in actual["asset_ids"]])
ui_actual = {a["requirement_id"]: a for a in selection["ui_coverage"]}
ui_expected = {a["requirement_id"]: a for a in catalog["ui_coverage"]}
check("16 unique UI requirement methods", len(ui_actual) == len(selection["ui_coverage"]) == 16 and ui_actual.keys() == ui_expected.keys())
for key, actual in ui_actual.items():
    check(key + " planned method preserved", all(actual[field] == ui_expected[key][field] for field in ["asset_ids", "method"]))

docs = [ROOT / "assets/g6/README.md", ROOT / "docs/G6\u8d44\u6e90\u51c6\u5907\u6267\u884c\u8bb0\u5f55.md"]
for doc in docs:
    for link in re.findall(r"\]\(([^)]+)\)", doc.read_text(encoding="utf-8")):
        if not link.startswith(("http://", "https://", "#")):
            # The report is produced by this invocation, so its link is valid after write.
            target = (doc.parent / link).resolve()
            check(doc.name + " link " + link, target.exists() or target == ROOT / "artifacts/g6-review/selection-check.json")

failed = [row for row in checks if not row["passed"]]
report = {
    "created_at": datetime.now(timezone.utc).isoformat(),
    "command": "python artifacts/g6-review/check_selection.py",
    "scope": "G6 selected file provenance, dimensions, mappings and two documentation link sets; no Godot, UI or gameplay regression",
    "selection_sha256": sha("assets/g6/selection.json"),
    "counts": {"sources": 6, "selected_assets": len(selected), "content_mappings": len(content_actual), "ui_requirements": len(ui_actual), "checks": len(checks), "failures": len(failed)},
    "categories": dict(Counter(a["category"] for a in selected.values())),
    "result": "pass" if not failed else "fail",
    "checks": checks,
}
(ROOT / "artifacts/g6-review/selection-check.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"result": report["result"], "counts": report["counts"], "failed": failed}, ensure_ascii=False))
raise SystemExit(1 if failed else 0)
