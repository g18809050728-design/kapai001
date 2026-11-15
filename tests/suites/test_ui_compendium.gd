extends RefCounted

class MissingCatalogueSession:
	extends GameSession
	func get_compendium() -> GameResult:
		return GameResult.failure(ApiError.new(&"CONTENT_INVALID", "compendium.test.missing"))

var _failures: Array[String] = []
var _checks := 0
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _out := ""
var _captures: Array = []
var _catalog: ContentDB


func run() -> Array[String]:
	_out = OS.get_environment("CAMPUS_COMPENDIUM_CAPTURE_OUT")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	_catalog = ContentDB.new("res://data/four_year")
	_check(_catalog.load("campus_four_year").ok, "real production catalogue loads")
	var session := _session()
	if _check_query(session):
		await _browse(session)
	else:
		session.free()
	await _legacy_and_pending()
	await _failure_screen()
	await _pointer_and_keyboard()
	_catalog = null
	tree.root.size = old_size
	_restore_style()
	var report := {"checks": _checks, "failures": _failures, "captures": _captures, "scope": "actual game UI, isolated saves, production definitions; visual review separately recorded"}
	if not _out.is_empty():
		var file := FileAccess.open(_out + "/checks.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("COMPENDIUM_CHECKS=", JSON.stringify(report))
	return _failures


func _restore_style() -> void:
	UiStyle.text_scale = 1


func _check_query(session: GameSession) -> bool:
	var result := session.get_compendium()
	_check(result.ok, "no-run read-only query succeeds")
	if result.ok:
		_check_catalogue(result.data)
	return result.ok


func _session() -> GameSession:
	var session := GameSession.new(SaveStore.new("user://compendium-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]))
	_check(session.update_settings({"autosave": false, "presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}}).ok, "isolated settings accepted")
	return session


func _check_catalogue(data: Dictionary) -> void:
	var card_ids: Array[String] = []
	var monster_ids: Array[String] = []
	var resolver := BattleCardRules.new(_catalog)
	for entry in data.cards:
		card_ids.append(str(entry.id))
		_check(UiStyle.texture(entry.id) != null, "card illustration exists " + entry.id)
		for variant in entry.variants:
			var state := BattleState.new({"card_by_id": {entry.id: {"definition_id": entry.id, "upgrade_level": variant.level}}})
			if variant.exam:
				state.exam_flags.assign([str(entry.definition.exam.condition)])
			var resolved := resolver.resolve_face(state, entry.id)
			var actual: Dictionary = variant.face.duplicate(true)
			actual.erase("related_units")
			actual.erase("related_scenes")
			_check(resolved.ok and SnapshotCodec.canonical_json(actual) == SnapshotCodec.canonical_json(resolved.data), "face equals real resolver " + entry.id + ":" + CompendiumText.variant_name(variant))
			_check(not CompendiumText.card_text(variant).is_empty(), "full readable card explanation " + entry.id)
		if entry.id.begins_with("R3-T"):
			_check(entry.variants.size() == 1, "derived cards do not offer invalid service upgrades " + entry.id)
	for entry in data.monsters:
		monster_ids.append(str(entry.id))
		_check(UiStyle.texture(entry.id) != null and ResourceLoader.exists(EnemyArt.rig_path(entry.id)), "monster art and exact rig exist " + entry.id)
		_check(not entry.terms.is_empty(), "direct or propagated year source exists " + entry.id)
		_check(not entry.sources.is_empty() or not entry.parents.is_empty(), "spawn/member provenance exists " + entry.id)
		var sections := CompendiumText.monster_sections(entry)
		_check(sections.size() >= entry.definition.phases.size() + 1, "all phases and sources are readable " + entry.id)
	_check(card_ids == _catalog.get_candidates({"kind": "card"}) and card_ids.size() == 174, "exact full card ID set")
	_check(monster_ids == _catalog.get_candidates({"kind": "task"}) and monster_ids.size() == 60, "exact full monster ID set, not encounter IDs")
	data.cards[0].definition.cost = 999
	_check(int(_catalog.get_definition("card", card_ids[0]).data.cost) != 999, "snapshot cannot mutate content catalogue")


func _browse(session: GameSession) -> void:
	(Engine.get_main_loop() as SceneTree).root.size = Vector2i(1280, 800)
	var shell: GameShell = _helpers.attach_shell(session)
	await _frames()
	var before := _helpers.fingerprint(session)
	_check(shell.press("menu:compendium"), "top-level menu entry works without a run")
	await _frames()
	_check(shell.page is UiCompendiumPage, "real game compendium page is installed")
	var page := shell.page as UiCompendiumPage
	_check(page.filtered_ids.size() == 174, "all cards unlocked on first opening")
	page = await _continuous_navigation(page, shell)
	await _all_items(page, "cards", 174)
	page.search("R3-T202")
	_check(page.filtered_ids == ["R3-T202"], "derived card searchable by ID")
	page.reset_filters()
	page.set_filter("owner", "T")
	_check(page.filtered_ids == ["R3-T201", "R3-T202"], "derived filter contains both generated cards")
	page.reset_filters()
	page.set_filter("owner", "P03")
	_check(page.filtered_ids.size() == 40, "character filter contains all 40 exclusive cards")
	page.set_filter("type", "work")
	for id in page.filtered_ids:
		_check(_catalog.get_definition("card", id).data.type == "work", "type filter intersects owner")
	page.search("definitely-no-result-xyz")
	_check(page.filtered_ids.is_empty() and page.visible_ids.is_empty() and page._buttons.has("compendium:back"), "empty results keep navigation usable")
	page.reset_filters()
	_check(page.filtered_ids.size() == 174, "reset restores complete list")
	page.show_tab("monsters")
	await _all_items(page, "monsters", 60)
	page.reset_filters()
	page.set_filter("kind", "auxiliary")
	_check(page.filtered_ids.size() == 3 and page.filtered_ids.has("Q0A_3_1"), "summoned auxiliaries are separate visible entries")
	page.set_filter("year", "1")
	_check(page.filtered_ids.has("Q0A_3_1"), "summoned auxiliaries inherit source year")
	page.reset_filters()
	page.set_filter("kind", "boss")
	_check(page.filtered_ids.has("FY_B4_TASK") and page.filtered_ids.has("FY_ROUTE_job_TASK"), "year and route bosses both included")
	page.show_tab("cards")
	_check(page.filtered_ids.size() == 174, "tab restores its own filter state")
	page.search("R3-P02-31")
	page.open_detail("R3-P02-31")
	await _frames()
	_check(is_instance_valid(page.detail), "detail opens")
	if is_instance_valid(page.detail):
		var modal := page.detail
		_check(page._buttons["compendium:back"].disabled, "detail blocks background buttons")
		_check(page._search.focus_mode == Control.FOCUS_NONE, "detail blocks background keyboard focus")
		for index in modal._entries[modal.selected_id].variants.size():
			modal.select_variant(index)
			_check(modal.selected_variant == index, "detail switches real base/upgraded/exam variants")
		modal.close()
		await _frames()
		_check(not page._buttons["compendium:back"].disabled, "detail close restores original button gates")
		_check((Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner() == page._buttons["compendium:item:R3-P02-31"], "detail restores selected item focus")
	page.reset_filters()
	page.show_tab("monsters")
	page.reset_filters()
	# Instantiate each actual installed rig once, with no gameplay commands.
	for id in page.filtered_ids.duplicate():
		page.open_detail(id)
		_check(is_instance_valid(page.detail) and is_instance_valid(page.detail._actor) and is_instance_valid(page.detail._actor.rig), "actual assembled monster model " + id)
		page.detail.close()
		await _frames()
	await _frames()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			(Engine.get_main_loop() as SceneTree).root.size = dimensions
			session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
			shell._apply_presentation()
			shell.refresh()
			await _frames()
			page = shell.page as UiCompendiumPage
			page.show_tab("cards")
			page.reset_filters()
			await _frames()
			await _capture(shell, "cards-%s-%s" % [dimensions.x, scale])
			_check_layout(page, dimensions)
			page.search("R3-P02-31")
			page.open_detail("R3-P02-31")
			await _frames()
			_check_detail_layout(page.detail, dimensions)
			await _capture(shell, "card-detail-%s-%s" % [dimensions.x, scale])
			page.detail._scroll.scroll_vertical = 100000
			await _frames()
			await _capture(shell, "card-detail-bottom-%s-%s" % [dimensions.x, scale])
			_key(KEY_ESCAPE)
			await _frames()
			_check(not is_instance_valid(page.detail), "physical Esc closes detail only")
			page.show_tab("monsters")
			page.reset_filters()
			await _frames()
			await _capture(shell, "monsters-%s-%s" % [dimensions.x, scale])
			_check_layout(page, dimensions)
			page.search("FY_B4_TASK")
			page.open_detail("FY_B4_TASK")
			await _frames()
			_check_detail_layout(page.detail, dimensions)
			_check(not page.detail._motion_enabled, "reduced motion respected")
			await _capture(shell, "monster-detail-%s-%s" % [dimensions.x, scale])
			page.detail._scroll.scroll_vertical = 100000
			await _frames()
			await _capture(shell, "monster-detail-bottom-%s-%s" % [dimensions.x, scale])
			page.detail.close()
			await _frames()
	_check(_helpers.fingerprint(session) == before, "all browsing, rendering and model previews preserve session/state/RNG/revision")
	page.search("N35")
	_check(page.filtered_ids == ["N35"], "monster exact ID search")
	_check(shell.press("compendium:back"), "returns to main menu")
	await _frames()
	_check(shell.press("menu:compendium"), "reopen catalogue")
	await _frames()
	page = shell.page as UiCompendiumPage
	_check(page.tab == "monsters" and page.filtered_ids == ["N35"], "menu return preserves previous tab/search")
	_check(_helpers.fingerprint(session) == before, "menu navigation is read only")
	shell.free()


func _all_items(page: UiCompendiumPage, tab: String, expected: int) -> void:
	page.show_tab(tab)
	page.reset_filters()
	await _frames()
	_check(page.visible_ids.size() == 8, "first local batch has eight thumbnails " + tab)
	var first: Control = page._buttons["compendium:item:" + page.visible_ids[0]]
	var first_id := first.get_instance_id()
	for index in ceili(expected / float(UiCompendiumPage.PAGE_SIZE)) - 1:
		var old_count := page.visible_ids.size()
		var old_position := page._scroll.scroll_vertical
		var bar := page._scroll.get_v_scroll_bar()
		if bar.max_value <= bar.page + 1:
			_wheel(page._scroll.get_global_rect().get_center())
		else:
			page._scroll.scroll_vertical = int(bar.max_value)
		await _frames()
		_check(page.visible_ids.size() == mini(old_count + 8, expected), "bottom appends exactly eight or final partial batch " + tab + ":" + str(index))
		_check(page._buttons["compendium:item:" + page.visible_ids[0]].get_instance_id() == first_id, "append keeps first thumbnail instance")
		_check(first.position.y == 0 and page._scroll.scroll_vertical >= old_position, "append keeps original content order and offset")
		var unique := {}
		for id in page.visible_ids:
			unique[id] = true
		_check(unique.size() == page.visible_ids.size(), "continuous gallery contains no duplicate IDs")
		_check(page._grid.get_child_count() == page.visible_ids.size(), "one thumbnail per loaded ID")
	_check(page.visible_ids == _catalog.get_candidates({"kind": "card" if tab == "cards" else "task"}), "continuous scrolling covers every production ID exactly " + tab)
	var count := page.visible_ids.size()
	page._scroll.scroll_vertical = int(page._scroll.get_v_scroll_bar().max_value)
	await _frames()
	_check(page.visible_ids.size() == count, "end of gallery cannot duplicate the final batch")


func _continuous_navigation(page: UiCompendiumPage, shell: GameShell) -> UiCompendiumPage:
	page.reset_filters()
	await _frames()
	_check(not page._buttons.has("compendium:previous") and not page._buttons.has("compendium:next"), "gallery has no previous/next page buttons")
	_check(page.visible_ids.size() == 8 and page._grid.columns <= 4, "eight-card batch uses at most four columns")
	var first: Control = page._buttons["compendium:item:" + page.visible_ids[0]]
	var identity := first.get_instance_id()
	var position := first.position
	for tick in 20:
		_wheel(page._scroll.get_global_rect().get_center())
		await _frames()
		if page.visible_ids.size() > 8:
			break
	_check(page.visible_ids.size() == 16, "physical mouse wheel appends the second eight-card batch")
	_check(first.get_instance_id() == identity and first.position == position, "wheel append preserves old controls and coordinates")
	_check(page._scroll.scroll_vertical > 0, "wheel append preserves a nonzero scroll offset")
	await _capture(shell, "cards-continuous-second-batch")
	var selected := ""
	for id in page.visible_ids:
		var tile: Control = page._buttons["compendium:item:" + id]
		if page._scroll.get_global_rect().intersection(tile.get_global_rect()).size.y >= 44:
			selected = id
			break
	var offset := page._scroll.scroll_vertical
	page.open_detail(selected)
	await _frames()
	_check(is_instance_valid(page.detail), "scrolling gallery entry opens full details")
	if is_instance_valid(page.detail):
		var loaded := page.visible_ids.size()
		_wheel(page._scroll.get_global_rect().get_center())
		await _frames()
		_check(page.visible_ids.size() == loaded and page._scroll.scroll_vertical == offset, "modal blocks background scroll and lazy loading")
		page.detail.close()
		await _frames()
		_check(abs(page._scroll.scroll_vertical - offset) <= 1, "closing same entry restores the exact gallery offset")
		_check(page._buttons["compendium:item:" + selected].has_focus(), "closing detail restores selected card focus")
	page._buttons["compendium:tab:cards"].grab_focus()
	_key(KEY_END)
	await _frames()
	_check(page.visible_ids.size() == 174, "End reaches the full catalogue, including unloaded cards")
	var bar := page._scroll.get_v_scroll_bar()
	_check(absf(page._scroll.scroll_vertical - maxf(0, bar.max_value - bar.page)) <= 1, "End scrolls to actual catalogue bottom")
	var bottom := page._scroll.scroll_vertical
	await _capture(shell, "cards-continuous-all-bottom")
	page.show_tab("monsters")
	await _frames()
	_check(page.visible_ids.size() == 8, "other tab starts with its own eight thumbnails")
	page.show_tab("cards")
	await _frames()
	_check(page.visible_ids.size() == 174 and abs(page._scroll.scroll_vertical - bottom) <= 1, "tab switch restores loaded extent and bottom offset")
	_check(shell.press("compendium:back"), "continuous gallery returns to menu")
	await _frames()
	_check(shell.press("menu:compendium"), "continuous gallery reopens from menu")
	await _frames()
	page = shell.page as UiCompendiumPage
	_check(page.visible_ids.size() == 174 and abs(page._scroll.scroll_vertical - bottom) <= 1, "menu return restores continuous gallery extent and offset")
	_key(KEY_HOME)
	await _frames()
	_check(page._scroll.scroll_vertical == 0, "Home returns to top")
	page.reset_filters()
	await _frames()
	var last: Control = page._buttons["compendium:item:" + page.visible_ids[7]]
	last.grab_focus()
	await _frames()
	_check(page.visible_ids.size() >= 16, "keyboard focus on final row loads the next batch")
	_key(KEY_TAB)
	await _frames()
	_check(page._buttons["compendium:item:" + page.visible_ids[8]].has_focus(), "Tab continues into the appended cards")
	page._buttons["compendium:tab:cards"].grab_focus()
	_key(KEY_PAGEDOWN)
	await _frames()
	_check(page._scroll.scroll_vertical > 0, "PageDown scrolls the continuous viewport")
	page.reset_filters()
	await _frames()
	page._scroll.scroll_vertical = int(page._scroll.get_v_scroll_bar().max_value)
	page.search("R3-T202")
	await _frames()
	_check(page.visible_ids == ["R3-T202"], "old queued append cannot leak into a new search")
	page.reset_filters()
	await _frames()
	page.open_detail(page.visible_ids[7])
	await _frames()
	if is_instance_valid(page.detail):
		page.detail.change_entry(1)
		var next_id := page.detail.selected_id
		page.detail.close()
		await _frames()
		_check(page._buttons.has("compendium:item:" + next_id) and page._buttons["compendium:item:" + next_id].has_focus(), "detail next across batch restores the new item focus")
		print("COMPENDIUM_SCROLL_GEOMETRY=", JSON.stringify({"scroll": str(page._scroll.get_global_rect()), "card": str(page._buttons["compendium:item:" + next_id].get_global_rect()), "offset": page._scroll.scroll_vertical}))
		_check(page._scroll.get_global_rect().encloses(page._buttons["compendium:item:" + next_id].get_global_rect()), "cross-batch detail selection scrolls fully into view")
	page.reset_filters()
	await _frames()
	return page


func _legacy_and_pending() -> void:
	var session := _session()
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", "42")).accepted, "legacy run starts for isolation check")
	var current_catalog: ContentDB = session._catalog
	var before := _helpers.fingerprint(session)
	var read := session.get_compendium()
	_check(read.ok and read.data.cards.size() == 174 and session._catalog == current_catalog, "encyclopedia stays full production without switching legacy active catalogue")
	_check(_helpers.fingerprint(session) == before, "legacy run unchanged")
	session.free()
	session = _session()
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", "0")).accepted, "choice compatibility run starts")
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	await _frames()
	_check(_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])), "real map enters choice battle")
	await _frames()
	var battle := shell.page as BattleScreen
	battle._finish_event_presentation()
	var card_id := ""
	for card in session.get_view().battle.hand:
		if card.definition_id == "K03":
			card_id = str(card.card_id)
	_check(not card_id.is_empty() and shell.press("card:" + card_id), "real K03 card creates pending choice")
	await _frames()
	_check(session.get_view().pending_choice != null, "public command produces genuine pending workspace")
	if session.get_view().pending_choice != null:
		before = _helpers.fingerprint(session)
		_check(shell.press("choice:menu"), "pending choice returns home")
		await _frames()
		_check(shell.press("menu:compendium"), "read-only compendium accessible with pending workspace")
		await _frames()
		_check(shell.page is UiCompendiumPage and shell.page.filtered_ids.size() == 174, "pending workspace can browse complete catalogue")
		_check(shell.press("compendium:back"), "pending browsing returns menu")
		await _frames()
		_check(shell.press("menu:continue"), "resume genuine pending workspace")
		await _frames()
		_check(session.get_view().pending_choice != null and _helpers.fingerprint(session) == before, "browse preserves complete pending state, RNG and revision")
	shell.free()
	await _frames()


func _failure_screen() -> void:
	var session := MissingCatalogueSession.new(SaveStore.new("user://compendium-missing-%s" % Time.get_ticks_usec()))
	var shell: GameShell = _helpers.attach_shell(session)
	await _frames()
	_check(shell.press("menu:compendium"), "failure page reachable")
	await _frames()
	_check(shell.page is UiCompendiumPage and shell.page._count.text.contains("加载失败"), "content load failure shown instead of an empty successful catalogue")
	_check(shell.press("compendium:back"), "failure page can return")
	await _frames()
	shell.free()
	await _frames()


func _pointer_and_keyboard() -> void:
	var session := _session()
	var shell: GameShell = _helpers.attach_shell(session)
	await _frames()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			(Engine.get_main_loop() as SceneTree).root.size = dimensions
			session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": false, "animation_speed": 1}})
			shell._apply_presentation()
			shell.show_screen("menu")
			await _frames()
			var menu := shell.page as UiExperiencePage
			menu._buttons["menu:compendium"].grab_focus()
			await _frames()
			await _capture(shell, "menu-%s-%s" % [dimensions.x, scale])
			_click(menu._buttons["menu:compendium"].get_global_rect().get_center())
			await _frames()
			_check(shell.page is UiCompendiumPage, "pointer opens main menu encyclopedia at each size/scale")
			if not shell.page is UiCompendiumPage:
				continue
			var page := shell.page as UiCompendiumPage
			page.show_tab("cards")
			page.reset_filters()
			await _frames()
			var first := page.visible_ids[0]
			var tile: Control = page._buttons["compendium:item:" + first]
			var visible_rect := tile.get_global_rect().intersection(page._scroll.get_global_rect())
			_check(visible_rect.size.y >= 44, "visible card target remains at least 44px")
			_click(visible_rect.get_center())
			await _frames()
			_check(is_instance_valid(page.detail), "pointer hits actual card tile")
			if is_instance_valid(page.detail):
				var modal := page.detail
				var option := modal._variants
				_click(option.get_global_rect().get_center())
				await _frames()
				_check(option.get_popup().visible, "pointer opens base/upgrade menu")
				# Mouse-opened menus start without a highlighted item; first Down focuses base.
				_popup_key(option.get_popup(), KEY_DOWN)
				await _frames()
				_popup_key(option.get_popup(), KEY_DOWN)
				await _frames()
				_popup_key(option.get_popup(), KEY_ENTER)
				await _frames()
				_check(modal.selected_variant == 1, "native variant control selects upgraded face %s/%s selected=%s" % [dimensions.x, scale, modal.selected_variant])
				modal.press("compendium:detail:close")
				await _frames()
				_key(KEY_ENTER)
				await _frames()
				_check(is_instance_valid(page.detail), "Enter opens focused card after focus restoration")
				if is_instance_valid(page.detail):
					_key(KEY_ESCAPE)
					await _frames()
			_click(page._buttons["compendium:tab:monsters"].get_global_rect().get_center())
			await _frames()
			page.reset_filters()
			await _frames()
			_check(page.tab == "monsters" and page.filtered_ids.size() == 60, "pointer switches monster tab")
			_key(KEY_SLASH)
			await _frames()
			_check(page._search.has_focus(), "slash focuses actual search input")
			page._search.text = "Q0A_3_1"
			page._search.text_changed.emit(page._search.text)
			await shell.get_tree().create_timer(.20).timeout
			await _frames()
			_check(page.filtered_ids == ["Q0A_3_1"], "typed search debounce reaches auxiliary")
			_key(KEY_ESCAPE)
			await _frames()
			_check(shell.page == page and not page._search.has_focus(), "Esc exits search without leaving gallery")
			first = page.visible_ids[0]
			tile = page._buttons["compendium:item:" + first]
			_click(tile.get_global_rect().get_center())
			await _frames()
			_check(is_instance_valid(page.detail), "pointer hits actual monster image")
			if is_instance_valid(page.detail):
				var modal := page.detail
				var before := _helpers.fingerprint(session)
				var count := modal._actor.rig.cue_count
				_click(modal._buttons["compendium:motion:attack"].get_global_rect().get_center())
				await _frames()
				_check(modal._actor.rig.cue_count == count + 1, "pointer starts actual native monster action")
				_key(KEY_END)
				await _frames()
				var bar := modal._scroll.get_v_scroll_bar()
				_check(absf(modal._scroll.scroll_vertical - maxf(0, bar.max_value - bar.page)) <= 1, "keyboard End reaches end of full explanation")
				await _capture(shell, "auxiliary-detail-bottom-%s-%s" % [dimensions.x, scale])
				_check(_helpers.fingerprint(session) == before, "model action preview and scrolling are read only")
				_click(modal._buttons["compendium:detail:close"].get_global_rect().get_center())
				await _frames()
				_check(not is_instance_valid(page.detail), "pointer closes modal")
			_key(KEY_ESCAPE)
			await _frames()
			_check(shell.page is UiExperiencePage, "second Esc returns to main menu")
	shell.free()
	await _frames()


func _wheel(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	Input.parse_input_event(event)


func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)


func _popup_key(popup: PopupMenu, code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.window_id = popup.get_window_id()
		Input.parse_input_event(event)


func _check_layout(page: UiCompendiumPage, dimensions: Vector2i) -> void:
	var bounds := Rect2(Vector2.ZERO, dimensions)
	_check(bounds.encloses(page._scroll.get_global_rect()) and page._scroll.size.y > 100, "gallery viewport fits at " + str(dimensions) + ":" + str(UiStyle.text_scale))
	_check(page._grid.size.x <= page._scroll.size.x + 1, "gallery never requires horizontal scrolling")
	for uid in ["compendium:back", "compendium:tab:cards", "compendium:tab:monsters"]:
		var button: Control = page._buttons[uid]
		_check(button.size.y >= 44 and bounds.encloses(button.get_global_rect()), "fixed target 44px and inside viewport " + uid)
	_check(page._search.size.y >= 44 and bounds.encloses(page._search.get_global_rect()), "search target fits")


func _check_detail_layout(modal: UiCompendiumDetail, dimensions: Vector2i) -> void:
	var bounds := Rect2(Vector2.ZERO, dimensions)
	_check(bounds.encloses(modal._scroll.get_global_rect()) and modal._scroll.size.y > 100, "complete detail scroll area fits")
	_check(modal._words.size.x <= modal._scroll.size.x + 1, "detail text wraps without horizontal clipping")
	for uid in ["compendium:detail:close", "compendium:detail:previous", "compendium:detail:next"]:
		var button: Control = modal._buttons[uid]
		_check(button.size.y >= 44 and bounds.encloses(button.get_global_rect()), "detail fixed target fits " + uid)


func _capture(shell: GameShell, name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := shell.get_viewport().get_texture().get_image()
	var path := _out + "/" + name + ".png"
	_check(image.save_png(path) == OK, "save real rendered evidence " + name)
	_captures.append(path)


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = code
	Input.parse_input_event(release)


func _frames() -> void:
	for _index in 4:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
