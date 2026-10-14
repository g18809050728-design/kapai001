class_name BattleChoicePanel
extends PanelContainer
##
## 效果内选择面板（例如「寻找思路」抽 2 弃 1）。
##
## 硬约束：
##   · 选项来自 view.pending_choice.candidates（引擎给的），界面不自己凑候选；
##   · 数量校验用 min_count / max_count（引擎给的），界面不做别的规则判断；
##   · 只发 confirmed(selected_ids)，实际的合法性最终仍由 engine.apply 复核。
##

signal confirmed(selected_ids: Array)

const BattleLabels := preload("res://src/ui/battle/battle_labels.gd")
const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

var choice_id := ""
var kind := ""
var min_count := 0
var max_count := 0
var prompt_key := ""
var source_card_id := ""

var _built := false
var _prompt: Label
var _options_row: HBoxContainer
var _hint: Label
var _confirm: Button
var _candidates: Array = []
var _buttons: Dictionary = {}
var _selected := PackedStringArray()


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    add_theme_stylebox_override("panel", BattleStyle.card_box(BattleStyle.PANEL, BattleStyle.WARN, 2))
    custom_minimum_size = Vector2(620, 260)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    _prompt = BattleStyle.title("", BattleStyle.FONT_H1, BattleStyle.WARN)
    _hint = BattleStyle.body_label("", BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL)
    _options_row = HBoxContainer.new()
    _options_row.add_theme_constant_override("separation", 8)
    _confirm = BattleStyle.button("确认", BattleStyle.OK)
    _confirm.pressed.connect(confirm)
    root.add_child(_prompt)
    root.add_child(_hint)
    root.add_child(_options_row)
    root.add_child(BattleStyle.hline())
    root.add_child(_confirm)
    add_child(root)


## choice 为 view.pending_choice（可能为 null）。
func render(choice: Variant, catalog = null) -> void:
    _build()
    if typeof(choice) != TYPE_DICTIONARY:
        visible = false
        _clear_options()
        return
    var request: Dictionary = choice
    choice_id = String(request.get("choice_id", ""))
    kind = String(request.get("kind", ""))
    prompt_key = String(request.get("prompt_key", ""))
    source_card_id = String(request.get("source_card_id", "")) if request.get("source_card_id") != null else ""
    min_count = int(request.get("min_count", 0))
    max_count = int(request.get("max_count", 0))
    _candidates = request.get("candidates", [])
    _selected = PackedStringArray()
    visible = true
    _prompt.text = _prompt_text()
    _clear_options()
    for raw in _candidates:
        var option: Dictionary = raw
        var option_id := String(option.get("id", ""))
        var button := BattleStyle.button(_option_text(option, catalog), BattleStyle.WARN)
        button.custom_minimum_size = Vector2(150, 56)
        button.pressed.connect(_on_option_pressed.bind(option_id))
        _options_row.add_child(button)
        _buttons[option_id] = button
    _refresh()


func _prompt_text() -> String:
    var action := "选择"
    if kind == "discard":
        action = "弃牌"
    if min_count == max_count:
        return "需要选择：%s %d 张" % [action, min_count]
    return "需要选择：%s %d 到 %d 张" % [action, min_count, max_count]


func _option_text(option: Dictionary, catalog) -> String:
    var preview: Dictionary = option.get("preview", {})
    var definition_id := String(preview.get("definition_id", ""))
    var text := BattleLabels.name_of(String(option.get("label_key", "")), definition_id)
    if int(preview.get("upgrade_level", 0)) > 0:
        text = "★ " + text
    return text


func _on_option_pressed(option_id: String) -> void:
    toggle(option_id)


## 选中 / 取消一个候选；超过上限时先挤掉最早选中的一个。
func toggle(option_id: String) -> void:
    if _selected.has(option_id):
        _selected.remove_at(_selected.find(option_id))
    else:
        if max_count > 0 and _selected.size() >= max_count:
            _selected.remove_at(0)
        _selected.append(option_id)
    _refresh()


func reset_selection() -> void:
    _selected = PackedStringArray()
    _refresh()


func selected_ids() -> Array:
    return Array(_selected)


func is_ready() -> bool:
    return _selected.size() >= min_count and _selected.size() <= max_count


func candidate_ids() -> PackedStringArray:
    var out := PackedStringArray()
    for raw in _candidates:
        out.append(String((raw as Dictionary).get("id", "")))
    return out


func is_selected(option_id: String) -> bool:
    return _selected.has(option_id)


func confirm() -> void:
    if not is_ready():
        return
    confirmed.emit(selected_ids())


func _refresh() -> void:
    for option_id in _buttons:
        var button: Button = _buttons[option_id]
        button.add_theme_stylebox_override("normal", BattleStyle.card_box(BattleStyle.PANEL_HI, BattleStyle.ACCENT if _selected.has(option_id) else BattleStyle.BORDER, 3 if _selected.has(option_id) else 1))
    _hint.text = "已选 %d / %d" % [_selected.size(), max_count]
    _confirm.disabled = not is_ready()


func _clear_options() -> void:
    for child in _options_row.get_children():
        _options_row.remove_child(child)
        child.queue_free()
    _buttons = {}