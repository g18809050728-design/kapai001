"""Prepare eight-cell image jobs and crop reviewed atlases; makes no API calls."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from PIL import Image

from build_card_art_prompts import ANCHORS, ROOT, STYLE

ART = ROOT / "docs/art"
OUTPUT = ROOT / "output/imagegen/card-atlas-v3-unified"
ASSETS = ART / "card-art-assets-v3.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def prepare():
    entries = json.loads((ART / "card-art-prompts-v3.json").read_text(encoding="utf-8"))["entries"]
    groups = [[e for e in entries if e["owner"] == owner and not e["card_id"].startswith("R3-T")]
              for owner in ["P01", "P02", "P03", "P04"]]
    groups.append([e for e in entries if e["owner"] == "C" or e["card_id"].startswith("R3-T")])
    batches, jobs = [], []
    for group in groups:
        for start in range(0, len(group), 8):
            bid = f"R3-ATLAS-{len(batches) + 1:02d}"
            lines = [
                "Use case: illustration-story. Produce ONE production sprite atlas of EIGHT separate campus card illustrations.",
                "Input image is a STYLE REFERENCE and P01/P04 identity reference from this game's existing art. Match its thin ink contours, bright ivory paper, flat translucent watercolor washes, simplified forms and spacious quiet backgrounds. Do NOT copy its 3x2 layout or its six subjects. Draw the eight NEW assigned scenes below in a strict 2x4 layout.",
                "Canvas: exactly 1024 x 1536 pixels, portrait. Strict 2 columns x 4 rows, equal 512 x 384 cells. Read row-major from top left.",
                "The entire canvas is filled by these eight cells. No outer margin, gutters, border, title, labels or numbering. Separate scenes at the exact halfway vertical boundary and four equal horizontal bands. NEVER combine cells or change their size/order.",
                "Shared art direction: " + STYLE,
                "Each cell is one horizontal 4:3 independent scene, NOT a card frame or a panel of a continuing comic. Match the existing game's gentle 2D ink-and-watercolor drawing, NOT realistic painting. Each scene should have at least 35 percent calm pale ivory background. Simple broad color washes; minimal material detail; one readable silhouette, natural adult hands. No dense laboratory scenery or dark cinematic shadows. The reference's linework and brightness take priority over descriptive complexity.",
                "Composition within EACH cell: essential objects and gestures inside central 70%, expendable quiet background at edges. The crop removes 16px from left/right and 12px from top/bottom of EACH cell. No subject, light trail, limb or object may cross into another cell.",
                "No readable text, letters, numerals, equations, branding, campus logos, watermarks, labels, UI, speech bubbles, trading card frames, exaggerated anatomy, weapons or horror. Blank pages and simple geometric diagrams only. Slot IDs below are instructions, NEVER draw them.",
            ]
            slots = []
            for i in range(8):
                row, col = divmod(i, 2)
                e = group[start+i] if start+i < len(group) else None
                crop = [col*512+16, row*384+12, (col+1)*512-16, (row+1)*384-12]
                slot = {"slot": i+1, "row": row+1, "column": col+1, "card_id": e["card_id"] if e else None, "crop": crop}
                slots.append(slot)
                if e:
                    owner = "P02" if e["card_id"].startswith("R3-T") else e["owner"]
                    lines.append(f"Row {row+1}, column {col+1}: {ANCHORS[owner]} 主体场景：{e['subject']}。")
                else:
                    lines.append(f"Row {row+1}, column {col+1}: unused cell; plain warm ivory paper texture only, completely empty.")
            lines.append("Final count check: exactly 2 columns and 4 equal-height rows. Keep every requested scene in its assigned slot. No additional panels or outer margin.")
            # The CLI strips surrounding whitespace before sending the payload.
            prompt = "\n".join(lines)
            pp = ART / "atlas-prompts-v3" / f"{bid}.txt"
            pp.parent.mkdir(parents=True, exist_ok=True)
            source_path = OUTPUT / f"{bid}-v2.png"
            if source_path.exists() and pp.exists() and pp.read_text(encoding="utf-8") != prompt:
                raise ValueError(f"Do not change prompts for existing output {source_path.name}; create a new version")
            pp.write_text(prompt, encoding="utf-8")
            batches.append({"batch_id": bid, "prompt_file": pp.relative_to(ROOT).as_posix(), "prompt_sha256": sha(pp), "source_file": f"output/imagegen/card-atlas-v3-unified/{bid}-v2.png", "slots": slots})
            jobs.append({"operation": "edit", "reference_image": "output/imagegen/card-atlas-v3-unified/style-reference.png", "prompt": prompt, "out": bid+"-v2.png", "size": "1024x1536", "quality": "medium", "n": 1})
    assert len(jobs) == 22
    corrections_path = ART / "card-atlas-corrections-v3.json"
    if corrections_path.exists():
        correction = json.loads(corrections_path.read_text(encoding="utf-8"))
        corrected_ids = {s["card_id"] for s in correction["slots"]}
        for batch in batches:
            for slot in batch["slots"]:
                if slot["card_id"] in corrected_ids:
                    slot.update(original_card_id=slot["card_id"], superseded_by=correction["batch_id"], card_id=None)
        pp = ROOT / correction["prompt_file"]
        batches.append({k: v for k, v in correction.items() if k not in ["reason", "reference_image"]} | {"prompt_sha256": sha(pp)})
        jobs.append({"operation": "edit", "reference_image": correction["reference_image"], "prompt": pp.read_text(encoding="utf-8"), "out": Path(correction["source_file"]).name, "size": "1024x1536", "quality": "medium", "n": 1})
    ids = [s["card_id"] for b in batches for s in b["slots"] if s["card_id"]]
    assert len(ids) == 174 and len(set(ids)) == 174
    write(ART / "card-atlas-layout-v3.json", {"version": 1, "columns": 2, "rows": 4, "requested_size": [1024,1536], "crop_size": [480,360], "batches": batches})
    for filename, subset in [("card-atlas-jobs-v3.jsonl", jobs), ("card-atlas-pilot-v3.jsonl", jobs[:1])]:
        (ART / filename).write_text("".join(json.dumps(j, ensure_ascii=False)+"\n" for j in subset), encoding="utf-8")
    pending = [j for j in jobs if not (OUTPUT / j["out"]).exists()]
    (ART / "card-atlas-pending-v3.jsonl").write_text("".join(json.dumps(j, ensure_ascii=False)+"\n" for j in pending), encoding="utf-8")
    if not ASSETS.exists():
        write(ASSETS, {"version": 1, "requirement_id": "FY-ART-001", "assets": []})
    print(f"Prepared {len(jobs)} atlases / {len(ids)} cards; pending: {len(pending)}. No API calls.")


def crop(install=False):
    layout = json.loads((ART / "card-atlas-layout-v3.json").read_text(encoding="utf-8"))
    config = json.loads((Path.home() / ".codex/imagegen/config.json").read_text(encoding="utf-8-sig"))
    review_file = OUTPUT / "visual-review.json"
    reviews = json.loads(review_file.read_text(encoding="utf-8")) if review_file.exists() else {}
    existing = json.loads(ASSETS.read_text(encoding="utf-8"))
    records = {a["asset_id"]: a for a in existing["assets"]}
    labels_path = ROOT / "src/ui/ui_labels.json"
    labels = json.loads(labels_path.read_text(encoding="utf-8-sig"))
    count = 0
    for batch in layout["batches"]:
        source = ROOT / batch["source_file"]
        if not source.exists():
            continue
        source_hash = sha(source)
        reviewed = reviews.get(batch["batch_id"], {})
        if install and (not reviewed.get("approved_for_prototype") or reviewed.get("source_sha256") != source_hash):
            raise ValueError(f"Missing matching AI visual review: {source.name}")
        correction_reference = ART / "card-atlas-corrections-v3.json"
        correction = json.loads(correction_reference.read_text(encoding="utf-8")) if correction_reference.exists() else {}
        reference_file = correction.get("reference_image") if batch["batch_id"] == correction.get("batch_id") else "output/imagegen/card-atlas-v3-unified/style-reference.png"
        with Image.open(source) as im:
            im.load()
            if im.size != (1024,1536):
                raise ValueError(f"Unexpected atlas dimensions: {source.name}: {im.size}")
            for slot in batch["slots"]:
                cid = slot["card_id"]
                if not cid:
                    continue
                if not install and records.get(cid, {}).get("selected"):
                    if records[cid]["source_sha256"] != source_hash:
                        raise ValueError(f"Selected source changed: {cid}")
                    continue
                relative = f"assets/cards/v3/{cid}.png" if install else f"output/imagegen/card-atlas-v3-unified/crops/{cid}.png"
                dest = ROOT / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                im.crop(slot["crop"]).convert("RGB").save(dest)
                record = {"asset_id": cid, "requirement_id": "FY-ART-001", "version": 2, "generated": True, "selected": install,
                          "status": "selected_for_prototype" if install else "generated_candidate", "batch_id": batch["batch_id"],
                          "prompt_file": batch["prompt_file"], "prompt_sha256": batch["prompt_sha256"], "provider": config["base_url"], "model": config["model"],
                          "api_mode": "bundled imagegen CLI edit with existing-art style reference; n=1", "quality": "medium", "requested_size": [1024,1536], "actual_atlas_size": list(im.size),
                          "source_file": batch["source_file"], "source_sha256": source_hash, "slot": slot, "processing": "Pillow crop then RGB PNG, no resampling", "size": [480,360],
                          "output": relative, "sha256": sha(dest), "reference_mode": "uploaded existing-game art contact sheet; objects-only subset for corrections", "reference_file": reference_file, "reference_sha256": sha(ROOT / reference_file), "seed": None,
                          "ai_visual_review": reviewed if install else None, "human_acceptance": "pending", "license_review": "provider terms not independently verified",
                          "recorded_utc": datetime.now(timezone.utc).isoformat()}
                records[cid] = record
                if install:
                    labels["textures"][cid] = "res://"+relative
                count += 1
    existing.update(assets=list(records.values()), generated_count=len(records), selected_count=sum(a["selected"] for a in records.values()))
    write(ASSETS, existing)
    if install:
        write(labels_path, labels)
    print(f"{'Installed' if install else 'Cropped'} {count} cards; original atlases retained.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "crop", "install"])
    args = parser.parse_args()
    if args.action == "prepare":
        prepare()
    else:
        crop(install=args.action == "install")
