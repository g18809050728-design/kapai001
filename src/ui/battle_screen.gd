class_name BattleScreen
extends Control
##
## 战斗画面（src/ui 战斗相关页面的唯一入口，ui-shell 从这里接管战斗）。
##
## 硬约束（《初步架构设计》§2 与战斗模块契约 §11）：
##   · 只做两件事：render(视图) 与 build_action()；
##   · 不直接改精力 / 牌堆 / 金币 / 触发次数——所有写操作都经 BattleEngine.apply；
##   · pending_choice 期间锁定其它操作，build_action 只接受 confirm_choice；
##   · 动画异步播放事件，关闭或加速动画不改变任何结算结果。
##
## 对外契约：
##   start_battle(battle_input) -> Result，battle_input 就是 RunService 的 battle_input；
##   signal battle_finished(outcome) 打出 BattleOutcome；
##   current_state() / current_rng_state() 供上层存档。
##

signal battle_finished(outcome: Dictionary)
signal action_applied(step: Dictionary)
signal view_updated(view: Dictionary)

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const BattleSessionScript := preload("res://src/ui/battle/battle_session.gd")
const AnimatorScript := preload("res://src/ui/battle/battle_event_animator.gd")
const CardWidgetScript := preload("res://src/ui/battle/battle_card_widget.gd")
const UnitSlotScript := preload("res://src/ui/battle/battle_unit_slot.gd")
const TaskCardScript := preload("res://src/ui/battle/battle_task_card.gd")
const LogPanelScript := preload("res://src/ui/battle/battle_log_panel.gd")
const DeckViewerScript := preload("res://src/ui/battle/battle_deck_viewer.gd")
const RulesDialogScript := preload("res://src/ui/battle/battle_rules_dialog.gd")
const ChoicePanelScript := preload("res://src/ui/battle/battle_choice_panel.gd")
const BattleLabels := preload("res://src/ui/battle/battle_labels.gd")
const BattleStyle := preload("res://src/ui/battle/battle_style.gd")

const MODE_NONE := ""
const MODE_CARD_TARGET := "card_target"
const MODE_REPLACE_UNIT := "replace_unit"
const MODE_ALLY_TARGET := "ally_target"

## 目录清单：默认跟出厂局流程一致（mvp），失败时按 MANIFEST_FALLBACKS 依次回落。
## 不能用 battle_mvp 当默认：它冻结在 12 张牌的旧切片，mvp 清单里的 K05/K10 等牌会让 begin 报 unknown_card。
var manifest_id := GameConstants.MANIFEST_MVP
var session = null
var animator = null

var _view: Dictionary = {}
var _mode := MODE_NONE
var _selected_card_id := ""
var _selected_targets: Array = []
var _replace_unit_id := ""
var _selected_unit_id := ""
var _retained: Array = []
var _submitted_actions: Array = []
var _start_result: Dictionary = {}
var _hint_override := ""
var _engine = null
var _catalog_error := ""

var _root: VBoxContainer
var _encounter_label: Label
var _round_label: Label
var _ddl_label: Label
var _phase_label: Label
var _pulse_label: Label
var _anim_button: Button
var _deck_button: Button
var _rules_button: Button
var _player_bar: ProgressBar
var _player_text: Label
var _focus_label: Label
var _status_row: HBoxContainer
var _relic_label: Label
var _exam_label: Label
var _scene_label: Label
var _task_row: HBoxContainer
var _unit_col: VBoxContainer
var _hand_row: HBoxContainer
var _hint_label: Label
var _cancel_button: Button
var _action_focus: Label
var _end_turn_button: Button
var _log_panel
var _deck_viewer
var _rules_dialog
var _choice_panel
var _overlay: Control
var _built := false


func _ready() -> void:
    _build()


func _build() -> void:
    if _built:
        return
    _built = true
    set_anchors_preset(Control.PRESET_FULL_RECT)
    var bg := ColorRect.new()
    bg.color = BattleStyle.BG
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)
    _root = VBoxContainer.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.offset_left = 14.0
    _root.offset_top = 12.0
    _root.offset_right = -14.0
    _root.offset_bottom = -12.0
    _root.add_theme_constant_override("separation", 8)
    add_child(_root)
    _root.add_child(_build_topbar())
    _root.add_child(_build_pulse_row())
    _root.add_child(BattleStyle.hline())
    var mid := HBoxContainer.new()
    mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    mid.add_theme_constant_override("separation", 12)
    mid.add_child(_build_left())
    mid.add_child(_build_center())
    mid.add_child(_build_right())
    _root.add_child(mid)
    _root.add_child(_build_hint_row())
    _hand_row = HBoxContainer.new()
    _hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
    _hand_row.add_theme_constant_override("separation", 8)
    _hand_row.custom_minimum_size = Vector2(0, 186)
    _root.add_child(_hand_row)
    _root.add_child(_build_action_row())
    _log_panel = LogPanelScript.new()
    _root.add_child(_log_panel)
    _build_overlay()
    animator = AnimatorScript.new()
    animator.name = "EventAnimator"
    add_child(animator)


