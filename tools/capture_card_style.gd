extends SceneTree

## Art-only acceptance probe: production cards, real views, isolated session stores.
var output := ""
var before := false
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var helper: RefCounted
var definitions := {}
var expected: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1 or DisplayServer.get_name() == "headless":
		push_error("Graphical renderer and a fresh output path are required")
		quit(1)
		return
	output = args[0]
	before = args.size() > 1 and args[1] == "before"
	if FileAccess.file_exists(output.path_join("report.json")):
		push_error("Retain prior evidence; choose a new output directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join("faces")))
	root.title = "174卡新插画核对 · 独立存档"
	helper = load("res://tests/suites/test_ui_shell_pages.gd").new()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/four_year/manifests/campus_four_year.json"))
	expected = manifest.enabled.card
	for definition in JSON.parse_string(FileAccess.get_file_as_string("res://data/four_year/definitions/cards.json")):
		definitions[definition.id] = definition
	_check(expected.size() == 174, "174 production IDs")
	for id in expected:
		var texture := UiStyle.texture(str(id))
		_check(texture != null and texture.get_size() == Vector2(480, 360), "exact texture size " + str(id))
		_check(texture == UiStyle.texture(str(id)), "cached shared texture " + str(id))
	await _compendium()
	await _battles()
	await _flows()
	UiStyle.text_scale = 1.0
	UiStyle.reduced_motion = false
	helper = null
	for _frame in 8:
		await process_frame
	var report := {"ok": failures.is_empty(), "before": before, "checks": checks, "failures": failures, "captures": captures,
		"scope": "production 174 textures and card variants; full card catalogue and production initial battles; controlled read-only room fixtures, not complete gameplay acceptance",
		"player_saves": "untouched; isolated SaveStore only"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for failure in failures:
		push_error(failure)
	print("CARD_STYLE_RESULT=", JSON.stringify({"ok": failures.is_empty(), "checks": checks.size(), "captures": captures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _session(suffix: String) -> GameSession:
	var session := GameSession.new(SaveStore.new("user://card-style-%s-%s-%s" % [suffix, OS.get_process_id(), Time.get_ticks_usec()]))
	session.update_settings({"autosave": false, "presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0},
		"audio": {"Master": 0, "Music": 0, "Ambience": 0, "SFX": 0, "UI": 0, "muted": true}})
	return session


func _scale(session: GameSession, shell: GameShell, dimensions: Vector2i, text_scale: int) -> void:
	root.size = dimensions
	session.update_settings({"presentation": {"text_scale": text_scale}})
	shell._apply_presentation()
	shell.refresh()
	await _settle()


func _compendium() -> void:
	root.size = Vector2i(1280, 800)
	var session := _session("catalogue")
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	var stable: String = helper.fingerprint(session)
	_check(shell.press("menu:compendium"), "normal menu opens compendium")
	await _settle()
	var page := shell.page as UiCompendiumPage
	_check(page != null, "production compendium page")
	if page == null:
		shell.free()
		return
	if not before:
		var seen: Array = []
		while true:
			await _settle()
			seen.append_array(page.visible_ids)
			var page_number := int(page._states.cards.page) + 1
			await _save("cards-page-%02d-top" % page_number, "production-gallery", page.visible_ids)
			page._scroll.scroll_vertical = 100000
			await _settle()
			await _save("cards-page-%02d-bottom" % page_number, "production-gallery", page.visible_ids)
			if page._buttons["compendium:next"].disabled:
				break
			page.change_page(1)
		_check(seen == expected, "all 174 production gallery IDs exactly once")
		page.reset_filters()
		page.open_detail(str(expected[0]))
		await _settle()
		var variants := 0
		for id in expected:
			page.detail.show_entry(str(id))
			await _settle()
			_check(page.detail._face.model.id == str(id), "production card face identity " + str(id))
			_check(page.detail._face.model.name == CompendiumText.title(page._entries.cards[id]), "visible card title " + str(id))
			await _save("detail-" + str(id), "production-card-detail", [id])
			await _face(page.detail, str(id))
			for index in page.detail._entries[id].variants.size():
				page.detail.select_variant(index)
				variants += 1
				_check(page.detail._face.model.id == str(id) and UiStyle.texture(str(page.detail._face.model.id)) == UiStyle.texture(str(id)), "variant shares exact image %s/%s" % [id, index])
		_check(variants == 374, "374 real base upgrade exam faces reuse original ID artwork")
		page.detail.close()
		await _settle()
	var samples: Array[String] = ["R3-P01-12", "R3-P02-01", "R3-P03-01", "R3-P04-01"]
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for text_scale in [100, 125, 150]:
			await _scale(session, shell, dimensions, text_scale)
			page = shell.page as UiCompendiumPage
			for id in samples:
				page.open_detail(id)
				await _settle()
				_check(page.detail._face.get_global_rect().intersection(shell.get_global_rect()).size.is_equal_approx(page.detail._face.size), "face fits %s/%s/%s" % [id, dimensions.x, text_scale])
				_check(page.detail._buttons["compendium:detail:close"].size.y >= 44, "detail close target %s/%s/%s" % [id, dimensions.x, text_scale])
				await _save("sample-%s-%s-%s" % [id, dimensions.x, text_scale], "production-detail-matrix", [id])
				page.detail.close()
				await _settle()
	_check(helper.fingerprint(session) == stable, "all card browsing preserves domain RNG revision and pending workspace")
	shell.free()
	await _settle()


func _battles() -> void:
	for id in ["P01", "P02", "P03", "P04"]:
		root.size = Vector2i(1280, 800)
		var session := _session("battle-" + id)
		_check(session.start_run(StartRunRequest.new(id, &"normal", "campus_four_year", "32")).accepted, "production run starts " + id)
		var shell := GameShell.new()
		shell.session = session
		root.add_child(shell)
		shell.show_screen("")
		await _settle()
		var node_id := str(session.get_view().run.reachable_node_ids[0])
		_check(helper.enter_node(shell, node_id), "map preview and existing confirmation enter node " + id)
		await _settle()
		_check(shell.page is BattleScreen, "production battle reached " + id)
		if shell.page is BattleScreen:
			var stable: String = helper.fingerprint(session)
			for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
				for text_scale in [100, 125, 150]:
					await _scale(session, shell, dimensions, text_scale)
					var battle := shell.page as BattleScreen
					for card in battle._hand_cards:
						_check(UiStyle.texture(str(card.card_data.definition_id)) != null, "visible hand card image " + str(card.card_data.definition_id))
					await _save("battle-%s-%s-%s" % [id, dimensions.x, text_scale], "normal-initial-battle", [])
			_check(helper.fingerprint(session) == stable, "battle visual matrix preserves state " + id)
		shell.free()
		await _settle()


func _flows() -> void:
	root.size = Vector2i(1280, 800)
	var session := _session("flow")
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "32")).accepted, "room read-only fixture starts")
	var stable: String = helper.fingerprint(session)
	var base: Dictionary = session.get_view().run.duplicate(true)
	var ids: Array[String] = ["R3-P01-12", "R3-P01-23", "R3-P01-40"]
	var details := {}
	for id in ids:
		details[id] = definitions[id].duplicate(true)
	var page := UiExperiencePage.new()
	page.theme = UiStyle.make_theme()
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = dimensions
		for text_scale in [100, 125, 150]:
			UiStyle.text_scale = text_scale / 100.0
			page.theme = UiStyle.make_theme()
			for kind in ["reward", "shop", "event", "grand", "rest", "deck"]:
				var fixture := base.duplicate(true)
				page.screen = kind if kind in ["reward", "shop", "event", "rest"] else "campaign"
				if kind == "reward":
					fixture.pending_reward = {"offer_id": "card-style", "items": [{"item_id": "cards", "kind": "card", "status": "pending", "candidates": ids, "candidate_details": details}]}
				elif kind == "shop":
					var stocks: Array = []
					for cid in ids:
						stocks.append({"stock_id": cid, "definition_id": cid, "kind": "card", "price": 45, "sold": false, "detail": details[cid]})
					fixture.shop = {"shop_id": "card-style", "stocks": stocks, "removal": {"price": 50, "used": 0, "max": 1, "minimum_deck_size": 8}}
				elif kind == "event":
					fixture.event = {"definition_id": "V01", "event_instance_id": "card-style", "options": [{"option_id": "gain", "effects": [{"op": "gain_card", "amount": 1}], "candidates": {"0": ids}, "candidate_details": details}]}
				elif kind == "rest":
					fixture.rest = {"options": [{"option_id": "upgrade", "needs_card": true}]}
				else:
					fixture.campaign_offer = {"offer_id": "card-style-" + kind, "kind": kind, "candidates": ids if kind == "grand" else [], "details": details, "node_meta": {"subtype": "L"}, "service_cost": 20}
				page.render(fixture)
				if kind == "grand":
					_check(page.press("campaign:category:cards"), "year reward card category opens")
				if kind == "event":
					_check(page.press("event:gain"), "event gain candidates open")
				if kind == "rest":
					_check(page.press("rest:option:upgrade"), "upgrade picker opens")
				if kind == "deck":
					_check(page.press("inspect:deck"), "deck inspector opens")
				await _settle()
				if kind in ["reward", "shop", "event", "grand"]:
					var found: Array[String] = []
					for child in page.find_children("*", "", true, false):
						if child is UiOfferCard:
							found.append(child.definition_id)
							_check(child._face is CardFaceView and child._face.mouse_filter == Control.MOUSE_FILTER_IGNORE, "production offer uses shared face without intercepting input " + kind)
					for cid in ids:
						_check(found.has(cid), "production room includes requested card %s/%s" % [kind, cid])
				_check(helper.fingerprint(session) == stable, "read-only room fixture " + kind)
				await _save("room-%s-%s-%s" % [kind, dimensions.x, text_scale], "controlled-room-fixture", ids)
				page._close_inspector()
	page.free()
	session.free()
	await _settle()


func _face(detail: UiCompendiumDetail, id: String) -> void:
	await RenderingServer.frame_post_draw
	var rect := detail._face.get_global_rect()
	var region := Rect2i(Vector2i(rect.position), Vector2i(rect.size))
	var image := root.get_texture().get_image().get_region(region)
	_check(image.save_png(output.path_join("faces/" + id + ".png")) == OK, "actual shared card-face crop " + id)


func _save(label: String, kind: String, ids: Array) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)
	captures.append({"file": label + ".png", "kind": kind, "ids": ids.duplicate(), "size": [root.size.x, root.size.y], "text_scale": roundi(UiStyle.text_scale * 100)})


func _settle() -> void:
	for _frame in 5:
		await process_frame


func _check(value: bool, label: String) -> void:
	checks.append({"ok": value, "label": label})
	if not value:
		failures.append(label)
