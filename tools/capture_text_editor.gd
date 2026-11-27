extends RefCounted

var _captures: Array[Dictionary] = []
var _output := ""
var _tree: SceneTree
var _path := ""


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
	_path = "user://text-editor-capture-%s.json" % Time.get_ticks_usec()
	TextOverrides.use_path(_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	var session := GameSession.new(SaveStore.new("user://text-editor-capture-save-%s" % Time.get_ticks_usec()))
	session.update_settings(
		{
			"autosave": false,
			"presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}
		}
	)
	var shell := GameShell.new()
	shell.session = session
	_tree.root.size = Vector2i(1280, 800)
	_tree.root.add_child(shell)
	await _settle()
	await _capture(shell, "main-menu", "menu")
	if not shell.press("menu:text_editor"):
		push_error("Text editor menu entry did not open")
		return 1
	await _settle()
	var page := shell.page as UiTextEditorPage
	if page == null:
		push_error("Text editor page was not installed")
		return 1
	await _capture(shell, "editor-entities-all", "all")
	page.show_tab("cards")
	page.search("")
	page.select_entity("card:R3-C-01")
	page.expand_field("card:R3-C-01:name")
	await _settle()
	await _capture(shell, "editor-card-entity", "cards")
	page.expand_field("card:R3-C-01:detail_0")
	await _settle()
	await _capture(shell, "editor-card-detail-field", "cards")
	page.expand_field("card:R3-C-01:battle_0")
	await _settle()
	await _capture(shell, "editor-card-battle-field", "cards")
	page.expand_field("card:R3-C-01:battle_glossary_0")
	await _settle()
	await _capture(shell, "editor-card-glossary-field", "cards")
	page.search("战斗说明")
	await _settle()
	await _capture(shell, "editor-search-field-hit", "cards")
	page.search("")
	page.show_tab("stories")
	page.select_entity_matching("story:events.V04")
	page.expand_field("story:events.V04:narrative")
	await _settle()
	await _capture(shell, "editor-story-entity", "stories")
	page.show_tab("glossary")
	page.search("")
	page.select_entity("glossary:focus")
	page.expand_field("glossary:focus:body")
	await _settle()
	await _capture(shell, "editor-glossary-entity", "glossary")
	page.show_tab("monsters")
	page.search("")
	page.select_entity("monster:N03")
	page.expand_field("monster:N03:name")
	await _settle()
	await _capture(shell, "editor-monster-entity", "monsters")
	page.show_tab("tutorial")
	page.search("")
	page.select_entity("tutorial:intro_1")
	page.expand_field("tutorial:intro_1:title")
	await _settle()
	await _capture(shell, "editor-tutorial-entity", "tutorial")
	page.show_tab("terms")
	page.search("")
	await _settle()
	await _capture(shell, "editor-terms-entity", "terms")
	page.show_tab("cards")
	page.search("")
	page.select_entity("card:R3-P01-09")
	page.expand_field("card:R3-P01-09:name")
	page.set_field_text("card:R3-P01-09:name", "一气呵成·演示")
	await _settle()
	await _capture(shell, "editor-entity-modified", "cards")
	page.save_entity()
	await _settle()
	await _capture(shell, "editor-entity-saved", "cards")
	page.search("definitely-no-text-result")
	await _settle()
	await _capture(shell, "editor-entity-empty", "cards")
	page.search("")
	page.show_tab("all")
	_tree.root.size = Vector2i(960, 600)
	session.update_settings({"presentation": {"text_scale": 150, "reduced_motion": true, "animation_speed": 0}})
	shell._apply_presentation()
	shell.refresh()
	await _settle()
	page = shell.page as UiTextEditorPage
	page.show_tab("cards")
	page.search("R3-C-01")
	page.select_entity_matching("card:R3-C-01")
	await _settle()
	await _capture(shell, "editor-card-960-150", "cards")
	var report := {
		"ok": _captures.size() >= 11,
		"captures": _captures,
		"override_path": _path,
		"scope": "entity-first main menu/editor; isolated session and override file",
	}
	var file := FileAccess.open(_output + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TEXT_EDITOR_CAPTURE=", _captures.size(), " OK=", report.ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	shell.free()
	return 0 if report.ok else 1


func _settle() -> void:
	for _frame in 6:
		await _tree.process_frame


func _capture(shell: GameShell, label: String, tab: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _output + "/" + label + ".png"
	var result := shell.get_viewport().get_texture().get_image().save_png(path)
	if result != OK:
		push_error("Unable to save " + path)
	var page := shell.page as UiTextEditorPage
	_captures.append(
		{
			"file": label + ".png",
			"tab": tab,
			"query": page.query if page != null else "",
			"selected": page.selected_id if page != null else "",
			"expanded": page._expanded_field if page != null else "",
			"size": [_tree.root.size.x, _tree.root.size.y],
			"text_scale": roundi(UiStyle.text_scale * 100),
		}
	)
