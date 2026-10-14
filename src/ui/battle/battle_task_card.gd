class_name BattleTaskCard
extends Button
##
## 一个任务卡（进度、屏障、公开意图）。
##
## 硬约束：所有数字来自 make_view 的 tasks 元素；界面不自己算完成量或压力。
##

signal chosen(task_id: String)

const BattleLabels := preload("res://src/ui/battle/battle_labels.gd")
const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

var task_id := ""
var definition_id := ""
var phase_key := ""
var work_remaining := 0
var work_max := 0
var shield := 0
var eligible_round := 0
var intent: Dictionary = {}
var selected := false
var selectable := false

var _built := false
var _name_label: Label
var _bar: ProgressBar
var _work_label: Label
var _intent_label: Label
var _extra_label: Label


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    text = ""
    custom_minimum_size = Vector2(300, 158)
    focus_mode = Control.FOCUS_NONE
    _name_label = BattleStyle.body_label("", BattleStyle.TEXT, BattleStyle.FONT_H2)
    _bar = BattleStyle.progress(0, 1, BattleStyle.WORK_COLOR)
    _work_label = BattleStyle.body_label("", BattleStyle.WORK_COLOR)
    _intent_label = BattleStyle.body_label("", BattleStyle.WARN)
    _extra_label = BattleStyle.body_label("", BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 5)
    content.set_anchors_preset(Control.PRESET_FULL_RECT)
    content.offset_left = 12.0
    content.offset_top = 10.0
    content.offset_right = -12.0
    content.offset_bottom = -10.0
    content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    content.add_child(_name_label)
    content.add_child(_bar)
    content.add_child(_work_label)
    content.add_child(_intent_label)
    content.add_child(_extra_label)
    add_child(content)
    pressed.connect(_on_pressed)
    _apply_style()


## entry 为 make_view 的 tasks 元素；round_index 用于标记未就绪的新任务。
func setup(entry: Dictionary, round_index: int, catalog = null) -> void:
    _build()
    task_id = String(entry.get("task_id", ""))
    definition_id = String(entry.get("definition_id", ""))
    phase_key = String(entry.get("phase_key", ""))
    work_remaining = int(entry.get("work_remaining", 0))
    work_max = maxi(1, int(entry.get("work_max", 1)))
    shield = int(entry.get("shield", 0))
    eligible_round = int(entry.get("eligible_round", 0))
    intent = entry.get("intent", {}) if entry.get("intent") != null else {}
    var title := BattleLabels.definition_name(catalog, "task", definition_id)
    if not phase_key.is_empty():
        title += "  [阶段 %s]" % phase_key
    _name_label.text = title
    _bar.max_value = work_max
    _bar.value = clampi(work_max - work_remaining, 0, work_max)
    _work_label.text = "剩余 %d / %d" % [work_remaining, work_max]
    _intent_label.text = _intent_text()
    _extra_label.text = _extra_text(round_index)
    disabled = work_remaining <= 0
    _apply_style()


## 意图：引擎给的就是 {index, pressure 或 shield, text_key}，界面只翻译不改写。
func _intent_text() -> String:
    if intent.is_empty():
        return "当前意图：无"
    var index := int(intent.get("index", 0))
    if intent.has("pressure"):
        return "当前意图 #%d：压力 %d" % [index, int(intent.get("pressure", 0))]
    if intent.has("shield"):
        return "当前意图 #%d：屏障 +%d" % [index, int(intent.get("shield", 0))]
    return "当前意图 #%d" % index


func _extra_text(round_index: int) -> String:
    var parts := PackedStringArray()
    if shield > 0:
        parts.append("屏障 %d" % shield)
    if eligible_round > round_index:
        parts.append("第 %d 轮才可行动" % eligible_round)
    return " · ".join(parts)


func set_selectable(value: bool) -> void:
    selectable = value
    _apply_style()


func set_selected(value: bool) -> void:
    selected = value
    _apply_style()


func click() -> void:
    if not selectable:
        return
    chosen.emit(task_id)


func _on_pressed() -> void:
    if selectable:
        chosen.emit(task_id)


func _apply_style() -> void:
    var fill := BattleStyle.PANEL_HI
    var border := BattleStyle.WORK_COLOR.darkened(0.45)
    var width := 2
    if selected:
        border = BattleStyle.ACCENT
        width = 3
    elif selectable:
        border = BattleStyle.ACCENT.darkened(0.15)
        width = 2
    add_theme_stylebox_override("normal", BattleStyle.card_box(fill, border, width))
    add_theme_stylebox_override("hover", BattleStyle.card_box(fill.lightened(0.1), BattleStyle.ACCENT, width))
    add_theme_stylebox_override("pressed", BattleStyle.card_box(fill, BattleStyle.ACCENT, 3))
    add_theme_stylebox_override("disabled", BattleStyle.card_box(BattleStyle.PANEL.darkened(0.2), BattleStyle.BORDER, 1))