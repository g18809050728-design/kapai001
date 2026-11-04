"""Validate local Markdown targets, annual map counts, and card prompt coverage."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import re
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/four-year-20261104/doc-check"


def main():
    issues = []
    files = [ROOT / "README.md", ROOT / "agent.md", ROOT / "实施计划与验收基线.md"]
    files += sorted((ROOT / "docs").rglob("*.md"))
    files += sorted((ROOT / "动作或者图片描述").rglob("*.md"))
    files += [ROOT / "assets/audio/README.md"]
    link_count = 0
    for path in files:
        source = path.read_text(encoding="utf-8-sig")
        for match in re.finditer(r"!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)", source):
            target = match[1].strip("<>")
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
                continue
            target = unquote(target.split("#", 1)[0])
            link_count += 1
            if target and not (path.parent / target).exists():
                issues.append(f"Missing target: {path.relative_to(ROOT)} -> {target}")
        if "????" in source:
            issues.append(f"Possible encoding damage: {path.relative_to(ROOT)}")

    catalog = json.loads((ROOT / "data/four_year/definitions/cards.json").read_text(encoding="utf-8-sig"))
    expected = {c["id"] for c in catalog if c["id"].startswith("R3-")}
    prompts = json.loads((ROOT / "docs/art/card-art-prompts-v3.json").read_text(encoding="utf-8"))
    entries = prompts["entries"]
    if len(entries) != 174 or len(expected) != 174 or {e["card_id"] for e in entries} != expected:
        issues.append("Prompt IDs must cover all 174 runtime R3 cards exactly once")
    if len({e["prompt"] for e in entries}) != 174:
        issues.append("Each card requires its own complete prompt")
    asset_path = ROOT / "docs/art/card-art-assets-v3.json"
    asset_manifest = json.loads(asset_path.read_text(encoding="utf-8")) if asset_path.exists() else {"assets": []}
    assets = {a["asset_id"]: a for a in asset_manifest["assets"]}
    textures = json.loads((ROOT / "src/ui/ui_labels.json").read_text(encoding="utf-8-sig"))["textures"]
    for entry in entries:
        cid = entry["card_id"]
        if not entry["prompt"] or not entry["negative_prompt"]:
            issues.append("Missing full prompt: " + cid)
        asset = assets.get(cid, {})
        if entry["generated"] != asset.get("generated", False) or entry["selected"] != asset.get("selected", False):
            issues.append("Prompt/asset status mismatch: " + cid)
        if entry["selected"] and not entry["generated"]:
            issues.append("Selected card was not generated: " + cid)
        if entry["generated"]:
            image = ROOT / asset["output"]
            source = ROOT / asset["source_file"]
            prompt = ROOT / asset["prompt_file"]
            for path, key in [(image, "sha256"), (source, "source_sha256"), (prompt, "prompt_sha256")]:
                if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != asset.get(key):
                    issues.append(f"Asset provenance mismatch: {cid}: {key}")
            if asset.get("reference_file"):
                reference = ROOT / asset["reference_file"]
                if not reference.exists() or hashlib.sha256(reference.read_bytes()).hexdigest() != asset.get("reference_sha256"):
                    issues.append("Reference image hash mismatch: " + cid)
        if entry["selected"]:
            if textures.get(cid) != entry["image_path"] or asset.get("output") != entry["image_path"].removeprefix("res://"):
                issues.append("Selected texture mapping mismatch: " + cid)
            review = asset.get("ai_visual_review") or {}
            if not review.get("approved_for_prototype") or review.get("source_sha256") != asset["source_sha256"]:
                issues.append("Missing matching AI visual review: " + cid)
        if entry["image_path"] != f"res://assets/cards/v3/{entry['card_id']}.png":
            issues.append("Prompt image path mismatch: " + entry["card_id"])

    builder_path = ROOT / "tools/build_four_year_content.py"
    spec = importlib.util.spec_from_file_location("four_year_builder", builder_path)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    maps = builder.maps()  # Includes adjacency, reachability and node-count checks.
    if sum(m["layers"] for m in maps) != 52 or sum(len(m["nodes"]) for m in maps) != 124:
        issues.append("Annual map totals invalid")
    report = {
        "command": "python tools/verify_four_year_docs.py",
        "utc": datetime.now(timezone.utc).isoformat(),
        "os": platform.platform(),
        "python": sys.version,
        "markdown_files": len(files),
        "local_links": link_count,
        "runtime_prompt_ids": len(expected),
        "prompt_entries": len(entries),
        "generated_card_art": sum(e["generated"] for e in entries),
        "selected_card_art": sum(e["selected"] for e in entries),
        "annual_nodes": [len(m["nodes"]) for m in maps],
        "annual_layers": [m["layers"] for m in maps],
        "exit_code": int(bool(issues)),
        "issues": issues,
        "input_hashes": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in files + [builder_path, ROOT / "docs/art/card-art-prompts-v3.json"]},
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    output = json.dumps({k: v for k, v in report.items() if k != "input_hashes"}, ensure_ascii=False, indent=2)
    (OUT / "stdout.txt").write_text(output + "\n", encoding="utf-8")
    print(output)
    return report["exit_code"]


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
