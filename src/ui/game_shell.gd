class_name GameShell
extends Control

signal web_menu_visible(visible: bool)
signal web_privacy_requested
signal web_account_requested(registering: bool)
signal web_guest_requested
signal web_guest_logout_requested
signal web_play_requested(developer_tools: bool)
signal web_section_requested(section: String)

const BattleDamagePopup = preload("res://src/ui/battle/battle_damage_popup_layer.gd")
const DEVELOPER_TOOL_ACTIONS := ["ui.test_room", "ui.text_editor"]
const WEB_PLAY_ACTIONS := ["ui.new_run", "ui.start_run", "ui.retry", "ui.continue", "ui.start_battle", "ui.resume_battle", "ui.test_room", "ui.text_editor"]
const PLAYABLE_ACCOUNT_STATES := ["", "ready", "guest"]
const LOCKED_WEB_ACTIONS := ["ui.web_account", "ui.web_register", "ui.web_guest", "ui.settings", "ui.web_privacy", "ui.back", "ui.save_settings", "ui.close_account_run", "ui.quit"]

var session: GameSession
var web_team_tools_available := true
var web_privacy_available := false
var web_account_state := ""
var web_registration_available := false
var web_account_name := ""
var web_account_message := ""
var _web_play_draft: Dictionary = {}
var _web_play_page_id := 0
var _web_play_screen := ""
var page: UiPage
var audio: AudioManager
var last_error: ApiError
var notice: String = "准备好开始你的四年冒险了吗？"
var _ui_screen := "menu"
var _back_screen := "menu"
var _page_key := ""
var _test_hud: TestHud
var _host: Control
var _background: TextureRect
var _notice_label: Label
var _status_label: Label
var _setup_defaults: Dictionary = {}
var _setup_seed_revision := 0
var _active_seed := ""
var _frame_margin: MarginContainer
var _frame_column: VBoxContainer
var _frame_panel: PanelContainer
var _restart_confirmation := false
var _advance_paused := false
var _submitted_scope := ""
var _business_notice := ""
var _damage_layer: Control
var _waiting_for_battle := false
var _remembered_choice: Dictionary = {}
var _save_status := "尚无本次会话的手动保存结果"
var _ui_feedback: Label
var _ui_feedback_generation := 0
var _compendium_state: Dictionary = {}
var _test_compendium: UiCompendiumPage
var _test_compendium_state: Dictionary = {}
var _test_compendium_focus: Control
var _test_compendium_pages: Dictionary = {}
var _text_editor_state: Dictionary = {}
var _text_library_cache: Dictionary = {}
var _text_library_loaded := false
var _quit_dialog: ConfirmationDialog
var _test_exit_dialog: ConfirmationDialog
var _test_exit_was_editing := false
var _tutorial: UiTutorialOverlay
var _tutorial_mode := ""
var _tutorial_replay := false
var _tutorial_pending := ""
var _tutorial_replay_requested := false
var _tutorial_intro_done := false
var _tutorial_battle_done := false
var _tutorial_run_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	if session == null:
		session = GameSession.new()
	if session.get_parent() == null:
		add_child(session)
	if audio == null:
		audio = AudioManager.new()
		add_child(audio)
	audio.apply_settings(session.get_audio_settings())
	_apply_presentation()
	_build_frame()
	refresh()


func _build_frame() -> void:
	var paper := ColorRect.new()
	paper.color = UiStyle.PAPER
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.modulate.a = 0.8
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	var margin := MarginContainer.new()
	_frame_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	_frame_column = column
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_status_label = Label.new()
	_status_label.text = "交大四年  /  DDL 战争"
	_status_label.add_theme_font_size_override("font_size", 16)
	column.add_child(_status_label)
	var panel := PanelContainer.new()
	_frame_panel = panel
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	_host = Control.new()
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_host)
	_notice_label = Label.new()
	_notice_label.custom_minimum_size.y = 22
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.add_theme_font_size_override("font_size", 12)
	_notice_label.add_theme_stylebox_override("normal",UiStyle.box(UiStyle.NIGHT))
	column.add_child(_notice_label)
	_damage_layer = BattleDamagePopup.new()
	_damage_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_layer.z_index = 500
	add_child(_damage_layer)
	_ui_feedback = Label.new()
	_ui_feedback.name = "UiActionFeedback"
	_ui_feedback.z_index = 600
	_ui_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_feedback.add_theme_stylebox_override("normal", UiStyle.surface(Color("20353d"), UiStyle.BRASS, 4))
	_ui_feedback.hide()
	add_child(_ui_feedback)


func show_screen(screen: String) -> void:
	_ui_screen = screen
	refresh()