func _build_topbar() -> Control:
    var bar := HBoxContainer.new()
    bar.add_theme_constant_override("separation", 14)
    _encounter_label = BattleStyle.title("遭遇", BattleStyle.FONT_H1)
    _round_label = BattleStyle.title("第 1 轮", BattleStyle.FONT_H1, BattleStyle.ACCENT)
    _ddl_label = BattleStyle.title("DDL 0", BattleStyle.FONT_H1, BattleStyle.DANGER)
    _phase_label = BattleStyle.body_label("", BattleStyle.TEXT_DIM)
    _anim_button = BattleStyle.button("动画：开", BattleStyle.TEXT_DIM)
    _anim_button.pressed.connect(toggle_animation)
    _deck_button = BattleStyle.button("牌堆", BattleStyle.ACCENT)
    _deck_button.pressed.connect(open_deck_viewer)
    _rules_button = BattleStyle.button("规则说明", BattleStyle.ACCENT)
    _rules_button.pressed.connect(open_rules)
    bar.add_child(_encounter_label)
    bar.add_child(_round_label)
    bar.add_child(_ddl_label)
    bar.add_child(_phase_label)
    bar.add_child(BattleStyle.spacer(Vector2(20, 0)))
    bar.add_child(_anim_button)
    bar.add_child(_deck_button)
    bar.add_child(_rules_button)
    return bar


func _build_left() -> Control:
    var col := VBoxContainer.new()
    col.custom_minimum_size = Vector2(268, 0)
    col.add_theme_constant_override("separation", 8)
    var box := BattleStyle.panel()
    var inner := VBoxContainer.new()
    inner.add_theme_constant_override("separation", 6)
    inner.add_child(BattleStyle.title("主角", BattleStyle.FONT_H2))
    _player_bar = BattleStyle.progress(0, 1, BattleStyle.OK)
    _player_text = BattleStyle.body_label("", BattleStyle.TEXT)
    _focus_label = BattleStyle.body_label("", BattleStyle.COST, BattleStyle.FONT_H1)
    inner.add_child(_player_bar)
    inner.add_child(_player_text)
    inner.add_child(_focus_label)
    _status_row = HBoxContainer.new()
    _status_row.add_theme_constant_override("separation", 4)
    inner.add_child(BattleStyle.title("状态", BattleStyle.FONT_SMALL, BattleStyle.TEXT_DIM))
    inner.add_child(_status_row)
    _relic_label = BattleStyle.body_label("", BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL)
    _exam_label = BattleStyle.body_label("", BattleStyle.WARN, BattleStyle.FONT_SMALL)
    inner.add_child(_relic_label)
    inner.add_child(_exam_label)
    box.add_child(inner)
    col.add_child(box)
    col.add_child(BattleStyle.spacer(Vector2(0, 0), false))
    return col


func _build_center() -> Control:
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.add_theme_constant_override("separation", 8)
    col.add_child(BattleStyle.title("任务", BattleStyle.FONT_H2))
    _task_row = HBoxContainer.new()
    _task_row.add_theme_constant_override("separation", 10)
    col.add_child(_task_row)
    col.add_child(BattleStyle.spacer(Vector2(0, 0), false))
    return col


func _build_right() -> Control:
    var col := VBoxContainer.new()
    col.custom_minimum_size = Vector2(300, 0)
    col.add_theme_constant_override("separation", 8)
    var scene_box := BattleStyle.panel()
    var scene_inner := VBoxContainer.new()
    scene_inner.add_theme_constant_override("separation", 4)
    scene_inner.add_child(BattleStyle.title("场景", BattleStyle.FONT_H2))
    _scene_label = BattleStyle.body_label("（无）", BattleStyle.TEXT_DIM)
    scene_inner.add_child(_scene_label)
    scene_box.add_child(scene_inner)
    col.add_child(scene_box)
    col.add_child(BattleStyle.title("单位槽", BattleStyle.FONT_H2))
    _unit_col = VBoxContainer.new()
    _unit_col.add_theme_constant_override("separation", 6)
    col.add_child(_unit_col)
    col.add_child(BattleStyle.spacer(Vector2(0, 0), false))
    return col


