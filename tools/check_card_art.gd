extends SceneTree

const OUT := "res://artifacts/verification/card-art-20261104/usage/render"
var failures: Array[String] = []
var screenshots: Array[String] = []


func _initialize() -> void:
	call_deferred("_check_art")


func _check_art() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/card-art-assets-v3.json"))
	var assets: Array = manifest.get("assets", [])
	_check(assets.size() == 174, "all 174 card images are recorded")
	var content: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/four_year/definitions/cards.json"))
	var runtime_ids: Array[String] = []
	var asset_ids: Array[String] = []
	for card in content:
		if str(card.id).begins_with("R3-"):
			runtime_ids.append(str(card.id))
	for asset in assets:
		var id := str(asset.asset_id)
		asset_ids.append(id)
		var texture := UiStyle.texture(id)
		_check(bool(asset.selected), "selected: " + id)
		_check(str(UiStyle.LABELS.data.textures.get(id, "")) == "res://" + str(asset.output), "installed index: " + id)
		_check(texture != null, "texture loads: " + id)
		if texture != null:
			_check(texture.get_size() == Vector2(480, 360), "texture dimensions: " + id)
			_check(texture == UiStyle.texture(id), "texture cache is reused: " + id)
	runtime_ids.sort()
	asset_ids.sort()
	_check(runtime_ids == asset_ids, "exact runtime card coverage without duplicate IDs")
	_check(UiStyle.texture("K01") != null, "legacy card image still loads")
	for id in ["P01", "P02", "P03", "P04"]:
		var session := GameSession.new(SaveStore.new("user://card-art-" + id))
		session.update_settings({"autosave": false, "audio": {"Master": 100, "Music": 70, "Ambience": 50, "SFX": 80, "UI": 70, "muted": true}})
		var started := session.start_run(StartRunRequest.new(id, &"normal", "campus_four_year", "42"))
		_check(started.accepted, "start four-year character: " + id)
		var shell := GameShell.new()
		shell.session = session
		root.add_child(shell)
		shell.show_screen("")
		var view := session.get_view()
		_check(shell.press("node:" + str(view.run.reachable_node_ids[0])), "enter first battle: " + id)
		_check(shell.page is BattleScreen, "actual battle screen: " + id)
		var battle := shell.page as BattleScreen
		if battle != null:
			for card in battle._hand_cards:
				_check(UiStyle.texture(str(card.card_data.definition_id)) != null, "actual hand uses installed image: " + id)
		await _save(id + "-battle-1280")
		root.size = Vector2i(960, 600)
		await _save(id + "-battle-960")
		root.size = Vector2i(1280, 800)
		shell.free()
		await process_frame
	await _check_flow_usage(content)
	var report := {"checked_textures": assets.size(), "rendered_characters": 4, "screenshots": screenshots, "failures": failures, "scope": "texture import, actual initial battles and controlled read-only page fixtures; not complete gameplay acceptance"}
	var file := FileAccess.open(OUT.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	for failure in failures:
		push_error(failure)
	print("CARD_ART_CHECK=" + ("passed" if failures.is_empty() else "failed"))
	quit(0 if failures.is_empty() else 1)


func _check_flow_usage(content: Array) -> void:
	var session := GameSession.new(SaveStore.new("user://card-art-flow"))
	session.update_settings({"autosave": false})
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted, "flow fixture starts")
	var helper = load("res://tests/suites/test_ui_shell_pages.gd").new()
	var before: String = helper.fingerprint(session)
	var base: Dictionary = session.get_view().run.duplicate(true)
	var ids: Array[String] = ["R3-P01-09", "R3-P01-23", "R3-P01-40"]
	var details: Dictionary = {}
	for card in content:
		if ids.has(str(card.id)):
			details[str(card.id)] = card.duplicate(true)
	var page := UiFlowPage.new()
	page.theme = UiStyle.make_theme()
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for kind in ["reward", "shop", "event", "grand", "service", "rest", "deck"]:
		var fixture := base.duplicate(true)
		page.screen = kind if kind in ["reward", "shop", "event", "rest"] else "campaign"
		if kind == "reward":
			fixture.pending_reward = {"offer_id": "art-reward", "items": [{"item_id": "cards", "kind": "card", "status": "pending", "candidates": ids, "candidate_details": details}]}
		elif kind == "shop":
			var stocks: Array = []
			for id in ids:
				stocks.append({"stock_id": id, "definition_id": id, "kind": "card", "price": 30, "sold": false, "detail": details[id]})
			fixture.shop = {"shop_id": "art-shop", "stocks": stocks, "removal": {"price": 50, "used": 0, "max": 1, "minimum_deck_size": 8}}
		elif kind == "event":
			fixture.event = {"event_instance_id": "art-event", "options": [{"option_id": "gain", "effects": [{"op": "gain_card", "amount": 1}], "candidates": {"0": ids}}]}
		elif kind == "rest":
			fixture.rest = {"options": [{"option_id": "upgrade", "needs_card": true}]}
		else:
			fixture.campaign_offer = {"offer_id": "art-" + kind, "kind": kind, "candidates": ids if kind == "grand" else [], "details": details, "node_meta": {"subtype": "L"}, "service_cost": 20}
		page.render(fixture)
		if kind == "rest":
			_check(page.press("rest:option:upgrade"), "rest upgrade selection works")
		if kind == "deck":
			_check(page.press("inspect:deck"), "deck inspector opens")
		var expected: Array = ids if kind in ["reward", "shop", "event", "grand"] else base.cards.map(func(card): return str(card.definition_id))
		var found: Array[String] = []
		for node in page.find_children("*", "TextureRect", true, false):
			var id := str(node.get_meta("art_id", ""))
			if not expected.has(id):
				continue
			found.append(id)
			_check(node.texture == UiStyle.texture(id), "page uses matching card image: " + kind + "/" + id)
			_check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "art preserves pointer actions: " + kind)
		for id in expected:
			_check(found.has(str(id)), "page includes card art: " + kind + "/" + str(id))
		if kind == "reward":
			_check(page.press("reward:cards:pick:" + ids[0]), "image reward selection works")
		_check(helper.fingerprint(session) == before, "render and local choices preserve state/RNG/revision: " + kind)
		await _save(kind + "-1280")
		root.size = Vector2i(960, 600)
		await _save(kind + "-960")
		_check(page.body.size.x <= page.size.x + 1, "page fits logical viewport at narrow window size: " + kind)
		root.size = Vector2i(1280, 800)
		page._close_inspector()
	page.free()
	session.free()


func _save(label: String) -> void:
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
	_check(code == OK, "save rendered view: " + label)
	if code == OK:
		screenshots.append(label + ".png")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
