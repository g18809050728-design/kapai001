"""Prepare, crop and install missing four-year art. No network or API calls."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from PIL import Image
from build_card_art_prompts import ROOT, STYLE

ART = ROOT / "docs/art"
OUT = ROOT / "output/imagegen/missing-art-four-year"
LAYOUT = ART / "missing-art-layout.json"
RECORDS = ART / "missing-art-assets.json"
REFERENCE = ROOT / "output/imagegen/card-atlas-v3-unified/style-reference.png"

BRIEFS = {
    "P02": "One adult Chinese woman, shoulder-length dark hair tied in a low ponytail, thin oval glasses, navy cardigan with a small muted lavender accent, holding a research notebook with blank tabbed pages. Calm organized expression; distinct from the reference's high-bun woman. Waist-up single portrait, front three-quarter view.",
    "P03": "One adult Chinese man with neat side-parted short dark hair, no glasses, sage-green jacket and a small muted plum accent, holding two blank index cards connected by a simple diagram. Thoughtful gently questioning expression; distinct from the reference's tousled-haired man. Waist-up single portrait, front three-quarter view. No poison, weapons or sinister costume.",
    "R3-U01": "One friendly adult Chinese student with short softly wavy hair, pale blue hoodie, holding an open exercise notebook, relaxed study companion. Waist-up single portrait, no glasses, no readable marks.",
    "R3-U02": "One attentive adult Chinese student with straight chin-length dark hair, mustard-yellow sweater, holding a closed book and simple pencil, quiet lecture-auditing classmate. Waist-up single portrait.",
    "R3-U03": "One dependable adult Chinese student with short cropped hair, rust-red overshirt over ivory T-shirt, holding a slim project folder with blank geometric tabs. Confident collaborative expression. Waist-up single portrait.",
    "FY_Y1_1": "A small folded campus guide booklet with a simple tree-lined campus map made of geometric paths, sage cover, no letters or numbers.",
    "FY_Y1_2": "A warm yellow canteen meal card beside a small ceramic rice bowl and chopsticks, simple original card graphic without text or logo.",
    "FY_Y1_3": "One old cream paper bookmark, softened corners, a pressed leaf and muted green tassel, gently worn but carefully kept.",
    "FY_Y1_4": "One round student-club enamel pin with an abstract sprout emblem, teal and warm yellow, no lettering or official crest.",
    "FY_Y2_1": "One plain sage laboratory access card with a minimal geometric chip and short blue lanyard, no lettering or portrait.",
    "FY_Y2_2": "One small bronze competition commemorative medal with abstract interlocking shapes, sage ribbon, no text or numerals.",
    "FY_Y2_3": "One sturdy engineering notebook with squared blank pages, short ruler and simple mechanical sketch made of circles and lines, muted navy cover.",
    "FY_Y2_4": "One slim deep-teal academic bookmark with a simple geometric cutout and lavender thread, neatly placed over a closed textbook.",
    "FY_Y3_1": "One unbranded internship identity badge on a short rust-red lanyard, abstract portrait silhouette and blank color bars only.",
    "FY_Y3_2": "One ivory recommendation envelope with a muted sage wax seal and a plain folded sheet peeking out, no writing.",
    "FY_Y3_3": "One lavender-bound research notebook opened to blank diagrams and colored tabs, small pencil resting diagonally, no equations or writing.",
    "FY_Y3_4": "One unbranded teal transit card and a small simple bus token, abstract route dots only, no letters or digits.",
    "FY_Y4_1": "One elegant deep-teal commemorative fountain pen with a small brass clip, beside its plain ivory presentation sleeve, no inscription.",
    "FY_Y4_2": "One small landscape graduation group photograph showing several simplified adult students in gowns under leafy campus trees, ivory photo border, no caption; anonymous miniature faces.",
    "FY_Y4_3": "One pale cream train ticket with a small generic train silhouette and abstract perforations, rust-red travel tag, no letters or numbers.",
    "FY_Y4_4": "One modest gold-colored degree commemorative pin with an abstract open-book and laurel emblem, sage ribbon, no university logo or letters.",
    "E01": "A substantial midterm exam paper stack, closed textbook and a simple hourglass, composed as a serious but friendly academic challenge, blank diagrams only.",
    "E02": "A course-design review folder, small cardboard engineering prototype and a pencil, neatly arranged for a mid-project check, no labels.",
    "E03": "A group-project sprint desk with three blank sticky-note columns, a small timer and shared folder, energetic but uncluttered.",
    "E04_1": "A modeling assignment represented by a small wireframe geometric model on a blank graph sheet and drafting compass, no formulae.",
    "E04_2": "A programming assignment represented by one laptop with simple colored code-like blocks and a small flowchart sheet, no actual text.",
    "E04_3": "A research-paper assignment represented by a bound cream manuscript, lavender tabs and an open reference book, no writing.",
    "E05": "A graduate summer research camp review represented by a presentation folder, campus building silhouette and small research diagram cards, no badges or lettering.",
    "E06": "An internship group interview represented by three empty chairs around a small table, a shared case-study folder and blank name cards, no people needed.",
    "E07": "A resit examination represented by a fresh exam sheet placed over a worn closed workbook, eraser and small hourglass, hopeful restrained mood.",
    "Q0A_1": "Requirements analysis represented by blank sticky notes connected by three clean arrows, small magnifying glass, ordered desk arrangement.",
    "Q0A_2": "Documentation writing represented by a tidy open binder, blank page blocks and a capped pen, sage divider tabs.",
    "Q0A_3": "Code development represented by a laptop with abstract colored module blocks and small branching diagram cards, no real code.",
    "Q0A_3_1": "Software test execution represented by a laptop with simple green check shapes and one amber warning shape, small desk timer, no text.",
    "Q0B_1": "A defense assignment represented by a thick project report and a simple poster board of diagrams waiting beside a chair, no text.",
    "Q0B_2": "An oral assignment defense represented by a small lectern, three blank question cards and a simple desktop microphone, no people or writing.",
    "Q0C": "An English proficiency examination represented by listening headphones, an answer sheet of empty bubbles and a pencil, no letters or numbers.",
    "Q0D": "An advanced English proficiency examination represented by listening headphones, a thicker blank reading booklet and a small hourglass, a muted lavender accent.",
    "Q0E_1": "A large academic project represented by a tall but tidy folder stack, cardboard prototype and one broad schedule diagram, no words.",
    "Q0E_2": "An additional project requirement represented by one rust-red sticky-note attachment clipped to a sage project folder, simple new diagram block, no text.",
    "Q0E_3": "A further project requirement represented by a mustard sticky-note attachment and two small new diagram sheets beside a project folder, distinct from the red attachment.",
    "N13": "An everyday homework pile with a pale blue exercise book, blunt pencil and three blank practice sheets, modest campus desk still life.",
    "N14": "Foundational mathematics represented by a graph notebook with simple triangles and curves, wooden ruler and drafting compass, no equations.",
    "N15": "A computer program represented by a small laptop, abstract branching blocks on its ivory screen and a tidy keyboard, no readable code.",
    "N16": "Class preparation represented by an open textbook, blank sticky tabs, highlighter and a small cup of tea, quiet pale desk.",
    "N17": "Literature reading represented by two open reference books, page clips and a magnifying glass over blank paragraph blocks.",
    "N18": "An English writing assignment represented by a cream writing notebook, simple speech-shape paper cutout and blue pen, no alphabet.",
    "N19": "A course project represented by a compact cardboard model, project folder and two connected planning cards, no letters.",
    "N20": "Advanced English vocabulary revision represented by a small ring of blank flashcards, colored divider tabs and a closed pocket dictionary.",
    "N21": "Pre-exam revision represented by a short stack of review booklets with colored tabs, a simple hourglass and a pencil, not frantic.",
    "N22": "Self-introduction practice represented by a tabletop microphone, blank profile card and a small round mirror, warm uncluttered still life.",
    "N23": "A group presentation represented by a small projection screen showing three abstract chart shapes and a shared folder on a lectern, no text.",
    "N24": "A campus physical fitness test represented by running shoes, a whistle and a plain stopwatch without digits, sage track curve in the background.",
    "N25": "An advisor meeting represented by two tea cups across a small table, open research notebook and a simple fountain pen, no people required.",
    "N26": "Lecture attendance represented by a folded lecture leaflet, plain ticket and several softly suggested auditorium seats, no lettering.",
    "N27": "A collaborative assignment represented by three hands arranging blank color-coded cards around a shared notebook, natural hands, simple close view.",
    "N28": "An early morning class represented by a sunrise window, a plain alarm clock with no digits and a half-open textbook, soft warm yellow light.",
    "N29": "Unreliable campus networking represented by a small router, laptop with a broken dotted connection symbol and a loose cable, gentle humorous academic nuisance.",
    "N30": "A research group update represented by an open laptop, small chart-only presentation board and neatly clipped progress sheets.",
    "N31": "An advisor's progress reminder represented by a desk calendar with empty squares, a growing folder stack and a small plain notification bell, no chat text.",
    "N32": "Scholarship evaluation represented by a simple laurel token, a portfolio folder and three blank assessment sheets, no medals with writing.",
    "N33": "Academic similarity checking represented by two manuscript sheets under a magnifying glass, matching abstract lines linked by a small loop, no percentages.",
    "N34": "Library seat reservation represented by one empty wooden study chair, a closed book and a backpack beside the desk, quiet pale background.",
    "N35": "An internship interview represented by a blank resume folder, two chairs across a small table and a neutral office plant, no faces needed.",
    "N36": "Language-test registration represented by a plain application form of empty boxes, pencil and unbranded student card, no letters or digits.",
    "N37": "An online examination represented by one laptop with a blank question-sheet layout, small webcam and simple unnumbered timer, no text.",
    "N38": "Peer evaluation represented by three blank evaluation cards with simple colored dots, several pencils and a shared project folder, no stars with numbers.",
    "FY_B1_TASK": "A first-year comprehensive assessment represented by an open mathematics workbook, small lab notebook and fresh green campus sprout, clear ceremonial arrangement with lots of ivory space.",
    "FY_B2_TASK": "A second-year comprehensive assessment represented by an engineering prototype, structured course binder and bronze competition token, sage and muted blue, uncluttered.",
    "FY_B3_TASK": "A third-year comprehensive review represented by a research portfolio, small chart board and an internship badge, calm mature academic milestone, no writing.",
    "FY_B4_TASK": "A graduation defense represented by a completed thesis, small lectern and a graduation cap with sage tassel, restrained warm celebratory academic challenge, no text or official insignia.",
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def config():
    return json.loads((Path.home() / ".codex/imagegen/config.json").read_text(encoding="utf-8-sig"))

def prepare():
    labels_path = ROOT / "src/ui/ui_labels.json"
    labels = json.loads(labels_path.read_text(encoding="utf-8-sig"))
    manifest_path = ROOT / "data/four_year/manifests/campus_four_year.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    assets = []
    for kind, filename, category in [("character", "characters", "portraits"), ("unit", "units", "portraits"), ("relic", "relics", "relics"), ("task", "tasks", "tasks")]:
        definition_path = ROOT / f"data/four_year/definitions/{filename}.json"
        for item in json.loads(definition_path.read_text(encoding="utf-8-sig")):
            asset_id = item["id"]
            if asset_id not in manifest["enabled"][kind]:
                continue
            key = labels["aliases"].get(asset_id, asset_id)
            existing = labels["textures"].get(key, "")
            if existing and (ROOT / existing.removeprefix("res://")).is_file():
                continue
            if asset_id not in BRIEFS:
                raise ValueError(f"Missing subject brief: {asset_id}")
            assets.append({"asset_id": asset_id, "kind": kind, "category": category,
                           "name": labels["labels"].get(asset_id, item["name_key"]),
                           "brief": BRIEFS[asset_id], "requirement_id": "FY-ART-002",
                           "definition_file": definition_path.relative_to(ROOT).as_posix(),
                           "output": f"assets/art/four-year/{category}/{asset_id}-v1.png"})
    if LAYOUT.exists():
        layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
        # A frozen layout remains the source of truth after installation.
        if assets and {x["asset_id"] for x in assets} != {x["asset_id"] for x in layout["assets"]}:
            raise ValueError("Missing-set changed; create a new version instead of rewriting this batch")
    else:
        if len(assets) != 71 or set(BRIEFS) != {a["asset_id"] for a in assets}:
            raise ValueError(f"Expected the audited 71 missing assets, found {len(assets)}")
        layout = {"version": 1, "requirement_id": "FY-ART-002", "manifest_id": manifest["id"],
                  "manifest_file": manifest_path.relative_to(ROOT).as_posix(), "manifest_sha256": sha(manifest_path),
                  "reference_file": REFERENCE.relative_to(ROOT).as_posix(), "reference_sha256": sha(REFERENCE),
                  "requested_size": [1024, 1536], "columns": 2, "rows": 4,
                  "asset_counts": dict(Counter(a["kind"] for a in assets)), "assets": assets, "batches": []}
        cfg = config()
        for start in range(0, len(assets), 8):
            batch_id = f"FY-ART-{start // 8 + 1:02d}"
            prompt_file = ART / "missing-art-prompts" / f"{batch_id}.txt"
            source = OUT / f"{batch_id}-v1.png"
            slots = []
            lines = [
                "Use case: illustration-story. Create ONE sprite atlas containing EIGHT independent campus-game assets, not eight variants.",
                "Input image is a STYLE REFERENCE from this game's installed art. Match its delicate dark-teal ink contours, simplified adult proportions, luminous ivory paper, flat translucent watercolor washes and sparse shadows. Do not copy its six subjects or 3x2 layout.",
                "Canvas exactly 1024 x 1536 pixels. Strict 2 columns x 4 rows of equal 512 x 384 cells, row-major from top left. No outer margin, gutters, borders, title, numbering or labels. No merged cells, extra panels or cross-cell objects.",
                "Shared art direction: " + STYLE,
                "Every cell has at least 35 percent quiet pale ivory background. One readable subject, simplified objects, gentle natural light. No photorealism, dense room scenery, dramatic shadows, horror, weapons, or poisoning people.",
                "No readable text, letters, numerals, equations, logos, official university crests, watermarks, UI or speech bubbles. All pages, cards, badges and screens use blank geometry. Asset IDs are instructions only, NEVER draw them.",
                "PORTRAIT cells: a single waist-up adult, complete hair/head and hands contained in the central narrow 4:5 portrait window, local pixel x=112..400 and y=12..372. No full-width landscape or multiple people in a portrait cell. Light ivory side areas are disposable.",
                "OBJECT/TASK cells: one compact scene with the important subject inside central 70 percent. Final crop is local x=16..496 and y=12..372; keep all essential objects in that rectangle. No elements across cell boundaries.",
            ]
            for index in range(8):
                row, col = divmod(index, 2)
                asset = assets[start + index] if start + index < len(assets) else None
                portrait = asset and asset["category"] == "portraits"
                inset_x = 112 if portrait else 16
                slot = {"slot": index + 1, "row": row + 1, "column": col + 1,
                        "asset_id": asset["asset_id"] if asset else None,
                        "crop": [col * 512 + inset_x, row * 384 + (0 if portrait else 12), (col + 1) * 512 - inset_x, row * 384 + (360 if portrait else 372)]}
                slots.append(slot)
                if asset:
                    lines.append(f"Row {row+1}, column {col+1}, {'PORTRAIT' if portrait else 'OBJECT/TASK'}: {asset['brief']}")
                else:
                    lines.append(f"Row {row+1}, column {col+1}: unused cell, empty warm ivory paper only.")
            lines.append("Final check: exactly 2 columns and 4 equal rows. Keep every assigned subject in its own slot and its specified safe crop. No text or extra decoration.")
            prompt = "\n".join(lines)
            prompt_file.parent.mkdir(parents=True, exist_ok=True)
            prompt_file.write_text(prompt, encoding="utf-8")
            layout["batches"].append({"batch_id": batch_id, "prompt_file": prompt_file.relative_to(ROOT).as_posix(),
                                      "prompt_sha256": sha(prompt_file), "source_file": source.relative_to(ROOT).as_posix(),
                                      "provider": cfg["base_url"], "model": cfg["model"], "quality": "medium", "n": 1, "slots": slots})
        write(LAYOUT, layout)
    jobs = [{"operation": "edit", "batch_id": b["batch_id"], "image": layout["reference_file"],
             "prompt_file": b["prompt_file"], "prompt_sha256": b["prompt_sha256"], "out": b["source_file"],
             "model": b["model"], "size": "1024x1536", "quality": b["quality"], "n": 1} for b in layout["batches"]]
    for name, subset in [("jobs", jobs), ("pending", [j for j in jobs if not (ROOT / j["out"]).exists()])]:
        (ART / f"missing-art-{name}.jsonl").write_text("".join(json.dumps(j, ensure_ascii=False) + "\n" for j in subset), encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    print(json.dumps({"assets": len(layout["assets"]), "batches": len(jobs), "counts": layout["asset_counts"], "pending": sum(not (ROOT / j["out"]).exists() for j in jobs)}))

def crop(install=False):
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    review_path = OUT / "visual-review.json"
    reviews = json.loads(review_path.read_text(encoding="utf-8")) if review_path.exists() else {}
    records = {}
    if RECORDS.exists():
        records = {x["asset_id"]: x for x in json.loads(RECORDS.read_text(encoding="utf-8"))["assets"]}
    labels_path = ROOT / "src/ui/ui_labels.json"
    labels = json.loads(labels_path.read_text(encoding="utf-8-sig"))
    assets = {a["asset_id"]: a for a in layout["assets"]}
    for batch in layout["batches"]:
        source = ROOT / batch["source_file"]
        if not source.exists():
            if install: raise ValueError(f"Missing atlas: {source}")
            continue
        source_hash = sha(source)
        review = reviews.get(batch["batch_id"], {})
        if sha(ROOT / batch["prompt_file"]) != batch["prompt_sha256"]:
            raise ValueError("Prompt provenance changed")
        if install and (not review.get("approved_for_prototype") or review.get("source_sha256") != source_hash):
            raise ValueError(f"Missing matching visual review: {batch['batch_id']}")
        with Image.open(source) as image:
            image.load()
            if image.size != (1024, 1536):
                raise ValueError(f"Unexpected atlas size: {source.name} {image.size}")
            for slot in batch["slots"]:
                asset_id = slot["asset_id"]
                if not asset_id: continue
                asset = assets[asset_id]
                candidate = OUT / "crops" / (asset_id + "-v1.png")
                candidate.parent.mkdir(parents=True, exist_ok=True)
                image.crop(slot["crop"]).convert("RGB").save(candidate)
                dest = ROOT / asset["output"] if install else candidate
                if install:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    if dest.exists() and dest.read_bytes() != candidate.read_bytes():
                        raise ValueError(f"Refuse to overwrite different installed image: {dest}")
                    dest.write_bytes(candidate.read_bytes())
                    labels["textures"][asset_id] = "res://" + asset["output"]
                records[asset_id] = asset | {"batch_id": batch["batch_id"], "generated": True, "selected": install,
                    "status": "selected_for_prototype" if install else "generated_candidate", "version": 1,
                    "source_file": batch["source_file"], "source_sha256": source_hash, "slot": slot,
                    "prompt_file": batch["prompt_file"], "prompt_sha256": batch["prompt_sha256"],
                    "reference_file": layout["reference_file"], "reference_sha256": layout["reference_sha256"],
                    "provider": batch["provider"], "model": batch["model"], "api_mode": "bundled imagegen CLI edit with uploaded style reference, n=1",
                    "quality": batch["quality"], "requested_size": [1024, 1536], "actual_atlas_size": list(image.size),
                    "size": [slot["crop"][2] - slot["crop"][0], slot["crop"][3] - slot["crop"][1]],
                    "candidate_file": candidate.relative_to(ROOT).as_posix(), "output": dest.relative_to(ROOT).as_posix(), "sha256": sha(dest),
                    "processing": "Pillow fixed crop to RGB PNG; no resampling", "ai_visual_review": review if install else None,
                    "human_acceptance": "pending", "license_review": "provider terms not independently verified",
                    "recorded_utc": datetime.now(timezone.utc).isoformat()}
    if install:
        # Encounters and their live task share artwork; stages never need another paid image.
        encounters = json.loads((ROOT / "data/four_year/definitions/encounters.json").read_text(encoding="utf-8-sig"))
        for encounter in encounters:
            members = encounter.get("initial_members", encounter["members"])
            if encounter["id"] not in labels["textures"] and encounter["id"] not in labels["aliases"] and members:
                labels["aliases"][encounter["id"]] = members[0]
        write(labels_path, labels)
    write(RECORDS, {"version": 1, "requirement_id": "FY-ART-002", "planned_count": 71,
                    "generated_count": len(records), "selected_count": sum(x["selected"] for x in records.values()), "assets": list(records.values())})
    print(json.dumps({"generated": len(records), "selected": sum(x["selected"] for x in records.values())}))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "crop", "install"])
    args = parser.parse_args()
    prepare() if args.action == "prepare" else crop(args.action == "install")