func refresh() -> void:
	if _waiting_for_battle or not is_instance_valid(_host):
		return
	if is_instance_valid(_test_compendium):
		if _developer_tools_allowed() and _is_test_workspace():
			return
		_close_test_compendium()
	if is_instance_valid(_ui_feedback):
		_ui_feedback.hide()
	if session.has_test_room():
		web_menu_visible.emit(false)
		_refresh_test_room()
		return
	if _ui_screen == "test_room":
		web_menu_visible.emit(false)
		_refresh_test_home()
		return
	_clear_test_hud()
	if _ui_screen.is_empty() and not _advance_paused and last_error == null:
		_advance_completed_nodes()
	var current := session.get_view()
	var screen := _ui_screen if not _ui_screen.is_empty() else String(current.screen)
	web_menu_visible.emit(screen in ["menu", "settings", "records"])
	var data: Dictionary = {}
	match screen:
		"menu":
			if web_account_state in PLAYABLE_ACCOUNT_STATES:
				data = _storage_view()
				data.profile = _profile_view()
			data.relic_pilot = session.is_relic_pilot()
			data.team_tools_available = _developer_tools_allowed()
			data.account_state = web_account_state
			data.account_name = web_account_name
			data.account_message = web_account_message
			data.registration_available = web_registration_available
		"records":
			var records := session.get_game_records()
			data.records = records.data if records.ok else []
			data.records_error = "" if records.ok else UiStyle.error_text(records.error)
			data.account_state = web_account_state
		"setup":
			var options := session.get_setup_options()
			if not options.ok:
				_report_error(options.error)
				_ui_screen = "menu"
				refresh()
				return
			data = {
				"characters": options.data.characters,
				"difficulties": options.data.difficulties,
				"difficulty_details": options.data.difficulty_details,
				"default_difficulty": String(options.data.default_difficulty),
				"manifests": options.data.manifests,
				"default_seed": options.data.default_seed
			}
			data.merge(_setup_defaults, true)
			data.seed_revision = _setup_seed_revision
			data.replaces_run = _has_previous_run()
			data.confirm_restart = _restart_confirmation
			var storage := _storage_view()
			data.unreadable_save = storage.has_save and not storage.can_continue
		"compendium":
			var catalogue := session.get_compendium()
			data = catalogue.data if catalogue.ok else {"error": UiStyle.error_text(catalogue.error)}
			var preferences := session.get_presentation_settings()
			data.motion_enabled = int(preferences.animation_speed) > 0 and not preferences.reduced_motion
			data.animation_speed = preferences.animation_speed
		"text_editor":
			if not _text_library_loaded:
				var built := session.get_text_library()
				_text_library_cache = (
					built.data if built.ok else {"error": UiStyle.error_text(built.error)}
				)
				_text_library_loaded = true
			data = _text_library_cache
		"settings":
			if web_account_state in PLAYABLE_ACCOUNT_STATES:
				data = _storage_view()
			data.web_privacy_available = web_privacy_available
			data.account_state = web_account_state
			data.settings = {"autosave": session.get_profile().autosave}
			data.settings.audio = session.get_audio_settings()
			data.settings.presentation = session.get_presentation_settings()
			var backup: Variant = data.get("backup_meta")
			data.can_restore = (
				current.run_id == null
				and backup is Dictionary
				and backup.get("valid", false)
			)
			data.can_save = current.can_save and web_account_state in PLAYABLE_ACCOUNT_STATES
			data.difficulty = current.run.get("difficulty", "") if current.run is Dictionary and web_account_state in PLAYABLE_ACCOUNT_STATES else ""
			if current.run is Dictionary and web_account_state in PLAYABLE_ACCOUNT_STATES:
				data.seed = _active_seed if not _active_seed.is_empty() else "旧存档未记录初始种子"
		"battle":
			if current.battle is Dictionary:
				data = current.battle.duplicate(true)
				data.pending_choice = current.pending_choice
				data.event_log = current.event_log.duplicate(true)
				data.run_id = current.run_id
				data.revision = current.revision
				data.can_save = current.can_save
				data.notice = notice
				if current.run is Dictionary:
					data.year_label = ("大" + ["一", "二", "三", "四"][int(current.run.term)-1]) if current.run.has("campaign") else "第一学期"
					data.character_id = current.run.get("character_id", "P01")
					data.max_vitality = current.run.get("max_vitality", 1)
					data.money = current.run.get("money", 0)
					data.route_nodes = current.run.get("nodes",[]).filter(func(node): return int(node.get("term",1)) == int(current.run.get("term",1))).duplicate(true)
					data.route_current = current.run.get("current_node_id","")
					data.route_reachable = current.run.get("reachable_node_ids",[]).duplicate()
					data.cards = current.run.get("cards", []).duplicate(true)
					data.relics = current.run.get("relics", []).duplicate(true)
			else:
				screen = "battle_entry"
				data = current.run.duplicate(true) if current.run is Dictionary else {}
		_:
			data = current.run.duplicate(true) if current.run is Dictionary else {}
			data.can_save = current.can_save
			data.terminal_summary = current.terminal_summary
			data.profile_commit_status = current.profile_commit_status
	data.run_id = str(current.run_id) if current.run_id != null else ""
	data.revision = current.revision
	data.event_log = current.event_log.duplicate(true)
	data.can_save = current.can_save
	data.save_reason = "可保存当前完整进度" if current.can_save else ("请先完成卡牌效果中的选择" if current.pending_choice != null else "尚未开始冒险")
	data.save_status = _save_status
	data.autosave = session.get_profile().autosave
	if current.run is Dictionary and web_account_state in PLAYABLE_ACCOUNT_STATES:
		data.difficulty = current.run.get("difficulty", "normal")
		data.character_id = current.run.get("character_id", "")
		data.relic_slots = current.run.get("relic_slots", 3)
	if page == null or _page_key != screen:
		if page != null:
			if page is BattleScreen:
				_remembered_choice = page.export_choice_selection()
			_host.remove_child(page)
			page.queue_free()
		if screen == "battle":
			page = BattleScreen.new()
			page.preview_callback = Callable(self, "_preview")
		elif screen == "compendium":
			page = UiCompendiumPage.new()
			if not _compendium_state.is_empty():
				page.tab = str(_compendium_state.get("tab", "cards"))
				page._states = _compendium_state.states.duplicate(true)
		elif screen == "records":
			page = preload("res://src/ui/records_page.gd").new()
		elif screen == "text_editor":
			page = UiTextEditorPage.new()
			if not _text_editor_state.is_empty():
				page.initial_state = _text_editor_state.duplicate(true)
		else:
			page = UiExperiencePage.new()
			page.screen = screen
		page.audio = audio
		_host.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.action_requested.connect(submit_action)
		page.local_selection_changed.connect(func(_selection: Dictionary): _regate())
		_page_key = screen
	_set_battle_frame(screen == "battle")
	if page is BattleScreen:
		var preferences := session.get_presentation_settings()
		if page.get_meta("presentation", {}) != preferences:
			page.animation_enabled = int(preferences.animation_speed) > 0 and not preferences.reduced_motion
			page.speed_scale = maxf(1, int(preferences.animation_speed))
			page.set_meta("presentation", preferences.duplicate(true))
	elif page is UiExperiencePage:
		var preferences := session.get_presentation_settings()
		page.character_motion_enabled = int(preferences.animation_speed) > 0 and not preferences.reduced_motion
	page.render(data)
	if page is BattleScreen and not _remembered_choice.is_empty():
		page.restore_choice_selection(_remembered_choice)
		_remembered_choice.clear()
	_regate()
	var background_id: String = (
		{"shop": "BG_shop", "rest": "BG_dorm", "battle": "BG_classroom", "summary": "BG_success"}
		. get(screen, "BG_campus")
	)
	if screen == "summary" and data.get("outcome", "") != "won":
		background_id = "BG_failure"
	_background.texture = UiStyle.texture(str(background_id))
	_status_label.text = "交大四年  /  DDL 战争"
	if current.run is Dictionary:
		_status_label.text += (
			"    %s · %s    精力 %s/%s    金钱 %s"
			% [
				("大" + ["一", "二", "三", "四"][int(current.run.term)-1]) if current.run.has("campaign") else "第一学期",
				UiStyle.label(str(current.run.character_id)),
				current.run.vitality,
				current.run.max_vitality,
				current.run.money
			]
		)
	_notice_label.text = notice
	_notice_label.add_theme_color_override(
		"font_color", UiStyle.RED.lightened(.3) if last_error != null else Color("c5cbbd")
	)
	if screen == "battle" and last_error != null:
		_notice_label.visible = true
		_notice_label.custom_minimum_size.y = 28
	if (
		screen == "battle"
		and _tutorial_intro_done
		and not _tutorial_battle_done
		and not tutorial_visible()
		and not session.has_test_room()
		and _tutorial_run_id == str(current.run_id)
	):
		_tutorial_pending = "battle"
	if _tutorial_replay_requested:
		_tutorial_replay_requested = false
		_show_tutorial("intro", true)
	_flush_tutorial_pending()


func _flush_tutorial_pending() -> void:
	if _tutorial_pending.is_empty() or tutorial_visible() or not is_instance_valid(page):
		return
	var mode := _tutorial_pending
	_tutorial_pending = ""
	_show_tutorial(mode)


func _show_tutorial(mode: String, replay: bool = false) -> void:
	if tutorial_visible() or not is_instance_valid(page):
		return
	if replay:
		_tutorial_pending = ""
	var steps: Array = (
		UiTutorialContent.intro_steps() if mode == "intro" else UiTutorialContent.battle_steps()
	)
	if steps.is_empty():
		return
	var overlay := UiTutorialOverlay.new()
	overlay.steps = steps
	overlay.anchor_provider = Callable(self, "_tutorial_anchor")
	overlay.finished.connect(_on_tutorial_finished.bind(mode, replay))
	add_child(overlay)
	_tutorial = overlay
	_tutorial_mode = mode
	_tutorial_replay = replay
	if is_instance_valid(page):
		page.set_process_input(false)


func _on_tutorial_finished(skipped: bool, mode: String, replay: bool) -> void:
	_tutorial = null
	_tutorial_mode = ""
	_tutorial_replay = false
	if is_instance_valid(page):
		page.set_process_input(true)
	if replay:
		return
	if mode == "intro":
		_tutorial_intro_done = true
		if skipped:
			_tutorial_battle_done = true
	elif mode == "battle":
		_tutorial_battle_done = true


func _tutorial_anchor(key: String) -> Rect2:
	if not is_instance_valid(page):
		return Rect2()
	var value: Variant = page.call("tutorial_anchor", key)
	return value if value is Rect2 else Rect2()


func tutorial_visible() -> bool:
	return is_instance_valid(_tutorial) and _tutorial.visible


func tutorial_state() -> Dictionary:
	if not tutorial_visible():
		return {}
	var state := _tutorial.state()
	state["mode"] = _tutorial_mode
	state["replay"] = _tutorial_replay
	return state


func set_web_account_state(state: String, registration: bool, nickname: String, message: String, role: String = "") -> void:
	web_account_state = state
	web_team_tools_available = state == "ready" and role == "admin"
	web_registration_available = registration
	web_account_name = nickname
	web_account_message = message
	if state not in PLAYABLE_ACCOUNT_STATES:
		_back_screen = "menu"
		if _ui_screen != "settings":
			_ui_screen = "menu"
	refresh()


