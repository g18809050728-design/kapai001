extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _catalog: ContentDB
var _path := ""
var _previous_path := ""


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	_previous_path = TextOverrides.current_path()
	_path = "user://text-editor-test-%s-%s.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	TextOverrides.use_path(_path)
	_catalog = ContentDB.new("res://data/four_year")
	_check(_catalog.load(RelicPilot.ROSTER).ok, "real production catalogue loads")
	var built := TextLibrary.build(_catalog)
	_check(built.ok, "text library builds from production data")
	if built.ok:
		_check_library(built.data)
		await _exercise_ui(built.data)
		await _active_run_check()
	_catalog = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	TextOverrides.use_path(_previous_path)
	UiStyle.text_scale = 1.0
	UiStyle.reduced_motion = false
	tree.root.size = old_size
	var report := {
		"checks": _checks,
		"failures": _failures,
		"entries": built.data.counts if built.ok else {},
		"scope": "actual main menu, production definitions, isolated text override file; no real save or player override file touched",
	}
	print("TEXT_EDITOR_CHECKS=", JSON.stringify(report))
	return _failures


func _check_library(data: Dictionary) -> void:
	var entries: Array = data.get("entries", [])
	var counts: Dictionary = data.get("counts", {})
	_check(entries.size() == int(counts.get("all", -1)), "counts cover every entry")
	var labels: Dictionary = UiStyle.LABELS.data.get("labels", {})
	var rx_ids := _catalog.get_candidates({"kind": "relic"})
	var label_total := labels.keys().filter(func(id): return not RelicPilot.is_retired(id)).size() + 6
	label_total += rx_ids.filter(func(id): return not labels.has(id)).size()
	_check(int(counts.get("names", 0)) == label_total, "active labels include RX names and omit retired FY")
	_check(int(counts.get("story", 0)) == 34, "all story title/location/narrative/option fields are present")
	_check(int(counts.get("glossary", 0)) == UiGlossary.ENTRIES.size() * 4, "all glossary fields are present")
	var compendium := CompendiumView.build(_catalog)
	_check(compendium.ok, "production card faces resolve for description defaults")
	if compendium.ok:
		var variants := 0
		for card in compendium.data.cards:
			for variant in card.variants:
				if not bool(variant.get("exam", false)):
					variants += 1
		var relic_count := _catalog.get_candidates({"kind": "relic"}).size()
		var passive_count := _catalog.get_candidates({"kind": "character"}).size()
		_check(
			int(counts.get("descriptions", 0)) == variants * 2 + relic_count + passive_count,
			"every base/upgraded card detail, battle detail, relic and passive description exists"
		)
	var seen: Dictionary = {}
	for entry in entries:
		var uid := str(entry.get("uid", ""))
		_check(not uid.is_empty(), "entry uid is non-empty")
		_check(not seen.has(uid), "entry uid is unique: " + uid)
		seen[uid] = true
		_check(entry.get("default") is String, "entry default is a string: " + uid)
		_check(not str(entry.get("default", "")).is_empty(), "entry default is readable: " + uid)
		_check(not str(entry.get("title", "")).is_empty(), "entry has a browsing title: " + uid)
	for id in _catalog.get_candidates({"kind": "card"}):
		_check(seen.has("card:%s:0:detail" % id), "card base detail exists: " + str(id))
		_check(seen.has("card:%s:0:battle" % id), "card base battle detail exists: " + str(id))
	for id in _catalog.get_candidates({"kind": "relic"}):
		_check(seen.has("relic:" + str(id)) and seen.has("label:" + str(id)), "relic name and description exist: " + str(id))
	_check(not seen.has("relic:FY_Y1_1") and not seen.has("label:FY_Y1_1"), "retired relic text is not editable")
	for id in _catalog.get_candidates({"kind": "character"}):
		var definition: Dictionary = _catalog.get_definition("character", id).data
		var passive_id := str(definition.get("passive", {}).get("id", ""))
		_check(seen.has("passive:" + passive_id), "passive description exists: " + passive_id)
	_check(seen.has("label:P01") and seen.has("label:R3-C-01"), "label entries use stable definition IDs")
	_check(seen.has("story:events.V01.narrative"), "event narrative entry exists")
	_check(seen.has("glossary:focus.body"), "glossary body entry exists")
	_check(UiStyle.label("P01") == "林序", "clean library does not change normal labels")
	_check(UiStyle.label("status.inspiration.name") == "灵感", "dotted status keys keep their canonical fallback")
	_check(UiStyle.label("task.n01.intent.pressure5") == "施加压力", "dotted task intent keys still resolve")


