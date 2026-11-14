"""Build original campus ink symbols with one optical/stroke system; no external art."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/map/glyphs"
OUT.mkdir(parents=True, exist_ok=True)
GLYPHS = {
    "N": '''<path d="M12 7 28 6 35 13 36 39 12 40Z M28 7 28 14 35 14 M17 20 26 20 M17 26 25 26 M17 32 22 32"/>
<path d="m26 35 3-7L39 15q2-2 4 1l-10 14Z" fill="white" stroke-width="1.4"/>''',
    "EL": '''<path d="M10 14 9 40 34 40 35 20 M6 19 5 44 29 44 M15 22 25 22 M15 28 22 28 M15 34 24 34"/>
<path d="m24 3 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z" fill="white" stroke-width="1.4"/>
<path d="m34 36 3-7 6-7"/>''',
    "B": '''<path d="M16 39Q6 34 7 23 M9 30 4 25 M11 34 5 32 M14 38 9 39 M8 24 5 18 M9 18 8 12 M32 39q10-5 9-16 M39 30l5-5 M37 34l6-2 M34 38l5 1 M40 24l3-6 M39 18l1-6"/>
<path d="m10 16 14-7 14 7-14 7Z" fill="white" stroke-width="1.4"/>
<path d="M16 23v7q8 7 16 0v-7 M36 18v13 M18 38q6 3 12 0"/>
<path d="M21 4h6 M24 2v4"/>''',
    "S": '''<path d="m17 6 5 2 7-2 3 1-5 9q11 8 12 17 1 10-15 10T9 33q1-10 12-17Z"/>
<path d="M18 17q6 3 13 0 M28 25q-7-4-9 1-2 4 5 5t4 7q-5 2-10-1 M24 23v17"/>
<path d="M12 32q-2 7 4 9" stroke-width="1.3"/>''',
    "R": '''<path d="M7 17 6 40 M41 22v18 M7 31h34 M8 24q8-3 17 0l15 1v11H7 M25 24v11 M11 21q4-5 9 0v5h-9Z"/>
<path d="M28 6h8l-8 9h8 M37 3h5l-4 5h5" stroke-width="1.8"/>''',
    "L": '''<path d="M24 12q-9-7-19-5l1 29q10-2 18 5 8-7 18-5l1-29q-10-2-19 5v29 M10 13q5 0 9 3 M10 20q5 0 9 3 M10 27q5 0 9 3 M29 16q5-3 9-3 M29 23q5-3 9-3 M29 30q5-3 9-3"/>
<path d="M2 12 3 40q11-2 21 4 10-6 21-4l1-28" stroke-width="1.25"/>''',
    "LAB": '''<path d="M18 5h12 M20 6v14L8 38q-3 5 3 5h26q6 0 3-5L28 20V6 M17 28q7-3 14 0 M18 37h10"/>
<circle cx="25" cy="32" r="1.8" fill="white" stroke="none"/><circle cx="32" cy="37" r="1.4" fill="white" stroke="none"/>
<path d="m12 12 3 3 M8 19h4" stroke-width="1.4"/>''',
    "K": '''<path d="M13 7q10-2 22 0l-2 16q-1 7-9 10-8-3-9-10Z M13 11H6q-1 15 11 16 M35 11h7q1 15-11 16 M24 33v8 M16 43q8-3 16 0 M20 12v9"/>
<path d="m23 14 2 4 4 1-3 3v4l-3-2-4 2 1-4-3-3 4-1Z" fill="white" stroke="none"/>''',
    "C": '''<path d="M16 16q-1-7 7-8 8 0 9 7 0 7-8 7-7 0-8-6Z M18 26q6-4 12 0l3 15H15Z M9 15q-6 0-6 6t7 6 M7 31q-5 0-5 9h9 M39 15q6 0 6 6t-7 6 M41 31q5 0 5 9h-9"/>
<path d="M20 31h8 M23 35h3" stroke-width="1.4"/>''',
    "T": '''<path d="m4 16 20-9 20 9-20 9Z M12 22v11q11 9 24 0V22 M41 18v16 M39 34h4l1 5h-6Z"/>
<path d="M16 39q8 5 16 0" stroke-width="1.4"/>
<path d="m17 15 7-3 7 3-7 3Z" fill="white" stroke="none"/>''',
    "I": '''<path d="M7 17q16-2 34 0l1 23q-17 4-36 0Z M17 16V9q7-3 14 0v7 M7 25q16 7 34 0 M21 26h6v8h-6Z M10 36v2 M38 36v2"/>
<path d="M21 11h6" stroke-width="1.3"/>''',
    "ST": '''<path d="M11 7q15 3 27-1l-1 29q-14 4-26 0Z M11 7Q4 4 5 12q1 5 6 3 M11 35q-7-2-6 5 1 6 9 3h20 M17 15h14 M17 21h11 M17 27h7"/>
<path d="m32 29 5 3 1 5-5 2-4-3Z" fill="white" stroke-width="1.4"/>
<path d="m32 39-1 6 4-2 3 1-1-6" stroke-width="1.6"/>''',
    "E": '''<path d="M40 24q0 17-16 18Q7 41 6 25 6 8 23 7q16-1 17 17Z" stroke-width="2.3"/>
<path d="M18 18q2-6 8-4 7 3 1 9-4 3-4 7" stroke-width="4.1"/>
<circle cx="23" cy="36" r="2.1" fill="white" stroke="none"/>''',
}
records = {}
for key, paths in GLYPHS.items():
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 48 48"><g fill="none" stroke="white" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round">' + paths + '</g></svg>\n'
    target = OUT / (key.lower() + ".svg")
    target.write_text(svg, encoding="utf-8")
    records[key] = {"file": target.name, "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}
(OUT / "source.json").write_text(json.dumps({"origin": "Original campus vector paths authored for UIR-019/063 composition correction",
    "viewbox": [48, 48], "base_stroke": 2.25, "external_images": False, "game_rng_used": False, "glyphs": records}, indent=2) + "\n", encoding="utf-8")
print("Built", len(records), "original glyphs")
