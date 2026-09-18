extends Control
## 羊皮纸卡面。对应规格 §4.3：名称 / 类型文字 / 能量费用 / 完整效果 / 可用状态，
## 并按新体系（设计元素表「点数与融牌规则」§11 界面要求）增加：
##   · 点数徽章与类型行的「N 点」标注（费用与点数使用不同标记，避免混淆）
##   · 三类相邻链的本牌强化摘要（倍数 / 因数 / 同点）
##   · 临时衍生牌标记（M31：不可融、不可保留）
##
## 设计：纸色卡面 + 类型色卡头 + 墨色正文。

signal card_clicked(instance_id: int)

const Palette = preload("res://src/ui/palette.gd")
const CardDB = preload("res://src/core/card_db.gd")
const T = preload("res://src/core/battle_types.gd")

const CARD_SIZE := Vector2(148, 208)
const HEADER_H := 44.0
const PAD := 10.0

var instance_id: int = -1
var def_id: String = ""
var playable: bool = true
var reason: String = ""
var selected: bool = false
## 有效点数（含本回合临时修正，R18）
var points: int = -1
## 临时点数修正量（0 表示未修正）
var point_delta: int = 0
var temp: bool = false
## 本次出牌会命中的关系提示，例如「倍数第 2 层」
var chain_hint: String = ""

var _built := false
var _bg: Panel
var _header: Panel
var _header_line: ColorRect
var _name_label: Label
var _cost_badge: Panel
var _cost_label: Label
var _points_badge: Panel
var _points_label: Label
var _type_label: Label
var _temp_label: Label
var _chain_label: Label
var _desc_label: Label
var _hint_label: Label
var _hover_tween: Tween


func setup(p_def_id: String, p_instance_id: int, p_playable: bool = true, p_reason: String = "",
                p_points: int = -1, p_chain_hint: String = "", p_temp: bool = false,
                p_point_delta: int = 0) -> void:
        def_id = p_def_id
        instance_id = p_instance_id
        playable = p_playable
        reason = p_reason
        points = p_points
        chain_hint = p_chain_hint
        temp = p_temp
        point_delta = p_point_delta
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

        _bg = Panel.new()
        _bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        _bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(_bg)

        _header = Panel.new()
        _header.position = Vector2.ZERO
        _header.size = Vector2(CARD_SIZE.x, HEADER_H)
        _header.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(_header)

        _header_line = ColorRect.new()
        _header_line.position = Vector2(0, HEADER_H - 2)
        _header_line.size = Vector2(CARD_SIZE.x, 2)
        _header_line.color = Color(0, 0, 0, 0.22)
        _header_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(_header_line)

        # 点数徽章（方形，左上）——与费用徽章（圆形，右上）形状与位置都不同
        _points_badge = Panel.new()
        _points_badge.position = Vector2(8, 9)
        _points_badge.size = Vector2(30, 26)
        _points_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var pbox := StyleBoxFlat.new()
        pbox.bg_color = Color(0.16, 0.14, 0.12, 0.94)
        pbox.set_corner_radius_all(5)
        pbox.set_border_width_all(2)
        pbox.border_color = Palette.SELECT
        _points_badge.add_theme_stylebox_override("panel", pbox)
        add_child(_points_badge)

        _points_label = Label.new()
        _points_label.set_anchors_preset(Control.PRESET_FULL_RECT)
        _points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _points_label.add_theme_font_size_override("font_size", 13)
        _points_label.add_theme_color_override("font_color", Palette.SELECT)
        _points_badge.add_child(_points_label)

        _name_label = Label.new()
        _name_label.position = Vector2(44, 10)
        _name_label.size = Vector2(CARD_SIZE.x - 44 - 40, 24)
        _name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _name_label.add_theme_font_size_override("font_size", 17)
        _name_label.add_theme_color_override("font_color", Palette.TEXT)
        add_child(_name_label)

        _cost_badge = Panel.new()
        _cost_badge.position = Vector2(CARD_SIZE.x - 34, 9)
        _cost_badge.size = Vector2(26, 26)
        _cost_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var cbox := StyleBoxFlat.new()
        cbox.bg_color = Color(0.09, 0.07, 0.05, 0.92)
        cbox.set_corner_radius_all(13)
        cbox.set_border_width_all(2)
        cbox.border_color = Palette.GOLD
        _cost_badge.add_theme_stylebox_override("panel", cbox)
        add_child(_cost_badge)

        _cost_label = Label.new()
        _cost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
        _cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _cost_label.add_theme_font_size_override("font_size", 15)
        _cost_label.add_theme_color_override("font_color", Palette.ENERGY)
        _cost_badge.add_child(_cost_label)

        _type_label = Label.new()
        _type_label.position = Vector2(PAD, HEADER_H + 2)
        _type_label.size = Vector2(CARD_SIZE.x - PAD * 2 - 34, 16)
        _type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _type_label.add_theme_font_size_override("font_size", 12)
        _type_label.add_theme_color_override("font_color", Palette.TEXT_INK_DIM)
        add_child(_type_label)

        _temp_label = Label.new()
        _temp_label.position = Vector2(CARD_SIZE.x - PAD - 32, HEADER_H + 2)
        _temp_label.size = Vector2(32, 16)
        _temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        _temp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _temp_label.add_theme_font_size_override("font_size", 11)
        _temp_label.add_theme_color_override("font_color", Palette.WARN)
        add_child(_temp_label)

        _chain_label = Label.new()
        _chain_label.position = Vector2(PAD, HEADER_H + 19)
        _chain_label.size = Vector2(CARD_SIZE.x - PAD * 2, 30)
        _chain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _chain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _chain_label.add_theme_font_size_override("font_size", 11)
        _chain_label.add_theme_color_override("font_color", Color("#5f6b4a"))
        add_child(_chain_label)

        _desc_label = Label.new()
        _desc_label.position = Vector2(PAD, HEADER_H + 50)
        _desc_label.size = Vector2(CARD_SIZE.x - PAD * 2, 78)
        _desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
        _desc_label.add_theme_font_size_override("font_size", 12)
        _desc_label.add_theme_color_override("font_color", Palette.TEXT_INK)
        add_child(_desc_label)

        _hint_label = Label.new()
        _hint_label.position = Vector2(PAD, 168)
        _hint_label.size = Vector2(CARD_SIZE.x - PAD * 2, 32)
        _hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _hint_label.add_theme_font_size_override("font_size", 12)
        _hint_label.add_theme_color_override("font_color", Palette.WARN)
        add_child(_hint_label)

        _built = true