func _session() -> GameSession:
	var session := GameSession.new(
		SaveStore.new("user://text-editor-saves-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	)
	_check(
		session.update_settings(
			{
				"autosave": false,
				"presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}
			}
		).ok,
		"isolated settings accepted"
	)
	return session


func _exercise_ui(data: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.size = Vector2i(1280, 800)
	var session := _session()
	var shell: GameShell = _helpers.attach_shell(session)
	await _frames()
	var before := SnapshotCodec.canonical_json(session.get_view().to_dictionary())
	_check(shell.page._buttons.has("menu:text_editor"), "main menu exposes the text editor entry")
	_check(shell.press("menu:text_editor"), "main menu entry opens through the real button")
	await _frames()
	_check(shell.page is UiTextEditorPage, "installed page is the text editor")
	var page: UiTextEditorPage = shell.page
	_check(page.library.size() == data.entries.size(), "page receives the complete library")
	_check(page.filtered.size() == data.entries.size(), "unfiltered view exposes every entry")
	_check(page.visible_entries.size() == UiTextEditorPage.BATCH_SIZE, "continuous list starts with one batch")
	_check(page._buttons.has("text_editor:save"), "save action is visible")
	_check(page._buttons.has("text_editor:back"), "back action is visible")
	_check(page._buttons["text_editor:save"].size.y >= 44, "save target is at least 44 pixels")
	_search_checks(page)
	await _edit_checks(page, session, before)
	await _reset_checks(page)
	await _persistence_checks(page)
	await _guard_and_state_checks(shell, page)
	await _layout_checks(shell, data)
	await _frames()
	var view := session.get_view()
	_check(str(view.run_id) == "null" or view.run_id == null, "editor never starts a run")
	_check(view.revision == 0, "editor never changes the domain revision")
	_check(
		SnapshotCodec.canonical_json(view.to_dictionary()) == before,
		"text edits do not mutate the session view"
	)
	if shell.page is UiTextEditorPage:
		shell.page._request_back()
		await _frames()
	shell.free()
	await _frames()


func _active_run_check() -> void:
	var session := _session()
	var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42"))
	_check(started.accepted, "isolated active run starts for editor isolation")
	if not started.accepted:
		return
	var before := SnapshotCodec.canonical_json(session.get_view().to_dictionary())
	var shell: GameShell = _helpers.attach_shell(session)
	await _frames()
	_check(shell.press("menu:text_editor"), "editor opens while a run is active")
	await _frames()
	var page: UiTextEditorPage = shell.page
	_check(page != null and page.select_entry("label:P01"), "active-run editor can select text")
	page.set_editor_text("运行中测试")
	page.save_changes()
	_check(UiStyle.label("P01") == "运行中测试", "active-run edit updates display text")
	_check(
		SnapshotCodec.canonical_json(session.get_view().to_dictionary()) == before,
		"editing with an active run preserves run, battle, RNG, revision and event log"
	)
	page._request_back()
	await _frames()
	shell.free()
	await _frames()


func _search_checks(page: UiTextEditorPage) -> void:
	page.search("R3-C-01")
	_check(_has_uid(page, "label:R3-C-01"), "search finds a definition label by ID")
	_check(_has_uid(page, "card:R3-C-01:0:detail"), "search finds card detail text by ID")
	page.search("写作业")
	_check(_has_uid(page, "label:R3-C-01"), "search finds a label by Chinese title")
	page.search("宿舍断电")
	_check(_has_uid(page, "story:events.V04.narrative"), "search finds story text by title")
	page.show_tab("story")
	page.search("")
	_check(page.filtered.size() == 34, "story tab contains all story fields")
	_check(page.selected_uid.begins_with("story:"), "tab switch selects the first visible story entry")
	page.search("断电")
	_check(not page.filtered.is_empty(), "story tab intersects the query")
	page.show_tab("names")
	page.search("")
	page.set_filter("人物")
	_check(not page.filtered.is_empty(), "name category filter has character labels")
	for entry in page.filtered:
		_check(entry.category == "人物", "name filter only returns the chosen category")
	page.set_filter("")
	page.show_tab("descriptions")
	page.set_filter("卡牌")
	_check(not page.filtered.is_empty(), "description tab has card texts")
	for entry in page.filtered:
		_check(entry.category == "卡牌", "description filter only returns cards")
	page.set_filter("")
	page.show_tab("glossary")
	_check(page.filtered.size() == UiGlossary.ENTRIES.size() * 4, "glossary tab has every editable field")
	page.search("definitely-no-text-editor-result")
	_check(page.filtered.is_empty(), "empty search produces no entries")
	_check(page.selected_uid.is_empty() and page.editor_text().is_empty(), "empty search clears the editor state")
	_check(page._buttons.has("text_editor:back"), "empty results keep navigation")
	page.search("")
	page.show_tab("all")
	page.select_entry("label:P03")
	page.set_editor_text("独特检索测试")
	page.search("独特检索测试")
	_check(_has_uid(page, "label:P03"), "search also covers the current draft text")
	page._undo_entry()
	page.search("")
	page.show_tab("all")


func _edit_checks(page: UiTextEditorPage, session: GameSession, before: String) -> void:
	_check(page.select_entry("label:P01"), "label entry is selectable")
	_check(page.editor_text() == "林序", "real label text reaches the editor")
	page.set_editor_text("林序·测试")
	_check(page.dirty_count() == 1, "label edit is marked dirty")
	page.save_changes()
	_check(TextOverrides.text("label:P01", "") == "林序·测试", "label override is stored")
	_check(UiStyle.label("P01") == "林序·测试", "label override applies to the live UI")
	_check(page.dirty_count() == 0, "save clears the dirty state")
	_check(FileAccess.file_exists(_path), "override file exists on disk")
	_check(
		SnapshotCodec.canonical_json(session.get_view().to_dictionary()) == before,
		"label edit leaves the session untouched"
	)
	page.show_tab("story")
	_check(page.select_entry("story:events.V01.narrative"), "story entry is selectable")
	page.set_editor_text("测试叙述\n第二段")
	page.save_changes()
	_check(
		CampusRoomIllustration.narrative("E", "V01") == "测试叙述\n第二段",
		"story override keeps line breaks and applies to the event narrative"
	)
	page.show_tab("glossary")
	_check(page.select_entry("glossary:focus.body"), "glossary entry is selectable")
	page.set_editor_text("测试专注说明")
	page.save_changes()
	_check(UiGlossary.describe("focus").contains("测试专注说明"), "glossary override applies")
	page.show_tab("descriptions")
	_check(page.select_entry("card:R3-C-01:0:detail"), "card detail is selectable")
	page.set_editor_text("测试卡牌说明")
	page.save_changes()
	var face := BattleCardRules.new(_catalog).resolve_face(
		BattleState.new({"card_by_id": {"R3-C-01": {"definition_id": "R3-C-01", "upgrade_level": 0}}}),
		"R3-C-01"
	)
	_check(face.ok, "card face resolves for the override check")
	if face.ok:
		_check(UiContentText.describe_card(face.data) == "测试卡牌说明", "card detail override applies")
	_check(page.select_entry("card:R3-C-01:0:battle"), "card battle detail is selectable")
	page.set_editor_text("测试战斗说明")
	page.save_changes()
	if face.ok:
		_check(
			UiContentText.describe_battle_card(face.data) == "测试战斗说明",
			"battle detail override applies without touching the face"
		)
	_check(page.select_entry("relic:RX-C01"), "relic description is selectable")
	page.set_editor_text("测试饰品说明")
	page.save_changes()
	var relic: Dictionary = _catalog.get_definition("relic", "RX-C01").data
	_check(UiContentText.describe_relic(relic) == "测试饰品说明", "relic override applies")
	_check(page.select_entry("passive:r3_p01_link_replay"), "passive description is selectable")
	page.set_editor_text("测试被动说明")
	page.save_changes()
	_check(
		UiContentText.describe_character_passive("r3_p01_link_replay") == "测试被动说明",
		"passive override applies"
	)
	_check(TextOverrides.count() == 7, "seven independent overrides coexist")


func _reset_checks(page: UiTextEditorPage) -> void:
	page.show_tab("names")
	page.select_entry("label:P01")
	page._reset_entry()
	page.save_changes()
	_check(UiStyle.label("P01") == "林序", "single-entry reset restores the original label")
	_check(TextOverrides.count() == 6, "single reset removes only one override")
	page._request_reset_all()
	page._request_reset_all()
	page.save_changes()
	_check(TextOverrides.count() == 0, "reset-all clears every override")
	_check(CampusRoomIllustration.narrative("E", "V01").begins_with("最后一节课"), "story reset restores original text")
	_check(UiGlossary.describe("focus").contains("每回合出牌的主要成本"), "glossary reset restores original text")
	var face := BattleCardRules.new(_catalog).resolve_face(
		BattleState.new({"card_by_id": {"R3-C-01": {"definition_id": "R3-C-01", "upgrade_level": 0}}}),
		"R3-C-01"
	)
	if face.ok:
		_check(
			UiContentText.describe_card(face.data).begins_with("作业 · 专注"),
			"card reset restores generated text"
		)


func _persistence_checks(page: UiTextEditorPage) -> void:
	page.show_tab("names")
	page.select_entry("label:P01")
	page.set_editor_text("持久化测试")
	page.save_changes()
	TextOverrides.use_path(_path)
	TextOverrides.reload_from_disk()
	_check(UiStyle.label("P01") == "持久化测试", "saved text survives a fresh load")
	_check(TextOverrides.last_error().is_empty(), "valid override file loads without an error")
	var bad := _path + ".bad"
	var file := FileAccess.open(bad, FileAccess.WRITE)
	file.store_string("{not-json")
	file.close()
	TextOverrides.use_path(bad)
	_check(UiStyle.label("P01") == "林序", "corrupt override file falls back to original text")
	_check(not TextOverrides.last_error().is_empty(), "corrupt override file is reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))
	TextOverrides.use_path(_path)
	_check(UiStyle.label("P01") == "持久化测试", "valid file still loads after rejecting a corrupt one")


func _guard_and_state_checks(shell: GameShell, page: UiTextEditorPage) -> void:
	page.show_tab("names")
	page.search("P01")
	page.select_entry("label:P01")
	page.set_editor_text("未保存内容")
	page._request_back()
	_check(shell._ui_screen == "text_editor", "unsaved edit requires a second back action")
	_check(page._exit_armed, "first back arms the discard warning")
	page._request_back()
	await _frames()
	_check(shell._ui_screen == "menu", "second back returns to the main menu")
	_check(UiStyle.label("P01") == "持久化测试", "discarded draft did not change saved text")
	_check(shell.press("menu:text_editor"), "editor reopens from the menu")
	await _frames()
	page = shell.page
	_check(page.tab == "names" and page.query == "P01" and page.selected_uid == "label:P01", "tab, query and selection are restored")
	page.show_tab("all")
	page.search("")
	await _frames()
	page._left_scroll.scroll_vertical = 600
	await _frames()
	page._request_back()
	await _frames()
	_check(shell.press("menu:text_editor"), "editor reopens for scroll restore")
	await _frames()
	page = shell.page
	_check(page.tab == "all" and page._left_scroll.scroll_vertical > 0, "list scroll position is restored")
	page.show_tab("names")
	page.search("")
	page.select_entry("label:P02")
	page.set_editor_text("许知微·测试")
	var event := InputEventKey.new()
	event.pressed = true
	event.ctrl_pressed = true
	event.keycode = KEY_S
	page._input(event)
	_check(TextOverrides.text("label:P02", "") == "许知微·测试", "Ctrl+S saves without a visible button press")
	# Return to a clean editor state for the layout checks.
	page._request_back()
	await _frames()


func _layout_checks(shell: GameShell, data: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for scale in [100, 125, 150]:
			UiStyle.text_scale = float(scale) / 100.0
			if not (shell.page is UiTextEditorPage):
				_check(shell.press("menu:text_editor"), "editor opens for layout check")
				await _frames()
			var page: UiTextEditorPage = shell.page
			page.initial_state = {}
			page.render(data)
			await _frames()
			_check(page.size.x > 0 and page.size.y > 0, "page lays out at %s / %d%%" % [str(dimensions), scale])
			_check(
				page._left_scroll.size.x > 0 and page._left_scroll.size.y > 0,
				"list pane is visible at %s / %d%%" % [str(dimensions), scale]
			)
			_check(page._text_edit.size.y >= 140, "editor field is usable at %s / %d%%" % [str(dimensions), scale])
			_check(page._buttons["text_editor:save"].size.y >= 44, "save remains at least 44px at %s / %d%%" % [str(dimensions), scale])
			_check(page._buttons["text_editor:back"].size.y >= 44, "back remains at least 44px at %s / %d%%" % [str(dimensions), scale])
			_check(page._buttons.has("text_editor:save"), "save action survives relayout")
			page.search("")
			page.show_tab("all")
			_check(page.filtered.size() == data.entries.size(), "relayout keeps the full library searchable")
			if shell.page is UiTextEditorPage:
				shell.page._request_back()
				await _frames()
	UiStyle.text_scale = 1.0


func _has_uid(page: UiTextEditorPage, uid: String) -> bool:
	for entry in page.filtered:
		if str(entry.get("uid", "")) == uid:
			return true
	return false


func _frames() -> void:
	for _index in 5:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
