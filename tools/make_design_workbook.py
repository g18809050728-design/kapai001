# -*- coding: utf-8 -*-
"""
生成本项目的《设计元素表》Excel —— 设计元素与配图的单一查阅面。

用途：
    这是「人 -> 助手」的决策载体。每张值表都有两列：
        当前值    代码里的实际值（本脚本填入，作为对照基线）
        你的决定  留空由人填写；填了就是明确的变更要求
    助手用 tools/read_design_workbook.py 读回本表，只报告「被改动的项」。
运行： python tools/make_design_workbook.py
产出： docs/设计元素表.xlsx
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.drawing.image import Image as XLImage
from openpyxl.utils import get_column_letter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "设计元素表.xlsx")
ART = os.path.join(ROOT, "assets", "art")
FIG = os.path.join(ROOT, "docs", "design")

FONT = "微软雅黑"
HDR_FILL = PatternFill("solid", fgColor="2F5597")
DEC_FILL = PatternFill("solid", fgColor="FFF2CC")
HDR_FONT = Font(name=FONT, size=10.5, bold=True, color="FFFFFF")
BODY = Font(name=FONT, size=10)
MONO = Font(name="Consolas", size=10)
BOLD = Font(name=FONT, size=10, bold=True)
TITLE = Font(name=FONT, size=14, bold=True, color="2F5597")
NOTE = Font(name=FONT, size=9.5, italic=True, color="808080")
THIN = Side(style="thin", color="BFBFBF")
BD = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

WINDOW = [
    ("viewport_width", "画布宽（设计分辨率）", 1600, "project.godot -> viewport_width"),
    ("viewport_height", "画布高（设计分辨率）", 900, "project.godot -> viewport_height"),
    ("stretch_mode", "拉伸模式", "canvas_items", "固定设计空间，避免布局漂移"),
    ("stretch_aspect", "拉伸比例", "keep", "保持 16:9，多余区域留黑边"),
]

PALETTE = [
    ("BG_DEEP", "最外层 / 远墙", "#171310", "低对比暖褐黑"),
    ("BG_STONE", "石墙", "#2a231c", "背景石材"),
    ("BG_FLOOR", "地面", "#241e18", "比石墙略深，形成地面感"),
    ("PANEL", "面板底", "#332a22", "以 84% 不透明度使用，让火光透出"),
    ("PANEL_HI", "面板强调", "#40352a", "按钮、次级面板"),
    ("BORDER", "描边", "#57493b", "1~2 px，暖灰"),
    ("BORDER_HI", "高光描边", "#7d6a53", "面板顶边与重要分区"),
    ("TEXT", "主文字", "#ece3d4", "暖白，接近羊皮纸"),
    ("TEXT_DIM", "次要文字", "#a79883", "说明、日志、副标题"),
    ("TEXT_INK", "纸面墨色", "#3b3024", "羊皮纸卡面上的正文色"),
    ("TEXT_INK_DIM", "纸面次要墨色", "#6b5b45", "卡面上的类型文字等"),
    ("GOLD", "金（描边/费用）", "#d9a441", "费用徽章边、场景牌描边"),
    ("SELECT", "选中 / 高亮", "#f2dc9e", "浅金，比金更亮"),
    ("HP", "生命", "#b0432f", "陶土红；血条填充"),
    ("HP_BG", "生命条底", "#3a2620", "血条背景"),
    ("SHIELD", "护盾", "#6f8fa8", "雾蓝，与生命明确区分"),
    ("ENERGY", "能量", "#e0a94a", "琥珀；费用数字与能量格统一"),
    ("GOOD", "就绪 / 正向", "#7a9a5a", "苔绿；随从可攻击"),
    ("WARN", "警告 / 不可用原因", "#c98a4b", "赭石；卡牌不可用原因"),
    ("TAUNT", "嘲讽", "#c9924a", "嘲讽标记"),
    ("PAPER", "羊皮纸", "#e9dcc3", "卡面底色"),
    ("PAPER_EDGE", "纸边", "#c9b691", "纸面暗部"),
]

CARD_TYPES = [
    ("ATTACK", "攻击", "#a8442f", "赭红（朱砂）"),
    ("DEFENSE", "防御", "#4a6f8f", "石青"),
    ("SKILL", "技能", "#7a5a8f", "紫藤"),
    ("SCENE", "场景", "#b08a3c", "金褐"),
    ("MINION", "随从", "#5f8a5a", "苔绿"),
]

FONTS = [
    ("card_name", "卡牌名称", 17, "bold", "是", "卡面左上角"),
    ("card_cost", "卡牌费用", 15, "bold", "是", "费用徽章内"),
    ("card_type", "卡牌类型文字", 12, "normal", "是", "卡头下方"),
    ("card_desc", "卡牌效果描述", 13, "normal", "是", "羊皮纸卡面正文"),
    ("card_hint", "卡牌不可用原因", 12, "normal", "是", "卡面底部"),
    ("minion_name", "随从名称", 15, "normal", "是", "随从槽"),
    ("minion_stat", "随从数值", 13, "normal", "是", "攻击 / 生命"),
    ("minion_state", "随从状态", 12, "normal", "是", "就绪 / 准备中"),
    ("panel_title", "面板标题", 18, "bold", "否", "玩家 / 魔像 / 随从区"),
    ("value_text", "数值文本", 15, "normal", "否", "生命 60/60、能量 3/10"),
    ("hint_text", "操作提示", 13, "normal", "否", "右下角控制区"),
    ("log_text", "日志", 12, "normal", "否", "结算日志（可折叠）"),
]

SIZES = [
    ("CARD_SIZE", "手牌单卡", 148, 208, "手牌区唯一可点击热区"),
    ("CARD_HEADER_H", "卡牌卡头高", 148, 44, "类型色卡头；宽随卡宽"),
    ("MINION_SLOT", "随从槽位", 130, 146, "两个固定槽位"),
    ("ENERGY_PIP", "能量格", 22, 12, "共 10 格（对应当前上限 10）"),
    ("HP_BAR", "生命条", 264, 26, "玩家 / 敌人各一条"),
    ("SCENE_BOX", "场景牌区", 600, 104, "名称 / 效果 / 剩余触发次数"),
    ("COST_BADGE", "费用徽章直径", 26, 26, "圆形，金边"),
    ("BUFF_ICON", "状态图标（规划）", 108, 108, "升级用，尚未实现"),
]

LAYOUT = [
    ("TOPBAR", "顶栏", 0, 0, 1600, 54, "战斗名称 / 回合数 / 玩法说明与快速开关"),
    ("PLAYER_PANEL", "左侧玩家区", 20, 66, 300, 336, "生命 / 护盾 / 能量 0~10"),
    ("MINION_PANEL", "左下随从区", 20, 412, 300, 196, "两个固定槽位"),
    ("FIELD", "中央场地区（无实心面板）", 336, 66, 928, 542, "露出石室背景；角色站于其中"),
    ("CHAR_PLAYER", "玩家角色立绘", 390, 190, 300, 420, "冒险者；站在场景里，不在面板内"),
    ("CHAR_ENEMY", "敌人角色立绘", 890, 170, 340, 440, "练习魔像"),
    ("SCENE_BOX", "场景牌区", 500, 82, 600, 104, "场景名称 / 效果 / 剩余次数"),
    ("ENEMY_PANEL", "右侧敌人区", 1280, 66, 300, 336, "名称 / 生命 / 护盾 / 当前意图"),
    ("ENEMY_HIT", "敌人点击热区", 1280, 250, 300, 152, "单体牌需点击此处确认"),
    ("LOG_PANEL", "结算日志（可折叠）", 1280, 412, 300, 196, "最近结算记录"),
    ("PILE_PANEL", "牌堆区", 20, 620, 160, 262, "抽牌堆 / 弃牌堆入口"),
    ("HAND_AREA", "手牌区", 196, 620, 1188, 262, "最多 10 张 / 重叠排列 / 悬停展开"),
    ("CONTROL_PANEL", "控制区", 1400, 620, 180, 262, "提示 / 确认使用 / 结束回合 / 重开"),
    ("KEEP_BAR", "保留操作条", 500, 566, 600, 40, "仅保留阶段显示"),
    ("LEGEND", "图例", 352, 588, 900, 20, "卡牌类型说明"),
]

ART_ASSETS = [
    ("ART_BG", "res://assets/art/bg_ruins.png", 1600, 900, "石室背景：拱门 / 石柱 / 地面 / 火把暖光 / 颗粒 / 暗角"),
    ("ART_VIGNETTE", "res://assets/art/vignette.png", 1600, 900, "暗角叠加层（RGBA）：中心透明、边缘 92%"),
    ("ART_ADVENTURER", "res://assets/art/char_adventurer.png", 300, 420, "冒险者立绘：兜帽剪影 + 轮廓光 + 暗色外描边"),
    ("ART_GOLEM", "res://assets/art/char_golem.png", 340, 440, "练习魔像立绘：石块躯干 + 余烬眼 + 苔藓"),
]

FIGURES = [
    ("palette", "色彩系统：分组逻辑与全部色值"),
    ("card_anatomy", "卡牌元素解剖：6 个元素与字号"),
    ("card_types", "五类卡牌：赭红 / 石青 / 紫藤 / 金褐 / 苔绿"),
    ("card_states", "卡牌四态：默认 / 悬停 / 选中 / 不可用"),
    ("battle_layout", "战斗界面布局：14 个区域的真实坐标"),
    ("hand_layout", "手牌区排布：1/3/6/10 张时的步长与重叠"),
    ("buff_icons", "Buff / Debuff 图标集（升级用，尚未实现）"),
    ("intent_status", "敌人意图三态 + 玩家状态元素 + 飘字规范"),
    ("flow_states", "界面状态流转与输入锁"),
]



# ── 游戏基本信息 ─────────────────────────────────────────
GAME = [
    ("game_name", "游戏名称（窗口标题）", "PVE 卡牌战斗 Demo", "project.godot", "config/name"),
    ("game_desc", "游戏描述", "遗迹入口 · 石制守卫 —— 单人 PVE 回合制卡牌战斗 Demo", "project.godot", "config/description"),
    ("encounter_title", "场景标题", "遗迹入口 · 石制守卫", "enemy_db.gd", "ENCOUNTER.title"),
    ("player_max_hp", "玩家最大生命", 60, "battle_types.gd", "PLAYER_MAX_HP"),
    ("player_start_hp", "玩家初始生命", 60, "battle_engine.gd", "init_battle"),
    ("player_start_shield", "玩家初始护盾", 0, "battle_engine.gd", "init_battle"),
    ("enemy_max_hp", "魔像生命", 35, "battle_types.gd", "GOLEM_MAX_HP"),
    ("energy_max", "能量上限", 10, "battle_types.gd", "MAX_ENERGY"),
    ("energy_start", "新战斗初始能量", 0, "battle_engine.gd", "init_battle"),
    ("hand_max", "手牌上限", 10, "battle_types.gd", "MAX_HAND"),
    ("draw_per_turn", "每回合抽牌数", 5, "battle_types.gd", "DRAW_PER_TURN"),
    ("minion_slots", "随从槽位数", 2, "battle_types.gd", "MINION_SLOTS"),
    ("scene_triggers", "能量涌泉触发次数", 3, "battle_types.gd", "SCENE_SPRING_TRIGGERS"),
    ("deck_size", "初始牌组张数", 20, "card_db.gd", "各卡数量合计"),
    ("card_kinds", "卡牌种类数", 11, "card_db.gd", "CARDS 条目数"),
    ("win_condition", "胜利条件", "魔像生命归零且玩家存活", "battle_engine.gd", "_check_endgame"),
    ("lose_condition", "失败条件", "玩家生命归零", "battle_engine.gd", "_check_endgame"),
    ("first_turn_hint", "首回合提示", "敌人本轮将攻击 6；若手中有格挡，可获得护盾抵消伤害。", "enemy_db.gd", "ENCOUNTER.first_turn_hint"),
]

# ── 实体信息：ID / 实体 / 属性 / 当前值 / 你的决定 / 实现位置 / 说明 ──
ENTITIES = [
    ("ENT_PLAYER", "玩家", "显示名称", "玩家", "battle_scene.gd", "左侧面板标题"),
    ("ENT_PLAYER", "玩家", "最大生命", 60, "battle_types.gd", "PLAYER_MAX_HP"),
    ("ENT_PLAYER", "玩家", "初始护盾", 0, "battle_engine.gd", "init_battle"),
    ("ENT_PLAYER", "玩家", "立绘", "res://assets/art/char_adventurer.png", "palette.gd", "ART_ADVENTURER"),
    ("ENT_PLAYER", "玩家", "站位 x,y,w,h", "390,190,300,420", "design_layout.gd", "CHAR_PLAYER；站在场景里"),
    ("ENT_ENEMY", "练习魔像", "显示名称", "练习魔像", "enemy_db.gd", "ENEMIES.practice_golem.name"),
    ("ENT_ENEMY", "练习魔像", "生命", 35, "enemy_db.gd", "max_hp"),
    ("ENT_ENEMY", "练习魔像", "初始护盾", 0, "enemy_db.gd", "initial_shield"),
    ("ENT_ENEMY", "练习魔像", "初始行为游标", 0, "battle_engine.gd", "init_battle"),
    ("ENT_ENEMY", "练习魔像", "立绘", "res://assets/art/char_golem.png", "palette.gd", "ART_GOLEM"),
    ("ENT_ENEMY", "练习魔像", "站位 x,y,w,h", "890,170,340,440", "design_layout.gd", "CHAR_ENEMY"),
    ("ENT_ENEMY", "练习魔像", "行为 0", "攻击 6（对玩家或最左嘲讽随从），下一格 1", "enemy_db.gd", "behaviors[0]"),
    ("ENT_ENEMY", "练习魔像", "行为 1", "防御 8（获得 8 护盾，本轮不攻击），下一格 2", "enemy_db.gd", "behaviors[1]"),
    ("ENT_ENEMY", "练习魔像", "行为 2", "重击 10，下一格 0", "enemy_db.gd", "behaviors[2]"),
    ("ENT_MINION", "随从·突击兵", "攻击 / 生命", "3 / 4", "card_db.gd", "striker 的 summon"),
    ("ENT_MINION", "随从·突击兵", "嘲讽", "否", "card_db.gd", "striker"),
    ("ENT_MINION", "随从·守卫", "攻击 / 生命", "2 / 7", "card_db.gd", "guardian 的 summon"),
    ("ENT_MINION", "随从·守卫", "嘲讽", "是", "card_db.gd", "guardian"),
]

# ── 卡牌信息：ID / 名称 / 类型 / 费用 / 目标 / 效果 / 数量 / 数值明细 / 备注 ──
CARDS = [
    ("slash", "斩击", "攻击", 0, "单个敌人", "获得 1 能量，然后造成 5 伤害", 4, "回能 +1 → 伤害 5", "免费牌；顺序为先回能后伤害"),
    ("shield_break", "破盾击", "攻击", 0, "单个敌人", "获得 1 能量，然后造成 3 伤害；目标有护盾时改为 7", 1, "回能 +1 → 伤害 3 / 7（看结算前有无护盾）", "按伤害结算前判定"),
    ("follow_up", "追击", "攻击", 0, "单个敌人", "获得 1 能量，然后造成 3 伤害；此前使用过攻击牌时改为 6", 2, "回能 +1 → 伤害 3 / 6（看此前已用攻击牌数）", "不把自己算进去"),
    ("block", "格挡", "防御", 0, "自身", "获得 6 护盾", 3, "护盾 +6", ""),
    ("meditate", "调息", "防御", 0, "自身", "获得 2 护盾和 1 能量", 2, "护盾 +2；回能 +1", ""),
    ("energy_blast", "能量冲击", "技能", 3, "单个敌人", "造成 12 伤害", 2, "伤害 12", "技能不计入攻击牌、不回能"),
    ("counter_stance", "攻守转换", "技能", 2, "单个敌人", "造成 5 伤害，然后获得 5 护盾", 1, "伤害 5 → 护盾 +5", "先伤害后给盾"),
    ("tactical_draw", "战术整理", "技能", 2, "无", "抽 2 张牌", 1, "抽 2", "结算中不会被本次洗牌抽回"),
    ("energy_spring", "能量涌泉", "场景", 2, "场景槽", "接下来 3 个玩家回合开始时额外获得 1 能量", 1, "回合开始回能 +1，共 3 次", "打出当回合不回能；满能量照扣次数"),
    ("striker", "突击兵", "随从", 2, "空随从槽", "召唤 3 攻击 / 4 生命随从", 1, "召唤 3/4，无嘲讽", "当回合不能攻击"),
    ("guardian", "守卫", "随从", 3, "空随从槽", "召唤 2 攻击 / 7 生命嘲讽随从", 2, "召唤 2/7，嘲讽", "当回合不能攻击"),
]

# ── 游戏机制：ID / 机制 / 当前规则 / 你的决定 / 实现位置 / 改动代价 / 说明 ──
MECHANICS = [
    ("M01", "回合开始回能", "每个玩家回合开始 +1 能量", "battle_engine._start_player_turn", "改配置表", "上限 10，溢出丢弃"),
    ("M02", "攻击牌回能", "成功使用普通攻击牌 +1，与是否被护盾挡下无关", "battle_engine._resolve_ops", "改配置表", "每张牌一次，不按伤害量"),
    ("M03", "承伤回能", "敌方一次行动造成玩家生命伤害 +1", "battle_engine._damage_player", "改代码", "被护盾全吸不算；随从受伤不算；每次行动最多一次"),
    ("M04", "能量上限与保留", "上限 10，可跨回合保留，不允许为负", "battle_types / _gain_energy", "改配置表", "满能量时仍消耗场景触发次数"),
    ("M05", "每回合抽牌", "玩家回合开始抽 5 张", "battle_engine._start_player_turn", "改配置表", "保留的牌不减少抽牌数"),
    ("M06", "手牌上限", "上限 10；超出的牌仍从牌库移出后进弃牌堆", "battle_engine._draw_cards", "改配置表", "不能让玩家以为没抽到"),
    ("M07", "牌库回收", "牌库空时把弃牌堆洗入牌库继续抽", "battle_engine._draw_cards", "改代码", "两堆都空则停止，无疲劳伤害"),
    ("M08", "玩家护盾清除", "下个玩家回合开始时清除", "battle_engine._start_player_turn", "改代码", "所以格挡只能挡一次敌方阶段"),
    ("M09", "敌方护盾清除", "下个敌方阶段开始时清除", "battle_engine._enemy_phase", "改代码", "与玩家不对称：魔像护盾会撑过玩家一整个回合"),
    ("M10", "保留一张牌", "结束回合时保留 1 张，其余进弃牌堆；可取消", "battle_engine.confirm_end_turn", "改代码", "无手牌时跳过选择"),
    ("M11", "随从自动攻击", "召唤当回合不能攻击；下回合起回合结束自动攻击一次", "battle_engine._resolve_minion_attacks", "改代码", "按槽位从左到右结算"),
    ("M12", "随从槽位", "2 个，填入最左空槽", "battle_engine._summon", "改配置表", "不可手动选择槽位"),
    ("M13", "嘲讽", "敌方单体攻击打最左侧存活嘲讽随从", "battle_state.leftmost_taunt_minion", "改代码", "意图目标实时更新，数值锁定"),
    ("M14", "超额伤害不溢出", "击败随从后的超额伤害不转给玩家", "battle_engine._damage_minion", "改代码", "也不触发玩家承伤回能"),
    ("M15", "场景牌唯一", "场上仅一张；新场景立即替换旧的；到期进弃牌堆", "battle_engine._play_scene", "改代码", ""),
    ("M16", "能量涌泉", "打出当回合不回能；此后 3 个回合开始各 +1；满能量照扣次数", "battle_engine._resolve_scene_turn_start", "改配置表", "第 3 次触发后进弃牌堆"),
    ("M17", "意图锁定与目标", "行动种类与数值公开后锁定；目标每次读取时按嘲讽重算", "battle_engine.get_intent_view", "改代码", "召唤守卫后目标立即改为守卫"),
    ("M18", "终局截断", "任何生命变化后检查；终局停止剩余效果、随从攻击与敌方行动", "battle_engine._check_endgame", "改代码", "进入终局后禁止出牌与结束回合"),
    ("M19", "攻击牌计数", "先快照「此前」数量再自增；技能不计入", "battle_engine.play_card", "改代码", "追击据此决定打 3 还是 6"),
    ("M20", "单体牌需手动确认目标", "即使只有一个敌人，单体牌也必须点击敌人确认", "battle_scene._on_enemy_clicked", "改代码", "避免误操作，不做自动选中"),
]
def head(ws, cols, widths, title):
    ws.sheet_view.showGridLines = False
    ws.cell(row=1, column=1, value=title).font = TITLE
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=max(1, len(cols)))
    ws.row_dimensions[1].height = 26
    for i, h in enumerate(cols, start=1):
        c = ws.cell(row=2, column=i, value=h)
        c.font = HDR_FONT
        c.fill = HDR_FILL
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        c.border = BD
    ws.row_dimensions[2].height = 24
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "A3"


def put(ws, r, vals, decide_cols=(), mono_cols=(), fill_cols=()):
    for i, v in enumerate(vals, start=1):
        c = ws.cell(row=r, column=i, value=v)
        c.font = MONO if i in mono_cols else BODY
        c.alignment = Alignment(vertical="center", wrap_text=True)
        c.border = BD
        if i in decide_cols:
            c.fill = DEC_FILL
        if i in fill_cols and isinstance(v, str) and v.startswith("#"):
            c.fill = PatternFill("solid", fgColor=v.lstrip("#"))
            c.font = MONO


def build():
    wb = Workbook()
    wb.remove(wb.active)

    ws = wb.create_sheet("说明")
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 18
    ws.column_dimensions["B"].width = 96
    ws.cell(row=1, column=1, value="设计元素表 / 使用说明").font = TITLE
    info = [
        ("这张表是什么", "本项目全部设计元素的单一查阅面：窗口 / 色彩 / 卡牌类型色 / 字号 / 布局坐标 / 元素尺寸 / 美术资源 / 设计配图。"),
        ("怎么用", "每张值表都有「当前值」和「你的决定」两列。要改什么，就在「你的决定」里填新值；不想改就留空。"),
        ("助手怎么读", "助手用 tools/read_design_workbook.py 读回本表，只报告「你的决定 与 当前值 不同」的项，因此不必通读全表。"),
        ("底色约定", "黄色底 = 留给你填的列；颜色格会按该色值填充，方便直接看。"),
        ("留空含义", "留空 = 保持当前值，不是删除。要恢复默认就把该格清空。"),
        ("颜色格式", "十六进制，如 #a8442f。"),
        ("尺寸格式", "整数像素。布局的 x/y 相对 1600x900 画布左上角。"),
        ("不在本表的", "规则数值（伤害 / 生命 / 行为循环）属于玩法平衡，见 docs/PVE卡牌Demo_升级方案.xlsx。"),
        ("已接入状态", "「字号」表有一列标出是否已接进代码；未接入的项即使改了也需要先接线。"),
        ("配图", "「设计图」表嵌入 9 张设计配图；「美术资源」表 G 列嵌入 4 张资产缩略图。"),
    ]
    r = 3
    for k, v in info:
        ws.cell(row=r, column=1, value=k).font = BOLD
        ws.cell(row=r, column=1).alignment = Alignment(vertical="top")
        c = ws.cell(row=r, column=2, value=v)
        c.font = BODY
        c.alignment = Alignment(vertical="top", wrap_text=True)
        ws.row_dimensions[r].height = 30
        r += 1

    ws = wb.create_sheet("游戏基本信息")
    head(ws, ["ID", "项目", "当前值", "你的决定", "来源", "说明"],
         [16, 24, 14, 16, 18, 44], "⑨ 游戏基本信息")
    r = 3
    for k, name, val, src, note in GAME:
        put(ws, r, [k, name, val, None, src, note], decide_cols=(4,))
        r += 1

    ws = wb.create_sheet("实体信息")
    head(ws, ["ID", "实体", "属性", "当前值", "你的决定", "实现位置", "说明"],
         [14, 14, 16, 46, 16, 30, 34], "⑩ 实体信息（玩家 / 敌人 / 随从）")
    r = 3
    for k, ent, attr, val, src, note in ENTITIES:
        put(ws, r, [k, ent, attr, val, None, src, note], decide_cols=(5,))
        r += 1

    ws = wb.create_sheet("卡牌信息")
    head(ws, ["ID", "名称", "类型", "费用", "目标", "效果", "数量", "数值明细",
              "决定费用", "决定数量", "决定效果", "备注"],
         [14, 10, 8, 6, 10, 40, 6, 36, 9, 9, 34, 30], "⑪ 卡牌信息（11 种 / 20 张）")
    r = 3
    for k, name, t, cost, target, desc, n, detail, note in CARDS:
        put(ws, r, [k, name, t, cost, target, desc, n, detail, None, None, None, note],
            decide_cols=(9, 10, 11))
        r += 1

    ws = wb.create_sheet("游戏机制")
    head(ws, ["ID", "机制", "当前规则", "你的决定", "实现位置", "改动代价", "说明"],
         [6, 20, 50, 30, 36, 10, 38], "⑫ 游戏机制（当前实现的行为约定）")
    r = 3
    for k, name, rule, src, cost, note in MECHANICS:
        put(ws, r, [k, name, rule, None, src, cost, note], decide_cols=(4,))
        r += 1

    ws = wb.create_sheet("界面")
    head(ws, ["ID", "名称", "当前值", "你的决定", "说明"], [18, 26, 14, 16, 54],
        "① 界面与画布参数（写入 project.godot）")
    r = 3
    for k, name, val, note in WINDOW:
        put(ws, r, [k, name, val, None, note], decide_cols=(4,))
        r += 1

    ws = wb.create_sheet("色彩")
    head(ws, ["ID", "用途", "当前值", "你的决定", "说明"], [18, 24, 16, 16, 50],
        "② 语义色（写入 src/ui/palette.gd）")
    r = 3
    for k, name, val, note in PALETTE:
        put(ws, r, [k, name, val, None, note], decide_cols=(4,), mono_cols=(3,), fill_cols=(3,))
        r += 1

    ws = wb.create_sheet("卡牌类型色")
    head(ws, ["枚举", "类型", "当前值", "你的决定", "说明"], [16, 12, 16, 16, 40],
        "③ 卡牌类型色（写入 palette.gd 的 CARD_COLORS）")
    r = 3
    for k, name, val, note in CARD_TYPES:
        put(ws, r, [k, name, val, None, note], decide_cols=(4,), mono_cols=(3,), fill_cols=(3,))
        r += 1

    ws = wb.create_sheet("字号")
    head(ws, ["ID", "用途", "当前值", "你的决定", "字重", "已接入", "说明"],
        [16, 22, 12, 14, 10, 10, 40], "④ 字号层级")
    r = 3
    for k, name, size, weight, wired, note in FONTS:
        put(ws, r, [k, name, size, None, weight, wired, note], decide_cols=(4,))
        r += 1

    ws = wb.create_sheet("元素尺寸")
    head(ws, ["ID", "元素", "当前宽", "当前高", "决定宽", "决定高", "说明"],
        [16, 22, 12, 12, 12, 12, 42], "⑤ 元素尺寸")
    r = 3
    for k, name, w, h, note in SIZES:
        put(ws, r, [k, name, w, h, None, None, note], decide_cols=(5, 6))
        r += 1

    ws = wb.create_sheet("布局")
    head(ws, ["ID", "区域", "当前 x", "当前 y", "当前 w", "当前 h",
            "决定 x", "决定 y", "决定 w", "决定 h", "说明"],
        [16, 24, 10, 10, 10, 10, 10, 10, 10, 10, 40],
        "⑥ 布局坐标（相对 1600x900 画布；写入 src/ui/design_layout.gd）")
    r = 3
    for k, name, x, y, w, h, note in LAYOUT:
        put(ws, r, [k, name, x, y, w, h, None, None, None, None, note],
            decide_cols=(7, 8, 9, 10))
        r += 1

    ws = wb.create_sheet("美术资源")
    head(ws, ["ID", "路径", "宽", "高", "你的决定（新路径 / 删除）", "说明", "缩略图"],
        [16, 40, 8, 8, 24, 46, 26], "⑦ 美术资源（由 tools/make_art_assets.py 生成）")
    r = 3
    for k, path, w, h, note in ART_ASSETS:
        put(ws, r, [k, path, w, h, None, note, ""], decide_cols=(5,), mono_cols=(2,))
        ws.row_dimensions[r].height = 78
        r += 1
    for i, (fn, desc) in enumerate([("bg_ruins.png", ""), ("vignette.png", ""),
            ("char_adventurer.png", ""), ("char_golem.png", "")]):
        p = os.path.join(ART, fn)
        if os.path.exists(p):
            im = XLImage(p)
            scale = min(1.0, 150.0 / im.width)
            im.width = int(im.width * scale)
            im.height = int(im.height * scale)
            im.anchor = "G%d" % (3 + i)
            ws.add_image(im)

    ws = wb.create_sheet("设计图")
    head(ws, ["配图", "说明", "图片"], [22, 58, 74],
        "⑧ 设计配图（PNG 预览；SVG 可编辑源在同目录）")
    r = 3
    for name, desc in FIGURES:
        c1 = ws.cell(row=r, column=1, value=name + ".png")
        c1.font = MONO
        c1.border = BD
        c2 = ws.cell(row=r, column=2, value=desc)
        c2.font = BODY
        c2.alignment = Alignment(vertical="top", wrap_text=True)
        c2.border = BD
        ws.row_dimensions[r].height = 152
        p = os.path.join(FIG, name + ".png")
        if os.path.exists(p):
            im = XLImage(p)
            scale = min(1.0, 340.0 / im.width)
            im.width = int(im.width * scale)
            im.height = int(im.height * scale)
            im.anchor = "C%d" % r
            ws.add_image(im)
        r += 1

    wb.save(OUT)
    return OUT


if __name__ == "__main__":
    p = build()
    print("saved:", os.path.relpath(p, ROOT))
    print("size :", os.path.getsize(p), "bytes")