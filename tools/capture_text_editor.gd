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
	await _capture(shell, "editor-all", "all")
	page.search("R3-C-01")
	await _settle()
	await _capture(shell, "editor-search-card", "all")
	page.search("宿舍断电")
	await _settle()
	await _capture(shell, "editor-search-story", "all")
	page.search("")
	page.show_tab("names")
	page.set_filter("人物")
	await _settle()
	await _capture(shell, "editor-names-people", "names")
	page.show_tab("descriptions")
	page.set_filter("卡牌")
	await _settle()
	await _capture(shell, "editor-descriptions-cards", "descriptions")
	page.show_tab("story")
	page.set_filter("事件")
	await _settle()
	await _capture(shell, "editor-story", "story")
	page.show_tab("glossary")
	await _settle()
	await _capture(shell, "editor-glossary", "glossary")
	page.show_tab("descriptions")
	page.set_filter("卡牌")
	page.search("")
	page.select_entry("card:R3-P02-31:1:detail")
	await _settle()
	await _capture(shell, "editor-card-detail", "descriptions")
	page._toggle_default()
	await _settle()
	await _capture(shell, "editor-card-default", "descriptions")
	page._toggle_default()
	page.show_tab("story")
	page.select_entry("story:events.V04.narrative")
	await _settle()
	await _capture(shell, "editor-story-detail", "story")
	page.show_tab("names")
	page.set_filter("人物")
	page.select_entry("label:P01")
	page.set_editor_text("林序·编辑器演示")
	await _settle()
	await _capture(shell, "editor-unsaved-label", "names")
	page._save()
	await _settle()
	await _capture(shell, "editor-saved-label", "names")
	page.search("definitely-no-text-result")
	await _settle()
	await _capture(shell, "editor-empty-search", "names")
	page.search("")
	page.show_tab("all")
	_tree.root.size = Vector2i(960, 600)
	session.update_settings({"presentation": {"text_scale": 150, "reduced_motion": true, "animation_speed": 0}})
	shell._apply_presentation()
	shell.refresh()
	await _settle()
	page = shell.page as UiTextEditorPage
	page.show_tab("names")
	page.set_filter("人物")
	page.search("P0")
	await _settle()
	await _capture(shell, "editor-960-150", "names")
	var report := {
		"ok": _captures.size() >= 12,
		"captures": _captures,
		"override_path": _path,
		"scope": "actual main menu and editor page; isolated session and override file",
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
			"selected": page.selected_uid if page != null else "",
			"size": [_tree.root.size.x, _tree.root.size.y],
			"text_scale": roundi(UiStyle.text_scale * 100),
		}
	)
