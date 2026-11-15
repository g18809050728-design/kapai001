"""Register the authorized story/UI scope and preserve pre-change evidence once."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'artifacts/verification/event-polish-20261115'
OUTPUT = ROOT / 'output/imagegen/event-polish-20261115'
DOCS = ['agent.md', '实施计划与验收基线.md', 'docs/界面层契约.md', '动作或者图片描述/需求台账.md']
MUTABLE = [
    'src/ui/experience_page.gd', 'src/ui/ui_style.gd', 'src/ui/campus_room_illustration.gd',
    'src/ui/room_scene_view.gd', 'src/ui/test_room_page.gd', 'src/ui/test_hud.gd',
]
STORIES = [
    ('V01', '节日放假', '假日前夕 · 校园大门',
     '最后一节课的铃声落下，校门口渐渐热闹起来。行李箱的滚轮声里，有人赶着回家，也有人摊开地图，约着去看看没去过的地方。\n\n难得空下来的一天，你想把时间留给谁，又或者，只留给自己？',
     'Chinese university gate on a mild autumn holiday afternoon, one rolling suitcase and a folded travel map on a low stone ledge in the foreground, a few adult university students with backpacks walking out in the middle distance, ginkgo branches framing a red brick gate, warm late sunlight, a feeling of freedom and anticipation. A blue duffel bag and a portable game controller on the ledge subtly suggest different holiday choices.'),
    ('V03', '选课咨询', '教学楼 · 选课咨询角',
     '教学楼的咨询桌前摊着几份课程安排。学长把笔记推到你面前，讲起那些只有上过课才知道的细节：哪里需要多花功夫，哪些习惯可以早点调整。\n\n课表还没定下来。你可以听听建议，也可以重新想想，什么才是自己现在最需要的。',
     'Quiet Chinese university teaching building corridor in afternoon, an adult senior student sitting naturally behind a small consultation desk explaining a course timetable to another adult student seen in three-quarter back view, blank course sheets with only abstract lines, a notebook and pencil, classroom windows and green trees, thoughtful friendly exchange. Natural adult proportions, relaxed shoulders, hands resting naturally on the desk.'),
    ('V04', '宿舍断电', '夜晚 · 忽然安静的宿舍',
     '啪的一声，宿舍里的灯灭了。电脑屏幕慢慢暗下去，窗外的月光却把桌上的复习资料照出一道银边。走廊传来几声抱怨，很快又安静下来。\n\n少了消息和屏幕的催促，这个夜晚突然有了别的可能：早点睡，或者借着小灯，把手里的内容再理一遍。',
     'Chinese university dormitory during a power outage at night, a completely dark laptop on a wooden study desk, neat revision notes and open textbooks, a small battery-powered warm reading lamp, a bunk bed with folded blue quilt and a pillow in the middle ground, cool moonlight from the window, potted plant silhouette, quiet lived-in room. Clearly no powered ceiling light and no lit computer screen. Cozy stillness, no people, no candle or unsafe flame.'),
    ('V10', '捡到校园卡', '午后 · 林荫路转角',
     '你在林荫路边捡到一张校园卡。卡套上还挂着一枚小小的挂件，像是刚从谁的口袋里滑出来。附近的脚步匆匆，暂时没有人回头寻找。\n\n失主大概还没发现。你望了望路口，又想起不远处的校园服务台。',
     'Close view of a blue university campus ID card in a transparent holder with a small ginkgo-leaf charm lying on a sunlit stone bench beside a leafy campus path, abstract unlettered card design with a simple silhouette only, no personal information, distant student service kiosk under trees, dappled afternoon sunlight. The card holder and charm are the unmistakable focal point, big enough to read as an object at small size.'),
    ('L', '图书馆', '午后 · 图书馆阅览区',
     '书架之间只听得见翻页的声音。你找到一张靠窗的空桌，把最近没想明白的问题和做过的笔记一起摊开。\n\n这里不催你赶路。认真整理一次，也许就能让接下来的学习轻松一些。',
     'Chinese university library reading area, tall orderly bookshelves receding behind a large oak reading desk, open reference book with abstract nonverbal diagrams, stacked notebooks and green-shaded reading lamp, empty chair near tall windows, leafy afternoon sunlight. The open reference book and welcoming study seat form the central focal group, no people.'),
    ('LAB', '实验室', '教学楼 · 实验工作台',
     '实验台上留着上一次尝试的记录，几根导线旁边压着改了一半的草稿。把想法说清楚是一回事，让它真正跑起来，又是另一回事。\n\n你挽起袖口，准备从最需要改进的地方开始，再验证一次。',
     'University engineering laboratory workbench with a small breadboard prototype, a neatly arranged low-voltage circuit board, oscilloscope with a simple waveform and no lettering, coiled wires and an open lab notebook, stool and workshop windows in background. Precise believable connections, tactile instruments, warm amber task light balanced with cool blue window light, no people, no dangerous high voltage.'),
    ('T', '导师交流', '傍晚 · 导师办公室',
     '办公室的门还开着。导师把桌上的材料挪了挪，示意你坐下，先说说最近卡在哪里。\n\n你原本准备了一长串问题，坐下后却发现，最需要的可能是把下一步想清楚。桌边的一杯热茶还冒着气。',
     'Cozy Chinese university professor office at dusk, desk with annotated research drafts shown as abstract marks, two ceramic tea cups and a welcoming empty visitor chair, warm desk lamp, orderly books and framed abstract artwork, softly blue window beyond. Composition suggests an ongoing mentoring conversation without showing identifiable characters. Inviting and thoughtful, tea steam subtle.'),
    ('C', '社团活动', '傍晚 · 社团活动室',
     '活动室里，伙伴们正把桌椅围成一圈。有人递来饮料，有人邀请你一起完成今天的准备，笑声把赶路时的疲惫冲淡了一点。\n\n待一会儿吧。你可以和大家歇口气，也可以搭把手，参与这次活动。',
     'Chinese university student club activity room, three adult students seated and standing naturally around a low table preparing colorful plain paper decorations, cups and a small acoustic guitar leaning against a chair, noticeboard with abstract shapes but no letters, sunset through windows, friendly collaborative atmosphere. Believable relaxed anatomy, faces not dominant, hands simple natural poses.'),
    ('I', '实习实践', '白天 · 校外实践工位',
     '临时工位上放着一份待整理的材料，旁边是已经排好顺序的工作清单。这里没有课堂铃声，只有同事偶尔走过，问一句进展如何。\n\n你检查好随身的本子，准备把学到的方法，放到真实的工作里试一试。',
     'Bright modern internship workspace for a university student, tidy desk with laptop showing abstract nonverbal charts, notebook, plain clipped visitor badge, reusable water bottle, empty ergonomic chair, shared office in soft focus beyond glass partitions, cool daylight with warm wood. A practical welcoming workday, not a corporate dashboard screenshot, no logos, no people.'),
    ('ST', '毕业设计', '深夜 · 毕设工作桌',
     '桌上的材料已经积了厚厚一叠。打印稿留着修改痕迹，草图旁边压着几张实验记录，熟悉的台灯照着这段漫长工作的下一小步。\n\n不必今晚解决所有问题。先把眼前这一部分整理好，让毕业设计再向前一点。',
     'University graduation project work desk late at night, a thick carefully clipped thesis manuscript with abstract marks and colored revision tabs, architectural or engineering mockup in cardboard, open notebook and pencil, ceramic mug, warm desk lamp, quiet dark blue window. Sense of steady progress and accumulated effort, uncluttered focal arrangement, no people.'),
    ('FAMILIAR', '校园熟人', '课间 · 熟悉的走廊',
     '走廊拐角传来一声招呼，是之前见过的熟面孔。你们聊了聊最近的课程和校园里的小事，原本紧绷的步子也跟着慢了下来。\n\n一段短短的闲聊结束，对方笑着挥挥手，催你别误了接下来的安排。',
     'Two adult university acquaintances having a brief friendly conversation in a sunlit campus corridor, natural casual stances at comfortable distance, one carrying a closed notebook and the other a canvas tote, leafy courtyard visible through the arches, a simple bench nearby, warm everyday campus atmosphere. Medium wide environmental composition, adult realistic proportions, no recognizable protagonist identity, no lettering.'),
]

STYLE = ('Original square narrative illustration for a Chinese campus deckbuilding game. '
         'Hand-painted gouache and watercolor with clean fine charcoal contours, textured paper, '
         'careful illustrative detail that remains readable at 400 pixels, muted sage green, warm ochre, '
         'ink navy and cream palette, cinematic but gentle lighting, believable material surfaces and perspective. '
         'A single coherent environmental scene with one strong central focal group occupying the middle 70 percent; '
         'keep all important objects at least 10 percent from each edge. Full painted background to all edges, '
         'not a card, not a screenshot, no decorative frame. No written words, no Chinese characters, no numbers, '
         'no watermark, no UI, no commercial logos. Adults only if people are specified, natural anatomy, '
         'no chibi, no horror, no exaggerated fantasy. ')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    if (EVIDENCE / 'before.zip').exists():
        raise SystemExit('Already prepared; do not overwrite baseline.')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(EVIDENCE / 'before.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for fn in DOCS + MUTABLE:
            archive.write(ROOT / fn, fn)
    protected = {}
    for folder in ['src', 'data', 'assets', 'tests']:
        for p in (ROOT / folder).rglob('*'):
            rel = p.relative_to(ROOT).as_posix()
            if p.is_file() and p.suffix != '.import' and rel not in MUTABLE:
                protected[rel] = sha(p)
    save_root = Path('C:/Users/Dev.LI/AppData/Roaming/Godot/app_userdata/交大四年：DDL战争/saves')
    saves = {p.relative_to(save_root).as_posix(): sha(p) for p in save_root.rglob('*') if p.is_file()}
    refs = ['event2.jpg', 'event1-sequence.jpg', 'event_3-sequence.jpg', 'mainmenu_qol.jpg']
    record = {'started_utc': datetime.now(timezone.utc).isoformat(), 'mutable': MUTABLE,
              'protected': protected, 'saves': saves,
              'documents': {fn: sha(ROOT / fn) for fn in DOCS},
              'references': {fn: sha(ROOT / 'ui-plan/references/slay-the-spire-2' / fn) for fn in refs}}
    (EVIDENCE / 'baseline.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    inventory = {'events': {}, 'rooms': {}}
    jobs = []
    config = json.loads(Path('C:/Users/Dev.LI/.codex/imagegen/config.json').read_text(encoding='utf-8-sig'))
    for key, title, place, narrative, scene in STORIES:
        entry = {'title': title, 'location': place, 'narrative': narrative,
                 'art': f'res://assets/art/events/{key}/illustration.png',
                 'background': f'res://assets/art/events/{key}/background.png'}
        inventory['events' if key.startswith('V') else 'rooms'][key] = entry
        prompt = STYLE + '\nScene: ' + scene
        (OUTPUT / f'{key}-v1-prompt.txt').write_text(prompt, encoding='utf-8')
        jobs.append({'prompt': prompt, 'out': f'{key}-v1.png', 'model': config['model'],
                     'size': '1024x1024', 'quality': 'high'})
    (OUTPUT / 'stories.json').write_text(json.dumps(inventory, ensure_ascii=False, indent=2), encoding='utf-8')
    for name, selected in [('jobs.jsonl', jobs), ('pilot.jsonl', [j for j in jobs if j['out'] == 'V04-v1.png']),
                           ('remaining.jsonl', [j for j in jobs if j['out'] != 'V04-v1.png'])]:
        (OUTPUT / name).write_text(''.join(json.dumps(j, ensure_ascii=False)+'\n' for j in selected), encoding='utf-8')
    design = '''# 事件叙事、场景与遗漏按钮精修

日期：2026-11-15。范围：根计划 §0.20.28；UIR-070（事件与校园情境）、UIR-071（遗漏按钮）。状态：登记完成，待 G6 出图核对后实施。

用户要求补全已有事件介绍、图片和背景，并继续优化此前遗漏的按钮。当前四学年实际启用 V01/V03/V04/V10 四个随机事件；四者共用一句介绍和校园图。六类校园服务 C/I/L/LAB/T/ST 借用卡图，校园熟人与导师共用描述。仅补这些现有入口，不扩大事件或规则池。

方案选择：采用每个事件/场景独立介绍与独立插图，插图同源派生暗色背景；相比继续裁切旧卡图，能明确表达停电、遗失校园卡等情境。整套重做全流程会影响已确认布局，故本批只深化已有事件构图和遗漏按钮。

G6：共 11 项，先生成 V04 核图，再继续其余 10 项。使用已授权 jiji.cc API、运行时配置模型，1024×1024/high；本轮开始累计110/200，计划成功后121/200。保留原图、完整提示词、hash、实际尺寸、服务/模型和派生方法。只作文字画风分析，无上传参考图或编辑接口承诺。原校园背景为水彩/细线、鼠尾草绿/暖赭/深蓝，沿用此语言。官方 event2/event1/event_3 只作构图和按钮参考，不提取商业运行素材。

G7：保持左侧情境、右侧标题/正文/切角选项的二代结构。图片边缘柔化融入场景；正文按事件 ID 精确路由，服务按 subtype 路由，未知ID和缺图沿旧资源回退。叙事不写死收益；代价、效果、候选、报价继续来自实际只读视图。补选项标题与效果的颜色层级、设置已选按钮的共享皮肤、测试主页及测试HUD原生按钮；不全盘推翻此前已优化控件。主操作≥44实际像素，状态不改变命中区，焦点轮廓可见。

边界：UI只读表述，不改 data 定义/manifest、规则、RNG、schema、存档、GameSession写口、命令ID/载荷/门控。免费无目标一次执行；付费/目标动作仅一次最终确认，取消左主操作右。四人P01V12/P02V8/P03V10/P04V11和60敌怪、共享骨架/战斗演出、地图语义及手牌保持。测试HUD变化只改外观与尺寸，不扩展测试能力。已有工作树不覆盖或提交。

验证：保存改前原字节与保护hash、真实档只读hash、参考hash。图形Godot采集前后同场景；覆盖四事件、六服务与熟人、两尺寸1280×800/960×600、100/125/150%字号、长文滚动、最后选项、选择/返回/确认、设置状态、测试主页/HUD按钮。专项测试检查身份与图文映射、缺图回退、查看/预选无状态RNG变化、真实免费/付费命令一次消费；实际运行完整规则/UI和默认入口，记录输入/环境/命令/退出码/原始输出。技术通过与AI视觉核对、用户最终美术判断分别记录；整版G0/G6/G8、自然四年通关和发行出口不据此通过。

证据：[本轮目录](../../artifacts/verification/event-polish-20261115/README.md)。需求：[逐项验收](../../动作或者图片描述/事件图文与按钮精修_20261115.md)。
'''
    (ROOT / 'docs/plans/2026-11-15-event-polish-design.md').write_text(design, encoding='utf-8')
    req = '''# 事件图文与按钮精修需求

日期：2026-11-15。用户原话：“接下来，补全我们的一些事件中缺少的介绍和图片等背景，然后继续优化一些以前没有优化过的按钮的ui”。

| ID | 触发与范围 | 可观察验收 | 状态 |
|---|---|---|---|
| UIR-070 | V01节日/V03选课/V04断电/V10校园卡；C/I/L/LAB/T/ST六服务及校园熟人 | 各有贴合情境的独立介绍/图片；背景跟随入口；规则收益仍由真实视图显示；缺图可回退；两尺寸三字号可阅读/滚动 | 登记，待资源核对/实现 |
| UIR-071 | 事件/服务选项、设置已选项、测试主页与HUD遗漏按钮 | 统一切角层次、悬停/按下/选中/禁用/焦点；主要点击区≥44px；保留UID、真实代价与禁用原因、一次执行及一次最终确认 | 登记，待实现 |

来源与设计：[根计划§0.20.28](../实施计划与验收基线.md)、[实施设计](../docs/plans/2026-11-15-event-polish-design.md)、[界面契约](../docs/界面层契约.md)。已有形象、规则与正式档保护边界见设计；11项独立图在既有200张授权内生成。资源核对、实机验证与最终用户美术评价分别记录。
'''
    (ROOT / '动作或者图片描述/事件图文与按钮精修_20261115.md').write_text(req, encoding='utf-8')
    notes = {
        'agent.md': '2026-11-15当前新增§0.20.28事件图文与遗漏按钮精修：已授权先登记/盘点，再独立G6核对11项场景图后进入G7实施。四事件、六服务及校园熟人按现有ID补叙事和同源背景；保留真实报价/命令/门控及四角色/60敌怪。见[设计](docs/plans/2026-11-15-event-polish-design.md)与[UIR-070/071](动作或者图片描述/事件图文与按钮精修_20261115.md)。状态：准备中，未声明验收。',
        'docs/界面层契约.md': '2026-11-15 §0.20.28/UIR-070/071追加：事件叙事/图片为纯表现映射，不加入内容定义或存档；按V01/V03/V04/V10及现有服务subtype与familiar精确路由，未知/缺图保留旧回退。选项报价/效果/目标/可用性仍由SessionView与preview门控提供；免费无目标一次执行，付费/目标一次最终确认，取消左/主操作右。按钮改色/层级/尺寸不改UID、命令载荷或焦点与背景隔离语义；主要操作≥44实际像素。G6图像核对先于G7接入，测试隔离真实档。见[本轮设计](plans/2026-11-15-event-polish-design.md)。状态：准备中。',
        '动作或者图片描述/需求台账.md': '2026-11-15新增[UIR-070/071事件图文与遗漏按钮](事件图文与按钮精修_20261115.md)：四随机事件、六校园服务、校园熟人各补情境介绍/图及同源背景；统一事件选项、设置选中及测试入口/HUD遗漏按钮。先核资源再接正常入口，11图预计累计121/200；规则与已选形象保护。见[设计](../docs/plans/2026-11-15-event-polish-design.md)。状态：登记，未验收。',
    }
    for fn, text in notes.items():
        p = ROOT / fn
        data = p.read_bytes()
        end = data.find(b'\n') + 1
        p.write_bytes(data[:end] + ('\n' + text + '\n').encode('utf-8') + data[end:])
    plan = ROOT / DOCS[1]
    raw = plan.read_bytes()
    section = '''## 0.20.28 2026-11-15 事件图文与遗漏按钮精修

用户要求补全已有事件缺少的介绍、图片和背景，并继续优化此前遗漏按钮。本节按已确认的二代UI目标，在当前四学年/G7范围追加执行例外：先登记UIR-070/071与界面契约、盘点11个既有情境，再独立G6出图/核图后进入G7接入及验证，无需逐图重复批准。使用既有jiji.cc与200张授权，开始累计110/200，预计新增11张；不扩大事件、规则或付费服务范围。

允许改UiExperiencePage、CampusRoomIllustration、RoomSceneView、UiStyle、TestRoomPage与TestHud的表现及新图文映射/工具/专项测试；现有data/规则/随机/存档/schema/写入口/命令UID与门控、四人物/60敌怪、骨架/演出及地图点击语义保持。免费无目标一次执行、付费/目标一次最终确认和取消左主操作右保留。保留改前原字节、保护与真实档hash、官方对照、实际素材和双尺寸三字号实渲；完整回归和自然通关/人工最终评价分开。具体设计与验收见[本轮设计](docs/plans/2026-11-15-event-polish-design.md)和[UIR-070/071](动作或者图片描述/事件图文与按钮精修_20261115.md)。当前状态：准备，尚未生成/实施/验收；原整版G0/G6/G8与发行出口不变。

'''
    marker = '## 1. 目标与版本边界'.encode('utf-8')
    assert raw.count(marker) == 1
    plan.write_bytes(raw.replace(marker, section.encode('utf-8') + marker, 1))
    print(json.dumps({'protected': len(protected), 'real_save_files': len(saves), 'stories': len(STORIES), 'planned_success_total': 121}, ensure_ascii=False))


if __name__ == '__main__':
    main()