func _apply() -> void:
        var card := CardDB.get_card(def_id)
        var ctype := int(card.get("type", -1))
        var tcol := Palette.card_color(ctype)

        _bg.add_theme_stylebox_override("panel", Palette.paper_box(tcol, 10, 3 if selected else 2))

        var hb := StyleBoxFlat.new()
        hb.bg_color = tcol
        hb.corner_radius_top_left = 9
        hb.corner_radius_top_right = 9
        hb.corner_radius_bottom_left = 0
        hb.corner_radius_bottom_right = 0
        _header.add_theme_stylebox_override("panel", hb)

        _name_label.text = String(card.get("name", "?"))
        _cost_label.text = str(int(card.get("cost", 0)))
        var p := points if points > 0 else CardDB.card_points(def_id)
        _points_label.text = str(p)
        _type_label.text = "%s · %d 点%s" % [
                String(T.CARD_TYPE_NAME.get(ctype, "")), p,
                ("  (%+d)" % point_delta) if point_delta != 0 else "",
        ]
        _temp_label.text = "临时" if temp else ""
        _desc_label.text = String(card.get("desc", ""))

        # 关系提示：优先显示本次会命中的链，否则显示本牌的三类强化摘要
        if chain_hint != "":
                _chain_label.text = chain_hint
                _chain_label.add_theme_color_override("font_color", Color("#8a5a20"))
        else:
                _chain_label.text = CardDB.chain_summary(def_id)
                _chain_label.add_theme_color_override("font_color", Color("#5f6b4a"))

        if not playable and reason != "":
                _hint_label.text = reason
                _hint_label.visible = true
        else:
                _hint_label.visible = false

        modulate = Color(1, 1, 1, 1.0) if playable else Color(0.70, 0.67, 0.62, 1.0)


func set_selected(v: bool) -> void:
        if selected == v:
                return
        selected = v
        if _built:
                _apply()


func _on_hover(hovering: bool) -> void:
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