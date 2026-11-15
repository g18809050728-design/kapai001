"""Audit and document the user-authorized continuous compendium gallery."""
from datetime import datetime, timezone
import difflib
import hashlib
import html
import json
from pathlib import Path
import re
import zipfile

from PIL import Image
import verify_compendium_scroll as verifier

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / 'artifacts/verification/compendium-scroll-20261115'
RUNS = ['checks-03', 'render-02', 'ui-01']


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def append(name, text):
    path = ROOT / name
    addition = ('\r\n\r\n' + text + '\r\n').encode('utf-8')
    body = path.read_bytes()
    if addition not in body:
        path.write_bytes(body + addition)


def main():
    baseline = load(EV / 'baseline.json')
    with zipfile.ZipFile(EV / 'before.zip') as archive:
        assert archive.testzip() is None
        original = {name: archive.read(name) for name in archive.namelist()}
    assert set(original) == set(baseline['snapshots'])
    assert all(hashlib.sha256(body).hexdigest() == baseline['snapshots'][name]
               for name, body in original.items())
    protected_now = {}
    for folder in ['src', 'data', 'assets', 'tests']:
        for path in (ROOT / folder).rglob('*'):
            name = path.relative_to(ROOT).as_posix()
            if path.is_file() and path.suffix != '.import' and name not in baseline['mutable']:
                protected_now[name] = digest(path)
    assert protected_now == baseline['protected'], 'protected code/data/art changed'
    saves_root = Path(baseline['saves_root'])
    saves_now = {p.relative_to(saves_root).as_posix(): digest(p)
                 for p in saves_root.rglob('*') if p.is_file()}
    assert saves_now == baseline['saves'], 'formal player saves changed'

    current_inputs = verifier.inputs()
    records = {name: load(EV / (name + '.run.json')) for name in RUNS}
    for name, record in records.items():
        assert record['exit_code'] == record['engine_errors'] == 0, name
        assert not record['changed_during_run'] and not record['unexpected_changes'], name
        assert record['inputs_before'] == record['inputs_after'] == current_inputs, name + ' input drift'
    render = load(EV / 'render-02/checks.json')
    assert not render['failures'] and render['checks'] > 1600
    assert len(render['captures']) == 50
    checks = next(json.loads(line.removeprefix('COMPENDIUM_CHECKS='))
                  for line in (EV / 'checks-03.stdout.txt').read_text(encoding='utf-8').splitlines()
                  if line.startswith('COMPENDIUM_CHECKS='))
    assert not checks['failures']

    pictures = []
    for name in render['captures']:
        path = ROOT / name.removeprefix('res://')
        with Image.open(path) as image:
            image.load()
            assert image.size in [(1280, 800), (960, 600)]
            pictures.append({'file': path.relative_to(EV).as_posix(),
                             'size': list(image.size), 'sha256': digest(path)})
    save(EV / 'image-audit.json', {'total': len(pictures), 'failed': 0, 'images': pictures})

    prior = ROOT / 'artifacts/verification/card-style-20261115'
    before_run = load(prior / 'render-01.run.json')
    assert before_run['inputs_before']['src/ui/compendium_page.gd'] == baseline['snapshots']['src/ui/compendium_page.gd']
    previous_picture = prior / 'render-01/cards-page-01-top.png'
    reference_dir = ROOT / 'artifacts/verification/compendium-20261115/references'
    for source in load(reference_dir / 'sources.json'):
        assert digest(reference_dir / source['file']) == source['sha256']
    reference = reference_dir / 'bestiary-contact.jpg'
    observations = {
        'reviewer': 'AI visual inspection of actual local images; final user aesthetic acceptance separate',
        'viewed': [p['file'] for p in pictures if Path(p['file']).name in {
            'cards-1280-100.png', 'cards-continuous-second-batch.png', 'cards-960-150.png',
            'cards-continuous-all-bottom.png', 'monsters-960-125.png', 'card-detail-bottom-960-150.png'}],
        'observations': [
            '1280x800 at 100%: first eight cards fit fully as four columns and two rows; no page controls.',
            'Second batch extends beneath existing rows; fixed filters and back action stay visible.',
            '174-card bottom includes the final two derived cards; no invented filler items.',
            '960x600 at 150% uses two columns with vertical scrolling and legible full-detail text.',
            '960x600 at 125% monsters use two columns without horizontal overflow.',
        ],
        'before': {'file': previous_picture.relative_to(ROOT).as_posix(), 'sha256': digest(previous_picture),
                   'source': 'previous batch actual render, not a new before run; page source agrees with before.zip'},
        'official_reference': {'file': reference.relative_to(ROOT).as_posix(), 'sha256': digest(reference)},
        'remaining_differences': 'Official archived bestiary has a right-side continuous name list, action catalogue and red back ribbon. This batch follows the user-requested eight-item gallery; it does not establish full visual equivalence.',
        'input_coverage_limit': 'Physical wheel and keyboard events plus native scrollbar value/bottom changes tested; no separate physical thumb-drag test claimed.',
    }
    save(EV / 'visual-review.json', observations)

    rule_context = load(prior / 'rules-evidence-reuse.json')
    drift = [name for name, expected in rule_context['inputs'].items() if digest(ROOT / name) != expected]
    assert set(drift) == set(baseline['mutable'])
    save(EV / 'rules-evidence-context.json', {
        'rerun_this_batch': False, 'source': rule_context['source'],
        'source_sha256': digest(ROOT / rule_context['source']),
        'previous_seconds': rule_context['previous_seconds'],
        'unchanged_prior_inputs': len(rule_context['inputs']) - len(drift),
        'authorized_ui_input_changes': drift,
        'scope': 'Historical rules context only; current full UI rerun. Rules/data hashes unchanged; not identical full prior inputs.',
    })

    result = (f'图鉴已改为首批8项、向下自动追加8项的连续画廊；标准窗口4列×2行，'
              f'小窗口/大字号减少列数。{checks["checks"]}项无头专项、{render["checks"]}项图形专项及'
              f'50张双尺寸三字号实渲通过；完整27套无头UI {records["ui-01"]["seconds"]:.3f}秒通过，'
              '各次退出0/引擎错误0/运行中输入未变。174卡/60怪完整顺序、末批、搜索筛选、'
              '页签/菜单返回、详情/焦点/偏移、滚轮及键盘连续导航核对通过。'
              '1627保护文件、8份改前原件与10个正式存档文件hash核对保持；API新增0、累计143/200。')
    evidence = '[实际效果与对照](artifacts/verification/compendium-scroll-20261115/review/index.html)'
    plan = ROOT / '实施计划与验收基线.md'
    old_header = original['实施计划与验收基线.md'].splitlines(keepends=True)[2]
    new_header = ('版本：v1.90｜日期：2026-11-15｜状态：§0.20.31八项连续图鉴已实现；' + result +
                  '规则未重跑，窗口化完整UI历史三项失败与用户最终美术/原整版G0/G6/G8出口另记。\r\n').encode('utf-8')
    body = plan.read_bytes()
    if old_header in body:
        body = body.replace(old_header, new_header, 1)
    else:
        assert new_header in body
    pending = '；需求UIR-075；状态实施中。'.encode('utf-8')
    completed = '；需求UIR-075；状态已实现，实际验证结果见下段。'.encode('utf-8')
    body = body.replace(pending, completed)
    assert body.replace(new_header, old_header, 1).startswith(original['实施计划与验收基线.md'])
    plan.write_bytes(body)
    append('实施计划与验收基线.md', '2026-11-15 §0.20.31实际结果：' + result + '见' + evidence +
           '与[验证记录](artifacts/verification/compendium-scroll-20261115/README.md)。仅图鉴画廊调整；原整版出口保持。')
    append('agent.md', '2026-11-15 §0.20.31/UIR-075实际交付：' + result + '见' + evidence +
           '和[验证记录](artifacts/verification/compendium-scroll-20261115/README.md)。规则未重跑；原整版出口保持。')
    append('docs/界面层契约.md', 'UIR-075实际核对：' + result +
           '滚条原生值/触底变化、真实滚轮及键盘已验证；未单独声称物理拖拽滚条手柄通过。'
           '详情仍保留前后项切换；取消的是画廊分页按钮。见[验证记录](../artifacts/verification/compendium-scroll-20261115/README.md)。')
    ledger = ROOT / '动作或者图片描述/需求台账.md'
    body = ledger.read_bytes()
    prefix = original['动作或者图片描述/需求台账.md']
    assert body.startswith(prefix)
    suffix = body[len(prefix):].replace('；实施中；本条取代'.encode('utf-8'),
        '；已实现，1692项无头/1742项图形专项及完整27套无头UI通过；本条取代'.encode('utf-8'))
    ledger.write_bytes(prefix + suffix)
    append('docs/plans/2026-11-15-compendium-scroll-design.md', '实际结果：' + result +
           '\n\n实看首批8张、第二批、174卡末尾、960/150%卡牌及长详情、960/125%怪物。'
           '首批恰好铺满视口时，向下滚轮主动接续第二批；详情期间冻结外层跟随焦点，关闭后恢复原偏移，跨批详情定位所选项。'
           '无头专项最终24.111秒、图形专项29.417秒；前期失败checks-01/02、render-01均保留，最终代码从checks-03到完整UI保持。'
           '\n\n规则未重跑：历史规则记录306项输入相同，2项本批画廊/专项测试按授权改变，未宣称全部308项输入相同。'
           '本轮图形图鉴专项及27套无头UI通过；上一批窗口化完整UI的3项失败没有在本轮修复或重跑。'
           '物理滚轮/键盘及原生滚条值触底已测，物理拖拽手柄未单独测。'
           '\n\n归档官方怪物名单、完整动作目录和红色返回带差异仍存在；本次按用户明确的每批8项连续画廊实现。'
           '本批完成不等于用户最终美术签收或整版G0/G6/G8验收。'
           '\n\n查看[当前效果与前后对照](../../artifacts/verification/compendium-scroll-20261115/review/index.html)'
           '及[完整验证](../../artifacts/verification/compendium-scroll-20261115/README.md)。')

    review = EV / 'review'
    review.mkdir(exist_ok=True)
    figures = [
        ('../render-02/cards-1280-100.png', '当前首批8张 · 1280×800 / 100%'),
        ('../../card-style-20261115/render-01/cards-page-01-top.png', '改前：上一批真实截图 · 12项按钮分页'),
        ('../render-02/cards-continuous-second-batch.png', '向下接上第二批8张'),
        ('../render-02/cards-continuous-all-bottom.png', '全部174卡末尾'),
        ('../render-02/cards-960-150.png', '小窗口大字号 · 960×600 / 150%'),
        ('../render-02/monsters-960-125.png', '怪物同样连续浏览 · 960×600 / 125%'),
    ]
    figures_html = ''.join(f'<figure><a href="{src}"><img src="{src}" alt="{html.escape(caption)}" loading="lazy"></a>'
                           f'<figcaption>{html.escape(caption)}</figcaption></figure>' for src, caption in figures)
    (review / 'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1"><title>图鉴八项连续下滑</title>'
        '<style>body{margin:24px auto;max-width:1400px;padding:0 18px;background:#101920;color:#eadfc5;'
        'font:17px/1.6 system-ui}a{color:#efce87}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,520px),1fr));'
        'gap:20px}figure{margin:0}img{display:block;width:100%;height:auto}figcaption{padding:8px 0}</style>'
        '<h1>图鉴：每批8项，连续下滑</h1><p>游戏主菜单 → 图鉴。向下接续后续卡牌，向上回看已加载条目。'
        '筛选、返回固定；页签和菜单往返恢复位置。</p><p>当前1742项图形专项、50张实渲及完整27套无头UI通过。'
        '下方改前图来自上一批已留存的真实渲染，其页面源码与本批改前快照一致。</p>'
        '<p><a href="../README.md">验证记录</a> · <a href="../visual-review.json">实际看图与差异</a></p>'
        '<div class="gallery">' + figures_html + '</div><p>官方归档的怪物右侧名单、动作目录及红色返回带仍有差异；'
        '本次采用用户要求的八项连续画廊。最终审美与整版验收另记。</p></html>', encoding='utf-8')
    readme = '# 图鉴八项连续下滑：实际交付\n\n2026-11-15，UIR-075，根计划§0.20.31。\n\n' + result + '\n\n'
    readme += '[查看实际效果与前后对照](review/index.html)。游戏入口：主菜单 → 图鉴。\n\n'
    readme += '| 核查 | 实际结果 |\n|---|---|\n'
    for name, label in [('checks-03', '图鉴无头专项'), ('render-02', '实际窗口图鉴专项'), ('ui-01', '完整27套无头UI')]:
        record = records[name]
        readme += f'| {label} | {record["seconds"]:.3f}秒；退出0/引擎错误0/输入无变。[精确命令/输入]({name}.run.json)、[原日志]({name}.stdout.txt) |\n'
    readme += ('\n专项覆盖174卡/60怪精确有序全集、每批8/末批6或4、原控件实例/坐标稳定、'
        '真实滚轮/键盘、Home/End、PageUp/PageDown、末行焦点预取、原生滚条触底、'
        '过期回调与快速筛选、搜索/空结果、页签/菜单往返、详情隔离/精确偏移/跨批定位、'
        '基础/升级/考试面、60实际骨架、旧局/待选/状态/RNG只读，以及双尺寸三字号。\n\n'
        '50张最终截图全部解码与尺寸/hash核对，实际看图6张及改前/官方归档记录见[视觉核对](visual-review.json)。'
        '小窗口大字号使用2列，每批仍8项，不保证同一个视口摆满8张。详情内的前后项按钮保留。'
        '未单独声称物理拖拽滚条手柄验证通过。\n\n'
        '规则本轮未重跑。历史61.078秒规则记录有306项输入保持，2项画廊/专项测试按授权变化，'
        '详见[历史规则上下文](rules-evidence-context.json)；不宣称当前全部308项输入相同。'
        '上一批窗口化完整UI的3项滚动/悬停失败仍按原批记录，本轮没有重跑或修复该套窗口测试。\n\n'
        '前期checks-01、checks-02和render-01失败保留：补齐首屏无滚动范围时的滚轮续载，'
        '固定专项窗口尺寸，纠正怪物最小列宽、详情焦点跟随和不足1像素的定位边界。'
        '最终checks-03、render-02、ui-01使用完全一致的源码/数据/测试/资源输入。\n\n'
        '只修改src/ui/compendium_page.gd、tests/suites/test_ui_compendium.gd及登记文档/新增工具/证据。'
        '原卡框和六类费用符号、174新卡图、60敌怪与四角色资源、业务规则/ID/费用/RNG/存档保持。'
        '8份原件见[before.zip](before.zip)，改动见[源码差异](existing-code.diff)，'
        '保护/正式存档hash及原文换行核对见[交付审计](delivery-audit.json)。\n\n'
        '归档二代怪物右侧连续名单、完整动作目录及红色返回带与本作仍有差异。'
        '本次完成八项连续画廊，不等于用户最终美术签收或整版G0/G6/G8出口完成。\n\n'
        '复现时在项目根目录使用新的证据名，避免覆盖旧记录：\n\n```powershell\n'
        'python -X utf8 tools/verify_compendium_scroll.py render-new -- --audio-driver Dummy --rendering-method gl_compatibility --script res://tools/run_compendium.gd -- test-full res://artifacts/verification/compendium-scroll-20261115/render-new\n'
        'python -X utf8 tools/verify_compendium_scroll.py ui-new -- --headless --script res://tests/run_ui_tests.gd\n```\n')
    (EV / 'README.md').write_text(readme, encoding='utf-8')

    document_checks = {}
    for name in baseline['documents']:
        body = (ROOT / name).read_bytes()
        if name == '实施计划与验收基线.md':
            body = body.replace(new_header, old_header, 1)
        assert body.startswith(original[name]), name + ' old bytes/line endings changed'
        document_checks[name] = {'original_bytes_preserved': True, 'current_sha256': digest(ROOT / name)}
    patches = []
    for name in baseline['mutable']:
        patches.extend(difflib.unified_diff(original[name].decode('utf-8').splitlines(),
            (ROOT / name).read_text(encoding='utf-8').splitlines(), fromfile='before/' + name,
            tofile='after/' + name, lineterm=''))
    (EV / 'existing-code.diff').write_text('\n'.join(patches) + '\n', encoding='utf-8')
    save(EV / 'delivery-audit.json', {'ok': True, 'date_utc': datetime.now(timezone.utc).isoformat(),
        'protected_files': len(protected_now), 'snapshots': len(original), 'formal_save_files': len(saves_now),
        'protected_changes': [], 'formal_save_changes': [], 'documents': document_checks,
        'plan_header_before': old_header.decode('utf-8'), 'plan_header_after': new_header.decode('utf-8'),
        'consistent_exact_input_runs': RUNS, 'pictures': len(pictures), 'api_added': 0,
        'api_cumulative_successful': 143, 'api_limit': 200,
        'finalizer_sha256': digest(Path(__file__)), 'visual_review': 'visual-review.json'})
    missing = []
    documents = [ROOT / name for name in baseline['documents']] + [
        ROOT / 'docs/plans/2026-11-15-compendium-scroll-design.md', EV / 'README.md']
    for document in documents:
        text = document.read_text(encoding='utf-8')
        if document.relative_to(ROOT).as_posix() in original:
            old_text = original[document.relative_to(ROOT).as_posix()].decode('utf-8')
            text = '\n'.join(line for line in text.splitlines() if line not in old_text.splitlines())
        for target in re.findall(r'\]\(([^)]+)\)', text):
            target = target.split('#')[0]
            if target and not re.match(r'^[a-z]+://', target) and not (document.parent / target).exists():
                missing.append([document.relative_to(ROOT).as_posix(), target])
    for target in re.findall(r'(?:src|href)="([^"]+)"', (review / 'index.html').read_text(encoding='utf-8')):
        if not (review / target).exists():
            missing.append(['review/index.html', target])
    assert not missing, missing
    save(EV / 'link-audit.json', {'ok': True, 'missing_new_targets': missing})
    print(json.dumps({'ok': True, 'protected': len(protected_now), 'saves': len(saves_now),
                      'headless_checks': checks['checks'], 'graphical_checks': render['checks'],
                      'screenshots': len(pictures), 'ui_seconds': records['ui-01']['seconds']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
