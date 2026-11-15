"""Close this art batch using retained results; preserve old document bytes."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'artifacts/verification/card-style-20261115'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def append(path, text):
    with path.open('ab') as output:
        output.write(('\r\n\r\n' + text.strip() + '\r\n').encode('utf-8'))


def main():
    if (EVIDENCE / 'completion.json').exists():
        raise SystemExit('Completion already exists; do not repeat document mutations')
    render = read(EVIDENCE / 'render-01.run.json')
    ui = read(EVIDENCE / 'ui-headless-02.run.json')
    report = read(EVIDENCE / 'render-01/report.json')
    browser = read(EVIDENCE / 'browser-check-01.json')
    rules = read(EVIDENCE / 'rules-evidence-reuse.json')
    assets = read(ROOT / 'output/imagegen/card-style-20261115/asset-manifest.json')
    for run in [render, ui]:
        assert run['exit_code'] == 0 and run['engine_errors'] == 0 and not run['changed_during_run']
    assert report['ok'] and len(report['checks']) == 1927 and len(report['captures']) == 288
    assert browser['ok'] and browser['checks'] == 966 and rules['ok']
    assert assets['installed'] and assets['selected_count'] == 174 and assets['api_successful'] == 22
    assert read(EVIDENCE / 'audit.json')['ok']

    status = ('174张角色风格/牌名插画已全部接入：22张八格图集、零失败/补图；'
              '1927项图形专项、288张窗口图和174张实际卡面、966项对照页检查通过；'
              f'完整27套无头UI {ui["seconds"]:.3f}秒通过，退出0/引擎错误0/运行中输入无变。'
              '规则沿用上批相同308项源码/数据/测试输入的通过证据，本轮未重跑。'
              '1477保护文件、180份改前原件与10个正式存档文件核对通过；'
              'API新增22、累计143/200，费用未返回。'
              '窗口化完整UI另有3项滚动/悬停检查失败，原始记录保留；不据此宣称窗口化全套通过。'
              '最终美术与原整版G0/G6/G8出口另记。')
    links = ('[新旧对照/放大/游戏卡面](artifacts/verification/card-style-20261115/review/index.html)、'
             '[实测记录](artifacts/verification/card-style-20261115/README.md)')
    plan = ROOT / '实施计划与验收基线.md'
    with zipfile.ZipFile(EVIDENCE / 'before.zip') as archive:
        original_plan = archive.read('实施计划与验收基线.md')
    old = next(line.rstrip(b'\r') for line in original_plan.split(b'\n') if line.startswith('版本：v1.88｜'.encode('utf-8')))
    new = ('版本：v1.89｜日期：2026-11-15｜状态：§0.20.30卡牌插画已完成制作与接入；' + status).encode('utf-8')
    content = plan.read_bytes()
    assert content.startswith(original_plan) and content.count(old) == 1
    content = content.replace(old, new, 1)
    state_old = '状态：清单与首批制作中。'.encode('utf-8')
    assert content.count(state_old) == 1
    content = content.replace(state_old, ('状态：' + status).encode('utf-8'), 1)
    plan.write_bytes(content)
    update = {'updates': [{'path': '实施计划与验收基线.md', 'old': old.decode('utf-8'),
                           'new': new.decode('utf-8'), 'reason': 'Update the current version/status line only; all other historical bytes and CR/CRLF endings remain intact.'}]}
    (EVIDENCE / 'document-header-updates.json').write_text(json.dumps(update, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    append(plan, '2026-11-15本批结果入口：' + links + '。全部八格与裁片逐批作AI观察，用户最终审美未签收。')
    append(ROOT / 'agent.md', '2026-11-15卡图实际结果（§0.20.30/UIR-074）：' + status + '先看' + links + '。正式人物、六类费用符号、规则/命令/RNG/存档保持。')

    design = ROOT / 'docs/plans/2026-11-15-card-style-design.md'
    data = design.read_bytes()
    data = data.replace('状态：制作中，未作最终审美验收。'.encode('utf-8'), '状态：174张制作与接入已完成，用户最终审美待查看。'.encode('utf-8'), 1)
    design.write_bytes(data)
    append(design, '实际结果：' + status + '\n\n'
           '[逐牌前后/放大/游戏卡面](../../artifacts/verification/card-style-20261115/review/index.html)；'
           '[完整实测、失败记录及复现命令](../../artifacts/verification/card-style-20261115/README.md)。'
           '四角色正式卡面及公共/衍生五张联系表已实际查看；林序最后八张夜景更暗但关键信息仍清楚，'
           '公共部分出镜人物与prompt指定不同但不绑定角色，逐批记录已如实保留。'
           '本批只换插图，整版卡框/布局及官方对照的其余差异不在本次重做。')
    append(ROOT / '动作或者图片描述/卡牌角色风格与牌名插画_20261115.md',
           '实际完成：' + status + '\n\n[新旧与实际游戏查看](../artifacts/verification/card-style-20261115/review/index.html)、'
           '[完整实测与限制](../artifacts/verification/card-style-20261115/README.md)。')
    ledger = ROOT / '动作或者图片描述/需求台账.md'
    data = ledger.read_bytes()
    old_row = '[证据](../artifacts/verification/card-style-20261115/)；制作中'.encode('utf-8')
    assert data.count(old_row) == 1
    data = data.replace(old_row, '[证据](../artifacts/verification/card-style-20261115/README.md)；174张已接入；1927图形专项/966浏览器/27套无头UI通过；窗口化全套3项失败单列，最终审美待用户查看'.encode('utf-8'), 1)
    ledger.write_bytes(data)
    append(ROOT / 'docs/界面层契约.md', 'UIR-074实际结果：' + status + '\n\n'
           '图鉴15页顶/底、174独立详情、374真实基础/升级/考试卡面复用均核对；两尺寸三字号覆盖四人初战及六类房间共享视图。'
           '房间图为当前UiExperiencePage只读fixture，四人初战使用正常生产命令；不冒充自然四年通关。'
           '[核查与原始日志](../artifacts/verification/card-style-20261115/README.md)。')
    append(ROOT / 'docs/全新卡牌图片生成提示词_v3.md', '2026-11-15当前174卡重绘已完成并选用174/174；'
           '22次API全成功，最后图集两格为空，没有生成重复候选或返工。'
           '升级与考试面复用对应ID新图，当前已安装资源来源以[manifest](art/card-art-assets-v3.json)和'
           '[本批结果](../artifacts/verification/card-style-20261115/README.md)为准。'
           '原图集/旧prompt/旧174图在改前ZIP保留，人工最终美术和许可未自动通过。')

    visual = {
        'reviewer': 'AI visual inspection; not user aesthetic approval',
        'reviewed_utc': datetime.now(timezone.utc).isoformat(),
        'all_atlas_reviews': 'output/imagegen/card-style-20261115/visual-review.json',
        'actual_cardface_contacts': ['review/face-contacts/' + name + '.jpg' for name in ['P01', 'P02', 'P03', 'P04', 'C']],
        'additional_rendered_samples': ['render-01/sample-R3-P01-12-960-150.png', 'render-01/sample-R3-P03-01-1280-100.png',
                                        'render-01/room-reward-1280-100.png', 'render-01/battle-P04-1280-100.png', 'review-960.png'],
        'observations': [
            'All 174 actual shared CardFaceView crops were inspected across five contact sheets; names, original type/cost symbols and central objects remain distinguishable.',
            'P01 last eight paintings use darker copper/teal night lighting; in the actual reward/cardface crops, connector highlights, hands and faces remain clear. This tonal difference is retained for user review.',
            'P02 paper/chapter visual vocabulary, P03 evidence/inquiry props and P04 handoff/group-work scenes remain distinct. No cropped central face or key object was identified in this inspection.',
            'Some public-card character assignments differ from prompt suggestions, already recorded per atlas; public cards do not have a required single character identity.',
            'Review page was also viewed at 960x600; navigation, counts and three art columns fit without horizontal overflow.'],
        'human_acceptance': 'pending user review',
    }
    for key in ['actual_cardface_contacts', 'additional_rendered_samples']:
        for name in visual[key]:
            assert (EVIDENCE / name).is_file(), name
    (EVIDENCE / 'game-visual-review.json').write_text(json.dumps(visual, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (EVIDENCE / 'README.md').write_text(f'''# 174卡人物风格与牌名插画：实际制作/接入记录

2026-11-15，UIR-074，根计划§0.20.30。174张已默认替换到原游戏路径，用户最终审美待查看。{status}

打开[逐牌新旧对照与放大](review/index.html)，可按角色/牌名搜索、切换旧图/新图/真实游戏卡面，并打开该牌实际详情。游戏入口为主菜单→图鉴→卡牌。实际卡面联系表：[林序](review/face-contacts/P01.jpg)、[许知微及论文衍生](review/face-contacts/P02.jpg)、[沈见章](review/face-contacts/P03.jpg)、[唐以宁](review/face-contacts/P04.jpg)、[公共](review/face-contacts/C.jpg)。

| 核查 | 实际结果/证据 |
|---|---|
| 生产 | 22次八格API全成功；四人各40、公共12、论文衍生2。2列×4行1024×1536、medium、n=1；最后两格空。22次dry-run、22次请求记录与完整prompt、实际上传正式人物参考均保留。累计成功143/200；费用未返回，不按图片数估算账单。 |
| 裁片/安装 | 174张480×360 RGB；损坏/尺寸错/精确重复均0。22张原图和174裁片hash通过，174正式ID精确集合、已安装图/候选/溯源一致。见[crop-audit](crop-audit.json)、[atlas-audit](atlas-audit.json)、[最终审计](audit.json)。 |
| 改前实渲 | before-03，29.711秒，825项、84截图，退出0/引擎错误0/运行中输入未变。此前before-01是验收工具用连续emit替代地图真实预选/确认造成失败，已修工具；before-02旧房间fixture后改为当前组件，二者原记录保留。 |
| 新图实渲 | render-01，{render['seconds']:.3f}秒，1927项，288张窗口截图＋174张真实CardFaceView裁片；退出0/引擎错误0/stderr空/输入未变。[报告](render-01/report.json)、[精确输入和命令](render-01.run.json)。 |
| 图鉴/变体 | 15页174卡精确集合，页顶/底30图，174独立详情/实际卡面，374真实基础/升级/考试面图片复用。无新ID或规则改动。 |
| 当前共享页面 | 四人正常生产初战及代表详情，两尺寸三字号各24图；当前UiExperiencePage奖励、商店、事件选牌、学年奖励、休息升级与牌组六类只读fixture共36图。fixture不冒充自然路线。 |
| 对照页 | 隔离Edge无头实例，966项、18.266秒；174张实际解码，718本地链接，角色计数40/42/40/40/12，牌名/ID搜索、空结果、新旧/卡面切换、放大/关闭、44px主筛选与两宽无横向溢出通过，JS错误0。[报告](browser-check-01.json)。 |
| 完整UI | 按项目此前完整验收同一命令的27套无头UI，本轮重跑{ui['seconds']:.3f}秒通过，退出0/引擎错误0/输入未变。[结果](ui-headless-02.run.json)、[原输出](ui-headless-02.stdout.txt)。 |
| 完整规则 | 本轮未重跑。逐项核对上批rules-verified的308份当前src/data/tests/project输入完全相同、无新增遗漏；复用其61.078秒/退出0/错误0证据，UID侧车另由本批保护审计核对。[明确复用记录](rules-evidence-reuse.json)。 |
| 原样保护 | 1477文件与10正式玩家存档文件hash不变；旧174图＋6文档共180原件ZIP完整，旧Markdown除登记的计划状态头行外字节前缀保持（含原CR/CRLF），新内容追加。 |

窗口化完整UI尝试ui-01没有通过：旧fixture商店滚动、战斗0.75秒悬停、奖励0.3秒悬停三项失败，311.473秒、退出1/三条引擎ERROR。[原结果](ui-01.run.json)、[stderr](ui-01.stderr.txt)保留；没有修改原src/data/tests或缩减断言来获得通过。随后同源码沿既有无头命令完整通过，但这不等于窗口化全套问题已修复，也未确认三项失败的根因。本轮1927项图形专项与全部实际卡面显示是独立通过的结果。

Godot导入import-01退出0、引擎错误0；stderr有历史artifacts的重复UID警告，未清理旧证据，也不声称其stderr为空。最终render-01及完整无头UI的stderr为空。

所有22份带牌名的裁片联系表均已逐批实际看图，详见[逐批观察](../../../output/imagegen/card-style-20261115/visual-review.json)；全部174真实卡面也按五张联系表核查，详见[实机视觉记录](game-visual-review.json)。林序最后八张夜间色调更暗，主要道具仍可辨；公共若干出镜人物与提示指定不同，公共牌不绑定人物，该差异已保留。人工最终审美、资源许可与整版G0/G6/G8出口分别记录。

正式P01 V12/P02 V8/P03 V10/P04 V11立绘/骨架、其他敌怪/事件图、原卡框/六类费用符号、内容/规则/命令/RNG/存档保持。仅更新assets/cards/v3/既有174PNG及资源溯源；不把本批图片替换当作整版UI复刻完成、自然四年通关、性能或发行验收。

复现检查命令（在项目根目录运行；Godot二进制由GODOT_BIN可覆盖）：

```powershell
python -X utf8 tools/process_card_style.py audit
python -X utf8 tools/verify_card_style.py render-new-name -- --audio-driver Dummy --rendering-method gl_compatibility --script res://tools/capture_card_style.gd -- res://artifacts/verification/card-style-20261115/render-new-name
python -X utf8 tools/verify_card_style.py ui-new-name -- --headless --script res://tests/run_ui_tests.gd
```

已有证据名不会覆盖。对照页浏览器复核脚本tools/verify_card_style_review.py保留精确页面hash和脚本hash，重新执行需使用新的报告名。不要重跑prepare/crop/install来检查当前安装；当前安装状态以manifest与audit为准。
''', encoding='utf-8')
    completion = {
        'completed_utc': datetime.now(timezone.utc).isoformat(), 'requirement_id': 'UIR-074',
        'installed_count': 174, 'atlas_requests': 22, 'api_before': 121, 'api_after': 143,
        'graphics_checks': 1927, 'window_captures': 288, 'actual_cardface_crops': 174,
        'browser_checks': 966, 'full_headless_ui': 'passed', 'full_windowed_ui': 'failed 3; retained, not claimed fixed',
        'full_rules': 'reused same 308 inputs; not rerun this batch',
        'human_acceptance': 'pending user review', 'production_code_or_data_changed': False,
        'header_updates': 'document-header-updates.json', 'review': 'review/index.html',
    }
    (EVIDENCE / 'completion.json').write_text(json.dumps(completion, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(completion, ensure_ascii=False))


if __name__ == '__main__':
    main()