func _developer_tools_allowed() -> bool:
	return web_team_tools_available and web_account_state in ["", "ready"]


func resolve_web_play(allowed: bool) -> void:
	var draft := _web_play_draft
	var requested_page_id := _web_play_page_id
	_web_play_draft = {}
	_web_play_page_id = 0
	if allowed and web_account_state in PLAYABLE_ACCOUNT_STATES and _ui_screen == _web_play_screen and is_instance_valid(page) and page.get_instance_id() == requested_page_id and not draft.is_empty():
		last_error = null
		_navigate(str(draft.type), draft.get("payload", {}))


func _set_battle_frame(battle: bool) -> void:
	for side in ["left", "right", "top", "bottom"]:
		_frame_margin.add_theme_constant_override("margin_" + side, 0)
	_frame_column.add_theme_constant_override("separation", 0)
	_status_label.visible = false
	_notice_label.visible = last_error != null
	_notice_label.custom_minimum_size.y = 28 if last_error != null else 0
	if battle:
		_frame_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		# Apply the hidden header/footer and panel style before the hand is
		# built; a deferred container sort would otherwise replace it mid-draw.
		_frame_margin.notification(Container.NOTIFICATION_SORT_CHILDREN)
		_frame_column.notification(Container.NOTIFICATION_SORT_CHILDREN)
		_frame_panel.notification(Container.NOTIFICATION_SORT_CHILDREN)
		if page != null:
			page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		_frame_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func _storage_view() -> Dictionary:
	var inspected := session.inspect_saves()
	if not inspected.ok:
		return {
			"has_active_session": session.get_view().run_id != null and session.get_view().terminal_summary == null,
			"has_save": false,
			"can_continue": false,
			"save_meta": null,
			"backup_meta": null,
			"save_error": UiStyle.error_text(inspected.error)
		}
	var storage: SessionStorageView = inspected.data
	return {
		"has_active_session": storage.has_active_session,
		"has_save": storage.has_save,
		"can_continue": storage.can_continue,
		"save_meta": storage.save_meta,
		"backup_meta": storage.backup_meta,
		"save_error": UiStyle.error_text(storage.save_error) if storage.has_save else ""
	}


func _profile_view() -> Dictionary:
	var profile := session.get_profile()
	return {
		"autosave": profile.autosave,
		"completed_run_ids": profile.completed_run_ids,
		"unlocked_characters": profile.unlocked_characters,
		"unlocked_ids": profile.unlocked_ids
	}


func preview_test_action(draft: Dictionary) -> ActionPreview:
	return _test_preview(draft)


func _preview(draft: Dictionary) -> ActionPreview:
	if draft.is_empty():
		return null
	if session.has_test_room():
		return _test_preview(draft)
	var result := session.preview_action(
		ActionDraft.new(StringName(str(draft.get("type", ""))), draft.get("payload", {}))
	)
	if result.ok:
		return result.data
	var preview := ActionPreview.new()
	preview.blocking_errors.append(result.error)
	return preview


func _regate() -> void:
	if page == null:
		return
	var gates := {}
	for uid in page.action_uids():
		var preview := _preview(page.action_draft(uid))
		var reason := "请先选择目标或候选"
		if preview != null and not preview.blocking_errors.is_empty():
			reason = UiStyle.error_text(preview.blocking_errors[0])
		gates[uid] = {
			"ok": preview != null and preview.can_submit,
			"reason": "" if preview != null and preview.can_submit else reason
		}
		# Incomplete local selections must stay disabled even for single-candidate offers.
		if draft_requires_selection(page.action_draft(uid)):
			gates[uid] = {"ok": false, "reason": "请先预选具体对象"}
	var current := session.get_view()
	for uid in page.button_uids():
		var draft := page.action_draft(uid)
		var type := str(draft.get("type", ""))
		if type == "ui.save":
			gates[uid] = {
				"ok": current.can_save and not session.has_test_room(),
				"reason": "测试房间请通过测试工具保存独立快照" if session.has_test_room() else ("" if current.can_save else ("请先完成当前选择" if current.pending_choice != null else "尚未开始冒险"))
			}
		elif (
			current.pending_choice != null
			and type.begins_with("ui.")
			and (
				type
				not in [
					"ui.menu",
					"ui.new_run",
					"ui.start_run",
					"ui.random_seed",
					"ui.cancel_restart",
					"ui.continue",
					"ui.back",
					"ui.web_account",
					"ui.web_register",
					"ui.web_guest",
					"ui.web_guest_logout", "ui.records", "ui.records_back", "ui.web_history", "ui.web_stats", "ui.quit",
					"ui.web_feedback", "ui.web_feedback_admin",
					"ui.compendium", "ui.compendium_back",
					"ui.text_editor", "ui.text_editor_back"
				]
			)
		):
			gates[uid] = {"ok": false, "reason": "请先完成当前选择"}
	page.apply_gating(gates)


func draft_requires_selection(draft: Dictionary) -> bool:
	var payload: Dictionary = draft.get("payload", {})
	if draft.get("type", "") == "claim_reward":
		return str(payload.get("candidate_id", "")).is_empty()
	return false


func press(uid: String) -> bool:
	if is_instance_valid(_test_compendium):
		return _test_compendium.press(uid)
	if tutorial_visible():
		if _tutorial.has_uid(uid):
			return _tutorial.press(uid)
		# Programmatic play (tests, capture tools) may act through the page even
		# while the teaching layer is open; a real pointer cannot reach it.
		_tutorial.close(true)
	return page.press(uid) if page != null else false


func submit_action(draft: Dictionary) -> void:
	if _waiting_for_battle or draft.is_empty() or is_instance_valid(_test_compendium):
		return
	var type := str(draft.get("type", ""))
	if tutorial_visible():
		if type.begins_with("tutorial."):
			return
		_tutorial.close(true)
	var payload: Dictionary = draft.get("payload", {})
	if (type.begins_with("test.") or type in DEVELOPER_TOOL_ACTIONS) and not _developer_tools_allowed():
		return
	if not web_account_state.is_empty():
		if web_account_state not in PLAYABLE_ACCOUNT_STATES and type not in LOCKED_WEB_ACTIONS:
			return
		if type in WEB_PLAY_ACTIONS:
			if _web_play_draft.is_empty() and is_instance_valid(page):
				_web_play_draft = draft.duplicate(true)
				_web_play_page_id = page.get_instance_id()
				_web_play_screen = _ui_screen
				web_play_requested.emit(type in DEVELOPER_TOOL_ACTIONS)
			return
	last_error = null
	if session.has_test_room() and not type.begins_with("test.") and not type.begins_with("ui."):
		if type == "abandon_run" and payload.get("confirmed") == true:
			_close_test_room()
			return
		_submit_test_battle_action(draft)
		return
	if type.begins_with("test."):
		_handle_test_command(type, payload)
		return
	if type.begins_with("ui."):
		_navigate(type, payload)
		return
	var current := session.get_view()
	var scope := "%s|%s" % [current.run_id, current.revision]
	if scope == _submitted_scope:
		return
	if str(draft.get("source_run_id", page.view.get("run_id", ""))) != str(current.run_id) or int(draft.get("source_revision", page.view.get("revision", -1))) != current.revision:
		last_error = ApiError.new(&"STALE_STATE", "ui.stale")
		notice = "界面已过期，请重新选择并确认。"
		refresh()
		return
	_submitted_scope = scope
	_business_notice = _describe_action(draft)
	var damage_anchors := (page as BattleScreen).damage_target_anchors() if page is BattleScreen else {}
	var result := session.submit(
		CommandContext.new(str(current.run_id), current.revision),
		GameAction.new(StringName(type), payload)
	)
	if not result.accepted:
		_submitted_scope = ""
		_report_error(result.error)
		refresh()
		return
	_ui_screen = ""
	_business_notice = _describe_result(draft, current, result.view)
	if current.run is Dictionary and result.view.run is Dictionary and not _business_notice.is_empty():
		_business_notice += " · 金钱 %+d · 精力 %+d" % [int(result.view.run.money) - int(current.run.money), int(result.view.run.vitality) - int(current.run.vitality)]
	_action_notice(result)
	var popup_count := 0
	var preferences := session.get_presentation_settings()
	if not damage_anchors.is_empty() and result.view.battle is Dictionary and not (page is BattleScreen and page.has_refined_actors()):
		popup_count = _damage_layer.queue_events(result.events, damage_anchors, int(preferences.animation_speed) > 0 and not preferences.reduced_motion, maxf(1.0, float(preferences.animation_speed)))
	if page is BattleScreen and page.animation_enabled and not result.view.battle is Dictionary and not result.events.is_empty():
		page.use_shell_damage_popups = false
		_waiting_for_battle = true
		page.result_presentation_finished.connect(_finish_battle_transition, CONNECT_ONE_SHOT)
		page.present_result(result.events, result.view.event_log, str(result.view.run_id), result.revision)
		return
	refresh()
	_present_card_gain(current, result.view)
	var final_view := session.get_view()
	if (
		page is BattleScreen
		and result.view.battle is Dictionary
		and final_view.battle is Dictionary
		and result.view.run_id == final_view.run_id
		and result.view.battle.battle_id == final_view.battle.battle_id
	):
		page.use_shell_damage_popups = popup_count > 0
		page.consume_events(result.events, str(result.view.run_id), result.revision)
	elif audio != null:
		for event in result.events:
			if event.type == &"ddl_ticked":
				audio.play_deadline(int(event.data.get("after", 0)))
			else:
				audio.play_event(str(event.type))


