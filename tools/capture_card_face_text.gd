extends SceneTree

## Evidence capture for the card-face text change: the same six production
## faces before/after, then a real first battle with the new face text.

const OUT := "res://artifacts/verification/card-face-text-20261126"
const IDS := ["R3-C-04", "R3-C-06", "R3-P01-20", "R3-P02-36", "R3-P04-01", "R3-P03-30"]

var captures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A graphical renderer is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	var db := ContentDB.new("res://data/four_year")
	if not db.load(RelicPilot.ROSTER).ok:
		push_error("catalog load failed")
		quit(1)
		return
	var catalogue := CompendiumView.build(db)
	if not catalogue.ok:
		push_error("compendium failed")
		quit(1)
		return
	var faces := {}
	for card in catalogue.data.get("cards", []):
		for variant in card.get("variants", []):
			if int(variant.get("level", 0)) != 0 or bool(variant.get("exam", false)):
				continue
			faces[str(card.id)] = variant.get("face", {})
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if not args.is_empty() else "all"
	if mode in ["all", "gallery"]:
		await _gallery(faces)
	if mode in ["all", "battle"]:
		await _battle()
	var report := {"cards": IDS, "captures": captures, "screenshots": captures.size()}
	var file := FileAccess.open(OUT.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CAPTURE=", JSON.stringify(report))
	quit(0)


func _gallery(faces: Dictionary) -> void:
	var stage := Control.new()
	stage.theme = UiStyle.make_theme()
	root.add_child(stage)
	var background := ColorRect.new()
	background.color = Color("142932")
	background.size = Vector2(1280, 800)
	stage.add_child(background)
	var width := 168.0
	for row in 2:
		var heading := Label.new()
		heading.text = "旧：自动生成短摘要" if row == 0 else "新：可编辑的“说明”字段"
		heading.position = Vector2(24, 12 + row * 392)
		heading.add_theme_font_size_override("font_size", 20)
		heading.add_theme_color_override("font_color", Color("f0dfbb"))
		stage.add_child(heading)
		for index in IDS.size():
			var id := str(IDS[index])
			var face: Dictionary = faces.get(id, {})
			var model := CardDisplayModel.from_card({"definition_id": id, "face": face})
			if row == 0:
				model["summary"] = UiContentText.card_summary(face)
			var view := CardFaceView.new()
			view.configure(model)
			view.position = Vector2(24 + index * 206, 44 + row * 392)
			view.size = Vector2(width, width * 244.0 / 168.0)
			stage.add_child(view)
	for frame in 6:
		await process_frame
	await _save("faces-before-after.png")
	stage.free()
	await process_frame


func _battle() -> void:
	var session := GameSession.new(SaveStore.new("user://card-face-text-%s" % OS.get_process_id()))
	session.update_settings({"autosave": false, "audio": {"Master": 0, "Music": 0, "Ambience": 0, "SFX": 0, "UI": 0, "muted": true}})
	if not session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted:
		push_error("run failed")
		return
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	shell.show_screen("")
	var view := session.get_view()
	shell.press("node:" + str(view.run.reachable_node_ids[0]))
	for _frame in 4:
		await process_frame
	print("entered=", shell.press("map:enter"), " battle=", shell.page is BattleScreen)
	for _frame in 240:
		await process_frame
	await _save("battle-hand.png")
	root.size = Vector2i(960, 600)
	for _frame in 12:
		await process_frame
	await _save("battle-hand-960.png")
	quit(0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		push_error("capture failed: " + name)
		return
	if image.save_png(OUT.path_join(name)) == OK:
		captures.append(name)
	else:
		push_error("save failed: " + name)
