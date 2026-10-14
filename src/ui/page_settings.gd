class_name UiSettingsPage
extends "res://src/ui/ui_page.gd"
##
## 设置页（《界面层契约》§12）：默认难度 / 默认种子 / 自动存档开关 / 存档维护。
##
## 设置文档走 SaveStore 的 settings 槽（SnapshotCodec.encode_document），页面不碰文件系统。
## 视图（shell 组装）：{settings:{difficulty, seed, autosave}, difficulties:[String], save_meta, backup_meta}
##

const GameConstants := preload("res://src/common/game_constants.gd")

var _difficulty: String = ""
var _seed: String = ""
var _autosave: bool = true
var _seed_field: LineEdit = null
var _autosave_box: CheckBox = null


func render(p_view: Dictionary) -> void:
	var raw_settings: Variant = p_view.get("settings")
	if typeof(raw_settings) == TYPE_DICTIONARY and _difficulty.is_empty():
		var settings: Dictionary = raw_settings
		_difficulty = String(settings.get("difficulty", GameConstants.DIFFICULTY_NORMAL))
		_seed = String(settings.get("seed", ""))
		_autosave = bool(settings.get("autosave", true))
	super.render(p_view)


## 保存草稿：难度/种子/自动存档都可能在选择之后才变，所以走 Callable。
func settings_draft() -> Dictionary:
	return {"type": "ui.save_settings", "payload": {"settings": current_settings()}}


func current_settings() -> Dictionary:
	return {"difficulty": _difficulty, "seed": _seed, "autosave": _autosave}


func _render(parent: Node) -> void:
	_header(parent, "设置", "默认值只影响新局；已开的局不受影响")
	var difficulties: Array = view.get("difficulties", [])
	if difficulties.is_empty():
		difficulties = [GameConstants.DIFFICULTY_RELAXED, GameConstants.DIFFICULTY_NORMAL, GameConstants.DIFFICULTY_HARD]
	_section(parent, "默认难度")
	var row := _row(parent)
	for raw_difficulty in difficulties:
		var difficulty := String(raw_difficulty)
		var text := difficulty
		if difficulty == _difficulty:
			text = "▶ " + text
		_local_button(row, "settings:difficulty:" + difficulty, text)

	_section(parent, "默认种子")
	_seed_field = LineEdit.new()
	_seed_field.name = "SeedField"
	_seed_field.text = _seed
	_seed_field.placeholder_text = "十进制整数；留空使用 0"
	_seed_field.text_changed.connect(_on_seed_changed)
	parent.add_child(_seed_field)

	_section(parent, "自动存档")
	_autosave_box = CheckBox.new()
	_autosave_box.name = "Autosave"
	_autosave_box.text = "每一步自动写 current_run"
	_autosave_box.button_pressed = _autosave
	_autosave_box.toggled.connect(_on_autosave_toggled)
	parent.add_child(_autosave_box)

	_section(parent, "存档维护")
	_hint(parent, "当前档：%s" % str(view.get("save_meta")))
	_hint(parent, "备份档：%s" % str(view.get("backup_meta")))

	_spacer(parent)
	_action_button(parent, "settings:save", "保存设置", Callable(self, "settings_draft"))
	_action_button(parent, "settings:restore_backup", "从备份恢复存档", {
		"type": "ui.restore_backup",
		"payload": {},
	})
	_action_button(parent, "settings:back", "返回主菜单", {"type": "ui.menu", "payload": {}})


func set_seed_text(text: String) -> void:
	_seed = text
	if _seed_field != null:
		_seed_field.text = text


func set_autosave(value: bool) -> void:
	_autosave = value
	if _autosave_box != null:
		_autosave_box.button_pressed = value


func _on_seed_changed(text: String) -> void:
	_seed = text


func _on_autosave_toggled(value: bool) -> void:
	_autosave = value


func _handle(uid: String) -> void:
	if uid.begins_with("settings:difficulty:"):
		_difficulty = uid.trim_prefix("settings:difficulty:")
		_selection_changed()
		return
	if uid == "settings:save":
		_submit({"type": "ui.save_settings", "payload": {"settings": current_settings()}})
		return
	if uid == "settings:restore_backup":
		_submit({"type": "ui.restore_backup", "payload": {}})
		return
	if uid == "settings:back":
		_submit({"type": "ui.menu", "payload": {}})