func _finish_battle_transition() -> void:
	_waiting_for_battle = false
	refresh()


func _refresh_test_home() -> void:
	_clear_test_hud()
	var options := session.get_test_room_options()
	var data: Dictionary = {}
	if options.ok:
		data = {
			"options": options.data,
			"relic_pilot": true,
			"files": {
				"presets": session.list_test_files("preset"),
				"snapshots": session.list_test_files("snapshot"),
				"records": session.list_test_files("record"),
			},
		}
	else:
		_report_error(options.error)
	if page == null or not (page is TestRoomPage) or _page_key != "test_home":
		var test_home := TestRoomPage.new()
		test_home.node_options = Callable(session, "get_test_node_options")
		_replace_page("test_home", test_home)
	page.render(data)
	_set_battle_frame(false)
	_status_label.text = "测试房间"
	_notice_label.text = notice
	_notice_label.add_theme_color_override(
		"font_color", UiStyle.RED if last_error != null else UiStyle.INK
	)
	_background.texture = UiStyle.texture("BG_home")


func _refresh_test_room() -> void:
	var test_view := session.get_test_view()
	var screen := str(test_view.get("screen", ""))
	if screen == "test_room_result":
		_clear_test_hud()
		if page == null or not (page is TestRoomPage) or _page_key != "test_result":
			var result_page := TestRoomPage.new()
			result_page.screen = "test_room_result"
			_replace_page("test_result", result_page)
		page.render({"view": test_view})
		_set_battle_frame(false)
		_status_label.text = "测试房间  /  实验结束"
		_notice_label.text = "结果为实验结果，不写入正式存档；可继续编辑或重试。"
		_notice_label.add_theme_color_override("font_color", UiStyle.GOLD)
		_background.texture = UiStyle.texture("BG_success")
		return
	if screen == "test_room_campus":
		if last_error == null:
			test_view = _advance_completed_test_node(test_view)
		var data: Dictionary = test_view.get("run", {})
		var room_screen := "campaign" if data.get("campaign_offer") is Dictionary else str(data.get("screen", "map"))
		data["revision"] = test_view.test.revision
		var key := "test_campus:" + room_screen
		if page == null or _page_key != key:
			var room_page := UiExperiencePage.new()
			room_page.screen = room_screen
			if bool(test_view.test.get("editing", false)):
				session.cancel_test_edit(_test_context())
				test_view = session.get_test_view()
			_replace_page(key, room_page)
		_set_battle_frame(false)
		page.offset_top = TestHud.bar_height()
		page.render(data)
		_ensure_test_hud()
		_test_hud.render(test_view)
		page.set_process_input(not bool(test_view.test.get("editing", false)))
		_notice_label.text = notice
		_background.texture = UiStyle.texture({"shop": "BG_shop", "rest": "BG_dorm"}.get(room_screen, "BG_campus"))
		_regate()
		return
	var battle_data := _test_battle_data(test_view)
	if page == null or not (page is BattleScreen) or _page_key != "test_battle":
		if bool(test_view.test.get("editing", false)):
			session.cancel_test_edit(_test_context())
			test_view = session.get_test_view()
		_replace_page("test_battle", BattleScreen.new())
		page.preview_callback = Callable(self, "_test_preview")
	_set_battle_frame(true)
	page.offset_top = TestHud.bar_height()
	if session.is_relic_pilot():
		var preferences := session.get_presentation_settings()
		page.animation_enabled = int(preferences.animation_speed) > 0 and not preferences.reduced_motion
		page.speed_scale = maxf(1, int(preferences.animation_speed))
	page.render(battle_data)
	_ensure_test_hud()
	_test_hud.render(test_view)
	var test_state: Dictionary = test_view.get("test", {})
	var locked := bool(test_state.get("paused", false)) or bool(test_state.get("editing", false))
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	page.set_process_input(not locked)
	_status_label.text = "测试房间  /  实验  /  %s" % str(test_view.get("config", {}).get("character_id", ""))
	_notice_label.text = notice
	_notice_label.add_theme_color_override(
		"font_color", UiStyle.RED if last_error != null else UiStyle.INK
	)
	_background.texture = UiStyle.texture("BG_classroom")
	_regate()


func _advance_completed_test_node(test_view: Dictionary) -> Dictionary:
	var node: Variant = test_view.run.get("node")
	if not node is Dictionary or node.status != "active" or node.kind == "shop":
		return test_view
	var context := _test_context_from(test_view)
	var draft := {"type": "leave_node", "payload": {"node_id": node.node_id}}
	var preview := session.preview_test_action(context, draft)
	if not preview.ok or not preview.data.can_submit:
		return test_view
	var result := session.submit_test_action(context, draft)
	if not result.accepted:
		_report_error(result.error)
		return test_view
	return session.get_test_view()


func _test_battle_data(test_view: Dictionary) -> Dictionary:
	var battle: Dictionary = test_view.get("battle", {})
	var data := battle.duplicate(true)
	var config: Dictionary = test_view.get("config", {})
	var test_state: Dictionary = test_view.get("test", {})
	data["pending_choice"] = test_view.get("pending_choice")
	data["event_log"] = []
	data["run_id"] = str(test_state.get("test_id", ""))
	data["revision"] = int(test_state.get("revision", 0))
	data["can_save"] = false
	data["save_reason"] = "测试房间请通过测试工具保存独立快照"
	data["notice"] = notice
	data["character_id"] = str(config.get("character_id", "P01"))
	data["max_vitality"] = int((battle.get("player", {}) as Dictionary).get("max_vitality", 1))
	data["money"] = int(test_view.get("run", {}).get("money", 0))
	var run: Dictionary = test_view.get("run", {})
	data["cards"] = run.get("cards", config.get("cards", []))
	data["route_nodes"] = run.get("nodes", [])
	data["route_current"] = run.get("current_node_id", "")
	data["route_reachable"] = run.get("reachable_node_ids", [])
	var relics: Array[Dictionary] = []
	for relic_id in battle.get("relics", []):
		relics.append({"definition_id": str(relic_id), "relic_id": str(relic_id), "slot": relics.size(), "detail": battle.get("relic_details", {}).get(str(relic_id), {}).duplicate(true)})
	data["relics"] = relics
	data["relic_slots"] = maxi(3, relics.size())
	var year := int(test_view.get("run", {}).get("term", 0))
	data["year_label"] = "测试 · 第 %d 学年" % year if year > 0 else "测试实验"
	return data


