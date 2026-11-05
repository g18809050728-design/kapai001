class_name GameShell
extends Control

const BattleDamagePopup = preload("res://src/ui/battle/battle_damage_popup_layer.gd")

var session: GameSession
var page: UiPage
var audio: AudioManager
var last_error: ApiError
var notice: String = "准备好开始你的四年冒险了吗？"
var _ui_screen := "menu"
var _back_screen := "menu"
var _page_key := ""
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
var _battle_transition_cover: TextureRect


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
	_background.modulate.a = 0.18
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
	_notice_label.custom_minimum_size.y = 32
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.add_theme_font_size_override("font_size", 15)
	column.add_child(_notice_label)
	_damage_layer = BattleDamagePopup.new()
	_damage_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_layer.z_index = 500
	add_child(_damage_layer)


func show_screen(screen: String) -> void:
	_ui_screen = screen
	refresh()


func refresh() -> void:
	if not is_instance_valid(_host):
		return
	if _ui_screen.is_empty() and not _advance_paused and last_error == null:
		_advance_completed_nodes()
	var current := session.get_view()
	var screen := _ui_screen if not _ui_screen.is_empty() else String(current.screen)
	var data: Dictionary = {}
	match screen:
		"menu":
			data = _storage_view()
			data.profile = _profile_view()
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
				"manifests": options.data.manifests,
				"default_seed": options.data.default_seed
			}
			data.merge(_setup_defaults, true)
			data.seed_revision = _setup_seed_revision
			data.replaces_run = _has_previous_run()
			data.confirm_restart = _restart_confirmation
			var storage := _storage_view()
			data.unreadable_save = storage.has_save and not storage.can_continue
		"settings":
			data = _storage_view()
			data.settings = {"autosave": session.get_profile().autosave}
			data.settings.audio = session.get_audio_settings()
			data.settings.presentation = session.get_presentation_settings()
			data.can_restore = (
				current.run_id == null
				and data.backup_meta is Dictionary
				and data.backup_meta.get("valid", false)
			)
			data.can_save = current.can_save
			data.difficulty = current.run.get("difficulty", "") if current.run is Dictionary else ""
			if current.run is Dictionary:
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
	if page == null or _page_key != screen:
		if page != null:
			_host.remove_child(page)
			page.queue_free()
		if screen == "battle":
			page = BattleScreen.new()
			page.preview_callback = Callable(self, "_preview")
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
	page.render(data)
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
		"font_color", UiStyle.RED if last_error != null else UiStyle.INK
	)
	if screen == "battle" and last_error != null:
		_notice_label.visible = true
		_notice_label.custom_minimum_size.y = 28


func _set_battle_frame(battle: bool) -> void:
	for side in ["left", "right", "top", "bottom"]:
		_frame_margin.add_theme_constant_override("margin_" + side, 0 if battle else 10)
	_frame_column.add_theme_constant_override("separation", 0 if battle else 10)
	_status_label.visible = not battle
	_notice_label.visible = not battle
	_notice_label.custom_minimum_size.y = 28 if battle else 32
	if battle:
		_frame_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		_frame_panel.remove_theme_stylebox_override("panel")


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


func _preview(draft: Dictionary) -> ActionPreview:
	if draft.is_empty():
		return null
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
				"ok": current.can_save,
				"reason": "请先完成当前选择" if current.pending_choice != null else "尚未开始冒险"
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
					"ui.back"
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
	return page.press(uid) if page != null else false


func submit_action(draft: Dictionary) -> void:
	if draft.is_empty():
		return
	var type := str(draft.get("type", ""))
	var payload: Dictionary = draft.get("payload", {})
	last_error = null
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
	if not damage_anchors.is_empty():
		popup_count = _damage_layer.queue_events(result.events, damage_anchors, int(preferences.animation_speed) > 0 and not preferences.reduced_motion, maxf(1.0, float(preferences.animation_speed)))
	if popup_count > 0 and page is BattleScreen and not result.view.battle is Dictionary:
		_show_battle_transition_cover(popup_count, preferences)
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
		page.consume_events(result.events, str(result.view.run_id), result.revision)
	elif audio != null:
		for event in result.events:
			if event.type == &"ddl_ticked":
				audio.play_deadline(int(event.data.get("after", 0)))
			else:
				audio.play_event(str(event.type))


func _show_battle_transition_cover(count: int, preferences: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image := get_viewport().get_texture().get_image()
	if image.is_empty():
		return
	_clear_battle_transition_cover()
	_battle_transition_cover = TextureRect.new()
	_battle_transition_cover.texture = ImageTexture.create_from_image(image)
	_battle_transition_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_transition_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_battle_transition_cover.stretch_mode = TextureRect.STRETCH_SCALE
	_battle_transition_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_battle_transition_cover.z_index = 400
	add_child(_battle_transition_cover)
	var speed := maxf(1.0, float(preferences.animation_speed))
	var duration := ((count - 1) * BattleDamagePopup.BASE_DELAY + (BattleDamagePopup.BASE_DURATION if int(preferences.animation_speed) > 0 and not preferences.reduced_motion else 0.4)) / speed
	get_tree().create_timer(duration + 0.05).timeout.connect(_clear_battle_transition_cover)


func _clear_battle_transition_cover() -> void:
	if is_instance_valid(_battle_transition_cover):
		_battle_transition_cover.queue_free()
	_battle_transition_cover = null


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
	match type:
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
				_active_seed = request.seed
				_ui_screen = ""
				_restart_confirmation = false
				_advance_paused = started.persistence == &"failed"
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
		"ui.back":
			_ui_screen = _back_screen
		"ui.save":
			if _handle_save(session.save_current()):
				_advance_paused = false
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
		"ui.quit":
			if session.get_view().run_id != null:
				if not _handle_save(session.save_and_exit()) or session.get_view().run_id != null:
					refresh()
					return
			get_tree().quit()
	refresh()


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


func _handle_save(result: GameResult) -> bool:
	if not result.ok:
		_report_error(result.error)
		return false
	notice = _persistence_notice(&"saved", result.data.profile_merge, result.data.profile_cleanup)
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
