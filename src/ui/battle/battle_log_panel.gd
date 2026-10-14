class_name BattleLogPanel
extends PanelContainer
##
## 结算日志面板：只显示 BattleSession 已经翻译好的日志行。
##
## 硬约束：不读规则状态；render 只替换文本，不做任何结算判断。
##

const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

const MAX_ROWS := 400

var _built := false
var _title: Label
var _toggle: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _expanded := true


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    add_theme_stylebox_override("panel", BattleStyle.panel_box())
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 4)
    var head := HBoxContainer.new()
    _title = BattleStyle.title("结算日志", BattleStyle.FONT_H2)
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _toggle = BattleStyle.button("收起", BattleStyle.TEXT_DIM)
    _toggle.custom_minimum_size = Vector2(72, 0)
    _toggle.pressed.connect(_on_toggle)
    head.add_child(_title)
    head.add_child(_toggle)
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _list = VBoxContainer.new()
    _list.add_theme_constant_override("separation", 2)
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.add_child(_list)
    root.add_child(head)
    root.add_child(BattleStyle.hline())
    root.add_child(_scroll)
    add_child(root)
    custom_minimum_size = Vector2(0, 150)


## entries 为 BattleSession.log_entries() 的结果。
func render(entries: Array) -> void:
    _build()
    for child in _list.get_children():
        child.queue_free()
        _list.remove_child(child)
    var shown: Array = entries
    if shown.size() > MAX_ROWS:
        shown = shown.slice(shown.size() - MAX_ROWS)
    for raw in shown:
        var entry: Dictionary = raw
        var label := BattleStyle.body_label(String(entry.get("text", "")), _tone(String(entry.get("kind", ""))), BattleStyle.FONT_SMALL)
        _list.add_child(label)
    if _scroll != null:
        _scroll.scroll_vertical = 1 << 30


func _tone(kind: String) -> Color:
    match kind:
        "play":
            return BattleStyle.ACCENT
        "gain":
            return BattleStyle.OK
        "loss":
            return BattleStyle.DANGER
        "choice":
            return BattleStyle.WARN
        "system":
            return BattleStyle.TEXT_DIM
    return BattleStyle.TEXT


func line_texts() -> PackedStringArray:
    var out := PackedStringArray()
    for child in _list.get_children():
        if child is Label:
            out.append((child as Label).text)
    return out


func line_count() -> int:
    return _list.get_child_count()


func latest_text() -> String:
    var count := _list.get_child_count()
    if count == 0:
        return ""
    return (_list.get_child(count - 1) as Label).text


func is_expanded() -> bool:
    return _expanded


func set_expanded(value: bool) -> void:
    _build()
    _expanded = value
    _scroll.visible = value
    _toggle.text = "收起" if value else "展开"


func _on_toggle() -> void:
    set_expanded(not _expanded)