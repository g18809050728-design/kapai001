"""Snapshot and register the user-authorized eight-item continuous gallery."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'artifacts/verification/compendium-scroll-20261115'
MUTABLE = ['src/ui/compendium_page.gd', 'tests/suites/test_ui_compendium.gd']
DOCS = ['agent.md', '实施计划与验收基线.md', 'docs/界面层契约.md', '动作或者图片描述/需求台账.md',
        'docs/plans/2026-11-15-compendium-design.md', '动作或者图片描述/全卡牌与怪物图鉴_20261115.md']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    if (EVIDENCE / 'baseline.json').exists() or (EVIDENCE / 'before.zip').exists():
        raise SystemExit('Baseline exists; do not overwrite')
    with zipfile.ZipFile(EVIDENCE / 'before.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for name in MUTABLE + DOCS:
            archive.write(ROOT / name, name)
    protected = {}
    for folder in ['src', 'data', 'assets', 'tests']:
        for p in (ROOT / folder).rglob('*'):
            name = p.relative_to(ROOT).as_posix()
            if p.is_file() and p.suffix != '.import' and name not in MUTABLE:
                protected[name] = sha(p)
    saves = Path('C:/Users/Dev.LI/AppData/Roaming/Godot/app_userdata/交大四年：DDL战争/saves')
    baseline = {'started_utc': datetime.now(timezone.utc).isoformat(), 'mutable': MUTABLE,
                'protected': protected, 'documents': {n: sha(ROOT/n) for n in DOCS},
                'snapshots': {n: sha(ROOT/n) for n in MUTABLE+DOCS}, 'saves_root': str(saves),
                'saves': {p.relative_to(saves).as_posix(): sha(p) for p in saves.rglob('*') if p.is_file()}}
    (EVIDENCE / 'baseline.json').write_text(json.dumps(baseline, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    blocks = {
        '实施计划与验收基线.md': '''## 0.20.31 2026-11-15 图鉴八项连续下滑

用户要求取消图鉴目前的按钮翻页，改为持续下滑、一页8张卡。本节在§0.20.29的G7范围内授权调整既有图鉴画廊：卡牌首批8张，接近底部自动追加8张，之前条目保留并可向上回看；怪物页签沿同一八项连续浏览，静态缩略图不实例化全量骨架。去掉上一页/下一页按钮和页码，保留固定返回、筛选及完整详情。标准布局每批4列×2行，较窄窗口/大字号减少列数而不裁掉说明。复用本批已装174卡图与60怪物形象，无新API请求。

只允许修改compendium_page及相关图鉴专项测试并新增工具/证据；保存旧原件和保护/正式档hash。搜索/筛选从首批重建，页签/菜单返回记住已加载数量与滚动；追加不重建旧卡、不移动鼠标下的原控件。滚轮/拖动滚条、键盘PageUp/PageDown、Home/End与焦点连续导航可用；详情隔离背景，关闭恢复原位置/条目，跨批查看则定位所选项。全部174/60精确集合、无重复、末批不足8、空结果、双尺寸三字号、只读状态/RNG/待选与焦点验证留证；必要专项和完整UI实际执行。玩法/ID/费用/卡框六类符号、人物/其他资源、GameSession写口、RNG/存档及原整版出口保持。设计见[连续下滑方案](docs/plans/2026-11-15-compendium-scroll-design.md)；需求UIR-075；状态实施中。''',
        'docs/界面层契约.md': '''## 2026-11-15 图鉴连续下滑（UIR-075，§0.20.31）

本条取代UIR-072/073的每页12项/上下页按钮约定：画廊首批8项，向下接近底部每批自动追加8项至筛选全集，原条目保持实例/顺序/坐标。卡牌标准最多4列，窄屏大字号减少列数；怪物沿同一连续导航，详情仍只装一套骨架。底部只保留返回与连续浏览进度提示，不再显示页码或分页按钮。空结果可重置/返回，最后不足8照常显示。

页签分别记query/filters/loaded/scroll；搜索/改筛选从8项和顶部开始，换页签或菜单重进恢复原已加载范围/位置。滚轮与滚条、PageUp/PageDown滚动视口，Home回顶、End抵达全集末尾；键盘到末行可继续后续条目。追加不自动抢焦点或滚回顶部；详情关闭保留原滚动，详情切换到未加载项时补到该项并恢复其焦点。依既有GameSession只读查询，不改业务/存档。实测与截图独立留证。''',
        '动作或者图片描述/需求台账.md': '''## 2026-11-15 图鉴八项连续浏览追加

| ID | 来源/触发 | 所需表现/边界 | 状态/证据 |
|---|---|---|---|
| UIR-075 | 用户取消图鉴按钮翻页，要求持续下滑、一页8张 | 首批8、底部自动追加8，原卡不重建；最多4列、双尺寸三字号；滚轮/滚条/键盘连续，搜索筛选/详情/焦点/滚动/只读保持 | [设计](../docs/plans/2026-11-15-compendium-scroll-design.md)、[独立证据](../artifacts/verification/compendium-scroll-20261115/)；实施中；本条取代UIR-072/073旧分页约定 |''',
        'agent.md': '''2026-11-15最新图鉴交互按§0.20.31/UIR-075：用户要求持续下滑、每批8项，取代每页12项的按钮分页。固定返回与筛选/详情保持，标准4列×2行、窄屏大字号自适应；滚轮/滚条/键盘连续、追加不重建旧卡，页签与菜单返回恢复位置。只改画廊与相应测试，复用174卡/60怪，无新API。见[设计](docs/plans/2026-11-15-compendium-scroll-design.md)，结果独立留证，不关闭原整版出口。''',
        'docs/plans/2026-11-15-compendium-design.md': '''2026-11-15用户新纠正：上文12项按钮分页被[八项连续下滑设计](2026-11-15-compendium-scroll-design.md)和根计划§0.20.31取代，按新设计实施并验证；原证据与旧页面描述保留历史含义。''',
        '动作或者图片描述/全卡牌与怪物图鉴_20261115.md': '''2026-11-15 UIR-075追加：图鉴不再点击上下页，首批8项、继续下滑自动接上下一批8项，至全部174卡/60怪。固定返回/筛选/详情及只读保持；新约定见[设计](../docs/plans/2026-11-15-compendium-scroll-design.md)，取代本篇旧分页描述。''',
    }
    for name, text in blocks.items():
        with (ROOT/name).open('ab') as f:
            f.write(('\r\n\r\n'+text+'\r\n').encode('utf-8'))
    print(json.dumps({'protected':len(protected), 'snapshots':len(baseline['snapshots']), 'saves':len(baseline['saves'])}))


if __name__ == '__main__':
    main()
