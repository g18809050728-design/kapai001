"""Slice API relic sheets, retain provenance, and make contact sheets for actual review."""
from __future__ import annotations

import hashlib
import json
import os
from statistics import median
from pathlib import Path
from urllib.parse import urlsplit

from PIL import Image, ImageDraw, ImageFont, ImageFilter

from build_relic_pilot_catalog import ART, ROOT, PACKAGE, dump

OUT = ROOT / 'assets/art/relic-pilot'
EVIDENCE = ROOT / 'artifacts/verification/relic-pilot-20261120'
SIZE = 256


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(sheet: Image.Image, slot: int, cols: int = 2, rows: int = 4) -> Image.Image:
    col, row = slot % cols, slot // cols
    w, h = sheet.size
    cell = sheet.crop((col * w // cols, row * h // rows, (col + 1) * w // cols, (row + 1) * h // rows)).convert('RGB')
    return fit(cell)


def fit(cell: Image.Image) -> Image.Image:
    # Trim only empty paper automatically. Preserve proportions, edges, and shadows.
    cw, ch = cell.size
    corners = [cell.getpixel((x, y)) for x, y in [(5, 5), (cw-6, 5), (5, ch-6), (cw-6, ch-6)]]
    paper = tuple(int(median(p[channel] for p in corners)) for channel in range(3))
    dark = cell.convert('L').filter(ImageFilter.GaussianBlur(2))
    cutoff = int(median(dark.getpixel((x, y)) for x, y in [(5,5),(cw-6,5),(5,ch-6),(cw-6,ch-6)])) - 28
    mask = dark.point(lambda lum: 255 if lum < cutoff else 0)
    probe = mask.resize((max(1,cw//8),max(1,ch//8)),Image.Resampling.BOX).point(lambda lum: 255 if lum > 74 else 0)
    bounded = probe.getbbox()
    if bounded is not None:
        x0,y0,x1,y1 = (v*8 for v in bounded)
        cell = cell.crop((max(0,x0-22),max(0,y0-22),min(cw,x1+22),min(ch,y1+22)))
    cell.thumbnail((SIZE, SIZE), Image.Resampling.LANCZOS)
    if max(cell.size) < SIZE:
        scale = SIZE / max(cell.size)
        cell = cell.resize(tuple(round(d*scale) for d in cell.size), Image.Resampling.LANCZOS)
    padded = Image.new('RGB', (SIZE,SIZE), paper)
    # Fade the last few pixels of original blank paper into the padding, not the subject.
    width,height = cell.size
    alpha = Image.new('L', cell.size)
    pen = ImageDraw.Draw(alpha)
    for border in range(10):
        pen.rectangle((border,border,width-border-1,height-border-1), fill=round(255*(border+1)/10))
    padded.paste(cell, ((SIZE-width)//2,(SIZE-height)//2), alpha)
    return padded


def contact(ids: list[str], page: int) -> None:
    stride = 138
    board = Image.new('RGB',(stride*8, stride*((len(ids)+7)//8)), '#e2ded2')
    draw = ImageDraw.Draw(board)
    font = ImageFont.load_default(size=13)
    for i, id_ in enumerate(ids):
        x, y = i%8*stride, i//8*stride
        with Image.open(OUT/f'{id_}.webp') as im:
            im.thumbnail((110,110),Image.Resampling.LANCZOS)
            board.paste(im,(x+14,y+5))
        draw.text((x+14,y+117),id_,font=font,fill='#172922')
    board.save(EVIDENCE/f'art-contact-{page}.jpg', quality=92)


def main() -> None:
    rows = {r['id']: r for r in json.loads((PACKAGE/'catalog.json').read_text(encoding='utf-8'))}
    sheets = json.loads((ART/'sheet-index.json').read_text(encoding='utf-8'))
    jobs_by_file = {}
    for path in [ART/'jobs.jsonl', ART/'corrections.jsonl']:
        if path.exists():
            for line in path.read_text(encoding='utf-8').splitlines():
                job = json.loads(line)
                jobs_by_file[job['out']] = (job, path)
    patch_path = ART/'corrections-index.json'
    patches = json.loads(patch_path.read_text(encoding='utf-8')) if patch_path.exists() else {}
    cfg = json.loads((Path(os.environ['USERPROFILE'])/'.codex/imagegen/config.json').read_text(encoding='utf-8-sig'))
    service = urlsplit(cfg['base_url']).hostname
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    OUT.mkdir(parents=True,exist_ok=True)
    records = []
    for source in sheets:
        source_file = ART/'raw'/source['file']
        with Image.open(source_file) as sheet:
            sheet.load()
            assert sheet.size == (1024,1536), (source_file,sheet.size)
            for slot,id_ in enumerate(source['cells']):
                raw = source_file
                version = 1
                with_patch = patches.get(id_, {})
                cell = slot + 1
                if with_patch.get('file') and (ART/'raw'/with_patch['file']).exists():
                    raw = ART/'raw'/with_patch['file']
                    with Image.open(raw) as corrected:
                        corrected.load()
                        cell = with_patch.get('cell', 0)
                        out = extract(corrected, cell-1, *with_patch.get('grid',[2,4])) if cell else fit(corrected.convert('RGB'))
                        raw_size = corrected.size
                    version = 2
                else:
                    out = extract(sheet,slot)
                    raw_size = sheet.size
                dest = OUT/f'{id_}.webp'
                out.save(dest,lossless=True,method=6)
                job, prompt_file = jobs_by_file[raw.name]
                records.append(dict(asset_id=id_, requirement_id='FY-RELIC-ART-001', name=rows[id_]['name_key'], wave=rows[id_]['wave'],
                    source=str(raw.relative_to(ROOT)).replace('\\','/'), sheet_cell=cell or None, source_sha256=sha(raw),
                    service=service, model=cfg['model'], request_size=job['size'], quality=job['quality'], source_dimensions=raw_size,
                    prompt_file=str(prompt_file.relative_to(ROOT)).replace('\\','/'), prompt_sha256=hashlib.sha256(job['prompt'].encode()).hexdigest(),
                    file=str(dest.relative_to(ROOT)).replace('\\','/'), sha256=sha(dest), dimensions=out.size, version=version,
                    processing='cut calibrated atlas cell; trim blank paper; preserve aspect; paper pad + lossless WebP',
                    status='pilot' if rows[id_]['wave'] else 'art_only'))
    assert len(records) == 104 and len({r['sha256'] for r in records}) == 104
    dump(OUT/'asset-manifest.json', records)
    for offset in range(0,len(records),32):
        contact([r['asset_id'] for r in records[offset:offset+32]],1+offset//32)
    print(f'{len(records)} distinct {SIZE}x{SIZE} relic icons')


if __name__ == '__main__':
    main()
