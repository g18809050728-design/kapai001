"""Compile the RX design table without editing or activating FY production content."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'docs/plans/2026-11-20-relic-pool-design(1).md'
PACKAGE = ROOT / 'data/four_year/relic_pilot'
ART = ROOT / 'output/imagegen/relic-pilot-20261120'
FIRST = ('RX-C01', 'RX-C02', 'RX-C09', 'RX-P01-01', 'RX-P02-01', 'RX-P03-01', 'RX-P04-01')
SECOND = (
    'RX-C05', 'RX-C17', 'RX-C23', 'RX-C26', 'RX-C28',
    'RX-P01-05', 'RX-P01-09', 'RX-P01-15',
    'RX-P02-02', 'RX-P02-07', 'RX-P02-15',
    'RX-P03-05', 'RX-P03-09', 'RX-P03-16',
    'RX-P04-06', 'RX-P04-08', 'RX-P04-11',
)
RARITIES = {'白': 'white', '蓝': 'blue', '紫': 'purple', '金': 'gold'}
STYLE = ('校园奇物图标：深青细墨线勾勒清楚轮廓，浅米白纸底，柔和半透明水彩平涂，低饱和鼠尾草绿、灰蓝、暖黄、点缀少量砖红。'
         '轻微俯视三分之四视角，物件完整，紧凑真实、少量磨损和极短柔和接触阴影。辨识度优先，缩成64px仍分得清。'
         '全图同一色调的干净浅米白纸纹，无字母、数字、题词、图标编号、场景、人、手、校徽、品牌、UI框、圆底座、光晕、分隔线或水印。'
         '物件上的符号只用短线、圆点、简几何；插图没有其他装饰。')
POSITIONS = ('第一行左', '第一行右', '第二行左', '第二行右', '第三行左', '第三行右', '第四行左', '第四行右')


def dump(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def read_design() -> list[dict]:
    rows = []
    for line in DESIGN.read_text(encoding='utf-8-sig').splitlines():
        if not re.match(r'^\| RX-(?:C\d{2}|P0[1-4]-\d{2}) \|', line):
            continue
        id_, name, quality, text, notes, visual = (value.strip() for value in line.split('|')[1:-1])
        rows.append(dict(id=id_, name_key=name.removesuffix(' ★'), owner=id_.split('-')[1] if id_.split('-')[1].startswith('P') else 'C',
                         rarity=RARITIES[quality[0]], text=text, notes=notes, visual=visual,
                         wave=1 if id_ in FIRST else 2 if id_ in SECOND else 0))
    assert len(rows) == len({r['id'] for r in rows}) == len({r['name_key'] for r in rows}) == 104
    assert sum(r['wave'] > 0 for r in rows) == 24
    return rows


def build_visual_reference(rows: list[dict]) -> None:
    fy = {}
    for line in DESIGN.read_text(encoding='utf-8-sig').splitlines():
        if re.match(r'^\| FY_Y[1-4]_[1-4] \|', line):
            id_, name, year, quality, visual = (value.strip() for value in line.split('|')[1:-1])
            fy[id_] = dict(name=name, year=year, rarity=RARITIES[quality], visual=visual)
    assert len(fy) == 16
    dump(DESIGN.with_name('2026-11-20-relic-visual-descriptions.json'), {
        'requirement_id': 'FY-RELIC-ART-001',
        'source': DESIGN.name,
        'common_prompt': STYLE,
        'rx': {r['id']: {k: r[k] for k in ('name_key', 'owner', 'rarity', 'visual', 'wave')} for r in rows},
        'fy_reference_only': fy,
    })


def build_art_jobs(rows: list[dict], size: str, quality: str) -> None:
    by_id = {row['id']: row for row in rows}
    sequence = [by_id[i] for i in (*FIRST, *SECOND)] + [row for row in rows if not row['wave']]
    jobs, index = [], []
    for offset in range(0, len(sequence), 8):
        group = sequence[offset:offset + 8]
        file = f'RX-sheet-{1 + offset // 8:02}.png'
        prompt = (f'{STYLE}\n制作一张竖幅精确二列四行的八格独立游戏物品图集，不留外框。'
                  '每个格子等宽等高，8件物品一格一件，按列中心 x=画宽的25%/75%；按行中心 y=画高的12.5%/37.5%/62.5%/87.5%。'
                  '每个物件含阴影都不超过格宽60%或格高67%，四周大面积纯净留白，不能跨格。'
                  '八个方形安全区域内分别画以下具体物件，顺序严格对应（编号和名称仅构图指导，不出现在图里）：\n'
                  + '\n'.join(f'{place}：{r["name_key"]}。{r["visual"]}' for place, r in zip(POSITIONS, group)))
        jobs.append(dict(prompt=prompt, out=file, size=size, quality=quality))
        index.append(dict(file=file, cells=[r['id'] for r in group]))
    ART.mkdir(parents=True, exist_ok=True)
    (ART / 'jobs.jsonl').write_text(''.join(json.dumps(job, ensure_ascii=False) + '\n' for job in jobs), encoding='utf-8')
    dump(ART / 'sheet-index.json', index)


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--size', default='1024x1536', choices=['1024x1536'])
    cli.add_argument('--quality', default='medium')
    args = cli.parse_args()
    rows = read_design()
    dump(PACKAGE / 'catalog.json', rows)
    build_visual_reference(rows)
    dump(PACKAGE / 'definitions.json', [
        {"id": r["id"], "name_key": r["name_key"], "rarity": r["rarity"],
         "availability": "drop", "tags": ["rx_pilot"],
         "rx": {"owner": r["owner"], "text": r["text"]}}
        for r in rows if r['wave']
    ])
    build_art_jobs(rows, args.size, args.quality)


if __name__ == '__main__':
    main()