func _build_hint_row() -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    _hint_label = BattleStyle.body_label("", BattleStyle.WARN)
    _hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _cancel_button = BattleStyle.button("取消选择", BattleStyle.DANGER)
    _cancel_button.pressed.connect(cancel_selection)
    _cancel_button.disabled = true
    row.add_child(_hint_label)
    row.add_child(_cancel_button)
    return row


func _build_action_row() -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    _action_focus = BattleStyle.title("专注 0", BattleStyle.FONT_H2, BattleStyle.COST)
    _end_turn_button = BattleStyle.button("结束回合", BattleStyle.WARN)
    _end_turn_button.custom_minimum_size = Vector2(160, 44)
    _end_turn_button.pressed.connect(end_turn)
    row.add_child(_action_focus)
    row.add_child(BattleStyle.spacer(Vector2(20, 0)))
    row.add_child(_end_turn_button)
    return row


func _build_overlay() -> void:
    _overlay = Control.new()
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay.visible = false
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    _choice_panel = ChoicePanelScript.new()
    _choice_panel.visible = false
    _choice_panel.confirmed.connect(_on_choice_confirmed)
    _deck_viewer = DeckViewerScript.new()
    _deck_viewer.visible = false
    _rules_dialog = RulesDialogScript.new()
    _rules_dialog.visible = false
    center.add_child(_choice_panel)
    center.add_child(_deck_viewer)
    center.add_child(_rules_dialog)
    _overlay.add_child(center)
    add_child(_overlay)


## 入口：ui-shell 把 RunService 的 battle_input 原样交过来。
func start_battle(battle_input: Dictionary) -> Dictionary:
    _build()
    var engine = _ensure_engine()
    if engine == null:
        _start_result = Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.ui.battle.catalog_unavailable", {"manifest": manifest_id})
        _set_hint("内容清单载入失败，无法开始战斗")
        return _start_result
    if session == null:
        session = BattleSessionScript.new()
    _start_result = session.start(engine, battle_input)
    if not Result.is_ok(_start_result):
        _set_hint(_error_text(_start_result))
        return _start_result
    _reset_selection()
    render(session.view())
    _play_events(session.last_events)
    _check_finished()
    return _start_result


func set_engine(engine_ref) -> void:
    _engine = engine_ref


func current_view() -> Dictionary:
    return _view


func current_state():
    if session == null:
        return null
    return session.state


func current_rng_state():
    if session == null:
        return null
    return session.rng_state


func start_result() -> Dictionary:
    return _start_result


func _ensure_engine():
    if _engine != null:
        return _engine
    var candidates: Array = [manifest_id]
    for fallback in MANIFEST_FALLBACKS:
        if not candidates.has(fallback):
            candidates.append(fallback)
    for candidate in candidates:
        var db := ContentDB.new()
        var info: Dictionary = db.load(String(candidate))
        if bool(info.get("ok", false)):
            manifest_id = String(candidate)
            _engine = BattleEngineScript.new(db)
            return _engine
        _catalog_error = db.last_error_code
    return null


func is_locked() -> bool:
    if session == null or not session.started():
        return true
    if session.finished():
        return true
    return session.pending_choice() != null


func is_finished() -> bool:
    if session == null:
        return false
    return session.finished()


func outcome():
    if session == null:
        return null
    return session.outcome()


func hint_text() -> String:
    _build()
    return _hint_label.text


func submitted_actions() -> Array:
    return _submitted_actions.duplicate(true)


func log_lines() -> PackedStringArray:
    if _log_panel == null:
        return PackedStringArray()
    return _log_panel.line_texts()



## render(视图)：界面唯一的刷新入口。只读视图，不修改任何规则状态。
func render(view: Dictionary) -> void:
    _build()
    _view = view
    _render_top(view)
    _render_player(view)
    _render_tasks(view)
    _render_units(view)
    _render_scene(view)
    _render_hand(view)
    _render_choice(view)
    _render_hint()
    _sync_lock()
    if _log_panel != null and session != null:
        _log_panel.render(session.log_entries())
    view_updated.emit(view)


