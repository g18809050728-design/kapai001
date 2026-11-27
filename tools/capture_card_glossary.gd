extends RefCounted

## Captures the battle card detail window with its glossary dropdown closed
## and open. Uses a real production session and pointer-free pinned panels so
## the screenshots show deterministic state.

var _output := ""
var _tree: SceneTree
var _captures: Array[Dictionary] = []


func run(tree: SceneTree) -> int:
	_tree = tree
	return await _capture_all()


func _capture_all() -> int:
	var arguments := OS.get_cmdline_user_args()
	_output = arguments[0] if not arguments.is_empty() else ""
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A graphical renderer and an output directory are required")
		return 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	var session := GameSession.new(SaveStore.new("user://card-glossary-capture-%s" % Time.get_ticks_usec()))
	session.update_settings(
		{
			"autosave": false,
			"presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}
		}
	)
	var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", "0"))
	if not started.accepted:
		push_error("Capture run did not start")
		return 1
	var shell := GameShell.new()
	shell.session = session
	_tree.root.add_child(shell)
	await _settle()
	shell.show_screen("")
	var view := session.get_view()
	var entered := false
	for node_id in view.run.reachable_node_ids:
		if shell.press("node:" + str(node_id)) and shell.press("map:enter"):
			entered = true
			break
	if not entered:
		push_error("Capture battle node did not open")
		return 1
	await _settle(10)
	var battle := shell.page as BattleScreen
	if battle == null or battle._hand_cards.is_empty():
		push_error("Capture battle has no hand")
		return 1
	var card := _glossary_card(battle)
	if card == null:
		push_error("Capture battle has no card with glossary text")
		return 1
	_tree.root.size = Vector2i(1280, 800)
	await _settle()
	battle = shell.page as BattleScreen
	card = _glossary_card(battle)
	_pin(battle, card)
	await _set_glossary(battle, false)
	await _capture(shell, "battle-card-glossary-collapsed-1280x800")
	await _set_glossary(battle, true)
	await _capture(shell, "battle-card-glossary-open-1280x800")
	_tree.root.size = Vector2i(960, 600)
	session.update_settings(
		{
			"presentation": {"text_scale": 150, "reduced_motion": true, "animation_speed": 0}
		}
	)
	shell._apply_presentation()
	shell.refresh()
	await _settle(10)
	battle = shell.page as BattleScreen
	if battle == null:
		push_error("Capture battle did not survive resize")
		return 1
	card = _glossary_card(battle)
	if card == null:
		push_error("Resized capture battle has no card with glossary text")
		return 1
	_pin(battle, card)
	await _set_glossary(battle, true)
	await _capture(shell, "battle-card-glossary-open-960x600-150")
	var report := {
		"ok": _captures.size() == 3,
		"captures": _captures,
		"scope": "real battle session; pinned card detail; glossary collapsed/open at 1280x800 100% and 960x600 150%",
	}
	var file := FileAccess.open(_output + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CARD_GLOSSARY_CAPTURE=", _captures.size(), " OK=", report.ok)
	shell.free()
	return 0 if report.ok else 1


func _glossary_card(battle: BattleScreen) -> BattleCard:
	for card in battle._hand_cards:
		var target := battle._card_hover_target(card)
		if not str(target.get("glossary", "")).strip_edges().is_empty():
			return card
	return null


func _pin(battle: BattleScreen, card: BattleCard) -> void:
	battle._pin_card_detail(battle._card_hover_target(card))
	battle._update_hover_window()


func _set_glossary(battle: BattleScreen, open: bool) -> void:
	if battle._glossary_open != open:
		battle._toggle_glossary()
	for _frame in 3:
		await _tree.process_frame


func _capture(shell: GameShell, label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _output + "/" + label + ".png"
	var result := shell.get_viewport().get_texture().get_image().save_png(path)
	if result != OK:
		push_error("Unable to save " + path)
	_captures.append(
		{
			"file": label + ".png",
			"size": [_tree.root.size.x, _tree.root.size.y],
			"text_scale": roundi(UiStyle.text_scale * 100),
		}
	)


func _settle(frames: int = 6) -> void:
	for _frame in frames:
		await _tree.process_frame