func _replace_page(key: String, next_page: UiPage) -> void:
	_clear_test_hud()
	if page != null:
		_host.remove_child(page)
		page.queue_free()
	page = next_page
	page.audio = audio
	_host.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.action_requested.connect(submit_action)
	page.local_selection_changed.connect(func(_selection: Dictionary): _regate())
	_page_key = key


func _ensure_test_hud() -> void:
	if _test_hud != null and is_instance_valid(_test_hud):
		_host.move_child(_test_hud, -1)
		return
	_test_hud = TestHud.new()
	_test_hud.setup(session)
	_host.add_child(_test_hud)
	_test_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_test_hud.test_command.connect(_handle_test_command)
	_host.move_child(_test_hud, -1)


func _clear_test_hud() -> void:
	if _test_hud == null:
		return
	if is_instance_valid(_test_hud):
		_test_hud.queue_free()
	_test_hud = null


func _is_test_workspace() -> bool:
	return session.has_test_room() or _ui_screen == "test_room"


func _open_test_compendium() -> void:
	if not _developer_tools_allowed() or not _is_test_workspace() or is_instance_valid(_test_compendium):
		return
	var catalogue := session.get_test_compendium()
	var data: Dictionary = catalogue.data if catalogue.ok else {"error": UiStyle.error_text(catalogue.error)}
	var preferences := session.get_presentation_settings()
	data.motion_enabled = int(preferences.animation_speed) > 0 and not preferences.reduced_motion
	data.animation_speed = preferences.animation_speed
	_test_compendium_focus = get_viewport().gui_get_focus_owner()
	for control in [page, _test_hud]:
		if is_instance_valid(control):
			_test_compendium_pages[control] = [control.visible, control.process_mode]
			control.process_mode = Node.PROCESS_MODE_DISABLED
			control.hide()
	_test_compendium = UiCompendiumPage.new()
	_test_compendium.test_context = true
	_test_compendium.z_index = 550
	_test_compendium.audio = audio
	if not _test_compendium_state.is_empty():
		_test_compendium.tab = _test_compendium_state.tab
		_test_compendium._states = _test_compendium_state.states.duplicate(true)
	_host.add_child(_test_compendium)
	_test_compendium.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_test_compendium.action_requested.connect(func(draft: Dictionary):
		if draft.get("type") == "ui.compendium_back":
			_close_test_compendium())
	_test_compendium.render(data)


func _close_test_compendium() -> void:
	if not is_instance_valid(_test_compendium):
		return
	var catalogue := _test_compendium
	_test_compendium = null
	catalogue._states[catalogue.tab].scroll = catalogue._scroll.scroll_vertical
	_test_compendium_state = {"tab": catalogue.tab, "states": catalogue._states.duplicate(true)}
	_host.remove_child(catalogue)
	catalogue.queue_free()
	for control in _test_compendium_pages:
		if is_instance_valid(control):
			var saved: Array = _test_compendium_pages[control]
			control.process_mode = saved[1]
			control.visible = saved[0]
	_test_compendium_pages.clear()
	if is_instance_valid(_test_compendium_focus) and _test_compendium_focus.is_visible_in_tree():
		_test_compendium_focus.grab_focus()
	_test_compendium_focus = null


func _test_context() -> Dictionary:
	return _test_context_from(session.get_test_view())


func _test_context_from(test_view: Dictionary) -> Dictionary:
	var test_state: Dictionary = test_view.get("test", {})
	return {
		"test_id": str(test_state.get("test_id", "")),
		"branch_id": int(test_state.get("branch_id", 0)),
		"expected_revision": int(test_state.get("revision", 0)),
	}


func _submit_test_battle_action(draft: Dictionary) -> void:
	var result := session.submit_test_action(_test_context(), draft)
	if not result.accepted:
		_report_error(result.error)
		refresh()
		return
	notice = "已提交测试命令"
	refresh()
	_present_test_relics(result)


func _present_test_relics(result: ActionResult) -> void:
	if page is BattleScreen:
		var relic_events := result.events.filter(func(event): return event.type == &"relic_triggered" and RelicPilot.is_rx(event.source_id))
		if not relic_events.is_empty():
			page.consume_events(relic_events, str(page.view.run_id), result.revision)


func _test_preview(draft: Dictionary) -> ActionPreview:
	if not session.has_test_room() or draft.is_empty():
		return null
	var type := str(draft.get("type", ""))
	if type.begins_with("test.") or type.begins_with("ui.") or (type == "abandon_run" and draft.get("payload", {}).get("confirmed") == true):
		var local := ActionPreview.new()
		local.can_submit = true
		return local
	var result := session.preview_test_action(_test_context(), draft)
	if result.ok:
		return result.data
	var preview := ActionPreview.new()
	preview.blocking_errors.append(result.error)
	return preview


func _handle_test_command(command: String, payload: Dictionary) -> void:
	if is_instance_valid(_test_compendium):
		return
	last_error = null
	match command:
		"test.compendium":
			_open_test_compendium()
		"test.start":
			var started := session.start_test_room(payload.get("config", {}))
			if not started.accepted:
				_report_error(started.error)
				refresh()
				return
			_ui_screen = ""
			notice = "实验开始；可随时打开编辑器。"
			refresh()
			var locate_key := str(payload.get("locate_node_key", ""))
			if not locate_key.is_empty() and _test_hud != null:
				_test_hud.open_node_map(locate_key, true)
			_present_test_relics(started)
		"test.patch":
			var patch := {
				"schema_version": 1,
				"resolution_policy": str(payload.get("policy", "rollback")),
				"ops": payload.get("ops", []),
			}
			var applied := session.apply_test_patch(_test_context(), patch)
			if _test_hud != null:
				_test_hud.editor_result(applied.accepted)
			if not applied.accepted:
				_report_error(applied.error)
				refresh()
				return
			if payload.get("ops", []).any(func(op): return op.get("op") == "enter_node"):
				session.cancel_test_edit(_test_context())
				if _test_hud != null:
					_test_hud.finish_node_jump()
			notice = "已应用修改"
			refresh()
		"test.begin_edit":
			session.begin_test_edit(_test_context())
			refresh()
		"test.cancel_edit":
			session.cancel_test_edit(_test_context())
			refresh()
		"test.undo", "test.redo":
			var direction := "undo" if command == "test.undo" else "redo"
			var stepped := session.step_test_history(_test_context(), direction)
			if not stepped.accepted:
				_report_error(stepped.error)
			else:
				notice = "已撤销" if direction == "undo" else "已重做"
			refresh()
		"test.pause":
			var test_view := session.get_test_view()
			var paused := bool(test_view.get("test", {}).get("paused", false))
			session.pause_test_room(not paused)
			notice = "已继续" if paused else "已暂停"
			refresh()
		"test.end_turn":
			if _test_draft_count() > 0:
				notice = "请先应用或丢弃草稿，再执行真实规则操作。"
				refresh()
				_show_ui_feedback(notice, true)
				return
			var editor_open := is_instance_valid(_test_hud) and _test_hud.is_editor_open()
			if bool(session.get_test_view().get("test", {}).get("editing", false)):
				session.cancel_test_edit(_test_context())
			var ended := session.submit_test_action(_test_context(), {"type": "end_turn", "payload": {}})
			if editor_open and session.has_test_room():
				session.begin_test_edit(_test_context())
			if not ended.accepted:
				_report_error(ended.error)
			else:
				notice = "已提交测试命令"
			refresh()
			if ended.accepted:
				_present_test_relics(ended)
		"test.restore_checkpoint":
			var restored := session.restore_test_checkpoint(
				_test_context(), str(payload.get("checkpoint_id", ""))
			)
			if not restored.accepted:
				_report_error(restored.error)
			else:
				notice = "已恢复检查点并建立新分支"
			refresh()
		"test.continue":
			var continued := session.set_test_outcome(_test_context(), "clear")
			if not continued.accepted:
				_report_error(continued.error)
			else:
				notice = "已清除实验结论，可继续编辑"
			refresh()
		"test.retry_same":
			_restart_test("initial", "same")
		"test.retry_current":
			_restart_test("current", "same")
		"test.save_snapshot":
			_save_test_file("snapshot")
		"test.save_preset":
			_save_test_file("preset")
		"test.save_record":
			_save_test_file("record")
		"test.save_and_exit":
			_request_test_exit(true)
		"test.close":
			if str(session.get_test_view().get("screen", "")) == "test_room_result":
				_close_test_room()
			else:
				_request_test_exit()
		"test.delete_snapshot":
			var deleted := session.delete_test_snapshot(str(payload.get("id", "")))
			if deleted.ok:
				notice = "已删除测试快照"
			else:
				_report_error(deleted.error)
			refresh()
			_show_ui_feedback(notice, last_error != null)
		"test.load_preset", "test.load_snapshot", "test.load_record":
			var id := str(payload.get("id", ""))
			var loaded: ActionResult
			match command:
				"test.load_preset":
					loaded = session.load_test_preset(id)
				"test.load_snapshot":
					loaded = session.load_test_snapshot(id)
				_:
					loaded = session.load_test_record(id)
			if not loaded.accepted:
				_report_error(loaded.error)
				refresh()
				return
			_ui_screen = ""
			notice = "已载入测试文件"
			refresh()
		_:
			notice = "未知测试命令：" + command
			refresh()


