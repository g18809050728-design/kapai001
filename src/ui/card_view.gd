extends PanelContainer
## 一张卡牌的视图：显示名称、类型文字、能量费用、完整效果与可用状态（规格 §4.3）。

signal card_clicked(instance_id: int)

const Palette = preload("res://src/ui/palette.gd")
const CardDB = preload("res://src/core/card_db.gd")
const T = preload("res://src/core/battle_types.gd")

const CARD_SIZE := Vector2(148, 208)

var instance_id: int = -1
var def_id: String = ""
var playable: bool = true
var reason: String = ""
var selected: bool = false

var _built := false
var _box: StyleBoxFlat
var _name_label: Label
var _cost_label: Label
var _type_label: Label
var _desc_label: Label
var _hint_label: Label
var _hover_tween: Tween


func setup(p_def_id: String, p_instance_id: int, p_playable: bool = true, p_reason: String = "") -> void:
	def_id = p_def_id
	instance_id = p_instance_id
	playable = p_playable
	reason = p_reason
	if _built:
		_apply()


func _ready() -> void:
	_build()
	_apply()
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _build() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP

	_box = StyleBoxFlat.new()
	_box.set_corner_radius_all(10)
	_box.set_border_width_all(2)
	add_theme_stylebox_override("panel", _box)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 9)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	add_child(margin)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)

	# 标题行：名称 + 费用
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 4)
	col.add_child(head)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 17)
	head.add_child(_name_label)

	var cost_badge := PanelContainer.new()
	cost_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_badge.custom_minimum_size = Vector2(26, 26)
	var cbox := StyleBoxFlat.new()
	cbox.bg_color = Color("#12141a")
	cbox.set_corner_radius_all(13)
	cbox.set_border_width_all(2)
	cbox.border_color = Palette.ENERGY_COLOR
	cost_badge.add_theme_stylebox_override("panel", cbox)
	head.add_child(cost_badge)

	_cost_label = Label.new()
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.add_theme_font_size_override("font_size", 15)
	_cost_label.add_theme_color_override("font_color", Palette.ENERGY_COLOR)
	cost_badge.add_child(_cost_label)

	# 类型文字（避免仅依赖颜色区分）
	_type_label = Label.new()
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type_label.add_theme_font_size_override("font_size", 12)
	col.add_child(_type_label)

	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.22)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sep)

	# 完整效果描述
	_desc_label = Label.new()
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_label.add_theme_font_size_override("font_size", 13)
	col.add_child(_desc_label)

	# 不可用原因（§4.3）
	_hint_label = Label.new()
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Palette.WARN)
	col.add_child(_hint_label)

	_built = true


func _apply() -> void:
	var card := CardDB.get_card(def_id)
	var ctype := int(card.get("type", -1))
	var base := Palette.card_color(ctype)
	if not playable:
		base = base.darkened(0.55)

	_box.bg_color = base
	_box.bg_color.a = 0.97
	if selected:
		_box.border_color = Palette.SELECT
		_box.set_border_width_all(3)
	else:
		_box.border_color = Palette.BORDER
		_box.set_border_width_all(2)

	_name_label.text = String(card.get("name", "?"))
	_cost_label.text = str(int(card.get("cost", 0)))
	_type_label.text = String(T.CARD_TYPE_NAME.get(ctype, ""))
	_desc_label.text = String(card.get("desc", ""))

	if not playable and reason != "":
		_hint_label.text = reason
		_hint_label.visible = true
	else:
		_hint_label.visible = false

	modulate = Color(1, 1, 1, 1.0 if playable else 0.78)


func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	if _built:
		_apply()


func _on_hover(hovering: bool) -> void:
	# 悬停放大，展示完整描述（§4.3）
	z_index = 20 if hovering else 0
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	var target := Vector2(1.14, 1.14) if hovering else Vector2.ONE
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", target, 0.08)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			card_clicked.emit(instance_id)
			accept_event()
