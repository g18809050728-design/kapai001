"""Cut selected V2 atlas cells into production icons without touching V1 or requesting images."""
from __future__ import annotations
import hashlib
import json
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlsplit
from PIL import Image, ImageDraw, ImageFont
from process_relic_pilot_art import extract

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'output/imagegen/relic-roster-20261120'
OUT = ROOT / 'assets/art/relic-roster-v2'
EVIDENCE = ROOT / 'artifacts/verification/relic-roster-20261120'
ORIGINAL = ROOT / 'assets/art/relic-pilot'


# Hand-reviewed crop cleanup. Each destination only contains an atlas neighbor's
# fringe; use spare paper from the same selected image, not a new illustration.
PAPER_CLEANUP = {
    'RX-C12': ((126, 226, 192, 255), (187, 225)),
    'RX-C32': ((0, 72, 16, 109), (1, 35)),
    'RX-P01-01': ((46, 224, 111, 251), (46, 190)),
    'RX-P02-03': ((12, 126, 54, 195), (13, 42)),
    'RX-P02-13': ((0, 117, 23, 185), (0, 28)),
}


def remove_atlas_fringe(icon, region):
    x0, y0, x1, y1 = region[0]
    sx, sy = region[1]
    width, height = x1 - x0, y1 - y0
    paper = icon.crop((sx, sy, sx + width, sy + height))
    mask = Image.new('L', paper.size)
    for y in range(height):
        for x in range(width):
            d = min(x if x0 else 6, y if y0 else 6,
                    width - 1 - x if x1 < icon.width else 6,
                    height - 1 - y if y1 < icon.height else 6)
            mask.putpixel((x, y), min(255, round(255 * d / 6)))
    icon.paste(paper, (x0, y0), mask)


def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


@lru_cache(maxsize=None)
def source_sha(p):
    return sha(p)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    cfg = read(Path.home() / '.codex/imagegen/config.json')
    jobs = {row['out']: row for file in sorted(ART.glob('*.jsonl')) for row in map(json.loads, file.read_text(encoding='utf-8-sig').splitlines())}
    sheets = read(ART/'sheet-index.json')
    if (ART/'corrections-index.json').is_file():
        sheets += read(ART/'corrections-index.json')
    cells = {}
    exclusions = set(read(ART/'v1-retained.json')) if (ART/'v1-retained.json').is_file() else set()
    for sheet in sheets:
        for i, id_ in enumerate(sheet['cells']):
            if id_ and id_ not in exclusions:
                cells[id_] = (sheet['file'], i)
    records = []
    for id_, (file, i) in cells.items():
        src = ART/'raw'/file
        with Image.open(src) as im:
            icon = extract(im, i, 2, 2)
        cleanup = PAPER_CLEANUP.get(id_)
        if cleanup:
            remove_atlas_fringe(icon, cleanup)
        dst = OUT/f'{id_}.webp'
        icon.save(dst, 'WEBP', lossless=True, method=6)
        record = dict(id=id_,version=2,file=dst.relative_to(ROOT).as_posix(),sha256=sha(dst),source=src.relative_to(ROOT).as_posix(),source_sha256=source_sha(src),cell=i+1,model=cfg['model'],service=urlsplit(cfg['base_url']).hostname,prompt_sha256=hashlib.sha256(jobs[file]['prompt'].encode('utf-8')).hexdigest(),size=[256,256])
        record['processing'] = 'Extract reviewed atlas cell; 256px lossless WebP'
        if cleanup:
            record['paper_cleanup'] = {'region': cleanup[0], 'donor_xy': cleanup[1], 'feather_px': 6}
        records.append(record)
    (OUT/'asset-manifest.json').write_text(json.dumps(records, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    ordered=sorted(cells)
    font=ImageFont.load_default(size=12)
    # V1 and V2 side-by-side at a true 64px icon size; clickable larger originals in the final review.
    for offset in range(0,len(ordered),24):
        subset=ordered[offset:offset+24]
        page=Image.new('RGB',(912,91*((len(subset)+5)//6)), '#202b2b')
        drawer=ImageDraw.Draw(page)
        for i,id_ in enumerate(subset):
            x=(i%6)*152+8; y=(i//6)*91+4
            for side,parent in enumerate([ORIGINAL,OUT]):
                with Image.open(parent/f'{id_}.webp') as im:
                    page.paste(im.resize((64,64),Image.Resampling.LANCZOS),(x+side*67,y))
            drawer.text((x,y+65),id_,fill='#f0dfb5',font=font)
        page.save(EVIDENCE/f'art-v1-v2-{1+offset//24}.jpg',quality=94)
    print(f'{len(records)} V2 icons, {len(list(ART.glob("raw/*.png")))} raw atlas outputs')

if __name__ == '__main__':
    main()
