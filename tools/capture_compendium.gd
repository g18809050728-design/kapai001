extends RefCounted

var _captures: Array[Dictionary] = []
var _output := ""
var _tree: SceneTree


func run(tree: SceneTree) -> int:
	_tree = tree
	return await _capture_all()


func _capture_all() -> int:
	var arguments := OS.get_cmdline_user_args()
	_output = arguments[1] if arguments.size() > 1 else ""
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A graphical renderer and a new output directory are required")
		return 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	var session := GameSession.new(SaveStore.new("user://compendium-capture-%s" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false, "presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}})
	var shell := GameShell.new()
	shell.session = session
	_tree.root.size = Vector2i(1280, 800)
	_tree.root.add_child(shell)
	await _settle()
	await _capture(shell, "main-menu", "menu", [])
	shell.press("menu:compendium")
	await _settle()
	var page := shell.page as UiCompendiumPage
	var seen := {"cards": [], "monsters": []}
	for kind_name in ["cards", "monsters"]:
		page.show_tab(kind_name)
		page.reset_filters()
		var pages := ceili(page.filtered_ids.size() / float(UiCompendiumPage.PAGE_SIZE))
		for index in pages:
			await _settle()
			seen[kind_name].append_array(page.visible_ids)
			await _capture(shell, "%s-page-%02d-top" % [kind_name, index + 1], kind_name, page.visible_ids)
			page._scroll.scroll_vertical = 100000
			await _settle()
			await _capture(shell, "%s-page-%02d-bottom" % [kind_name, index + 1], kind_name, page.visible_ids)
			if index + 1 < pages:
				page.change_page(1)
	page.reset_filters()
	for id in page.filtered_ids.duplicate():
		page.open_detail(id)
		await _settle()
		await _capture(shell, "monster-" + id, "monster-detail", [id])
		page.detail.close()
		await _settle()
	page.show_tab("cards")
	page.reset_filters()
	var variant_count := 0
	var exam_ids: Array[String] = []
	for id in page.filtered_ids:
		var entry: Dictionary = page._entries.cards[id]
		variant_count += entry.variants.size()
		if entry.definition.has("exam"):
			exam_ids.append(id)
	for id in exam_ids:
		page.open_detail(id)
		await _settle()
		for index in page.detail._entries[id].variants.size():
			page.detail.select_variant(index)
			await _settle()
			await _capture(shell, "card-%s-variant-%s" % [id, index], "card-variant", [id], index)
		page.detail.close()
		await _settle()
	_tree.root.size = Vector2i(960, 600)
	session.update_settings({"presentation": {"text_scale": 150}})
	shell._apply_presentation()
	shell.refresh()
	await _settle()
	page = shell.page as UiCompendiumPage
	for spec in [["cards", "R3-P04-06"], ["cards", "R3-P03-30"], ["monsters", "FY_B4_TASK"]]:
		page.show_tab(spec[0])
		page.reset_filters()
		page.search(spec[1])
		page.open_detail(spec[1])
		await _settle()
		for index in page.detail._entries[spec[1]].get("variants", [{}]).size():
			if spec[0] == "cards":
				page.detail.select_variant(index)
			await _settle()
			await _capture(shell, "long-%s-v%s-top" % [spec[1], index], "long-detail", [spec[1]], index)
			page.detail._scroll.scroll_vertical = 100000
			await _settle()
			await _capture(shell, "long-%s-v%s-bottom" % [spec[1], index], "long-detail", [spec[1]], index)
		page.detail.close()
		await _settle()
	var catalogue := session.get_compendium()
	var valid: bool = seen.cards.size() == 174 and seen.monsters.size() == 60 and variant_count == 374
	for kind_name in ["cards", "monsters"]:
		var unique := {}
		var expected: Array = []
		for id in seen[kind_name]:
			unique[id] = true
		for entry in catalogue.data[kind_name]:
			expected.append(str(entry.id))
		valid = valid and seen[kind_name].size() == unique.size() and seen[kind_name] == expected
	var report := {"ok": valid, "cards": seen.cards, "monsters": seen.monsters, "variants": variant_count, "exam_cards": exam_ids, "captures": _captures, "manifest_id": catalogue.data.manifest_id, "content_hash": catalogue.data.content_hash, "saves": "isolated capture fixture; actual player saves untouched"}
	var file := FileAccess.open(_output + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COMPENDIUM_CAPTURE=", _captures.size(), " OK=", valid)
	shell.free()
	return 0 if valid else 1


func _settle() -> void:
	for _frame in 4:
		await _tree.process_frame


func _capture(shell: GameShell, label: String, kind_name: String, ids: Array, variant: int = -1) -> void:
	await RenderingServer.frame_post_draw
	var path := _output + "/" + label + ".png"
	var result := shell.get_viewport().get_texture().get_image().save_png(path)
	if result != OK:
		push_error("Unable to save " + path)
	_captures.append({"file": label + ".png", "kind": kind_name, "ids": ids.duplicate(), "variant": variant, "size": [_tree.root.size.x, _tree.root.size.y], "text_scale": roundi(UiStyle.text_scale * 100)})
