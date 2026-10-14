class_name BattleUnitSlot
extends Button
##
## 一个单位槽（只读视图 + 点击）。
##
## 硬约束：数值全部来自 make_view 的 units 元素，不读 BattleState。
## 点击语义由战斗界面决定：普通模式 = 选协作目标，换班模式 = 选被替换的单位。
##

signal chosen(unit_id: String)

const BattleLabels := preload("res://src/ui/battle/battle_labels.gd")
const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

var unit_id := ""
var definition_id := ""
var selected := false
var replace_mode := false

var _built := false
var _name_label: Label
var _stat_label: Label
var _extra_label: Label
var _bar: ProgressBar


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    text = ""
    custom_minimum_size = Vector2(0, 96)
    focus_mode = Control.FOCUS_NONE
    _name_label = BattleStyle.body_label("", BattleStyle.TEXT, BattleStyle.FONT_H2)
    _stat_label = BattleStyle.body_label("", BattleStyle.TEXT, BattleStyle.FONT_SMALL)
    _extra_label = BattleStyle.body_label("", BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL)
    _bar = BattleStyle.progress(0, 1, BattleStyle.OK)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 4)
    content.set_anchors_preset(Control.PRESET_FULL_RECT)
    content.offset_left = 10.0
    content.offset_top = 8.0
    content.offset_right = -10.0
    content.offset_bottom = -8.0
    content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    content.add_child(_name_label)
    content.add_child(_bar)
    content.add_child(_stat_label)
    content.add_child(_extra_label)
    add_child(content)
    pressed.connect(_on_pressed)
    _apply_style()


## entry 为 make_view 的 units 元素；view 用来翻协作目标的任务名。
func setup(entry: Dictionary, view: Dictionary, catalog = null, session = null) -> void:
    _build()
    unit_id = String(entry.get("unit_id", ""))
    definition_id = String(entry.get("definition_id", ""))
    var vitality := int(entry.get("vitality", 0))
    var max_vitality := maxi(1, int(entry.get("max_vitality", 1)))
    _name_label.text = BattleLabels.definition_name(catalog, "unit", definition_id)
    if bool(entry.get("guard", false)):
        _name_label.text += "  [护卫]"
    _bar.max_value = max_vitality
    _bar.value = clampi(vitality, 0, max_vitality)
    _stat_label.text = "精力 %d/%d  ·  协作 %d  ·  放松 %d" % [vitality, max_vitality, int(entry.get("cooperation", 0)), int(entry.get("relax", 0))]
    _extra_label.text = _extra_text(entry, view, session)
    disabled = false
    _apply_style()


func _extra_text(entry: Dictionary, view: Dictionary, session) -> String:
    var parts := PackedStringArray()
    var target_id := String(entry.get("target_id", "")) if entry.get("target_id") != null else ""
    if target_id.is_empty():
        parts.append("协作目标：行动顺序最前")
    else:
        parts.append("协作目标：%s" % _task_name(target_id, view, session))
    parts.append("已行动 %d 次" % int(entry.get("actions_taken", 0)))
    return " · ".join(parts)


func _task_name(task_id: String, view: Dictionary, session) -> String:
    if session != null:
        return session.task_label(task_id)
    for raw in (view.get("tasks", []) as Array):
        if String((raw as Dictionary).get("task_id", "")) == task_id:
            return String((raw as Dictionary).get("definition_id", task_id))
    return task_id


func set_selected(value: bool) -> void:
    selected = value
    _apply_style()


func set_replace_mode(value: bool) -> void:
    replace_mode = value
    _apply_style()


func click() -> void:
    chosen.emit(unit_id)


func _on_pressed() -> void:
    chosen.emit(unit_id)


func _apply_style() -> void:
    var fill := BattleStyle.PANEL_HI
    var border := BattleStyle.COOPERATION_COLOR.darkened(0.4)
    var width := 1
    if selected:
        border = BattleStyle.ACCENT
        width = 3
    elif replace_mode:
        border = BattleStyle.DANGER
        width = 2
    add_theme_stylebox_override("normal", BattleStyle.card_box(fill, border, width))
    add_theme_stylebox_override("hover", BattleStyle.card_box(fill.lightened(0.1), border, width))
    add_theme_stylebox_override("pressed", BattleStyle.card_box(fill, BattleStyle.ACCENT, 3))
    add_theme_stylebox_override("disabled", BattleStyle.card_box(BattleStyle.PANEL.darkened(0.2), BattleStyle.BORDER, 1))