func _render_top(view: Dictionary) -> void:
    var encounter_id := String(view.get("encounter_id", ""))
    _encounter_label.text = BattleLabels.definition_name(_catalog(), GameConstants.KIND_ENCOUNTER, encounter_id)
    _round_label.text = "第 %d 轮" % int(view.get("round_index", 0))
    _ddl_label.text = "DDL %d" % int(view.get("ddl", 0))
    _phase_label.text = BattleLabels.phase_name(String(view.get("phase", "")))
    var zones: Dictionary = view.get("zones", {})
    _deck_button.text = "牌堆  抽%d 弃%d 耗%d" % [int(zones.get("draw", 0)), int(zones.get("discard", 0)), int(zones.get("exhaust", 0))]
    _anim_button.text = "动画：开" if animator != null and animator.animation_enabled else "动画：关"


func _render_player(view: Dictionary) -> void:
    var player: Dictionary = view.get("player", {})
    var vitality := int(player.get("vitality", 0))
    var max_vitality := maxi(1, int(player.get("max_vitality", 1)))
    _player_bar.max_value = max_vitality
    _player_bar.value = clampi(vitality, 0, max_vitality)
    _player_text.text = "精力 %d / %d   放松 %d" % [vitality, max_vitality, int(player.get("relax", 0))]
    _focus_label.text = "专注 %d" % int(player.get("focus", 0))
    _action_focus.text = "专注 %d" % int(player.get("focus", 0))
    _clear_children(_status_row)
    var found := false
    for raw in (view.get("statuses", []) as Array):
        var status: Dictionary = raw
        if String(status.get("holder_id", "")) != String(player.get("entity_id", "")):
            continue
        found = true
        var stacks := int(status.get("stacks", 0))
        var tone := BattleStyle.DANGER if _is_bad_status(String(status.get("status_id", ""))) else BattleStyle.OK
        _status_row.add_child(BattleStyle.chip("%s %d" % [BattleLabels.status_name(String(status.get("status_id", ""))), stacks], tone))
    if not found:
        _status_row.add_child(BattleStyle.body_label("无", BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL))
    var relic_names := PackedStringArray()
    for raw_id in (view.get("relics", []) as Array):
        relic_names.append(BattleLabels.definition_name(_catalog(), GameConstants.KIND_RELIC, String(raw_id)))
    _relic_label.text = "饰品：" + ("、".join(relic_names) if relic_names.size() > 0 else "无")
    var exam_names := PackedStringArray()
    for raw_id in (view.get("exam_limits", []) as Array):
        exam_names.append(BattleLabels.exam_limit_name(String(raw_id)))
    _exam_label.text = "" if exam_names.size() == 0 else "考试限制：" + "、".join(exam_names)


func _render_tasks(view: Dictionary) -> void:
    _clear_children(_task_row)
    var round_index := int(view.get("round_index", 0))
    for raw in (view.get("tasks", []) as Array):
        var card = TaskCardScript.new()
        card.setup(raw, round_index, _catalog())
        card.set_selectable(_mode == MODE_CARD_TARGET or _mode == MODE_ALLY_TARGET)
        card.set_selected(_selected_targets.has(String((raw as Dictionary).get("task_id", ""))))
        card.chosen.connect(select_target)
        _task_row.add_child(card)


func _render_units(view: Dictionary) -> void:
    _clear_children(_unit_col)
    var slots := 3
    if _catalog() != null:
        slots = _catalog().battle_int("unit_slots", 3)
    var units: Array = view.get("units", [])
    for raw in units:
        var slot = UnitSlotScript.new()
        slot.setup(raw, view, _catalog(), session)
        slot.set_replace_mode(_mode == MODE_REPLACE_UNIT)
        slot.set_selected(_selected_unit_id == String((raw as Dictionary).get("unit_id", "")))
        slot.chosen.connect(select_unit)
        _unit_col.add_child(slot)
    for index in range(units.size(), slots):
        var empty := BattleStyle.panel()
        empty.add_theme_stylebox_override("panel", BattleStyle.card_box(BattleStyle.PANEL.darkened(0.2), BattleStyle.BORDER, 1))
        empty.custom_minimum_size = Vector2(0, 96)
        var label := BattleStyle.body_label("空槽 %d" % (index + 1), BattleStyle.TEXT_DIM, BattleStyle.FONT_SMALL)
        empty.add_child(label)
        _unit_col.add_child(empty)