func _restart_test(origin: String, seed_mode: String) -> void:
	var restarted := session.restart_test_battle(_test_context(), origin, seed_mode)
	if not restarted.accepted:
		_report_error(restarted.error)
	else:
		notice = "已开始新尝试"
	refresh()


func _save_test_file(kind: String) -> bool:
	var result: GameResult
	match kind:
		"preset":
			result = session.save_test_preset("测试预设")
		"record":
			result = session.save_test_record("测试记录")
		_:
			result = session.save_test_snapshot("测试快照")
	if not result.ok:
		_report_error(result.error)
		refresh()
		_show_ui_feedback(notice, true)
		return false
	notice = "已保存" + str({"snapshot": "测试快照", "preset": "测试预设", "record": "测试记录"}.get(kind, "测试文件"))
	refresh()
	_show_ui_feedback(notice)
	return true


func _test_draft_count() -> int:
	return _test_hud.editor.draft_count() if is_instance_valid(_test_hud) and is_instance_valid(_test_hud.editor) else 0


func _request_test_exit(save_immediately: bool = false) -> void:
	if not session.has_test_room():
		return
	if not is_instance_valid(_test_exit_dialog):
		_test_exit_was_editing = bool(session.get_test_view().get("test", {}).get("editing", false))
		session.begin_test_edit(_test_context())
		refresh()
		if is_instance_valid(_test_hud):
			_test_hud.set_process_input(false)
			_test_hud.editor.set_process_input(false)
		_show_test_exit_dialog()
	if save_immediately:
		_save_and_close_test_room()
	else:
		_test_exit_dialog.popup_centered()


func _show_test_exit_dialog(choose_policy: bool = false) -> void:
	if is_instance_valid(_test_exit_dialog):
		_test_exit_dialog.hide()
		_test_exit_dialog.queue_free()
	_test_exit_dialog = ConfirmationDialog.new()
	_test_exit_dialog.name = "TestRoomExitDialog"
	_test_exit_dialog.title = "退出测试房间" if not choose_policy else "保存前处理待选"
	_test_exit_dialog.dialog_text = (
		"保存当前实验及已编辑草稿，或丢弃本次未保存内容并返回主菜单。取消会保留实验和草稿。"
		if not choose_policy else
		"当前存在未完成选择。请选择回退到该操作前，或保留已生效部分并截断后续结算，再应用草稿并保存。取消保留原实验。"
	)
	_test_exit_dialog.ok_button_text = "保存并退出" if not choose_policy else "回退后保存退出"
	_test_exit_dialog.cancel_button_text = "取消"
	_test_exit_dialog.dialog_autowrap = true
	_test_exit_dialog.dialog_hide_on_ok = false
	_test_exit_dialog.add_theme_stylebox_override("panel", UiStyle.surface(UiStyle.CREAM, UiStyle.BRASS))
	_test_exit_dialog.add_theme_constant_override("buttons_min_height", 44)
	_test_exit_dialog.get_ok_button().set_meta("uid", "test:exit:save_snapshot" if not choose_policy else "test:exit:rollback")
	_test_exit_dialog.get_cancel_button().set_meta("uid", "test:exit:cancel")
	_test_exit_dialog.confirmed.connect(func(): _save_and_close_test_room("rollback" if choose_policy else ""))
	var secondary := _test_exit_dialog.add_button("丢弃并退出" if not choose_policy else "截断后保存退出", false, "discard" if not choose_policy else "truncate")
	secondary.set_meta("uid", "test:exit:discard" if not choose_policy else "test:exit:truncate")
	_test_exit_dialog.custom_action.connect(func(action: StringName):
		if action == &"truncate":
			_save_and_close_test_room("truncate")
		else:
			_close_test_room())
	_test_exit_dialog.canceled.connect(_cancel_test_exit)
	add_child(_test_exit_dialog)
	_test_exit_dialog.get_label().add_theme_font_size_override("font_size", TestUiTokens.font(16))
	for button in [_test_exit_dialog.get_ok_button(), _test_exit_dialog.get_cancel_button(), secondary]:
		button.add_theme_font_size_override("font_size", TestUiTokens.font(16))
		UiStyle.button_skin(button, "primary" if button == _test_exit_dialog.get_ok_button() else "secondary")
	_test_exit_dialog.popup_centered(Vector2i(mini(600, int(size.x) - 32), 210))
	_test_exit_dialog.get_cancel_button().grab_focus()


func _cancel_test_exit() -> void:
	if is_instance_valid(_test_exit_dialog):
		_test_exit_dialog.hide()
		_test_exit_dialog.queue_free()
	_test_exit_dialog = null
	if session.has_test_room() and not _test_exit_was_editing:
		session.cancel_test_edit(_test_context())
	if is_instance_valid(_test_hud):
		_test_hud.set_process_input(true)
		_test_hud.editor.set_process_input(true)
	refresh()


func _save_and_close_test_room(policy: String = "") -> void:
	if session.get_test_view().get("pending_choice") is Dictionary and policy.is_empty():
		_show_test_exit_dialog(true)
		return
	var ops: Array = []
	if _test_draft_count() > 0:
		ops = _test_hud.editor.draft_operations()
	var saved := session.save_test_snapshot_with_patch(_test_context(), {
		"schema_version": 1, "resolution_policy": policy if not policy.is_empty() else "stable", "ops": ops,
	}, "测试快照")
	if not saved.ok:
		_report_error(saved.error)
		refresh()
		if is_instance_valid(_test_exit_dialog):
			var error_path := str(saved.error.details.get("path", ""))
			_test_exit_dialog.dialog_text = "保存失败，实验与草稿已保留。可重试或取消。\n%s · %s%s" % [notice, str(saved.error.code), "\n" + error_path if not error_path.is_empty() else ""]
			_test_exit_dialog.popup_centered()
		return
	if _test_draft_count() > 0:
		_test_hud.editor_result(true)
	_close_test_room()


func _close_test_room() -> void:
	var closed := session.close_test_room()
	if not closed.accepted:
		_report_error(closed.error)
		refresh()
		return
	if is_instance_valid(_test_exit_dialog):
		_test_exit_dialog.hide()
		_test_exit_dialog.queue_free()
	_test_exit_dialog = null
	_ui_screen = "menu"
	notice = "已退出测试房间；正式进度未改变。"
	refresh()


