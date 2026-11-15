"""Audit this compendium batch and record the completed, narrowly scoped result."""
from datetime import datetime, timezone
import difflib
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import zipfile

from PIL import Image
import verify_compendium

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / 'artifacts/verification/compendium-20261115'
RUNS = ['render-verified', 'capture-verified', 'rules-verified', 'ui-verified', 'menu-verified']


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    baseline = load(EV / 'baseline.json')
    records = {name: load(EV / (name + '.run.json')) for name in RUNS}
    current = verify_compendium.inputs()
    for name, record in records.items():
        assert record['exit_code'] == record['engine_errors'] == 0, name
        assert not record['changed_during_run'] and not record['unexpected_changes'], name
        assert record['inputs_before'] == record['inputs_after'] == current, name + ' inputs'
    render = load(EV / 'render-verified/checks.json')
    capture = load(EV / 'capture-verified/manifest.json')
    assert render['checks'] == 1851 and not render['failures'] and len(render['captures']) == 48
    manifest = load(ROOT / 'data/four_year/manifests/campus_four_year.json')
    assert sorted(capture['cards']) == sorted(manifest['enabled']['card']) and len(capture['cards']) == 174
    assert sorted(capture['monsters']) == sorted(manifest['enabled']['task']) and len(capture['monsters']) == 60
    assert capture['variants'] == 374 and len(capture['exam_cards']) == 14 and capture['ok']

    protected_changes = [name for name, expected in baseline['protected'].items()
                         if not (ROOT / name).is_file() or digest(ROOT / name) != expected]
    assert not protected_changes, protected_changes
    saves_root = Path('C:/Users/Dev.LI/AppData/Roaming/Godot/app_userdata/交大四年：DDL战争/saves')
    actual_saves = {p.relative_to(saves_root).as_posix(): digest(p) for p in saves_root.rglob('*') if p.is_file()}
    assert actual_saves == baseline['saves'], 'actual player saves changed'
    with zipfile.ZipFile(EV / 'before.zip') as archive:
        assert archive.testzip() is None and len(archive.namelist()) == 8
        original = {name: archive.read(name) for name in archive.namelist()}

    pictures = [EV / 'render-verified' / Path(path).name for path in render['captures']]
    pictures += [EV / 'capture-verified' / item['file'] for item in capture['captures']]
    image_records = []
    for path in pictures:
        with Image.open(path) as image:
            image.load()
            assert image.size in [(1280, 800), (960, 600)], str(path)
            image_records.append({'file': path.relative_to(EV).as_posix(), 'size': list(image.size), 'sha256': digest(path)})
    assert len(pictures) == 219
    for reference in load(EV / 'references/sources.json'):
        assert digest(EV / 'references' / reference['file']) == reference['sha256']

    rules_seconds = records['rules-verified']['seconds']
    ui_seconds = records['ui-verified']['seconds']
    result = (f'已接入主菜单图鉴：174卡/60怪全部开放；374个真实卡面及14种考试替代牌可查。'
              f'1851项图形专项、完整规则{rules_seconds:.3f}秒、完整27套UI{ui_seconds:.3f}秒与隔离正常GameShell入口均通过，'
              '最终运行退出0/引擎错误0/输入未变。219张最终实渲、全部分页/60怪详情和双尺寸三字号留证；'
              '1614保护文件、8份改前原件与10个正式档核对保持。API新增0、累计121/200。')
    evidence_link = '[实渲与查看入口](artifacts/verification/compendium-20261115/review/index.html)'
    plan_path = ROOT / '实施计划与验收基线.md'
    old_header = original['实施计划与验收基线.md'].splitlines(keepends=True)[2]
    new_header = ('版本：v1.88｜日期：2026-11-15｜状态：§0.20.29全卡牌/怪物图鉴已实现；' + result + '用户最终美术与原整版出口另记。\r\n').encode('utf-8')
    plan = plan_path.read_bytes()
    if old_header in plan:
        plan = plan.replace(old_header, new_header, 1)
    else:
        assert new_header in plan
    pending = '当前状态：资源盘点完成，实施与验证中；结果按实测追加，不据此关闭原整版G0/G6/G8出口。'.encode('utf-8')
    completed = ('当前状态：' + result + '见' + evidence_link + '及[验证记录](artifacts/verification/compendium-20261115/README.md)。'
                 '与官方图鉴仍有右侧连续怪物名单、动作目录及红色返回带差异；本批不据此关闭原整版G0/G6/G8出口。').encode('utf-8')
    if pending in plan:
        plan = plan.replace(pending, completed, 1)
    else:
        assert completed in plan
    assert plan.replace(new_header, old_header, 1).startswith(original['实施计划与验收基线.md'])
    plan_path.write_bytes(plan)

    additions = {
        'agent.md': '\r\n2026-11-15图鉴实施核对：' + result + '见' + evidence_link + '及[验证记录](artifacts/verification/compendium-20261115/README.md)。原整版门槛保留。\r\n',
        'docs/界面层契约.md': '\r\n图鉴实测：' + result + '完整ID、只读/待选、鼠标/键盘、焦点和失败页的结果见[证据](../artifacts/verification/compendium-20261115/README.md)。实际界面使用双页签/分页/左右详情，与官方连续名单及动作目录仍有差异，未宣称像素级复刻。\r\n',
    }
    for name, addition in additions.items():
        path = ROOT / name
        body = path.read_bytes()
        assert body.startswith(original[name]), name
        if addition.encode('utf-8') not in body:
            path.write_bytes(body + addition.encode('utf-8'))
    ledger_path = ROOT / '动作或者图片描述/需求台账.md'
    ledger = ledger_path.read_bytes()
    assert ledger.startswith(original['动作或者图片描述/需求台账.md'])
    prefix = original['动作或者图片描述/需求台账.md']
    suffix = ledger[len(prefix):].replace('实施与验证中'.encode('utf-8'), '已实现；1851图形专项/完整规则/27套UI通过；[219张实渲及完整证据](../artifacts/verification/compendium-20261115/README.md)'.encode('utf-8'))
    ledger_path.write_bytes(prefix + suffix)
    design = ROOT / 'docs/plans/2026-11-15-compendium-design.md'
    body = design.read_bytes()
    placeholder = '实际结果：待实施验证后填写。'.encode('utf-8')
    actual = ('实际结果：' + result + '\n\n'
              '已核对正式全部ID分页、所有60套实际骨架、172种可升级牌与2种不可常规升级衍生牌。'
              '鼠标打开原生版本菜单后，首次Down只高亮基础项，再Down/Enter选择升级；已用真实Godot输入验证，未以发射选择信号替代该路径。'
              '详情父页依赖收敛为UiPage，解除页面与详情的具体类型循环依赖；独立动态装载及完整UI启动方式均验证退出释放。'
              '旧包活动局、真实K03待选→主页→图鉴→继续的完整状态/RNG/revision保持，正式玩家档只读hash保持。\n\n'
              '实际看图：标准卡牌五列、怪物独立形象可辨；960×600/150%时卡牌两列且画廊需滚动，固定操作可见。'
              '详情背景不透字，左侧完整形象与右侧长文分开，毕业答辩多阶段/附属来源/考试升级面已查看。'
              '该新增图鉴与归档二代仍有差异：双页签及分页画廊、左右详情、前后切换，并非右侧连续怪物名单；动作仅待机/出手/受击，缺少完整动作目录、官方红色返回带。'
              '既有主菜单在小窗口大字号下标题换行、选项需滚动，图鉴焦点会自动滚入可见区域。未声称整版美术或G8完成。\n\n'
              '实现：`src/app/compendium_view.gd`、`GameSession.get_compendium`、`src/ui/compendium_page.gd`、`compendium_detail.gd`、`compendium_text.gd`及主菜单/路由。'
              '可查看[实际截图](../../artifacts/verification/compendium-20261115/review/index.html)、[完整证据](../../artifacts/verification/compendium-20261115/README.md)和[ID/截图清单](../../artifacts/verification/compendium-20261115/capture-verified/manifest.json)。').encode('utf-8')
    if placeholder in body:
        design.write_bytes(body.replace(placeholder, actual, 1))

    original_hashes = {name: hashlib.sha256(value).hexdigest() for name, value in original.items()}
    for name, expected in baseline['documents'].items():
        assert original_hashes[name] == expected
        actual_doc = (ROOT / name).read_bytes()
        if name == '实施计划与验收基线.md':
            actual_doc = actual_doc.replace(new_header, old_header, 1)
        assert actual_doc.startswith(original[name]), name + ' historical bytes'
    patches = []
    for name in baseline['mutable']:
        patches.extend(difflib.unified_diff(original[name].decode('utf-8').splitlines(),
                                           (ROOT / name).read_text(encoding='utf-8').splitlines(),
                                           fromfile='before/' + name, tofile='after/' + name, lineterm=''))
    (EV / 'existing-code.diff').write_text('\n'.join(patches) + '\n', encoding='utf-8')
    write_json(EV / 'image-audit.json', {'images': image_records, 'total': len(image_records), 'failed': 0})
    audit = {'ok': True, 'date_utc': datetime.now(timezone.utc).isoformat(),
             'protected_count': len(baseline['protected']), 'protected_changes': protected_changes,
             'actual_save_count': len(actual_saves), 'actual_saves_unchanged': True,
             'before_snapshot_count': len(original), 'before_snapshot_hashes': original_hashes,
             'historical_document_bytes': 'all original bytes retained; only current plan status header replaced',
             'cards': 174, 'monsters': 60, 'card_faces': 374, 'exam_cards': 14, 'graphical_checks': render['checks'],
             'images': len(pictures), 'new_api_images': 0, 'api_cumulative': 121,
             'runs': {name: {key: record[key] for key in ['command', 'started_utc', 'seconds', 'exit_code', 'engine_errors', 'unexpected_changes']} for name, record in records.items()},
             'scope': 'compendium batch only; original G0/G6/G8, natural four-year completion, final human art review and release acceptance remain separate'}
    write_json(EV / 'audit.json', audit)
    rows = '\n'.join(f'| {name} | {record["seconds"]:.3f}s | 0 | 0 | 无 |' for name, record in records.items())
    readme = f'''# 全卡牌与怪物图鉴验证记录

日期：2026-11-15。{result}

游戏入口：主菜单 → 图鉴 → 卡牌 / 怪物。无存档可进，全部开放。支持名称/ID/全文搜索、组合筛选、分页和详情；卡牌真实基础/升级/考试面，怪物完整骨架、三种动作与全部阶段/意图/来源。

查看[实渲评审入口](review/index.html)、[60怪物总览](review/all-monsters.jpg)、[正式ID/截图清单](capture-verified/manifest.json)、[专项断言](render-verified/checks.json)与[保留核对](audit.json)。本页和评审网页仅为证据，功能已进入Godot工程。

| 运行 | 耗时 | 退出码 | 引擎错误 | 运行中输入变化 |
|---|---|---|---|---|
{rows}

引擎：Godot v4.7.2 stable；Windows 11；GL Compatibility图形实渲，NVIDIA RTX 4060 Laptop。每个运行的`.run.json`保留完整命令、精确src/data/tests/资源/工具输入hash、环境和退出码，`.stdout.txt`/`.stderr.txt`为未裁改原始日志。最终五次运行的全部输入仍与当前文件逐字节匹配。

`render-verified`含1851项检查及48张双尺寸三字号实渲。`capture-verified`含171张：全部15卡牌页/5怪物页的顶底、60怪物详情、14张考试牌共56个实际卡面、14张小窗口长文顶底和主菜单。全部219张可解码并留有尺寸/hash，见[图片核对](image-audit.json)。

规则测试完整运行`res://tests/run_tests.gd`；UI完整27套运行`res://tests/run_ui_tests.gd`，其中新增图鉴套件为1803项无截图检查。正常入口烟测以隔离SaveStore创建真实GameShell并从`menu:compendium`进入；不是直接启动默认main.gd读写玩家档，未将此称为打包/干净环境发行测试。

全量集合逐项核正式manifest；374卡面对照原BattleCardRules解析器；全60套骨架实际实例化；搜索/交集/空结果/重置/逐页无漏无重复；键鼠打开/版本选择/动作/全文滚动/关闭/返回与焦点恢复；关闭动态有效；错误页可返回。使用实际K03待选和旧campus_mvp局验证图鉴查询/返回/继续不换活动目录，不改变完整状态、RNG或revision。正式存档目录10文件的集合及hash保持，未操作实际玩家局。

实际看图记录：卡面保留原六类费用符号；标准画廊五列，小窗口150%字号两列并滚动；详情背景不透字，毕业答辩阶段长文、附属来源及协调推进考试升级面可读，固定操作保持。归档官方参考与来源/hash见[references](references/sources.json)。仍有明确差异：分页双页签、左右详情和前后切换代替官方右侧连续怪物名单；三种动作尚未复刻完整动作目录；返回按钮沿本作通用按钮，未复刻红色返回带。既有主菜单小窗口大字号有标题换行和滚动。这些不以自动测试通过抹去。

`before.zip`为8份改前原件，`baseline.json`记录1614保护文件及10真实档。既有四个允许源码文件的本批变更见[diff](existing-code.diff)。旧文档按bytes追加/局部状态更新，剥除本轮追加并恢复计划状态标题后，原文完整字节保持；内容定义、规则/RNG/存储、四人和60怪原美术资源保持。新增API请求0，累计121/200。

失败历史保留且不作为通过依据：早期短生命周期专项启动器/直接截图启动器出现退出资源释放错误，曾统一用显式装载和释放的生命周期入口通过；完整UI前两轮虽然行为通过，退出仍有资源错误，仅增加等待和释放不足以修复。继续定位后，将详情父页类型从UiCompendiumPage收敛为UiPage、解除具体类型的循环依赖；独立动态装载短程检查无错误，再按最终输入完整重跑。完整UI启动器也保留显式释放每套实例及脚本、等异步帧退休后退出。早期原生菜单键盘测试把第一次Down误认为升级项，实际第一次仅高亮基础，已修正输入路径；截图工具首轮类型错误已修正。最终五次运行均退出0且无引擎错误，未过滤错误或清空缓存。

重跑请使用新的run名/输出目录，避免覆盖证据：

```powershell
python -X utf8 tools/verify_compendium.py render-NEW -- --rendering-method gl_compatibility --script res://tools/run_compendium.gd -- test-full res://artifacts/verification/compendium-20261115/render-NEW
python -X utf8 tools/verify_compendium.py capture-NEW -- --rendering-method gl_compatibility --script res://tools/run_compendium.gd -- capture res://artifacts/verification/compendium-20261115/capture-NEW
python -X utf8 tools/verify_compendium.py rules-NEW -- --headless --script res://tests/run_tests.gd
python -X utf8 tools/verify_compendium.py ui-NEW -- --headless --script res://tests/run_ui_tests.gd
```

本批实现需求UIR-072/073。用户最终美术判断、原整版G0/G6/G8、自然四年通关、性能/打包和发行验收继续独立登记。
'''
    (EV / 'README.md').write_text(readme, encoding='utf-8')

    class Links(HTMLParser):
        def handle_starttag(self, tag, attrs):
            for key, value in attrs:
                if key in ['src', 'href'] and value and not value.startswith(('http:', 'https:', '#')):
                    assert (EV / 'review' / value).resolve().is_file(), value

    Links().feed((EV / 'review/index.html').read_text(encoding='utf-8'))
    print(json.dumps({'ok': True, 'protected': len(baseline['protected']), 'real_saves': len(actual_saves), 'images': len(pictures), 'runs': {name: round(record['seconds'], 3) for name, record in records.items()}}, ensure_ascii=False))


if __name__ == '__main__':
    main()
