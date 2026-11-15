"""Check exact production coverage and trace every selected enemy source."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/enemy-roster-20261115"
EV = ROOT / "artifacts/verification/enemy-roster-20261115"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    roster = read(RAW / "roster.json")
    index = read(ROOT / "assets/art/enemies/roster.json")
    enabled = read(ROOT / roster["manifest"])["enabled"]["task"]
    config = read(Path("C:/Users/Dev.LI/.codex/imagegen/config.json"))
    issues, entries, bodies = [], [], {}
    for entry in roster["entries"]:
        id_ = entry["id"]
        registered = index["enemies"].get(id_)
        record = {"asset_id": id_, "name": entry["name"], "requirement_ids": entry["requirements"],
                  "version": registered["version"] if registered else None}
        if not registered:
            record["status"] = "missing"
            issues.append(id_ + ": no registered art")
            entries.append(record)
            continue
        spec_file = ROOT / registered["rig"].removeprefix("res://")
        spec = read(spec_file)
        if spec["definition_id"] != id_:
            issues.append(id_ + ": wrong rig identity")
        record.update({"rig": registered["rig"], "rig_sha256": digest(spec_file),
                       "bones": len(spec["bones"]), "parts": len(spec["parts"]),
                       "meshes": sum(bool(p.get("mesh")) for p in spec["parts"])})
        body_file = ROOT / registered["texture"].removeprefix("res://")
        body_hash = digest(body_file)
        if body_hash in bodies:
            issues.append(id_ + ": duplicate body with " + bodies[body_hash])
        bodies[body_hash] = id_
        record["body_sha256"] = body_hash
        record["status"] = "selected_for_production_pending_user_art_review"
        record["visual_review"] = "See visual-review.json for actual AI observations; no human acceptance claimed."
        if id_ == "N01":
            record.update({"source_mode": "reuse_existing_reviewed_v4", "api_images": 0})
        else:
            source = read(spec_file.parent / "source.json")
            original = ROOT / source["source"]
            prompt = ROOT / entry["prompt_file"]
            prompt_hash = hashlib.sha256(prompt.read_text(encoding="utf-8").encode("utf-8")).hexdigest()
            if digest(original) != source["source_sha256"]:
                issues.append(id_ + ": source hash mismatch")
            if prompt_hash != entry["prompt_sha256"]:
                issues.append(id_ + ": prompt hash mismatch")
            with Image.open(original) as image:
                image.load()
                actual = list(image.size)
            if actual != [1024, 1024]:
                issues.append(id_ + ": unexpected original dimensions")
            outputs = []
            for part in source["outputs"]:
                path = ROOT / part["file"]
                with Image.open(path) as image:
                    image.load()
                    rgba = np.asarray(image.convert("RGBA")).astype(np.int16)
                    alpha = rgba[:, :, 3]
                    transparency = float(np.mean(alpha == 0))
                    opaque = alpha >= 128
                    magenta = opaque & (np.minimum(rgba[:, :, 0], rgba[:, :, 2]) - rgba[:, :, 1] > 100)
                    if transparency <= 0 or not np.any(opaque):
                        issues.append(id_ + ": no usable transparent foreground " + path.name)
                    if digest(path) != part["sha256"]:
                        issues.append(id_ + ": part hash mismatch " + path.name)
                    outputs.append({**part, "transparent_ratio": transparency,
                                    "opaque_magenta_pixels": int(magenta.sum())})
            record.update({"source_mode": "fallback_cli_generate-batch_text_only",
                           "api_images": 1, "service": config["base_url"], "model": config["model"],
                           "requested_size": "1024x1024", "requested_quality": "high",
                           "actual_size": actual, "prompt_file": entry["prompt_file"],
                           "prompt_sha256": prompt_hash, "prompt_file_sha256": digest(prompt),
                           "prompt_hash_note": "Prompt string uses LF as in JSONL requests; Windows text file byte hash is retained separately.",
                           "source_file": source["source"],
                           "source_sha256": digest(original), "uploaded_images": [],
                           "processing": source["method"], "outputs": outputs})
        entries.append(record)
    if set(index["enemies"]) != set(enabled):
        issues.append("registered IDs do not exactly match enabled task IDs")
    routes = [x for x in index["enemies"] if x.startswith("FY_ROUTE_")]
    route_bodies = [index["enemies"][x]["texture"] for x in routes]
    if len(routes) != 4 or len(set(route_bodies)) != 4:
        issues.append("four route bosses do not yet have independent bodies")
    generated = len(list(RAW.glob("*-v1.png")))
    manifest = {"scope": "60 exact task IDs enabled by campus_four_year; art only; normal game route",
                "requirements": ["UIR-069"], "expected": len(enabled), "registered": len(index["enemies"]),
                "new_images_successful": generated, "successful_before_this_task": 51,
                "successful_total": 51 + generated, "authorized_successful_limit": 200,
                "api_cost": "not returned; failed/cancelled request charges are unknown",
                "interruption": "remaining batch stopped at 33 successful new images with HTTP 403 insufficient balance; user confirmed balance replenishment; resume-01 only requests 26 absent outputs",
                "machine_status": "passed" if not issues else "incomplete_or_failed", "issues": issues,
                "art_acceptance": "AI visual review is recorded separately; user final review remains open",
                "entries": entries}
    (RAW / "asset-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (EV / "coverage.json").write_text(json.dumps({k: v for k, v in manifest.items() if k != "entries"},
                                               ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: manifest[k] for k in ["expected", "registered", "new_images_successful", "successful_total", "machine_status", "issues"]}, ensure_ascii=False))
    return bool(issues)


if __name__ == "__main__":
    raise SystemExit(main())