func _has_previous_run() -> bool:
	var current := session.get_view()
	if current.run_id != null:
		return current.terminal_summary == null
	var storage := _storage_view()
	return storage.has_active_session or (storage.has_save and not (storage.save_meta is Dictionary and storage.save_meta.get("unfinished") == false)) or (not storage.has_save and storage.backup_meta != null)


func _advance_completed_nodes() -> void:
	# Finish the resolved node; entering the next node is always a map click.
	var current := session.get_view()
	if (
		current.pending_choice != null
		or current.terminal_summary != null
		or current.battle != null
		or not current.node is Dictionary
	):
		return
	if (
		str(current.node.get("status", "")) != "active"
		or str(current.node.get("kind", "")) == "shop"
	):
		return
	var draft := {"type": "leave_node", "payload": {"node_id": current.node.node_id}}
	var preview := _preview(draft)
	if preview == null or not preview.can_submit:
		return
	var result := session.submit(
		CommandContext.new(str(current.run_id), current.revision),
		GameAction.new(StringName(draft.type), draft.payload)
	)
	if not result.accepted:
		_report_error(result.error)
		return
	_action_notice(result)


func _action_notice(result: ActionResult) -> void:
	notice = (_business_notice + " · " if not _business_notice.is_empty() else "") + _persistence_notice(result.persistence, result.profile_merge, result.profile_cleanup)
	_advance_paused = (
		result.persistence == &"failed"
		or result.profile_merge in [&"failed", &"pending"]
		or result.profile_cleanup in [&"failed", &"pending"]
	)
	if result.save_error != null:
		notice += " · " + UiStyle.error_text(result.save_error)


func _navigate(type: String, payload: Dictionary) -> void:
	if type in DEVELOPER_TOOL_ACTIONS and not _developer_tools_allowed():
		return
	if session.has_test_room():
		if type == "ui.menu":
			_request_test_exit()
		elif type == "ui.retry":
			_restart_test("initial", "same")
		elif type == "ui.save":
			_save_test_file("snapshot")
		return
	match type:
		"ui.records":
			_ui_screen = "records"
		"ui.records_back":
			_ui_screen = "menu"
		"ui.tutorial":
			_tutorial_replay_requested = true
		"ui.web_saves", "ui.web_history", "ui.web_stats", "ui.web_feedback", "ui.web_feedback_admin":
			var section := type.trim_prefix("ui.web_")
			if web_account_state == "ready" and (section not in ["stats", "feedback_admin"] or _developer_tools_allowed()):
				web_section_requested.emit(section)
			return
		"ui.compendium":
			_ui_screen = "compendium"
		"ui.compendium_back":
			if page is UiCompendiumPage:
				page._states[page.tab].scroll = page._scroll.scroll_vertical
				_compendium_state = {"tab": page.tab, "states": page._states.duplicate(true)}
			_ui_screen = "menu"
		"ui.text_editor":
			_ui_screen = "text_editor"
			notice = "文本编辑：只修改显示文案；规则、数值、命令与存档不变。"
		"ui.text_editor_back":
			if page is UiTextEditorPage:
				_text_editor_state = page.export_state()
			_ui_screen = "menu"
		"ui.test_room":
			_ui_screen = "test_room"
			_restart_confirmation = false
			notice = "测试房间使用独立上下文，不会改动正式存档。"
			refresh()
			return
		"ui.menu":
			_ui_screen = "menu"
			_restart_confirmation = false
		"ui.new_run", "ui.retry":
			var options := session.get_setup_options()
			if not options.ok:
				_report_error(options.error)
				refresh()
				return
			var generated := (
				session.generate_run_seed()
				if options.data.default_seed.is_empty()
				else GameResult.success(options.data.default_seed)
			)
			if not generated.ok:
				_report_error(generated.error)
				refresh()
				return
			_setup_defaults.default_seed = generated.data
			_setup_seed_revision += 1
			var current := session.get_view()
			if current.run_id != null:
				_setup_defaults.default_character_id = str(current.run.character_id)
			_restart_confirmation = false
			_ui_screen = "setup"
			notice = "配置好新冒险后开始；返回菜单可继续原来的进度。"
		"ui.random_seed":
			var generated := session.generate_run_seed()
			if generated.ok:
				_setup_defaults.default_seed = generated.data
				_setup_seed_revision += 1
			else:
				_report_error(generated.error)
		"ui.cancel_restart":
			_restart_confirmation = false
		"ui.start_run":
			var replacing := _has_previous_run()
			if replacing and not bool(payload.get("confirmed", false)):
				_restart_confirmation = true
				refresh()
				return
			_setup_defaults.default_seed = str(payload.get("seed", "0"))
			var request := StartRunRequest.new(
				str(payload.get("character_id", "")),
				StringName(str(payload.get("difficulty", "normal"))),
				str(payload.get("manifest_id", "")),
				str(payload.get("seed", "0"))
			)
			var started := (
				session.restart_run(request, true) if replacing or session.get_view().run_id != null else session.start_run(request)
			)
			if started.accepted:
				_save_status = "本次冒险尚无手动保存结果"
				_active_seed = request.seed
				_ui_screen = ""
				_restart_confirmation = false
				_advance_paused = started.persistence == &"failed"
				_tutorial_run_id = str(session.get_view().run_id)
				_tutorial_intro_done = false
				_tutorial_battle_done = false
				_tutorial_pending = "intro"
				notice = (
					"冒险开始。选择地图上的第一个节点。 "
					+ _persistence_notice(
						started.persistence, started.profile_merge, started.profile_cleanup
					)
				)
				if started.save_error != null:
					notice += " · " + UiStyle.error_text(started.save_error)
				if not started.archived_save_path.is_empty():
					notice += " 旧存档原件已保留：" + started.archived_save_path
			else:
				_report_error(started.error)
		"ui.continue", "ui.start_battle", "ui.resume_battle":
			if session.get_view().run_id == null:
				var restored := session.continue_run()
				if not restored.ok:
					_report_error(restored.error)
					refresh()
					return
			_ui_screen = ""
			_submitted_scope = ""
			notice = "已返回当前冒险。"
		"ui.settings":
			_back_screen = _ui_screen
			_ui_screen = "settings"
		"ui.web_account", "ui.web_register":
			if _ui_screen == "menu":
				web_account_requested.emit(type == "ui.web_register")
			return
		"ui.web_guest":
			if _ui_screen == "menu" and web_account_state in ["login", "unavailable"]:
				web_guest_requested.emit()
			return
		"ui.web_guest_logout":
			if _ui_screen == "menu" and web_account_state == "guest":
				web_guest_logout_requested.emit()
			return
		"ui.web_privacy":
			if web_privacy_available and _ui_screen == "settings":
				web_privacy_requested.emit()
			return
		"ui.back":
			_ui_screen = _back_screen
		"ui.save":
			if _handle_save(session.save_current()):
				_advance_paused = false
			if page != null:
				page.view.save_status = _save_status
			_regate()
			_show_ui_feedback(notice, last_error != null)
			return
		"ui.save_settings":
			var changed := session.update_settings(payload)
			if changed.ok:
				audio.apply_settings(session.get_audio_settings())
				_apply_presentation()
				notice = "设置已保存。" + ("自动保存已开启。" if changed.data.autosave else "自动保存已关闭，请手动保存进度。")
			else:
				_report_error(changed.error)
		"ui.restore_backup":
			var restored := session.restore_backup()
			if restored.ok:
				_ui_screen = ""
				notice = "已从备份恢复。正式档未被替换，手动保存后更新正式档。"
			else:
				_report_error(restored.error)
		"ui.close_account_run":
			if session.get_view().run_id != null and not _handle_save(session.save_and_exit()):
				refresh()
				return
			_ui_screen = "settings" if payload.get("return_to", "") == "settings" else "menu"
		"ui.quit":
			_request_quit()
			return
	refresh()
	if type == "ui.compendium_back" and page != null and page._buttons.has("menu:compendium"):
		page._buttons["menu:compendium"].grab_focus()
	if type == "ui.text_editor_back" and page != null and page._buttons.has("menu:text_editor"):
		page._buttons["menu:text_editor"].grab_focus()
	if type == "ui.save_settings":
		_show_ui_feedback(notice, last_error != null)