func _render_scene(view: Dictionary) -> void:
    var scene: Variant = view.get("scene")
    if typeof(scene) != TYPE_DICTIONARY:
        _scene_label.text = "（无场景）"
        _scene_label.add_theme_color_override("font_color", BattleStyle.TEXT_DIM)
        return
    var scene_dict: Dictionary = scene
    var definition_id := String(scene_dict.get("definition_id", ""))
    var text := BattleLabels.definition_name(_catalog(), GameConstants.KIND_SCENE, definition_id)
    text += "（第 %d 轮建立）" % int(scene_dict.get("established_round", 0))
    if scene_dict.get("pending_random_result") != null:
        text += "\n下次预抽结果：" + _scene_result_text(scene_dict.get("pending_random_result"))
    _scene_label.text = text
    _scene_label.add_theme_color_override("font_color", BattleStyle.SCENE_COLOR)


func _scene_result_text(raw: Variant) -> String:
    if typeof(raw) != TYPE_DICTIONARY:
        return String(raw)
    return BattleLabels.effect_text(raw, _catalog())


func _render_hand(view: Dictionary) -> void:
    _clear_children(_hand_row)
    for raw in (view.get("hand", []) as Array):
        var widget = CardWidgetScript.new()
        widget.setup(raw, _catalog())
        widget.set_selected(_selected_card_id == String((raw as Dictionary).get("card_id", "")))
        widget.chosen.connect(select_card)
        _hand_row.add_child(widget)


func _render_choice(view: Dictionary) -> void:
    var pending: Variant = view.get("pending_choice")
    _choice_panel.render(pending, _catalog())
    _sync_overlay()


func _sync_overlay() -> void:
    if _overlay == null:
        return
    _overlay.visible = _choice_panel.visible or _deck_viewer.visible or _rules_dialog.visible


## 提示文案：只说「现在该做什么」，不暴露隐藏信息。
func _render_hint() -> void:
    if not _hint_override.is_empty():
        _hint_label.text = _hint_override
        return
    var pending: Variant = _view.get("pending_choice")
    if typeof(pending) == TYPE_DICTIONARY:
        _hint_label.text = "待选期间只能确认这次选择（其余操作已锁定）"
        return
    if is_finished():
        _hint_label.text = "战斗已结束"
        return
    match _mode:
        MODE_CARD_TARGET:
            _hint_label.text = "已选「%s」，请点击一个任务作为目标（可取消）" % _card_label(_selected_card_id)
        MODE_REPLACE_UNIT:
            _hint_label.text = "单位槽已满：请点击要换下的单位（可取消）"
        MODE_ALLY_TARGET:
            _hint_label.text = "已选单位「%s」，请点击协作目标任务（可取消）" % _unit_label(_selected_unit_id)
        _:
            _hint_label.text = "点击手牌出牌；需要目标时再点任务或单位"


func _sync_lock() -> void:
    var pending: Variant = _view.get("pending_choice")
    var pending_active := typeof(pending) == TYPE_DICTIONARY
    var locked := is_locked()
    _end_turn_button.disabled = locked
    _deck_button.disabled = pending_active
    _rules_button.disabled = pending_active
    _anim_button.disabled = pending_active
    _cancel_button.disabled = locked or _mode == MODE_NONE
    for raw in _hand_row.get_children():
        if raw is Button:
            (raw as Button).disabled = locked or not (raw as CardWidgetScript).playable
    for raw in _task_row.get_children():
        if raw is TaskCardScript:
            (raw as TaskCardScript).set_selectable(not locked and (_mode == MODE_CARD_TARGET or _mode == MODE_ALLY_TARGET))
    for raw in _unit_col.get_children():
        if raw is UnitSlotScript:
            (raw as Button).disabled = locked


func _build_pulse_row() -> Control:
    var row := HBoxContainer.new()
    _pulse_label = BattleStyle.body_label("", BattleStyle.ACCENT, BattleStyle.FONT_SMALL)
    row.add_child(_pulse_label)
    return row


func _on_event_played(event: Dictionary) -> void:
    if _pulse_label == null or session == null:
        return
    var entry: Dictionary = session.describe_event(event)
    if entry.is_empty():
        return
    _pulse_label.text = "▸ " + String(entry.get("text", ""))


func _play_events(events: Array) -> void:
    if animator == null:
        return
    animator.enqueue(events)


func _check_finished() -> void:
    if session == null or not session.finished():
        return
    var outcome_dict: Dictionary = session.outcome()
    _set_hint("战斗结束：%s（%s）" % [BattleLabels.outcome_name(String(outcome_dict.get("result", ""))), BattleLabels.reason_name(String(outcome_dict.get("reason", "")))])
    render(session.view())
    battle_finished.emit(outcome_dict)


