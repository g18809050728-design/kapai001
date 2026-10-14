class_name BattleRulesDialog
extends PanelContainer
##
## 规则说明弹窗：把《战斗模块契约》与 rulesets.json 的公开参数写成玩家能读的说明。
##
## 硬约束：只读 ContentDB 的配置数值，不读 BattleState，不解释当前局面。
##

const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

var _built := false
var _label: Label
var _sections: PackedStringArray = PackedStringArray()


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    add_theme_stylebox_override("panel", BattleStyle.card_box(BattleStyle.PANEL, BattleStyle.ACCENT.darkened(0.2), 2))
    custom_minimum_size = Vector2(680, 480)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    var head := HBoxContainer.new()
    var title := BattleStyle.title("战斗规则说明", BattleStyle.FONT_H1)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var close_button := BattleStyle.button("关闭", BattleStyle.TEXT_DIM)
    close_button.pressed.connect(close)
    head.add_child(title)
    head.add_child(close_button)
    root.add_child(head)
    root.add_child(BattleStyle.hline())
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _label = BattleStyle.body_label("", BattleStyle.TEXT)
    _label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_label)
    root.add_child(scroll)
    add_child(root)


## catalog 为 ContentDB；null 时用契约里的默认值兜底。
func render(catalog = null) -> void:
    _build()
    var focus_per_turn := 3
    var focus_cap := 10
    var draw_per_turn := 5
    var unit_slots := 3
    var unit_cost := 1
    var min_ddl := 1
    if catalog != null:
        focus_per_turn = catalog.battle_int("base_focus_per_turn", 3)
        focus_cap = catalog.battle_int("focus_cap", 10)
        draw_per_turn = catalog.battle_int("base_draw_per_turn", 5)
        unit_slots = catalog.battle_int("unit_slots", 3)
        unit_cost = catalog.battle_int("unit_action_vitality_cost", 1)
        min_ddl = catalog.battle_int("minimum_ddl", 1)
    _sections = PackedStringArray([
        _round_flow_text(focus_per_turn, focus_cap, draw_per_turn),
        _resource_text(),
        _choice_text(),
        _unit_text(unit_slots, unit_cost),
        _scene_text(),
        _outcome_text(min_ddl),
        _control_text(),
    ])
    _label.text = "\n".join(_sections)


func section_count() -> int:
    return _sections.size()


func text_content() -> String:
    return _label.text


func _round_flow_text(focus_per_turn: int, focus_cap: int, draw_per_turn: int) -> String:
    return "【回合流程】\n玩家准备（回 %d 专注，上限 %d）→ 抽牌（%d 张）→ 玩家行动 → 合作行动 → 弃牌 → 敌方准备 → 敌方技能 → 敌方压力 → 回合结束，然后进入下一轮。" % [focus_per_turn, focus_cap, draw_per_turn]


func _resource_text() -> String:
    return "【完成量 · 屏障 · 压力】\n完成量先扣任务屏障，再减未完成量，超额不结转。压力先扣放松、再减精力。精力归零即失败；任务全部完成立即胜利。"


func _choice_text() -> String:
    return "【效果内选择】\n有的牌结算到一半需要选牌（例如「寻找思路」抽 2 弃 1）。此时界面会锁定其它操作，必须先确认这次选择；一旦进入选择就不能取消整张牌。"


func _unit_text(unit_slots: int, unit_cost: int) -> String:
    return "【单位与场景】\n合作牌召入单位，槽位 %d 个；槽满时必须先选一个单位换下，取消则不提交、不扣费。合作行动按入场顺序，每个单位每回合最多行动一次，之后自身失去 %d 精力。" % [unit_slots, unit_cost]


func _scene_text() -> String:
    return "【场景与考试】\n场景牌建立场景，替换立即停止旧持续规则，已经恢复的精力不撤销。考试限制会替换特定牌的正文（合作牌变备考面、场景牌变回忆面），界面会在卡面标注。"


func _outcome_text(min_ddl: int) -> String:
    return "【DDL 与胜负】\nDDL 是还能经历的轮末次数，每轮末 -1；DDL 扣到 %d 时若仍有任务未完成即失败。胜利条件：所有任务阶段完成。" % min_ddl


func _control_text() -> String:
    return "【操作】\n点手牌 → 需要目标时点任务或单位 → 界面用引擎的 preview 判定一次，合法即提交；点「取消」撤销当前选择。待选期间只能确认选择。日志区的每一行都来自引擎事件。"


func open() -> void:
    _build()
    visible = true


func close() -> void:
    visible = false


func is_open() -> bool:
    return visible
