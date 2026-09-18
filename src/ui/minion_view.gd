extends PanelContainer
## 随从槽位。对应规格 §4.2：攻击、生命、自动攻击就绪状态、嘲讽标记。
## 新体系增加（设计元素表 M35 / M33）：仆从独立护盾、场上监听说明、作为指令目标时可点击。
##
## 视觉：暖色石台。空槽位是一块压暗的石板，占位后换成苔绿色的随从牌面。
## 状态一律用文字表达，不只靠颜色。

signal minion_clicked(slot: int)

const Palette = preload("res://src/ui/palette.gd")
const T = preload("res://src/core/battle_types.gd")

var slot: int = 0
## 是否允许点击（选中「指令 / 短令」后为 true）
var selectable: bool = false
var selected: bool = false

var _built := false
var _name_label: Label
var _stat_label: Label
var _shield_label: Label
var _state_label: Label
var _taunt_label: Label
var _monitor_label: Label
var _box: StyleBoxFlat


func _ready() -> void:
        _build()
        show_minion({}, "", "")


func _build() -> void:
        custom_minimum_size = Vector2(130, 146)
        _box = Palette.box(Palette.PANEL, 10, 1, Palette.BORDER)
        add_theme_stylebox_override("panel", _box)
        mouse_filter = Control.MOUSE_FILTER_IGNORE

        var margin := MarginContainer.new()
        margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
        for side in ["left", "right"]:
                margin.add_theme_constant_override("margin_" + side, 9)
        for side in ["top", "bottom"]:
                margin.add_theme_constant_override("margin_" + side, 8)
        add_child(margin)

        var col := VBoxContainer.new()
        col.mouse_filter = Control.MOUSE_FILTER_IGNORE
        col.add_theme_constant_override("separation", 2)
        margin.add_child(col)

        _name_label = Label.new()
        _name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _name_label.add_theme_font_size_override("font_size", 15)
        col.add_child(_name_label)

        var sep := ColorRect.new()
        sep.color = Color(1, 1, 1, 0.08)
        sep.custom_minimum_size = Vector2(0, 1)
        sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
        col.add_child(sep)

        _stat_label = Label.new()
        _stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _stat_label.add_theme_font_size_override("font_size", 13)
        col.add_child(_stat_label)

        _shield_label = Label.new()
        _shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _shield_label.add_theme_font_size_override("font_size", 12)
        _shield_label.add_theme_color_override("font_color", Palette.SHIELD)
        col.add_child(_shield_label)

        _taunt_label = Label.new()
        _taunt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _taunt_label.add_theme_font_size_override("font_size", 12)
        _taunt_label.add_theme_color_override("font_color", Palette.TAUNT)
        col.add_child(_taunt_label)

        _monitor_label = Label.new()
        _monitor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _monitor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _monitor_label.add_theme_font_size_override("font_size", 10)
        _monitor_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
        col.add_child(_monitor_label)

        _state_label = Label.new()
        _state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _state_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _state_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
        _state_label.add_theme_font_size_override("font_size", 12)
        col.add_child(_state_label)

        _built = true


## minion 为空字典表示空槽位。
func show_minion(minion: Dictionary, def_id: String, card_name: String,
                monitor_desc: String = "") -> void:
        if not _built:
                _build()
        mouse_filter = Control.MOUSE_FILTER_STOP if selectable else Control.MOUSE_FILTER_IGNORE
        _apply_border()

        if minion.is_empty():
                _box.bg_color = Palette.PANEL.darkened(0.30)
                _box.bg_color.a = 0.72
                _name_label.text = "空槽位 %d" % (slot + 1)
                _name_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
                _stat_label.text = ""
                _shield_label.text = ""
                _taunt_label.text = ""
                _monitor_label.text = ""
                _state_label.text = "可召唤随从牌"
                _state_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
                return

        var hp := int(minion.get("hp", 0))
        var dead := hp <= 0
        if dead:
                _box.bg_color = Palette.PANEL.darkened(0.45)
                _box.bg_color.a = 0.7
                _name_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
        else:
                var base := Palette.card_color(T.CardType.MINION)
                _box.bg_color = base.darkened(0.34)
                _box.bg_color.a = 0.94
                _name_label.add_theme_color_override("font_color", Palette.TEXT)

        _name_label.text = card_name
        _stat_label.text = "%d 攻击 / %d 生命" % [int(minion.get("attack", 0)), hp]
        _stat_label.add_theme_color_override("font_color", Palette.TEXT)
        var shield := int(minion.get("shield", 0))
        _shield_label.text = ("护盾 %d（下个玩家回合清除）" % shield) if shield > 0 else ""
        _taunt_label.text = "嘲讽" if bool(minion.get("taunt", false)) else ""
        _monitor_label.text = monitor_desc

        if dead:
                _state_label.text = "已死亡"
                _state_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
        elif bool(minion.get("can_attack", false)):
                _state_label.text = "已就绪：回合结束自动攻击"
                _state_label.add_theme_color_override("font_color", Palette.GOOD)
        else:
                _state_label.text = "准备中（本回合不攻击）"
                _state_label.add_theme_color_override("font_color", Palette.WARN)


func set_selected(v: bool) -> void:
        if selected == v:
                return
        selected = v
        _apply_border()


func _apply_border() -> void:
        if _box == null:
                return
        if selected:
                _box.border_color = Palette.SELECT
                _box.set_border_width_all(3)
        else:
                _box.border_color = Palette.BORDER
                _box.set_border_width_all(1)


func _gui_input(event: InputEvent) -> void:
        if not selectable:
                return
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
                        minion_clicked.emit(slot)
                        accept_event()