func _clear_children(node: Node) -> void:
    if node == null:
        return
    for child in node.get_children():
        node.remove_child(child)
        child.queue_free()


func _catalog():
    if _engine != null:
        return _engine.catalog
    if session != null:
        return session.catalog()
    return null



func _is_bad_status(status_id: String) -> bool:
    return status_id in ["anxiety", "procrastination", "drowsiness", "extra_requirements"]


func _card_label(card_id: String) -> String:
    if session == null:
        return card_id
    return session.card_name(card_id)


func _unit_label(unit_id: String) -> String:
    for raw in (_view.get("units", []) as Array):
        var unit: Dictionary = raw
        if String(unit.get("unit_id", "")) == unit_id:
            return BattleLabels.definition_name(_catalog(), GameConstants.KIND_UNIT, String(unit.get("definition_id", "")))
    return unit_id


func _set_hint(text: String) -> void:
    _hint_override = text
    if _hint_label != null:
        _hint_label.text = text


## 把引擎给的 error 译成一行中文；不猜、不补规则。
func _error_text(result: Dictionary) -> String:
    var error: Dictionary = result.get("error", {})
    if typeof(error) != TYPE_DICTIONARY:
        return "操作被拒绝"
    var message_key := String(error.get("message_key", ""))
    var code := String(error.get("code", ""))
    var details: Dictionary = error.get("details", {}) if typeof(error.get("details")) == TYPE_DICTIONARY else {}
    match code:
        GameConstants.ERROR_INSUFFICIENT_RESOURCE:
            return _insufficient_text(message_key, details)
        GameConstants.ERROR_INVALID_TARGET:
            return "目标不合法（%s）" % message_key
        GameConstants.ERROR_LIMIT_REACHED:
            return "这张牌的限次已用完"
        GameConstants.ERROR_CHOICE_PENDING:
            return "还有待选没确认"
        GameConstants.ERROR_WRONG_PHASE:
            return "当前阶段不能这么做"
    return "操作被拒绝：%s" % message_key


# 交互：全部输入都先过 is_locked()，待选期间只有确认选择能通过

func select_card(card_id: String) -> void:
    _build()
    if is_locked():
        return
    _reset_selection()
    _hint_override = ""
    _selected_card_id = card_id
    _resolve_card_selection()


func select_target(task_id: String) -> void:
    _build()
    if is_locked():
        return
    _hint_override = ""
    if _mode == MODE_ALLY_TARGET:
        _submit(build_action(GameConstants.ACTION_SET_ALLY_TARGET, {"unit_id": _selected_unit_id, "task_id": task_id}))
        return
    if _mode != MODE_CARD_TARGET:
        return
    if _selected_targets.has(task_id):
        _selected_targets = []
    else:
        _selected_targets = [task_id]
    _resolve_card_selection()


func select_unit(unit_id: String) -> void:
    _build()
    if is_locked():
        return
    _hint_override = ""
    if _mode == MODE_REPLACE_UNIT:
        _replace_unit_id = unit_id
        _resolve_card_selection()
        return
    if _selected_unit_id == unit_id:
        _reset_selection()
        render(_view)
        return
    _reset_selection()
    _selected_unit_id = unit_id
    _mode = MODE_ALLY_TARGET
    render(_view)


func cancel_selection() -> void:
    _build()
    if is_locked():
        return
    _reset_selection()
    _set_hint("已取消选择")
    render(_view)


func end_turn() -> void:
    _build()
    if is_locked():
        return
    _reset_selection()
    _hint_override = ""
    _submit(build_action(GameConstants.ACTION_END_TURN, {"retained_card_ids": _retained}))


## 效果内选择：只有这条路在待选期间可用。
func confirm_choice(selected_ids: Array) -> void:
    _build()
    if session == null:
        return
    var pending: Variant = session.pending_choice()
    if typeof(pending) != TYPE_DICTIONARY:
        return
    var choice_id := String((pending as Dictionary).get("choice_id", ""))
    _submit(build_action(GameConstants.ACTION_CONFIRM_CHOICE, {"choice_id": choice_id, "selected_ids": selected_ids}))


func _on_choice_confirmed(selected_ids: Array) -> void:
    confirm_choice(selected_ids)


func toggle_animation() -> void:
    _build()
    if session != null and session.pending_choice() != null:
        return
    if animator == null:
        return
    animator.toggle_enabled()
    _anim_button.text = "动画：开" if animator.animation_enabled else "动画：关"


