"""Preserve the existing workspace, then register the authorized compendium."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'artifacts/verification/compendium-20261115'
DOCS = ['agent.md', '实施计划与验收基线.md', 'docs/界面层契约.md', '动作或者图片描述/需求台账.md']
MUTABLE = ['src/app/game_session.gd', 'src/ui/game_shell.gd', 'src/ui/experience_page.gd', 'tests/run_ui_tests.gd']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    if (EVIDENCE / 'before.zip').exists():
        raise SystemExit('Baseline exists; never overwrite it.')
    with zipfile.ZipFile(EVIDENCE / 'before.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for name in DOCS + MUTABLE:
            archive.write(ROOT / name, name)
    protected = {}
    for folder in ['src', 'data', 'assets', 'tests']:
        for p in (ROOT / folder).rglob('*'):
            name = p.relative_to(ROOT).as_posix()
            if p.is_file() and p.suffix != '.import' and name not in MUTABLE:
                protected[name] = sha(p)
    saves = Path('C:/Users/Dev.LI/AppData/Roaming/Godot/app_userdata/交大四年：DDL战争/saves')
    baseline = {
        'started_utc': datetime.now(timezone.utc).isoformat(), 'mutable': MUTABLE,
        'protected': protected, 'documents': {name: sha(ROOT / name) for name in DOCS},
        'saves': {p.relative_to(saves).as_posix(): sha(p) for p in saves.rglob('*') if p.is_file()},
    }
    (EVIDENCE / 'baseline.json').write_text(json.dumps(baseline, ensure_ascii=False, indent=2), encoding='utf-8')
    manifest = json.loads((ROOT / 'data/four_year/manifests/campus_four_year.json').read_text(encoding='utf-8'))
    inventory = {'manifest': 'campus_four_year', 'manifest_sha256': sha(ROOT / 'data/four_year/manifests/campus_four_year.json'),
                 'cards': manifest['enabled']['card'], 'monsters': manifest['enabled']['task'],
                 'resource_decision': 'Reuse the 174 installed card illustrations, shared CardFaceView and 60 installed enemy bodies/rigs. No new generation or paid resources.',
                 'reference_note': 'Archived official main menu/card hierarchy; June 19 official bestiary screenshots requested for this screen. Acquisition status recorded separately.'}
    (EVIDENCE / 'resource-inventory.json').write_text(json.dumps(inventory, ensure_ascii=False, indent=2), encoding='utf-8')

    blocks = {
        '实施计划与验收基线.md': '''
## 0.20.29 2026-11-15 全卡牌与全怪物图鉴

用户要求制作可在游戏中查看全部卡牌与怪物的图鉴。本节在现有四学年/G7范围登记实施例外：先登记UIR-072/073及界面契约，核对正式manifest的174卡牌/60任务ID、既有卡图/怪物主体/骨架和官方画面，再据独立设计实现主菜单入口、分类画廊、搜索筛选及完整详情，无需再次申请实施许可。本批G6复用已安装资源，不调用付费API；原人物及怪物造型保持。

允许新增只读图鉴视图构建器、页面/详情组件/工具/专项测试，修改GameSession只读查询、GameShell页面导航、主菜单入口及完整UI测试清单。内容定义、规则/费用/升级/考试解析器、RNG、存档/schema/写入口和原命令门控保持；新增查询使用独立正式ContentDB，不替换进行中的局/测试目录。所有正式ID从首次打开全部可见，不加解锁门槛，不混入历史内容包。卡牌基础/升级/考试面调用既有真实解析器，怪物显示定义数值/阶段/意图及直接或召唤/转化来源，不把基础数值冒充难度修正后的战斗实时值。

保留改前原件、保护与真实档hash、参考来源、双尺寸三字号实渲及实际看图记录；核查全量精确集合、搜索筛选/分页、键鼠/返回/焦点、只读及待选/RNG不变，运行相关与完整回归。主按钮至少44像素，完整长文可滚动。具体设计见[图鉴设计](docs/plans/2026-11-15-compendium-design.md)和[UIR-072/073](动作或者图片描述/全卡牌与怪物图鉴_20261115.md)。当前状态：资源盘点完成，实施与验证中；结果按实测追加，不据此关闭原整版G0/G6/G8出口。
''',
        'docs/界面层契约.md': '''
## 2026-11-15 全量图鉴追加（UIR-072/073，根计划§0.20.29）

主菜单新增一级“图鉴”入口menu:compendium，以ui.compendium进入独立只读页面，compendium:back返回主菜单。全部内容以campus_four_year当前正式manifest为界：174种卡牌（含两衍生）与60种任务怪物（含附属/四学年首领/四路线终敌）首次打开全部展示，不依赖存档或发现进度。GameSession.get_compendium查询独立内容目录并返回副本，不激活局、不替换当前目录、不提交业务命令、不推进RNG/revision、不读写正式档；错误可见、可返回。

卡牌/怪物页签分别保存搜索、筛选、页码与滚动位置，画廊按固定每页12项浏览，不同时实例化全量骨架。卡牌复用CardFaceView及六类原费用符号，基础/升级/考试面调用BattleCardRules.resolve_face，条件、限次、关联伙伴/场景和长文完整可查。怪物缩略图使用精确ID资源，详情使用一个已安装原生骨架展示完整形象；显示基础工作量、阶段/意图、特殊机制和直接/召唤/转化来源，难度实时修正不冒充图鉴基础值。搜索支持名称、ID与说明，怪物按类别/学年筛选，卡牌按人物/类型/稀有度筛选。

详情隔离背景点击/键盘焦点，关闭恢复原条目与画廊滚动；Esc关闭详情后再Esc返回主菜单，搜索时Esc先退出搜索焦点。分页/关闭/返回保持44像素点击区，两尺寸三字号保留完整可滚动信息。图鉴不扩展局内导航，因此既有待选工作区/手牌语义原样保留；在待选返回主页后仍可只读查看图鉴并继续当前选择。实测结果与差异另记。
''',
        '动作或者图片描述/需求台账.md': '''
## 2026-11-15 图鉴追加

| ID | 来源与触发 | 表现及范围 | 状态/证据 |
|---|---|---|---|
| UIR-072 | 用户要求所有卡牌图鉴；主菜单/卡牌页签/详情 | 174正式ID全部可见；人物/类型/稀有度/搜索/分页；原卡面符号；基础、升级及考试面和完整规则说明 | 复用现有174卡图；[需求](全卡牌与怪物图鉴_20261115.md)、[设计](../docs/plans/2026-11-15-compendium-design.md)；实施与验证中 |
| UIR-073 | 用户要求所有怪物图鉴；怪物页签/详情 | 60正式ID全部可见；类型/学年/搜索/分页；原形象及骨架；基础工作量/阶段/意图/机制/来源；双尺寸三字号和只读状态 | 复用已安装60怪物；[需求](全卡牌与怪物图鉴_20261115.md)；实施与验证中 |
''',
        'agent.md': '''
2026-11-15当前追加根计划§0.20.29图鉴：用户已授权在主菜单制作所有卡牌与怪物的游戏内图鉴。已核正式manifest为174卡/60怪；复用现有资源，新增只读查询、搜索筛选、画廊和详情，原规则/档案/RNG/人物怪物资源保持。按[设计](docs/plans/2026-11-15-compendium-design.md)与[UIR-072/073](动作或者图片描述/全卡牌与怪物图鉴_20261115.md)实施并独立留证；本批技术/视觉结果与原整版门槛分别记录。
''',
    }
    for name, block in blocks.items():
        with (ROOT / name).open('ab') as f:
            f.write(('\r\n'+block.strip()+'\r\n').encode('utf-8'))
    print(json.dumps({'protected':len(protected),'saves':len(baseline['saves']), 'cards':len(inventory['cards']), 'monsters':len(inventory['monsters'])}, ensure_ascii=False))


if __name__ == '__main__':
    main()
