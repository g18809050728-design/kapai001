extends SceneTree

const OUT := "res://artifacts/verification/four-year-20261104/missing-art-complete/views"
var failures: Array[String] = []
var screenshots: Array[String] = []
var checked := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	var records: Dictionary = _json("res://docs/art/missing-art-assets.json")
	_check(records.generated_count == 71 and records.selected_count == 71, "71 generated and installed")
	var seen: Array[String] = []
	for asset in records.assets:
		var id := str(asset.asset_id)
		_check(not seen.has(id), "unique asset: " + id)
		seen.append(id)
		_check(bool(asset.selected), "selected: " + id)
		_check(str(UiStyle.LABELS.data.textures.get(id, "")) == "res://" + str(asset.output), "installed index: " + id)
		var texture := UiStyle.texture(id)
		_check(texture != null, "imported texture: " + id)
		if texture != null:
			var expected := Vector2(288, 360) if asset.category == "portraits" else Vector2(480, 360)
			_check(texture.get_size() == expected, "crop dimensions: " + id)
			_check(texture == UiStyle.texture(id), "cached texture: " + id)
		checked += 1
	var enabled: Dictionary = _json("res://data/four_year/manifests/campus_four_year.json").enabled
	var expected_counts := {"character": 4, "unit": 7, "relic": 16, "task": 56}
	for kind in expected_counts:
		_check(enabled[kind].size() == expected_counts[kind], "active inventory: " + kind)
		for id in enabled[kind]:
			_check(UiStyle.texture(str(id)) != null, "complete enabled coverage: " + str(id))
	for encounter in _json("res://data/four_year/definitions/encounters.json"):
		_check(UiStyle.texture(str(encounter.id)) != null, "encounter shares task art: " + str(encounter.id))
	for id in ["P01", "P04", "K01", "R3-P01-01", "F01", "BG_classroom"]:
		_check(UiStyle.texture(id) != null, "existing artwork retained: " + id)
	await _setup()
	await _battles()
	await _relics()
	var file := FileAccess.open(OUT.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checked_new_textures": checked, "enabled_counts": expected_counts, "screenshots": screenshots, "failures": failures, "scope": "real texture loading and initial battles, controlled read-only encounter/companion/relic fixtures; human acceptance pending"}, "  "))
	file.close()
	for failure in failures:
		push_error(failure)
	print("MISSING_ART_CHECK=" + ("passed" if failures.is_empty() else "failed"))
	quit(0 if failures.is_empty() else 1)


func _setup() -> void:
	var session := GameSession.new(SaveStore.new("user://missing-art-setup"))
	session.update_settings({"autosave": false})
	var helper = load("res://tests/suites/test_ui_shell_pages.gd").new()
	var before: String = helper.fingerprint(session)
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	_check(shell.press("menu:new"), "open real setup")
	_check_art(shell.page, ["P01", "P02", "P03", "P04"], "setup")
	for viewport_size in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = viewport_size
		await _frames()
		await _save("setup-%d-top" % viewport_size.x)
		var scroll: ScrollContainer = shell.page._scroll
		for portrait in shell.page.find_children("*", "TextureRect", true, false):
			if str(portrait.get_meta("art_id", "")) == "P03":
				scroll.scroll_vertical += int(portrait.global_position.y - scroll.global_position.y - 12)
				break
		await _save("setup-%d-middle" % viewport_size.x)
		scroll.scroll_vertical = 0
	_check(helper.fingerprint(session) == before, "setup rendering preserves state/RNG/revision")
	shell.free()
	root.size = Vector2i(1280, 800)
	await process_frame


func _battles() -> void:
	var helper = load("res://tests/suites/test_ui_shell_pages.gd").new()
	for character in ["P02", "P03"]:
		var session := GameSession.new(SaveStore.new("user://missing-art-" + character))
		session.update_settings({"autosave": false})
		_check(session.start_run(StartRunRequest.new(character, &"normal", "campus_four_year", "42")).accepted, "actual run starts: " + character)
		var shell := GameShell.new()
		shell.session = session
		root.add_child(shell)
		shell.show_screen("")
		_check(shell.press("node:" + str(session.get_view().run.reachable_node_ids[0])), "actual first battle: " + character)
		_check(shell.page is BattleScreen, "battle page: " + character)
		var page := shell.page as BattleScreen
		if page != null:
			_check_art(page, [character], "actual battle portrait")
			await _pair(character + "-actual-battle")
			var before: String = helper.fingerprint(session)
			# Public view copies demonstrate later content without altering a live campaign.
			var fixture := page.view.duplicate(true)
			var task_template: Dictionary = fixture.tasks[0].duplicate(true)
			fixture.tasks = []
			for id in ["N13", "E01", "FY_B4_TASK"]:
				var task := task_template.duplicate(true)
				task.definition_id = id
				task.task_id = "art-" + id
				task.phase_count = 3 if id == "FY_B4_TASK" else 1
				task.phase_index = 1
				fixture.tasks.append(task)
			fixture.units = []
			for id in ["R3-U01", "R3-U02", "R3-U03"]:
				fixture.units.append({"unit_id": "art-" + id, "definition_id": id, "vitality": 8, "cooperation": 2, "relax": 1, "guard": 0})
			page.render(fixture)
			_check_art(page, [character, "N13", "E01", "FY_B4_TASK", "R3-U01", "R3-U02", "R3-U03"], "encounters and companions")
			await _pair(character + "-encounter-companion-fixture")
			_check(helper.fingerprint(session) == before, "battle display preserves state/RNG/revision: " + character)
		shell.free()
		await process_frame


func _relics() -> void:
	var session := GameSession.new(SaveStore.new("user://missing-art-relics"))
	session.update_settings({"autosave": false})
	_check(session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42")).accepted, "relic fixture starts")
	var helper = load("res://tests/suites/test_ui_shell_pages.gd").new()
	var before: String = helper.fingerprint(session)
	var fixture: Dictionary = session.get_view().run.duplicate(true)
	var ids: Array[String] = ["FY_Y1_1", "FY_Y1_2", "FY_Y1_3"]
	var details: Dictionary = {}
	for relic in _json("res://data/four_year/definitions/relics.json"):
		if ids.has(str(relic.id)):
			details[str(relic.id)] = relic.duplicate(true)
	fixture.relics = []
	for id in ids:
		fixture.relics.append({"definition_id": id, "relic_id": "art-" + id, "detail": details[id]})
	fixture.campaign_offer = {"offer_id": "missing-art-relic", "kind": "relic", "candidates": ids, "details": details}
	var page := UiFlowPage.new()
	page.screen = "campaign"
	page.theme = UiStyle.make_theme()
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.render(fixture)
	_check_art(page, ids, "relic candidates")
	_check(page.press("campaign:replace:art-" + ids[0]), "local replacement choice works with art")
	_check(helper.fingerprint(session) == before, "replacement selection preserves state/RNG/revision")
	await _pair("relic-candidates")
	for viewport_size in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = viewport_size
		await _frames()
		page._scroll.scroll_vertical = int(page._scroll.get_v_scroll_bar().max_value)
		await _save("relic-candidates-%d-bottom" % viewport_size.x)
	page._scroll.scroll_vertical = 0
	root.size = Vector2i(1280, 800)
	_check(page.press("inspect:relics"), "equipped relic inspector opens")
	_check_art(page, ids, "equipped relics")
	await _pair("relic-inspector")
	_check(helper.fingerprint(session) == before, "relic inspection preserves state/RNG/revision")
	page.free()
	session.free()


func _check_art(page: Node, expected: Array, context: String) -> void:
	var found: Array[String] = []
	for node in page.find_children("*", "TextureRect", true, false):
		var id := str(node.get_meta("art_id", ""))
		if not expected.has(id):
			continue
		found.append(id)
		_check(node.texture != null and node.texture == UiStyle.texture(id), "matching art: " + context + "/" + id)
		_check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "art lets pointer through: " + context + "/" + id)
	for id in expected:
		_check(found.has(str(id)), "visible art node: " + context + "/" + str(id))


func _pair(label: String) -> void:
	for viewport_size in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = viewport_size
		await _save(label + "-%d" % viewport_size.x)
	root.size = Vector2i(1280, 800)


func _frames() -> void:
	for frame in 5:
		await process_frame


func _save(label: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
	_check(code == OK, "saved view: " + label)
	if code == OK:
		screenshots.append(label + ".png")


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