func open_deck_viewer() -> void:
    _build()
    if session != null and session.pending_choice() != null:
        return
    _deck_viewer.render(_view, _catalog())
    _deck_viewer.open()
    _sync_overlay()


func close_deck_viewer() -> void:
    _build()
    _deck_viewer.close()
    _sync_overlay()


func open_rules() -> void:
    _build()
    if session != null and session.pending_choice() != null:
        return
    _rules_dialog.render(_catalog())
    _rules_dialog.open()
    _sync_overlay()


func close_rules() -> void:
    _build()
    _rules_dialog.close()
    _sync_overlay()


func deck_viewer():
    _build()
    return _deck_viewer


func rules_dialog():
    _build()
    return _rules_dialog


func choice_panel():
    _build()
    return _choice_panel


# 出牌解析：合法性一律问引擎的 preview，界面不自己判断

func _play_draft() -> Dictionary:
    var target_ids: Array = []
    for raw in _selected_targets:
        target_ids.append(String(raw))
    var replace_unit_id: Variant = null
    if not _replace_unit_id.is_empty():
        replace_unit_id = _replace_unit_id
    return build_action(GameConstants.ACTION_PLAY_CARD, {"card_id": _selected_card_id, "target_ids": target_ids, "replace_unit_id": replace_unit_id})


func _resolve_card_selection() -> void:
    if _selected_card_id.is_empty():
        _reset_selection()
        render(_view)
        return
    var draft: Dictionary = _play_draft()
    var preview: Variant = _preview(draft)
    if preview == null:
        _reset_selection()
        _set_hint("无法预览这张牌")
        render(_view)
        return
    var preview_dict: Dictionary = preview
    var required: Array = preview_dict.get("required_selections", [])
    if required.has("target_ids"):
        _mode = MODE_CARD_TARGET
        render(_view)
        return
    if required.has("replace_unit_id"):
        _mode = MODE_REPLACE_UNIT
        render(_view)
        return
    _mode = MODE_NONE
    if bool(preview_dict.get("can_submit", false)):
        _submit(draft)
        return
    _set_hint(_first_blocking_error(preview_dict))
    render(_view)


func _preview(draft: Dictionary):
    if session == null or draft.is_empty():
        return null
    var result: Dictionary = session.preview(draft)
    if not Result.is_ok(result):
        return null
    return result["data"]


func _first_blocking_error(preview: Dictionary) -> String:
    var errors: Array = preview.get("blocking_errors", [])
    if errors.is_empty():
        return "这个操作暂时不合法"
    var first: Dictionary = errors[0]
    return _error_text({"error": first})


func _reset_selection() -> void:
    _mode = MODE_NONE
    _selected_card_id = ""
    _selected_targets = []
    _replace_unit_id = ""
    _selected_unit_id = ""


# 提交：唯一会写状态的地方，且必须走 BattleEngine.apply

func _submit(action: Dictionary) -> Dictionary:
    if session == null:
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.battle.not_started", {})
    if action.is_empty():
        _set_hint("当前操作被锁定，请先完成待选")
        render(_view)
        return Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.ui.battle.locked", {})
    var step: Dictionary = session.submit(action)
    if not Result.is_ok(step):
        _set_hint(_error_text(step))
        render(_view)
        return step
    _reset_selection()
    _hint_override = ""
    _submitted_actions.append(action.duplicate(true))
    render(session.view())
    _play_events(session.last_events)
    action_applied.emit(step)
    _check_finished()
    return step


## build_action(协议)：界面唯一产出动作的函数。
## 待选期间只接受 confirm_choice，其余一律返回空字典（调用方拿不到可提交的动作）。
func build_action(action_type: String, params: Dictionary = {}) -> Dictionary:
    if action_type != GameConstants.ACTION_CONFIRM_CHOICE and is_locked():
        return {}
    match action_type:
        GameConstants.ACTION_PLAY_CARD:
            return {"type": action_type, "payload": {
                "card_id": String(params.get("card_id", "")),
                "target_ids": (params.get("target_ids", []) as Array).duplicate(),
                "replace_unit_id": params.get("replace_unit_id"),
            }}
        GameConstants.ACTION_CONFIRM_CHOICE:
            return {"type": action_type, "payload": {
                "choice_id": String(params.get("choice_id", "")),
                "selected_ids": (params.get("selected_ids", []) as Array).duplicate(),
            }}
        GameConstants.ACTION_SET_ALLY_TARGET:
            return {"type": action_type, "payload": {
                "unit_id": String(params.get("unit_id", "")),
                "task_id": String(params.get("task_id", "")),
            }}
        GameConstants.ACTION_END_TURN:
            return {"type": action_type, "payload": {
                "retained_card_ids": (params.get("retained_card_ids", []) as Array).duplicate(),
            }}
    return {}


