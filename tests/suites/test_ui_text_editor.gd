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
	_path = "user://text-entity-test-%s-%s.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	TextOverrides.use_path(_path)
	_catalog = ContentDB.new("res://data/four_year")
	_check(_catalog.load(RelicPilot.ROSTER).ok, "real production catalogue loads")
	var built := TextEntityLibrary.build(_catalog)
	_check(built.ok, "entity library builds from production data")
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
		"entities": built.data.counts if built.ok else {},
		"fields": built.data.field_count if built.ok else 0,
		"scope": "entity-first main menu/editor, production definitions, isolated override file; no real save or player override file",
	}
	print("TEXT_EDITOR_CHECKS=", JSON.stringify(report))
	return _failures


func _check_library(data: Dictionary) -> void:
	var entities: Array = data.get("entities", [])
	var counts: Dictionary = data.get("counts", {})
	_check(entities.size() == 600, "entity count is exact for the RX roster and tutorial")
	_check(int(counts.get("cards", 0)) == 174, "174 card entities")
	_check(int(counts.get("relics", 0)) == 104, "104 RX relic entities")
	_check(int(counts.get("characters", 0)) == 4, "4 character entities")
	_check(int(counts.get("stories", 0)) == 11, "11 story entities")
	_check(int(counts.get("glossary", 0)) == 43, "43 glossary entities")
	_check(int(counts.get("monsters", 0)) == 60, "60 monster entities")
	_check(int(counts.get("tutorial", 0)) == 6, "6 tutorial page entities")
	_check(int(counts.get("terms", 0)) == 198, "198 fallback name entities")
	_check(int(data.get("field_count", 0)) == 2092, "2092 logical fields")
	_check(int(data.get("uid_count", 0)) == 2112, "2112 backing UIDs")
	_check(int(data.get("source_uid_count", 0)) == 2100, "2100 source library UIDs")
	_check(TextOverrides.defaults_error().is_empty(), "bundled default text parses cleanly")
	_check(TextOverrides.default_text("glossary:anxiety.short", "").begins_with("每层减少"), "bundled glossary default applies")
	_check(TextOverrides.default_text("card:R3-C-04:0:detail", "").contains("放松 3"), "bundled card detail default applies")
	_check(TextOverrides.default_text("relic:RX-C07", "").contains("每战首次"), "bundled relic default applies")
	_check(TextOverrides.default_text("passive:r3_p03_compound_reaction", "").contains("额外 +1 层"), "bundled passive default applies")
	var by_id: Dictionary = {}
	var by_uid: Dictionary = {}
	for entity in entities:
		var id := str(entity.id)
		_check(not id.is_empty(), "entity id is non-empty")
		_check(not by_id.has(id), "entity id is unique: " + id)
		by_id[id] = entity
		_check(not entity.fields.is_empty(), "entity has fields: " + id)
		for field in entity.fields:
			_check(not str(field.key).is_empty(), "field key is set: " + id)
			_check(not field.uids.is_empty(), "field has UIDs: " + id)
			_check(field.default is String, "field default is a string: " + id)
			for uid in field.uids:
				by_uid[uid] = field
	for uid in TextLibrary.build(_catalog).data.entries:
		_check(by_uid.has(uid.uid), "every original UID belongs to a field: " + uid.uid)
	var card: Dictionary = by_id["card:R3-C-01"]
	_check(card.fields.size() == 7, "card entity exposes name, detail/battle/glossary base/upgrade")
	_check(_field_for_uid(card, "card:R3-C-01:0:battle_glossary").get("label", "") == "基础名词解释", "card glossary is a separate labeled field")
	_check(not str(_field_for_uid(card, "card:R3-C-01:0:battle_glossary").get("default", "")).contains("名词解释："), "card glossary default stores only term lines")
	_check(
		not str(_field_for_uid(card, "card:R3-C-01:0:battle").get("default", "")).contains("打出后按顺序结算：")
		and not str(_field_for_uid(card, "card:R3-C-01:1:battle").get("default", "")).contains("打出后按顺序结算："),
		"base and upgraded battle defaults omit the removed ordered-resolution heading"
	)
	var clean_battle_defaults := true
	for entity in entities:
		if str(entity.type) != "cards":
			continue
		for field in entity.fields:
			for uid in field.uids:
				if str(uid).ends_with(":battle") and str(field.default).contains("打出后按顺序结算："):
					clean_battle_defaults = false
	_check(clean_battle_defaults, "every card base and upgraded battle field omits the removed heading")
	_check(str(card.meta.owner) == "C", "card metadata keeps owner for filtering")
	var story: Dictionary = by_id["story:events.V01"]
	_check(story.fields.size() >= 6, "event entity exposes title/location/narrative/options")
	var title_field: Dictionary = _field_for_uid(story, "label:V01")
	_check(not title_field.is_empty() and title_field.uids.has("story:events.V01.title"), "event title aliases label and story title")
	var glossary: Dictionary = by_id["glossary:focus"]
	var name_field: Dictionary = _field_for_uid(glossary, "glossary:focus.name")
	_check(not name_field.is_empty() and name_field.uids.has("label:focus"), "glossary name aliases shared label")
	var anxiety: Dictionary = by_id["glossary:anxiety"]
	var anxiety_short: Dictionary = _field_for_uid(anxiety, "glossary:anxiety.short")
	_check(str(anxiety_short.get("default", "")).begins_with("每层减少"), "editor default shows bundled text")
	var option_field: Dictionary = _field_for_uid(story, "story:events.V01.option_titles.leave")
	_check(not option_field.is_empty(), "all event options have editable fields")
	var monster: Dictionary = by_id["monster:N03"]
	_check(monster.fields.size() >= 2, "monster entity exposes name and intent labels")
	_check(_field_for_uid(monster, "label:N03").uids.has("label:N03"), "monster name maps to its label")
	_check(by_id.has("term:N03") == false, "monster name is no longer in the other bucket")
	_check(by_id.has("term:K01"), "unmapped legacy labels are preserved as fallback entities")
	var tutorial: Dictionary = by_id["tutorial:intro_1"]
	_check(tutorial.fields.size() == 9, "tutorial page exposes chapter, title, body and three bullets")
	_check(
		str(_field_for_uid(tutorial, "tutorial:intro_1.title").default) == "基础数值",
		"tutorial title default uses the baked user edit"
	)
	_check(
		TextOverrides.default_text("tutorial:intro_1.body", "fallback") == "",
		"tutorial empty body is preserved as a default"
	)
	_check(
		str(_field_for_uid(by_id["tutorial:battle_1"], "tutorial:battle_1.title").default)
		== "敌人",
		"battle tutorial title default uses the baked user edit"
	)
	_check(
		str(_field_for_uid(by_id["tutorial:intro_3"], "tutorial:intro_3.next").default)
		== "开始冒险",
		"tutorial final button copy is editable"
	)
	_check(by_id.has("tutorial:battle_3"), "all six tutorial pages are entities")
	_check(not by_id.has("relic:FY_Y1_1"), "retired FY relic text is not editable")
	_check(UiStyle.label("status.inspiration.name") == "灵感", "dotted status keys keep their canonical fallback")
	_check(UiStyle.label("task.n01.intent.pressure5") == "施加压力", "dotted task intent keys still resolve")


