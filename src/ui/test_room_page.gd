class_name TestRoomPage
extends UiPage

## Test room home and result page. Configuration is local UI state; starting and
## loading are submitted as test commands handled by GameShell/GameSession.

var screen: String = "test_room_home"
var _character_id := "P01"
var _encounter_id := "N01"
var _seed := "42"
var _prepared := false


func render(data: Dictionary) -> void:
	view = data.duplicate(true)
	if screen == "test_room_result":
		_render_result()
	else:
		_render_home()


func _render_home() -> void:
	var options: Dictionary = view.get("options", {})
	if options.is_empty():
		reset_page("测试房间", "内容加载失败。")
		add_button(body, "test:back", "返回主菜单", {"type": "ui.menu"})
		return
	if not _prepared:
		var characters: Array = options.get("characters", [])
		if not characters.is_empty():
			_character_id = str(characters[0].get("id", "P01"))
		var encounters: Array = options.get("encounters", [])
		_encounter_id = str(encounters[0].get("id", "N01")) if not encounters.is_empty() else "N01"
		_prepared = true
	reset_page("测试房间", "修改只作用于本实验，不影响正式存档；随时可打开编辑器。")
	add_text(body, "选择角色后开始；也可以先载入预设或快照。")
	var character_row: HBoxContainer = add_row(body)
	for character in options.get("characters", []):
		var id := str(character.get("id", ""))
		var caption := UiStyle.label(id) + (" ✓" if id == _character_id else "")
		add_button(
			character_row,
			"test:character:" + id,
			caption,
			{},
			func():
				_character_id = id
				render(view)
		)
	var config_panel: VBoxContainer = add_panel(body)
	add_text(config_panel, "遭遇 ID：%s" % _encounter_id, 14, UiStyle.MUTED)
	var encounter_input := LineEdit.new()
	encounter_input.text = _encounter_id
	encounter_input.placeholder_text = "遭遇 ID，如 N01"
	encounter_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encounter_input.text_changed.connect(func(value: String): _encounter_id = value.strip_edges())
	config_panel.add_child(encounter_input)
	add_text(config_panel, "种子", 14, UiStyle.MUTED)
	var seed_input := LineEdit.new()
	seed_input.text = _seed
	seed_input.placeholder_text = "seed"
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.text_changed.connect(func(value: String): _seed = value.strip_edges())
	config_panel.add_child(seed_input)
	var start_row: HBoxContainer = add_row(body)
	add_button(
		start_row,
		"test:start",
		"开始实验",
		{
			"type": "test.start",
			"payload": {
				"config": {
					"character_id": _character_id,
					"encounter_id": _encounter_id,
					"seed": _seed,
				}
			},
		}
	)
	add_button(start_row, "test:back", "返回主菜单", {"type": "ui.menu"})
	var files: Dictionary = view.get("files", {})
	var presets: Array = files.get("presets", [])
	if not presets.is_empty():
		add_text(body, "预设", 18)
		for preset in presets:
			var preset_row: HBoxContainer = add_row(body)
			add_text(preset_row, "%s · %s" % [preset.get("name", ""), preset.get("id", "")], 14)
			add_button(
				preset_row,
				"test:load_preset:" + str(preset.get("id", "")),
				"载入",
				{"type": "test.load_preset", "payload": {"id": str(preset.get("id", ""))}}
			)
	var snapshots: Array = files.get("snapshots", [])
	if not snapshots.is_empty():
		add_text(body, "快照", 18)
		for snapshot in snapshots:
			var snapshot_row: HBoxContainer = add_row(body)
			add_text(snapshot_row, "%s · %s" % [snapshot.get("name", ""), snapshot.get("id", "")], 14)
			add_button(
				snapshot_row,
				"test:load_snapshot:" + str(snapshot.get("id", "")),
				"载入",
				{"type": "test.load_snapshot", "payload": {"id": str(snapshot.get("id", ""))}}
			)
	var records: Array = files.get("records", [])
	if not records.is_empty():
		add_text(body, "记录", 18)
		for record in records:
			var record_row: HBoxContainer = add_row(body)
			add_text(record_row, "%s · %s" % [record.get("name", ""), record.get("id", "")], 14)
			add_button(
				record_row,
				"test:load_record:" + str(record.get("id", "")),
				"载入",
				{"type": "test.load_record", "payload": {"id": str(record.get("id", ""))}}
			)


func _render_result() -> void:
	var test_view: Dictionary = view.get("view", {})
	var battle: Dictionary = test_view.get("battle", {})
	var result: Dictionary = test_view.get("result", {})
	var test_state: Dictionary = test_view.get("test", {})
	reset_page("实验结束", "结果来源：%s" % _source_name(str(result.get("source", ""))))
	add_text(body, "分支 %s · rev %s · 干预 %s 次" % [
		test_state.get("branch_id", 0), test_state.get("revision", 0), test_state.get("interventions", 0)
	])
	add_text(body, "回合 %s · DDL %s · 剩余精力 %s" % [
		battle.get("round_index", 0),
		battle.get("ddl", 0),
		(battle.get("player", {}) as Dictionary).get("vitality", 0),
	])
	var row: HBoxContainer = add_row(body)
	add_button(row, "test:result:continue", "继续编辑", {"type": "test.continue"})
	add_button(row, "test:result:retry_same", "同条件重试", {"type": "test.retry_same"})
	add_button(row, "test:result:retry_current", "以当前为新起点", {"type": "test.retry_current"})
	add_button(row, "test:result:save", "保存记录", {"type": "test.save_record"})
	add_button(row, "test:result:exit", "保存并返回", {"type": "test.save_and_exit"})
	add_button(row, "test:result:discard", "丢弃并返回", {"type": "test.close"})


func _source_name(source: String) -> String:
	return str(
		{
			"normal": "正常结算",
			"manual": "人工判定",
			"truncated": "截断结算",
			"abandoned": "主动结束",
			"none": "未结束",
		}
		.get(source, source)
	)