## 保留手牌（base_retention_count 为 0 时界面不给入口，接口保留）。
func toggle_retain(card_id: String) -> void:
    if _retained.has(card_id):
        _retained.erase(card_id)
        return
    var allowed := 0
    if _catalog() != null:
        allowed = _catalog().battle_int("base_retention_count", 0)
    if _retained.size() >= allowed:
        return
    _retained.append(card_id)


func retained_card_ids() -> Array:
    return _retained.duplicate()


func hand_card_ids() -> PackedStringArray:
    var out := PackedStringArray()
    for raw in _hand_row.get_children():
        if raw is CardWidgetScript:
            out.append((raw as CardWidgetScript).card_id)
    return out


func task_ids() -> PackedStringArray:
    var out := PackedStringArray()
    for raw in _task_row.get_children():
        if raw is TaskCardScript:
            out.append((raw as TaskCardScript).task_id)
    return out


func unit_widgets() -> Array:
    var out: Array = []
    for raw in _unit_col.get_children():
        if raw is UnitSlotScript:
            out.append(raw)
    return out


func task_widgets() -> Array:
    var out: Array = []
    for raw in _task_row.get_children():
        if raw is TaskCardScript:
            out.append(raw)
    return out


func hand_widgets() -> Array:
    var out: Array = []
    for raw in _hand_row.get_children():
        if raw is CardWidgetScript:
            out.append(raw)
    return out


func selection_mode() -> String:
    return _mode


func player_text() -> String:
    _build()
    return _player_text.text


func focus_text() -> String:
    _build()
    return _focus_label.text


func scene_text() -> String:
    _build()
    return _scene_label.text


func ddl_text() -> String:
    _build()
    return _ddl_label.text



## 给冒烟测试用的锁快照：待选期间除确认选择外的一切入口都应为 true。
func lock_snapshot() -> Dictionary:
    _build()
    var cards_disabled := true
    for raw in _hand_row.get_children():
        if raw is Button and not (raw as Button).disabled:
            cards_disabled = false
    var tasks_selectable := false
    for raw in _task_row.get_children():
        if raw is TaskCardScript and (raw as TaskCardScript).selectable:
            tasks_selectable = true
    var units_disabled := true
    for raw in _unit_col.get_children():
        if raw is Button and not (raw as Button).disabled:
            units_disabled = false
    return {
        "end_turn": _end_turn_button.disabled,
        "deck": _deck_button.disabled,
        "rules": _rules_button.disabled,
        "anim": _anim_button.disabled,
        "cancel": _cancel_button.disabled,
        "cards_disabled": cards_disabled,
        "tasks_selectable": tasks_selectable,
        "units_disabled": units_disabled,
        "overlay": _overlay.visible,
    }


## 提前把界面建好（ui-shell 想在 start_battle 之前设动画开关时用）。
func prepare() -> void:
    _build()


## 读档续战：ui-shell 的 main.gd 会调；rng_ref 传该战斗的随机快照才能保证读档后结果一致。
func resume_battle(battle_state, rng_ref = null) -> Dictionary:
    _build()
    var engine = _ensure_engine()
    if engine == null:
        _start_result = Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.ui.battle.catalog_unavailable", {"manifest": manifest_id})
        _set_hint("内容清单载入失败，无法继续战斗")
        return _start_result
    if session == null:
        session = BattleSessionScript.new()
    _start_result = session.adopt(engine, battle_state, rng_ref)
    if not Result.is_ok(_start_result):
        _set_hint(_error_text(_start_result))
        return _start_result
    _reset_selection()
    _hint_override = ""
    render(session.view())
    return _start_result



## 内容清单回落顺序（第一个能载入的就用）。
const MANIFEST_FALLBACKS: Array = [GameConstants.MANIFEST_MVP, "battle_mvp"]



## 资源不足：专注与精力是两种代价，报错必须分清（K10 一类主动支付精力）。
func _insufficient_text(message_key: String, details: Dictionary) -> String:
    var required := int(details.get("required", 0))
    if message_key.contains("vitality"):
        return "精力不足：需要 %d，且支付后至少留 %d" % [required, int(details.get("must_keep", 1))]
    return "专注不足：需要 %d" % required
