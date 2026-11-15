"""Snapshot existing art and register the authorized 174-card refresh (no API)."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

from PIL import Image, ImageOps, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/card-style-20261115'
EVIDENCE = ROOT / 'artifacts/verification/card-style-20261115'
DOCS = ['agent.md', '实施计划与验收基线.md', 'docs/界面层契约.md',
        '动作或者图片描述/需求台账.md', 'docs/art/card-art-assets-v3.json',
        'docs/全新卡牌图片生成提示词_v3.md']


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write(p, data):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    if (EVIDENCE / 'baseline.json').exists() or (EVIDENCE / 'before.zip').exists():
        raise SystemExit('Baseline already exists; never overwrite it.')
    manifest_path = ROOT / 'data/four_year/manifests/campus_four_year.json'
    ids = json.loads(manifest_path.read_text(encoding='utf-8'))['enabled']['card']
    assert len(ids) == len(set(ids)) == 174
    mutable = [f'assets/cards/v3/{cid}.png' for cid in ids]
    with zipfile.ZipFile(EVIDENCE / 'before.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for name in DOCS + mutable:
            archive.write(ROOT / name, name)
    protected = {}
    for folder in ['src', 'data', 'assets', 'tests', 'docs/提交文档_20261114']:
        for p in (ROOT / folder).rglob('*'):
            name = p.relative_to(ROOT).as_posix()
            if p.is_file() and p.suffix != '.import' and name not in mutable:
                protected[name] = sha(p)
    saves = Path('C:/Users/Dev.LI/AppData/Roaming/Godot/app_userdata/交大四年：DDL战争/saves')
    write(EVIDENCE / 'baseline.json', {
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'mutable': mutable, 'protected': protected,
        'documents': {name: sha(ROOT / name) for name in DOCS},
        'old_art': {name: sha(ROOT / name) for name in mutable},
        'saves_root': str(saves),
        'saves': {p.relative_to(saves).as_posix(): sha(p) for p in saves.rglob('*') if p.is_file()},
        'manifest_sha256': sha(manifest_path), 'api_before': 121, 'api_ceiling': 200,
    })
    # Opaque identity references keep the uploaded reference compact and unambiguous.
    references = {}
    for cid in ['P01', 'P02', 'P03', 'P04']:
        src = ROOT / f'assets/art/characters/{cid}/neutral.png'
        with Image.open(src) as im:
            im = im.convert('RGBA')
            bbox = im.getchannel('A').getbbox()
            cropped = im.crop(bbox)
            full = ImageOps.contain(cropped, (490, 740), Image.Resampling.LANCZOS)
            board = Image.new('RGB', (1024, 768), '#ece7dc')
            board.paste(full, (10+(490-full.width)//2, 14+(740-full.height)//2), full)
            upper = cropped.crop((0, 0, cropped.width, round(cropped.height*.56)))
            upper = ImageOps.contain(upper, (490, 700), Image.Resampling.LANCZOS)
            board.paste(upper, (520+(490-upper.width)//2, 30+(700-upper.height)//2), upper)
            dest = OUT / 'references' / (cid+'.png')
            dest.parent.mkdir(parents=True, exist_ok=True)
            board.save(dest)
        references[cid] = {'source':src.relative_to(ROOT).as_posix(), 'source_sha256':sha(src),
                           'file':dest.relative_to(ROOT).as_posix(), 'sha256':sha(dest),
                           'role':'current formal character identity AND painted linework reference, not an edit target or atlas layout'}
    board = Image.new('RGB', (1536, 1024), '#ece7dc')
    for i, cid in enumerate(references):
        with Image.open(ROOT / references[cid]['file']) as im:
            thumb = ImageOps.contain(im, (768, 512), Image.Resampling.LANCZOS)
            board.paste(thumb, ((i%2)*768, (i//2)*512))
    all_ref = OUT / 'references/all-characters.png'
    board.save(all_ref)
    references['C'] = {'file':all_ref.relative_to(ROOT).as_posix(), 'sha256':sha(all_ref),
                       'role':'four formal identities and shared rendering; public scenes may show any of these adults'}
    write(OUT / 'references/manifest.json', references)
    blocks = {
        '实施计划与验收基线.md': '''
## 0.20.30 2026-11-15 174卡按角色风格与牌名重绘

用户要求目前174种牌按各人物风格设计，画面能表达牌名，沿已授权API每次8张生成。本节登记G6→G7的本批实施范围：核对正式manifest/卡表/真实效果、当前P01V12/P02V8/P03V10/P04V11形象→逐牌专属构图与八格清单→首张实际看图→继续22图集→核对裁片→替换现有174张插图并在图鉴、战斗、商店及奖励等共享卡面中实渲。无需重复请求费用或实施许可。覆盖本批§0.8.1的单一旧水彩画风约束；媒介以当前正式人物为准，四人各有可辨别的色板/道具/动作语言，避免40张通用桌面或同一姿势换色。

限定2列×4行1024×1536、medium、n=1，四人各5图集、公共12与衍生2共2图集，最后两格为空。实际上传对应正式人物作身份/笔触参考，单张CLI edit生成八个新独立场景，不把参考立绘当编辑目标、不照搬其排列。API沿本机当前配置，已有成功121/200，本轮首次22张；返工单列，仅重做明确缺失/不合格项，不盲目重跑。保存完整提示词、参考输入/输出hash、格位、裁切、AI视觉观察与实际请求/成功数；价格未知，不以文件数冒称实际账单。

只替换既有卡图文件及资源溯源记录；升级/考试面继续复用对应ID插图，卡名/规则由原UI渲染，保留六类原费用符号、卡框、长文、交互与命中区。人物正式立绘/骨架、其他美术、全部内容定义/ID/规则/RNG/存档/schema/命令及正式玩家档保持。先保存旧174图和文档字节、保护文件/10正式档hash，裁片机器检查与逐图观察后再安装；登记独立设计、UIR-074与界面契约。机器/AI观察、用户审美签收与原整版G0/G6/G8出口分开，未运行的检查不写通过。

本批设计：[174卡角色风格重绘](docs/plans/2026-11-15-card-style-design.md)；原件/提示词：[生产目录](output/imagegen/card-style-20261115/)；独立证据：[验证目录](artifacts/verification/card-style-20261115/)。状态：清单与首批制作中。
''',
        'docs/界面层契约.md': '''
## 2026-11-15 按角色与牌名重绘卡图（UIR-074，§0.20.30）

174个正式R3 ID只更新assets/cards/v3/<ID>.png对应插图，既有UiStyle.texture索引、CardFaceView、基础/升级/考试复用、费用六类符号、标题与长文保持。每图512×384格位内裁为480×360；主体与关键动作置于安全区，120×90缩略仍可辨。四位当前正式人物作为实际上传的身份与绘画参考，逐牌名称/真实效果决定场景，公共牌不绑单一人物，论文两衍生沿许知微语汇。原始API输出、精确裁切、prompt与参考hash、视觉记录及已安装图hash均在独立manifest留证；旧174图在改前ZIP保留。只改美术资源不改变业务规则、查询或交互。图鉴全量分页与代表卡详情、双尺寸三字号战斗及奖励/商店实渲在核图后验证，最终审美由用户判断。
''',
        '动作或者图片描述/需求台账.md': '''
## 2026-11-15 174卡插图角色风格追加

| ID | 来源/触发 | 所需表现/边界 | 状态/证据 |
|---|---|---|---|
| UIR-074 | 用户要求按人物风格和牌名制作174卡，每次8张API | 林序调试/连携、许知微论文/章节、沈见章证据/追问、唐以宁分工/伙伴；每牌具体构图，当前正式身份、自然人体；卡框文字和六类符号保持，升级/考试复用 | [详细需求](卡牌角色风格与牌名插画_20261115.md)、[设计](../docs/plans/2026-11-15-card-style-design.md)、[证据](../artifacts/verification/card-style-20261115/)；制作中 |
''',
        'agent.md': '''
2026-11-15最新卡图工作按§0.20.30/UIR-074实施：用户要求174卡按人物风格/牌名重绘，每次八格，现有API及费用授权继续。保留当前正式人物和六类费用符号、规则/命令/RNG/存档；先生成核对首图后继续22图集并替换现有174插图，详见[设计](docs/plans/2026-11-15-card-style-design.md)。旧素材、输入/输出和保护hash独立留证，AI观察不作用户最终美术签收；原整版出口保持。
''',
        'docs/全新卡牌图片生成提示词_v3.md': '''
2026-11-15用户要求按当前正式人物风格和牌名重制174卡；本篇旧图集/水彩画风记录保留历史含义。当前新批次以[角色风格重绘设计](plans/2026-11-15-card-style-design.md)、output/imagegen/card-style-20261115/逐牌清单/完整提示词和独立资源manifest为准，根计划§0.20.30授权。旧174图已快照；实际完成/接入按新批次证据登记。
''',
    }
    for name, block in blocks.items():
        with (ROOT / name).open('ab') as f:
            f.write(('\r\n'+block.strip()+'\r\n').encode('utf-8'))
    print(json.dumps({'cards':len(ids), 'protected':len(protected), 'snapshots':len(DOCS)+len(mutable),
                      'saves':len(json.loads((EVIDENCE/'baseline.json').read_text(encoding='utf-8'))['saves']),
                      'api_calls':0}, ensure_ascii=False))


if __name__ == '__main__':
    main()
