"""Archive the current review delivery before the v3.1 document revision."""
from pathlib import Path
import hashlib
import json
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DELIVERY = HERE.parent

if __name__ == '__main__':
    archive = HERE / 'before-v3.1.zip'
    if archive.exists():
        raise SystemExit('Existing revision archive retained; do not replace it.')
    files = [ROOT / n for n in ('README.md', 'agent.md', '实施计划与验收基线.md', 'AGENTS.md')]
    files += sorted((ROOT / 'docs').rglob('*.md'))
    files += sorted((ROOT / '动作或者图片描述').rglob('*.md'))
    files += [p for p in DELIVERY.iterdir() if p.is_file() and p.suffix != '.zip']
    records = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, p.relative_to(ROOT).as_posix())
        z.writestr('SHA256.json', json.dumps(records, ensure_ascii=False, indent=2))
    (HERE / 'before-v3.1.json').write_text(json.dumps(records, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'Archived {len(files)} files before v3.1 edits.')
