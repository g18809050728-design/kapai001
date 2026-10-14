class_name BattleDeckViewer
extends PanelContainer
##
## 牌堆查看弹窗。
##
## 硬约束（牌堆公平性）：
##   · 抽牌堆只显示数量，绝不显示内容或顺序。引擎的 BattleView 也只给计数，
##     弃牌堆与消耗堆的内容来自 zones_public，界面只做展示。
##   · 本类不洗牌、不读牌堆顺序、不修改任何状态。
##

const BattleLabels := preload("res://src/ui/battle/battle_labels.gd")
const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

var _built := false
var _body: VBoxContainer
var _counts: Dictionary = {}
var _public: Dictionary = {}
var _shown: Dictionary = {}


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    add_theme_stylebox_override("panel", BattleStyle.card_box(BattleStyle.PANEL, BattleStyle.ACCENT.darkened(0.2), 2))
    custom_minimum_size = Vector2(560, 420)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    var head := HBoxContainer.new()
    var title := BattleStyle.title("牌堆", BattleStyle.FONT_H1)
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
    _body = VBoxContainer.new()
    _body.add_theme_constant_override("separation", 6)
    _body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_body)
    root.add_child(scroll)
    add_child(root)


## view 为 BattleEngine.make_view 的结果。
func render(view: Dictionary, catalog = null) -> void:
    _build()
    _counts = view.get("zones", {})
    _public = view.get("zones_public", {})
    if typeof(_public) != TYPE_DICTIONARY:
        _public = {}
    _shown = {}
    for child in _body.get_children():
        _body.remove_child(child)
        child.queue_free()
    _add_section("抽牌堆", int(_counts.get("draw", 0)), "只显示数量：抽牌顺序是隐藏信息，任何界面都不得暴露", [], catalog)
    _add_section("弃牌堆", int(_counts.get("discard", 0)), "", _pile_entries("discard"), catalog)
    _add_section("消耗堆", int(_counts.get("exhaust", 0)), "", _pile_entries("exhaust"), catalog)
    _add_section("手牌", int(_counts.get("hand", 0)), "", [], catalog)
    _add_section("结算区", int(_counts.get("resolving", 0)), "", [], catalog)


func _add_section(title: String, count: int, note: String, entries: Array, catalog) -> void:
    _body.add_child(BattleStyle.title("%s（%d 张）" % [title, count], BattleStyle.FONT_H2, BattleStyle.ACCENT))
    if not note.is_empty():
        _body.add_child(BattleStyle.body_label(note, BattleStyle.WARN, BattleStyle.FONT_SMALL))
    if entries.is_empty():
        if note.is_empty() and count > 0:
            _body.add_child(BattleStyle.body_label("内容未由视图提供", BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL))
        return
    for raw in entries:
        var entry: Dictionary = raw
        _body.add_child(BattleStyle.body_label(_row_text(entry, catalog), BattleStyle.TEXT, BattleStyle.FONT_SMALL))


func _row_text(entry: Dictionary, catalog) -> String:
    var face: Dictionary = entry.get("face", {})
    var text := BattleLabels.name_of(String(face.get("name_key", "")), String(entry.get("definition_id", "")))
    if int(entry.get("upgrade_level", 0)) > 0:
        text = "★ " + text
    var effects := BattleLabels.effect_list_text(face.get("effects", []), catalog)
    if not effects.is_empty():
        text += " · " + effects
    return text


func _pile_entries(pile: String) -> Array:
    var raw: Variant = _public.get(pile, [])
    if typeof(raw) != TYPE_ARRAY:
        return []
    return raw


func open() -> void:
    _build()
    visible = true


func close() -> void:
    visible = false


func is_open() -> bool:
    return visible


func zone_count(pile: String) -> int:
    return int(_counts.get(pile, 0))


## 公开堆的卡面列表（弃牌堆 / 消耗堆）。
func pile_card_ids(pile: String) -> PackedStringArray:
    var out := PackedStringArray()
    for raw in _pile_entries(pile):
        out.append(String((raw as Dictionary).get("card_id", "")))
    return out


## 抽牌堆永远不暴露内容：这个函数是给测试钉死「不暴露抽牌顺序」用的。
func draw_pile_card_ids() -> PackedStringArray:
    return PackedStringArray()


func section_titles() -> PackedStringArray:
    var out := PackedStringArray()
    for child in _body.get_children():
        if child is Label and (child as Label).get_theme_font_size("font_size") == BattleStyle.FONT_H2:
            out.append((child as Label).text)
    return out