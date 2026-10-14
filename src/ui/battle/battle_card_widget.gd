class_name BattleCardWidget
extends Button
##
## 手牌卡面（只读视图 + 点击）。
##
## 硬约束：只根据 make_view 给的 hand 元素渲染；不读 BattleState，
## 不计算费用或完成量（费用用 effective_cost，数值用 face，均为引擎已算好的值）。
##

signal chosen(card_id: String)

const BattleLabels := preload("res://src/ui/battle/battle_labels.gd")
const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

var card_id := ""
var definition_id := ""
var playable := false
var upgrade_level := 0
var effective_vitality_cost := 0
var selected := false

var _built := false
var _content: VBoxContainer
var _cost_label: Label
var _vitality_label: Label
var _name_label: Label
var _meta_label: Label
var _effect_label: Label
var _tail_label: Label
var _type_color := BattleStyle.TEXT_DIM


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    text = ""
    custom_minimum_size = Vector2(164, 178)
    clip_text = true
    focus_mode = Control.FOCUS_NONE
    add_theme_font_size_override("font_size", BattleStyle.FONT_BODY)
    _cost_label = BattleStyle.title("0", BattleStyle.FONT_H1, BattleStyle.COST)
    _vitality_label = BattleStyle.body_label("", BattleStyle.DANGER, BattleStyle.FONT_SMALL)
    _vitality_label.visible = false
    _name_label = BattleStyle.body_label("", BattleStyle.TEXT, BattleStyle.FONT_H2)
    _meta_label = BattleStyle.body_label("", BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL)
    _effect_label = BattleStyle.body_label("", BattleStyle.TEXT)
    _tail_label = BattleStyle.body_label("", BattleStyle.WARN, BattleStyle.FONT_SMALL)
    _content = VBoxContainer.new()
    _content.add_theme_constant_override("separation", 3)
    _content.set_anchors_preset(Control.PRESET_FULL_RECT)
    _content.offset_left = 10.0
    _content.offset_top = 8.0
    _content.offset_right = -10.0
    _content.offset_bottom = -8.0
    _content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var cost_row := HBoxContainer.new()
    cost_row.add_theme_constant_override("separation", 8)
    cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    cost_row.add_child(_cost_label)
    cost_row.add_child(_vitality_label)
    _content.add_child(cost_row)
    _content.add_child(_name_label)
    _content.add_child(_meta_label)
    _content.add_child(_effect_label)
    _content.add_child(BattleStyle.spacer(Vector2(0, 0), false))
    _content.add_child(_tail_label)
    add_child(_content)
    pressed.connect(_on_pressed)
    _apply_style()


## entry 为 make_view 的 hand 元素（或 zones_public 里的同构卡面）。
func setup(entry: Dictionary, catalog = null) -> void:
    _build()
    card_id = String(entry.get("card_id", ""))
    definition_id = String(entry.get("definition_id", ""))
    upgrade_level = int(entry.get("upgrade_level", 0))
    playable = bool(entry.get("playable", false))
    var face: Dictionary = entry.get("face", {})
    var card_type := String(face.get("type", ""))
    _type_color = BattleStyle.card_type_color(card_type)
    _cost_label.text = str(int(entry.get("effective_cost", 0)))
    _cost_label.add_theme_color_override("font_color", BattleStyle.COST if playable else BattleStyle.TEXT_DIM)
    effective_vitality_cost = int(entry.get("effective_vitality_cost", 0))
    _vitality_label.text = "精力 %d" % effective_vitality_cost
    _vitality_label.visible = effective_vitality_cost > 0
    var display_name := BattleLabels.name_of(String(face.get("name_key", "")), definition_id)
    if upgrade_level > 0:
        display_name += "  ★"
    _name_label.text = display_name
    var rarity := String(face.get("rarity", "")) if face.get("rarity") != null else ""
    _meta_label.text = "%s · %s" % [BattleLabels.card_type_name(card_type), BattleLabels.rarity_name(rarity)]
    _meta_label.add_theme_color_override("font_color", _type_color)
    _effect_label.text = BattleLabels.effect_list_text(face.get("effects", []), catalog)
    _tail_label.text = _tail_text(face)
    tooltip_text = _tooltip_text(display_name, entry, face, catalog)
    disabled = not playable
    _apply_style()


func _tail_text(face: Dictionary) -> String:
    var parts := PackedStringArray()
    if not String(face.get("exam_face", "")).is_empty():
        parts.append("考试替代面")
    if bool(face.get("exhaust", false)):
        parts.append("耗尽")
    var limit := BattleLabels.limit_text(face.get("limit"))
    if not limit.is_empty():
        parts.append(limit)
    if not String(face.get("target", "")).is_empty():
        parts.append("目标：" + _target_name(String(face.get("target", ""))))
    return " · ".join(parts)


func _target_name(target: String) -> String:
    match target:
        "self":
            return "自身"
        "task":
            return "任务"
        "unit":
            return "单位"
    return target


func set_selected(value: bool) -> void:
    selected = value
    _apply_style()


## 供测试与键盘路径使用的确定性点击。
func click() -> void:
    if disabled:
        return
    chosen.emit(card_id)


func _on_pressed() -> void:
    chosen.emit(card_id)


func _apply_style() -> void:
    var fill := BattleStyle.PANEL_HI
    var border := _type_color.darkened(0.35)
    var width := 2
    if selected:
        border = BattleStyle.ACCENT
        fill = BattleStyle.PANEL_HI.lightened(0.08)
        width = 3
    if not playable:
        fill = BattleStyle.PANEL.darkened(0.15)
        border = BattleStyle.BORDER
        width = 1
    add_theme_stylebox_override("normal", BattleStyle.card_box(fill, border))
    add_theme_stylebox_override("hover", BattleStyle.card_box(fill.lightened(0.1), border))
    add_theme_stylebox_override("pressed", BattleStyle.card_box(fill, BattleStyle.ACCENT, ))
    add_theme_stylebox_override("disabled", BattleStyle.card_box(fill, border))



# 供冒烟测试断言「卡面读数 = 视图字段」

func cost_text() -> String:
    return _cost_label.text


func name_text() -> String:
    return _name_label.text


func meta_text() -> String:
    return _meta_label.text


func effects_text() -> String:
    return _effect_label.text


func tail_text() -> String:
    return _tail_label.text


func is_playable() -> bool:
    return playable



## 精力代价（K10 一类主动支付精力的牌）在卡面上单列，避免跟专注混淆。
func _tooltip_text(display_name: String, entry: Dictionary, face: Dictionary, catalog) -> String:
    var lines := PackedStringArray()
    lines.append("%s（%s）" % [display_name, BattleLabels.card_type_name(String(face.get("type", "")))])
    var cost_line := "专注 %d" % int(entry.get("effective_cost", 0))
    if effective_vitality_cost > 0:
        cost_line += "  ·  精力 %d（主动支付，绕过放松）" % effective_vitality_cost
    lines.append(cost_line)
    lines.append(BattleLabels.effect_list_text(face.get("effects", []), catalog))
    var tail := _tail_text(face)
    if not tail.is_empty():
        lines.append(tail)
    return "\n".join(lines)


func vitality_cost_text() -> String:
    if not _built:
        return ""
    return _vitality_label.text