func _show_ui_feedback(message: String, error: bool = false) -> void:
	_ui_feedback_generation += 1
	var generation := _ui_feedback_generation
	_ui_feedback.add_theme_font_size_override("font_size", roundi(17 * UiStyle.text_scale))
	_ui_feedback.add_theme_color_override("font_color", Color("ffd0ba") if error else UiStyle.CREAM)
	var width := minf(600 * minf(UiStyle.text_scale, 1.2), size.x - 64)
	_ui_feedback.position = Vector2((size.x - width) * .5, 66)
	# Give wrapping its final width before setting text, otherwise an initially
	# zero-width Label caches one character per line and stays unnecessarily tall.
	_ui_feedback.size = Vector2(width, 0)
	_ui_feedback.text = message
	_ui_feedback.size.y = 0
	_ui_feedback.show()
	get_tree().create_timer(6.0 if error else 3.5).timeout.connect(func():
		if generation == _ui_feedback_generation and is_instance_valid(_ui_feedback): _ui_feedback.hide())


func _apply_presentation() -> void:
	var preferences := session.get_presentation_settings()
	UiStyle.text_scale = int(preferences.text_scale) / 100.0
	UiStyle.reduced_motion = bool(preferences.reduced_motion)


func _describe_action(draft: Dictionary) -> String:
	var payload: Dictionary = draft.get("payload", {})
	match str(draft.get("type", "")):
		"claim_reward":
			return "已获得：" + UiStyle.label(str(payload.get("candidate_id", "")))
		"skip_reward":
			return "已跳过此项奖励"
		"remove_card":
			return "已支付金钱并移除所选卡牌"
		"buy_item":
			return "购买成功，商品已到账"
		"take_rest":
			return "休整完成"
		"choose_event":
			return "事件选择已生效"
		"choose_campaign":
			return "学年选择已生效：" + str({"card": "卡牌已加入牌组", "upgrade": "卡牌已升级", "remove": "卡牌已移除", "claim": "饰品领取已完成", "convert": "饰品已折算金钱", "resources": "资源已领取", "skip": "已跳过"}.get(str(payload.get("option_id", "")), "方向 / 去向已确认"))
	return ""


func _describe_result(draft: Dictionary, before: SessionView, after: SessionView) -> String:
	if not before.run is Dictionary or not after.run is Dictionary:
		return _describe_action(draft)
	var payload: Dictionary = draft.get("payload", {})
	var candidate := str(payload.get("candidate_id", ""))
	if draft.get("type", "") == "choose_campaign" and payload.get("option_id", "") == "claim":
		var old_ids: Array = before.run.relics.map(func(relic): return str(relic.definition_id))
		if old_ids.has(candidate):
			return "重复饰品已折算金钱：" + UiStyle.label(candidate)
		var replacement := str(payload.get("replace_relic_id", ""))
		for relic in before.run.relics:
			if str(relic.relic_id) == replacement:
				return "饰品已替换：" + UiStyle.label(str(relic.definition_id)) + " → " + UiStyle.label(candidate)
		return "已获得饰品：" + UiStyle.label(candidate)
	var old_cards: Array = before.run.cards.map(func(card): return str(card.card_id))
	for card in after.run.cards:
		if not old_cards.has(str(card.card_id)):
			return "已加入牌组：" + UiStyle.label(str(card.definition_id))
	return _describe_action(draft)


func _present_card_gain(before: SessionView, after: SessionView) -> void:
	var preferences := session.get_presentation_settings()
	if preferences.reduced_motion or int(preferences.animation_speed) == 0 or not before.run is Dictionary or not after.run is Dictionary:
		return
	var ids: Array = before.run.cards.map(func(card): return str(card.card_id))
	for card in after.run.cards:
		if ids.has(str(card.card_id)):
			continue
		var image := TextureRect.new()
		image.texture = UiStyle.texture(str(card.definition_id))
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.size = Vector2(100, 140)
		image.position = size * 0.5 - image.size * 0.5
		image.z_index = 300
		add_child(image)
		var destination := Vector2(40, 80)
		if page._buttons.has("inspect:deck"):
			destination = page._buttons["inspect:deck"].global_position - global_position
		var tween := create_tween().set_parallel(true)
		var duration := 0.35 / maxf(1, int(preferences.animation_speed))
		tween.tween_property(image, "position", destination, duration)
		tween.tween_property(image, "scale", Vector2(0.25, 0.25), duration)
		tween.tween_property(image, "modulate:a", 0.0, duration)
		tween.chain().tween_callback(image.queue_free)
		return


func _request_quit() -> void:
	if is_instance_valid(_quit_dialog):
		_quit_dialog.popup_centered()
		return
	var dirty_text: bool = page is UiTextEditorPage and page.dirty_count() > 0
	var dirty_test := session.has_test_room() and bool(session.get_test_view().get("test", {}).get("dirty", false))
	if not session.has_unsaved_progress() and not dirty_text and not dirty_test:
		_finish_quit(false)
		return
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "有未保存的进度"
	_quit_dialog.dialog_text = "当前进度尚未保存。保存后退出游戏？"
	_quit_dialog.ok_button_text = "保存并退出"
	_quit_dialog.cancel_button_text = "取消"
	if dirty_text or dirty_test or not session.get_view().can_save:
		_quit_dialog.dialog_text = "有未保存的编辑或尚未完成的选择。返回完成并保存，或放弃这些修改后退出。"
		_quit_dialog.ok_button_text = "返回游戏"
		_quit_dialog.confirmed.connect(func(): _quit_dialog.queue_free(); _quit_dialog = null)
	else:
		_quit_dialog.confirmed.connect(func(): _quit_dialog.queue_free(); _quit_dialog = null; _finish_quit(true))
	_quit_dialog.add_button("不保存退出", false, "discard")
	_quit_dialog.custom_action.connect(func(_action): _finish_quit(false))
	_quit_dialog.canceled.connect(func(): _quit_dialog.queue_free(); _quit_dialog = null)
	add_child(_quit_dialog)
	_quit_dialog.popup_centered(Vector2i(mini(520, int(size.x) - 32), 180))
	_quit_dialog.get_cancel_button().grab_focus()


func _finish_quit(save: bool) -> void:
	if save and not _handle_save(session.save_current()):
		refresh()
		return
	if not web_account_state.is_empty():
		web_section_requested.emit("quit")
	get_tree().quit()


func _handle_save(result: GameResult) -> bool:
	if not result.ok:
		_report_error(result.error)
		_save_status = "最近手动保存失败：" + UiStyle.error_text(result.error)
		return false
	notice = _persistence_notice(&"saved", result.data.profile_merge, result.data.profile_cleanup)
	_save_status = "最近手动保存：" + notice
	return (
		result.data.profile_merge not in [&"failed", &"pending"]
		and result.data.profile_cleanup not in [&"failed", &"pending"]
	)


func _persistence_notice(saved: StringName, merged: StringName, cleanup: StringName) -> String:
	if saved == &"failed":
		return "操作已生效，但进度保存失败。请手动重试保存。"
	if merged in [&"failed", &"pending"]:
		return "本局已保存，长期进度待更新；请重试保存。"
	if cleanup in [&"failed", &"pending"]:
		return "长期进度已更新，收尾保存待重试。"
	if saved == &"saved":
		return "进度已保存。" if merged == &"not_pending" else "本局与长期进度已保存。"
	return "操作已生效；请在稳定状态手动保存。" if not session.get_profile().autosave else "请完成当前选择，之后自动保存。"


func _report_error(error: ApiError) -> void:
	last_error = error
	notice = UiStyle.error_text(error)
	if audio != null:
		audio.play_ui("error")

