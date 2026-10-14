class_name UiSetupPage
extends "res://src/ui/ui_page.gd"
##
## 选人页（《界面层契约》§3）：人物 / 难度 / 种子 -> create_run。
##
## 视图（shell 组装，非 RunView）：
##   {characters: [{id, name_key, locked, reason, starter_relic_id, starter_cards}],
##    difficulties: [String], defaults: {character_id, difficulty, seed}, mode: "new"|"retry"}
##
## 本页只产出 create_run 草稿；开局校验（解锁、清单、种子、起始牌组）全部由 RunService.create 判定，
## 失败原因由 shell 写进 status_text 显示。
##

const GameConstants := preload("res://src/common/game_constants.gd")

var _character_id: String = ""
var _difficulty: String = ""
var _seed_text: String = ""
var _seed_field: LineEdit = null


func render(p_view: Dictionary) -> void:
	var defaults: Variant = p_view.get("defaults")
	if typeof(defaults) == TYPE_DICTIONARY:
		var data: Dictionary = defaults
		if _character_id.is_empty():
			_character_id = String(data.get("character_id", ""))
		if _difficulty.is_empty():
			_difficulty = String(data.get("difficulty", GameConstants.DIFFICULTY_NORMAL))
		if _seed_text.is_empty():
			_seed_text = String(data.get("seed", ""))
	super.render(p_view)


## 测试与自动化用：等价于在种子输入框里打字。
func set_seed_text(text: String) -> void:
	_seed_text = text
	if _seed_field != null:
		_seed_field.text = text


func selected() -> Dictionary:
	return {"character_id": _character_id, "difficulty": _difficulty, "seed": _seed_text}


func _render(parent: Node) -> void:
	_header(parent, "新的一局", "选人物 / 难度 / 种子")

	_section(parent, "人物")
	for raw_character in (view.get("characters", []) as Array):
		var character: Dictionary = raw_character
		var character_id := String(character.get("id", ""))
		var locked := bool(character.get("locked", false))
		var uid := "setup:character:" + character_id
		var text := character_id
		if String(character.get("name_key", "")) != "":
			text += "（%s）" % String(character.get("name_key"))
		if character_id == _character_id:
			text = "▶ " + text
		var button := _local_button(parent, uid, text)
		button.disabled = locked
		if locked:
			_reasons[uid] = String(character.get("reason", "未解锁"))
			button.tooltip_text = _reasons[uid]
		var starter_cards: Variant = character.get("starter_cards")
		_hint(parent, "起始牌：%s  初始饰品：%s" % [
			str(starter_cards),
			String(character.get("starter_relic_id", "")),
		])

	_section(parent, "难度")
	var row := _row(parent)
	for raw_difficulty in (view.get("difficulties", []) as Array):
		var difficulty := String(raw_difficulty)
		var text := difficulty
		if difficulty == _difficulty:
			text = "▶ " + text
		_local_button(row, "setup:difficulty:" + difficulty, text)

	_section(parent, "种子")
	_seed_field = LineEdit.new()
	_seed_field.name = "SeedField"
	_seed_field.text = _seed_text
	_seed_field.placeholder_text = "十进制整数；留空使用 0"
	_seed_field.text_changed.connect(_on_seed_changed)
	parent.add_child(_seed_field)
	_local_button(parent, "setup:seed_random", "换个随机种子")

	_spacer(parent)
	_action_button(parent, "setup:start", "开始新局", Callable(self, "create_draft"))
	_action_button(parent, "setup:back", "返回主菜单", {"type": "ui.menu", "payload": {}})


## 当前选择 -> create_run 草稿（shell 直接交给 RunService.create）。
func create_draft() -> Dictionary:
	return {
		"type": "create_run",
		"payload": {
			"character_id": _character_id,
			"difficulty": _difficulty,
			"seed": _seed_text,
		},
	}


func _on_seed_changed(text: String) -> void:
	_seed_text = text


func _handle(uid: String) -> void:
	if uid.begins_with("setup:character:"):
		_character_id = uid.trim_prefix("setup:character:")
		_selection_changed()
		return
	if uid.begins_with("setup:difficulty:"):
		_difficulty = uid.trim_prefix("setup:difficulty:")
		_selection_changed()
		return
	if uid == "setup:seed_random":
		set_seed_text(str(Time.get_ticks_usec() % 100000000))
		_selection_changed()
		return
	if uid == "setup:start":
		_submit(create_draft())
		return
	if uid == "setup:back":
		_submit({"type": "ui.menu", "payload": {}})