func _field_for_uid(entity: Dictionary, uid: String) -> Dictionary:
	for field in entity.fields:
		if field.uids.has(uid):
			return field
	return {}


func _session() -> GameSession:
	var session := GameSession.new(
		SaveStore.new("user://text-entity-saves-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
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
	_check(shell.press("menu:text_editor"), "main menu opens the entity editor")
	await _frames()
	_check(shell.page is UiTextEditorPage, "entity editor page is installed")
	var page: UiTextEditorPage = shell.page
	_check(page.library.size() == data.entities.size(), "page receives all entities")
	_check(page.counts == data.counts, "page counts are entity counts")
	_check(page.filtered.size() == data.entities.size(), "all entities are initially browsable")
	_check(page.selected_id == "card:R3-P01-09", "first entity is selected for immediate editing")
	_check(page._field_blocks.size() == 7, "selected card exposes seven field blocks")
	_check(page._buttons.has("text_editor:save_entity"), "entity-level save is visible")
	_check(page._buttons.has("text_editor:save"), "global save is visible")
	_search_checks(page)
	await _edit_checks(page, session, before)
	await _reset_checks(page)
	await _compat_checks(page)
	await _guard_and_state_checks(shell, page)
	await _layout_checks(shell, data)
	await _frames()
	var view := session.get_view()
	_check(view.run_id == null, "editor does not start a run")
	_check(view.revision == 0, "editor does not change the domain revision")
	_check(
		SnapshotCodec.canonical_json(view.to_dictionary()) == before,
		"entity edits do not mutate the session view"
	)
	if shell.page is UiTextEditorPage:
		shell.page._request_back()
		await _frames()
	shell.free()
	await _frames()


func _search_checks(page: UiTextEditorPage) -> void:
	page.show_tab("cards")
	page.search("R3-C-01")
	_check(page.filtered.size() == 1, "exact card ID returns one entity")
	_check(page.selected_id == "card:R3-C-01", "exact card search selects the entity")
	_check(page._entity_modified_count(page._selected) == 0, "clean entity has no modified fields")
	page.search("战斗说明")
	_check(not page.filtered.is_empty(), "battle field label returns owning card entities")
	page.search("名词解释")
	_check(not page.filtered.is_empty(), "card glossary field is searchable")
	page.search("战斗说明")
	page.select_entity_matching("card:R3-P01-09")
	_check(page.selected_id == "card:R3-P01-09", "field-matched entity is selected")
	_check(str(page._expanded_field).ends_with(":battle_0"), "matched battle field is expanded")
	page.search("")
	page.set_filter("P01")
	_check(not page.filtered.is_empty(), "owner filter returns cards")
	for entity in page.filtered:
		_check(str(entity.meta.owner) == "P01", "owner filter only returns Lin Xu cards")
	page.set_filter("")
	page.set_filter2("work")
	for entity in page.filtered:
		_check(str(entity.meta.card_type) == "work", "card type filter only returns work cards")
	page.set_filter2("")
	page.show_tab("stories")
	page.search("")
	_check(page.filtered.size() == 11, "story tab has event and room entities")
	page.search("宿舍断电")
	_check(page.filtered.size() == 1 and str(page.selected_id).begins_with("story:events.V04"), "story search selects the event entity")
	page.show_tab("glossary")
	page.search("")
	_check(page.filtered.size() == 43, "glossary tab has term entities")
	page.search("专注")
	_check(page.filtered.size() >= 1, "glossary search finds term entities")
	page.show_tab("monsters")
	page.search("")
	_check(page.filtered.size() == 60, "monster tab has all monster entities")
	page.search("C语言练习")
	_check(page.filtered.size() == 1 and page.selected_id == "monster:N03", "monster name search selects its entity")
	page.search("")
	page.set_filter("boss")
	_check(not page.filtered.is_empty(), "monster kind filter returns bosses")
	for entity in page.filtered:
		_check(str(entity.meta.kind) == "boss", "monster filter only returns bosses")
	page.set_filter("")
	page.show_tab("tutorial")
	page.search("")
	_check(page.filtered.size() == 6, "tutorial tab has all six pages")
	_check(str(page.filtered[0].id) == "tutorial:intro_1", "tutorial list starts at the first page")
	_check(str(page.filtered[5].id) == "tutorial:battle_3", "tutorial list ends at the last page")
	page.search("精力")
	_check(page.filtered.size() >= 1, "tutorial search finds the resources page")
	page.search("")
	_check(page.select_entity("tutorial:intro_1"), "first tutorial page is selectable")
	page.show_tab("terms")
	page.search("")
	_check(page.filtered.size() == 198, "other tab keeps remaining legacy and shared label entities")
	page.show_tab("all")
	page.search("")


func _edit_checks(page: UiTextEditorPage, session: GameSession, before: String) -> void:
	page.show_tab("cards")
	page.search("")
	_check(page.select_entity("card:R3-C-01"), "card entity is selectable")
	var keys: Array = page.entity_field_keys("card:R3-C-01")
	_check(keys.size() == 7, "card field keys are complete")
	var detail_key := "card:R3-C-01:detail_0"
	var name_key := "card:R3-C-01:name"
	var battle_key := "card:R3-C-01:battle_0"
	var glossary_key := "card:R3-C-01:battle_glossary_0"
	_check(page._field_blocks[glossary_key].field.label == "基础名词解释", "card glossary field has its own label")
	_check(page.field_text(glossary_key).contains("专注："), "card glossary field starts from the generated term lines")
	page.expand_field(detail_key)
	page.set_field_text(detail_key, "测试基础说明")
	_check(page.dirty_count() == 1, "one field edit is one dirty field")
	_check(page._entity_modified_count(page._selected) == 1, "entity shows one modified field")
	_check(page.field_text(name_key) == "写作业", "editing a field leaves the name unchanged")
	_check(not page.field_text(battle_key).is_empty(), "other card fields remain readable")
	page.save_entity()
	_check(TextOverrides.text("card:R3-C-01:0:detail", "") == "测试基础说明", "entity save writes the edited UID")
	_check(page.dirty_count() == 0, "entity save clears its dirty state")
	_check(TextOverrides.text("card:R3-C-01:1:detail", "") == "", "entity save does not write untouched variants")
	var face := _resolve_card("R3-C-01")
	_check(face.ok, "card face resolves")
	if face.ok:
		_check(UiContentText.describe_card(face.data) == "测试基础说明", "card override applies to the live description")
		page.set_field_text(battle_key, "测试战斗说明")
		page.set_field_text(glossary_key, "专注：测试名词解释")
		page.save_entity()
		_check(UiContentText.describe_battle_card(face.data) == "测试战斗说明", "battle description field edits only the effect text")
		_check(
			UiContentText.describe_battle_card_glossary(face.data) == "专注：测试名词解释",
			"glossary field edits only the glossary text"
		)
		page._reset_field(battle_key)
		page._reset_field(glossary_key)
		page.save_entity()
	_check(
		SnapshotCodec.canonical_json(session.get_view().to_dictionary()) == before,
		"card entity edit leaves the session untouched"
	)
	page.set_field_text(name_key, "测试卡牌名")
	page.save_entity()
	_check(UiStyle.label("R3-C-01") == "测试卡牌名", "card name field applies to labels")
	page.show_tab("glossary")
	page.search("")
	_check(page.select_entity("glossary:focus"), "glossary entity is selectable")
	var glossary_name := "glossary:focus:name"
	page.set_field_text(glossary_name, "测试专注")
	page.save_entity()
	_check(UiStyle.label("focus") == "测试专注", "glossary alias writes shared label")
	_check(UiGlossary.label("focus") == "测试专注", "glossary alias writes glossary name")
	_check(UiGlossary.describe("focus").begins_with("测试专注"), "glossary description uses the edited name")
	page.show_tab("stories")
	page.search("")
	_check(page.select_entity("story:events.V01"), "event entity is selectable")
	var story_title := "story:events.V01:title"
	page.set_field_text(story_title, "测试事件标题")
	page.save_entity()
	_check(UiStyle.label("V01") == "测试事件标题", "event title alias writes label")
	_check(CampusRoomIllustration.details("events", "V01").title == "测试事件标题", "event title alias writes story title")
	var option_key := "story:events.V01:option_leave"
	_check(page._field_blocks.has(option_key), "event option field exists")
	page.set_field_text(option_key, "测试离开")
	page.save_entity()
	_check(
		CampusRoomIllustration.option_title("V01", "leave", "fallback") == "测试离开",
		"event option override applies to the event page caption"
	)
	page.show_tab("relics")
	page.search("")
	_check(page.select_entity("relic:RX-C01"), "relic entity is selectable")
	page.set_field_text("relic:RX-C01:description", "测试饰品说明")
	page.save_entity()
	_check(
		UiContentText.describe_relic(_catalog.get_definition("relic", "RX-C01").data) == "测试饰品说明",
		"relic entity description applies"
	)
	page.show_tab("characters")
	page.search("")
	_check(page.select_entity("character:P01"), "character entity is selectable")
	page.set_field_text("character:P01:passive", "测试被动说明")
	page.save_entity()
	_check(
		UiContentText.describe_character_passive("r3_p01_link_replay") == "测试被动说明",
		"character passive applies"
	)
	page.show_tab("tutorial")
	page.search("")
	_check(page.select_entity("tutorial:intro_1"), "tutorial page is selectable")
	_check(page.entity_field_keys("tutorial:intro_1").size() == 9, "tutorial page has nine field keys")
	page.set_field_text("tutorial:intro_1:title", "测试数值页")
	page.set_field_text("tutorial:intro_1:bullet_0_text", "测试精力说明")
	page.save_entity()
	_check(TextOverrides.text("tutorial:intro_1.title", "") == "测试数值页", "tutorial title override writes its UID")
	_check(
		UiTutorialContent.intro_steps()[0].title == "测试数值页",
		"tutorial overlay reads the edited title"
	)
	_check(
		UiTutorialContent.intro_steps()[0].bullets[0].text == "测试精力说明",
		"tutorial overlay reads the edited bullet"
	)
	page._reset_entity()
	page.save_entity()
	_check(UiTutorialContent.intro_steps()[0].title == "基础数值", "tutorial reset restores the baked default title")
	page.show_tab("monsters")
	page.search("")
	_check(page.select_entity("monster:N03"), "monster entity is selectable")
	page.set_field_text("monster:N03:name", "测试怪物名")
	page.save_entity()
	_check(UiStyle.label("N03") == "测试怪物名", "monster name applies to labels")
	var intent_key := ""
	for key in page.entity_field_keys("monster:N03"):
		if str(key).ends_with(":intent_0"):
			intent_key = str(key)
			break
	_check(not intent_key.is_empty(), "monster entity has intent fields")
	if not intent_key.is_empty():
		var intent_uid := str(page._field_blocks[intent_key].field.uids[0])
		page.set_field_text(intent_key, "测试意图名")
		page.save_entity()
		_check(
			UiStyle.label(intent_uid.trim_prefix("label:")) == "测试意图名",
			"monster intent label applies to the shared intent text"
		)


func _resolve_card(id: String) -> GameResult:
	return BattleCardRules.new(_catalog).resolve_face(
		BattleState.new({"card_by_id": {id: {"definition_id": id, "upgrade_level": 0}}}),
		id
	)


func _reset_checks(page: UiTextEditorPage) -> void:
	page.show_tab("cards")
	page.search("")
	page.select_entity("card:R3-C-01")
	page._reset_entity()
	page.save_entity()
	_check(UiStyle.label("R3-C-01") == "写作业", "entity reset restores card name")
	_check(TextOverrides.text("card:R3-C-01:0:detail", "") == "", "entity reset clears card detail override")
	page.show_tab("glossary")
	page.search("")
	page.select_entity("glossary:focus")
	page._reset_entity()
	page.save_entity()
	_check(UiStyle.label("focus") == "专注" and UiGlossary.label("focus") == "专注", "glossary alias reset clears both UIDs")
	page._request_reset_all()
	page._request_reset_all()
	page._save()
	_check(TextOverrides.count() == 0, "global reset clears every override")
	_check(CampusRoomIllustration.narrative("E", "V01").begins_with("最后一节课"), "global reset restores story")
	_check(UiGlossary.describe("focus").contains("每回合出牌的主要成本"), "global reset restores glossary")


func _compat_checks(page: UiTextEditorPage) -> void:
	var original := {"label:P01": "旧档林序", "label:V01": "旧档事件"}
	var error := TextOverrides.save_values(original)
	_check(error.is_empty(), "legacy override file writes")
	page.initial_state = {}
	page.render(TextEntityLibrary.build(_catalog).data)
	page.select_entity("character:P01")
	_check(page.field_text("character:P01:name") == "旧档林序", "existing label override maps into character field")
	_check(page._entity_modified_count(page._selected) == 1, "existing override is marked modified")
	page._reset_entity()
	page.save_entity()
	_check(UiStyle.label("P01") == "林序", "migrated entity reset restores default")
	var legacy_battle := {"card:R3-C-01:0:battle": "旧战斗说明\n打出后按顺序结算：\n1. 旧步骤\n名词解释：\n专注：旧术语"}
	var migration_error := TextOverrides.save_values(legacy_battle)
	_check(migration_error.is_empty(), "legacy single-window battle override writes")
	TextOverrides.reload_from_disk()
	_check(TextOverrides.text("card:R3-C-01:0:battle", "") == "旧战斗说明\n1. 旧步骤", "legacy battle override keeps other lines and drops only the removed heading")
	_check(
		TextOverrides.text("card:R3-C-01:0:battle_glossary", "") == "专注：旧术语",
		"legacy glossary block migrates to the separate UID"
	)
	page.initial_state = {}
	page.render(TextEntityLibrary.build(_catalog).data)
	page.select_entity("card:R3-C-01")
	_check(page.field_text("card:R3-C-01:battle_0") == "旧战斗说明\n1. 旧步骤", "migrated battle field drops only the removed heading")
	_check(page.field_text("card:R3-C-01:battle_glossary_0") == "专注：旧术语", "migrated glossary field shows term text")
	page._reset_entity()
	page.save_entity()
	var bad := _path + ".bad"
	var file := FileAccess.open(bad, FileAccess.WRITE)
	file.store_string("{bad")
	file.close()
	TextOverrides.use_path(bad)
	_check(UiStyle.label("P01") == "林序", "corrupt override file falls back to default")
	_check(not TextOverrides.last_error().is_empty(), "corrupt override file is reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))
	TextOverrides.use_path(_path)
	TextOverrides.reload_from_disk()


func _guard_and_state_checks(shell: GameShell, page: UiTextEditorPage) -> void:
	page.show_tab("cards")
	page.search("R3-C-01")
	page.select_entity("card:R3-C-01")
	page.set_field_text("card:R3-C-01:name", "未保存名称")
	page._request_back()
	_check(shell._ui_screen == "text_editor", "unsaved entity requires a second back action")
	_check(page._exit_armed, "first back arms discard warning")
	page._request_back()
	await _frames()
	_check(shell._ui_screen == "menu", "second back returns to menu")
	_check(UiStyle.label("R3-C-01") == "写作业", "discarding a draft does not save it")
	_check(shell.press("menu:text_editor"), "entity editor reopens")
	await _frames()
	page = shell.page
	_check(page.tab == "cards" and page.query == "R3-C-01" and page.selected_id == "card:R3-C-01", "tab/query/selection restore")
	page.show_tab("stories")
	page.search("")
	page.select_entity("story:events.V04")
	page.expand_field("story:events.V04:narrative")
	page._request_back()
	await _frames()
	_check(shell.press("menu:text_editor"), "editor reopens for field state restore")
	await _frames()
	page = shell.page
	_check(page.tab == "stories" and page.selected_id == "story:events.V04", "story selection restores")
	_check(page._expanded_field == "story:events.V04:narrative", "expanded field restores")
	page.show_tab("cards")
	page.search("")
	page.select_entity("card:R3-C-01")
	page.set_field_text("card:R3-C-01:name", "CtrlS 名称")
	var event := InputEventKey.new()
	event.pressed = true
	event.ctrl_pressed = true
	event.keycode = KEY_S
	page._input(event)
	_check(UiStyle.label("R3-C-01") == "CtrlS 名称", "Ctrl+S saves the entity draft")
	page._request_back()
	await _frames()


func _layout_checks(shell: GameShell, data: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var page := shell.page as UiTextEditorPage
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for scale in [100, 125, 150]:
			UiStyle.text_scale = float(scale) / 100.0
			if not (shell.page is UiTextEditorPage):
				_check(shell.press("menu:text_editor"), "editor opens for layout")
				await _frames()
			page = shell.page
			page.initial_state = {}
			page.render(data)
			page.show_tab("cards")
			page.search("R3-C-01")
			page.select_entity("card:R3-C-01")
			page.expand_field("card:R3-C-01:detail_0")
			await _frames()
			_check(page.size.x > 0 and page.size.y > 0, "page lays out at %s / %d%%" % [str(dimensions), scale])
			_check(page._left_scroll.size.x > 0 and page._left_scroll.size.y > 0, "entity list visible at %s / %d%%" % [str(dimensions), scale])
			_check(page._field_blocks.size() == 7, "card fields exist at %s / %d%%" % [str(dimensions), scale])
			_check(page._buttons["text_editor:save"].size.y >= 44, "global save target at %s / %d%%" % [str(dimensions), scale])
			_check(page._buttons["text_editor:save_entity"].size.y >= 44, "entity save target at %s / %d%%" % [str(dimensions), scale])
			_check(page._buttons["text_editor:back"].size.y >= 44, "back target at %s / %d%%" % [str(dimensions), scale])
			if shell.page is UiTextEditorPage:
				shell.page._request_back()
				await _frames()
	UiStyle.text_scale = 1.0


func _active_run_check() -> void:
	var session := _session()
	var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42"))
	_check(started.accepted, "isolated active run starts")
	if not started.accepted:
		return
	var before := SnapshotCodec.canonical_json(session.get_view().to_dictionary())
	var shell: GameShell = _helpers.attach_shell(session)
	await _frames()
	_check(shell.press("menu:text_editor"), "entity editor opens while a run is active")
	await _frames()
	var page: UiTextEditorPage = shell.page
	_check(page.select_entity("card:R3-C-01"), "active-run editor selects a card entity")
	page.set_field_text("card:R3-C-01:name", "运行中卡名")
	page.save_entity()
	_check(UiStyle.label("R3-C-01") == "运行中卡名", "active-run entity edit applies display text")
	_check(
		SnapshotCodec.canonical_json(session.get_view().to_dictionary()) == before,
		"entity editing preserves run, battle, RNG, revision and event log"
	)
	page._request_back()
	await _frames()
	shell.free()
	await _frames()


func _frames() -> void:
	for _index in 5:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
