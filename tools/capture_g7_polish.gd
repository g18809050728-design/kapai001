extends SceneTree

var _output := ""
var _steps: Array[Dictionary] = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_capture")


func _capture() -> void:
	if _output.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	root.size = Vector2i(1280, 800)
	var session := GameSession.new(
		SaveStore.new("user://g7-polish-visual-%s" % Time.get_ticks_usec())
	)
	session.update_settings({"autosave": false})
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	shell.press("menu:new")
	shell.press("setup:start")
	await _save("map", "real production start")
	shell.press("inspect:deck")
	await _save("deck", "real production deck, local overlay")
	shell.press("inspect:close")
	shell.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
	shell.press("battle:deck")
	await _save("battle-deck", "real production battle, local full-deck panel")
	shell.free()
	# Controlled display fixtures use production state and content; no player saves.
	var catalog := ContentDB.new()
	catalog.load("campus_mvp")
	var service := RunService.new(catalog)
	var created := service.create(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	var state: RunState = created.data.state
	state.vitality = state.max_vitality - 2
	var page := UiFlowPage.new()
	page.theme = UiStyle.make_theme()
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = UiStyle.PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	root.move_child(background, 0)
	for node in state.nodes:
		if node.kind not in ["shop", "rest"]:
			continue
		state.current_node_id = node.node_id
		node.status = "active"
		if node.kind == "shop":
			var stocks: Array = []
			for entry in [["card", "K05", 35], ["relic", "A05", 80], ["meal", "", 25]]:
				stocks.append(
					{
						"stock_id": str(entry[0]),
						"kind": entry[0],
						"definition_id": entry[1],
						"price": entry[2],
						"base_price": entry[2],
						"sold": false
					}
				)
			node.context = {
				"shop":
				ShopState.new({"shop_id": "visual-shop", "node_id": node.node_id, "stocks": stocks})
			}
		else:
			node.context = {"used": false, "option_id": ""}
		page.screen = str(node.kind)
		page.render(service.make_view(state))
		if node.kind == "rest":
			page.press("rest:option:upgrade")
		await _save(
			str(node.kind), "controlled display context; production definitions and public RunView"
		)
	page.free()
	background.free()
	var file := FileAccess.open(_output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"screens": _steps, "isolated_storage": true}, "\t"))
	file.close()
	print("G7 polish visual capture passed")
	quit(0)


func _save(label: String, source: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(_output.path_join(label + ".png"))
	_steps.append(
		{"label": label, "source": source, "size": [root.size.x, root.size.y], "save_error": result}
	)
	if result != OK:
		push_error("capture failed: " + label)
		quit(1)
