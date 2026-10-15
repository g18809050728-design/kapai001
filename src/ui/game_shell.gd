class_name GameShell
extends Control

var session: GameSession
var page: UiPage
var last_error: ApiError
var notice: String = "准备好开始你的第一学期了吗？"
var _ui_screen := "menu"
var _back_screen := "menu"
var _page_key := ""
var _host: Control
var _background: TextureRect
var _notice_label: Label
var _status_label: Label
var _setup_defaults: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	if session == null:
		session = GameSession.new()
	if session.get_parent() == null:
		add_child(session)
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
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_status_label = Label.new()
	_status_label.text = "交大四年  /  DDL 战争"
	_status_label.add_theme_font_size_override("font_size", 16)
	column.add_child(_status_label)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	_host = Control.new()
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_host)
	_notice_label = Label.new()
	_notice_label.custom_minimum_size.y = 48
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.add_theme_font_size_override("font_size", 15)
	column.add_child(_notice_label)


func show_screen(screen: String) -> void:
	_ui_screen = screen
	refresh()


func refresh() -> void:
	if not is_instance_valid(_host):
		return
	var current := session.get_view()
	var screen := _ui_screen if not _ui_screen.is_empty() else String(current.screen)
	var data: Dictionary = {}
	match screen:
		"menu":
			data = _storage_view()
			data.profile = _profile_view()
			data.can_start_new = current.run_id == null or current.terminal_summary != null
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
		"settings":
			data = _storage_view()
			data.settings = {"autosave": session.get_profile().autosave}
			data.can_restore = (
				current.run_id == null
				and data.backup_meta is Dictionary
				and data.backup_meta.get("valid", false)
			)
			data.can_save = current.can_save
			data.difficulty = current.run.get("difficulty", "") if current.run is Dictionary else ""
			if current.run is Dictionary:
				data.seed = _setup_defaults.get("default_seed", "旧存档未记录初始种子")
		"battle":
			if current.battle is Dictionary:
				data = current.battle.duplicate(true)
				data.pending_choice = current.pending_choice
				data.event_log = current.event_log.duplicate(true)
				data.run_id = current.run_id
				data.revision = current.revision
				data.can_save = current.can_save
			else:
				screen = "battle_entry"
				data = current.run.duplicate(true) if current.run is Dictionary else {}
		_:
			data = current.run.duplicate(true) if current.run is Dictionary else {}
			data.can_save = current.can_save
			data.terminal_summary = current.terminal_summary
			data.profile_commit_status = current.profile_commit_status
	if page == null or _page_key != screen:
		if page != null:
			_host.remove_child(page)
			page.queue_free()
		if screen == "battle":
			page = BattleScreen.new()
			page.preview_callback = Callable(self, "_preview")
		else:
			page = UiFlowPage.new()
			page.screen = screen
		_host.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.action_requested.connect(submit_action)
		page.local_selection_changed.connect(func(_selection: Dictionary): _regate())
		_page_key = screen
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
			"    第一学期 · %s    精力 %s/%s    金钱 %s"
			% [
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


func _storage_view() -> Dictionary:
	var inspected := session.inspect_saves()
	if not inspected.ok:
		return {
			"has_active_session": session.get_view().run_id != null,
			"has_save": false,
			"save_meta": null,
			"backup_meta": null,
			"save_error": UiStyle.error_text(inspected.error)
		}
	var storage: SessionStorageView = inspected.data
	return {
		"has_active_session": storage.has_active_session,
		"has_save": storage.has_save,
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
	var current := session.get_view()
	for uid in page.button_uids():
		var draft := page.action_draft(uid)
		var type := str(draft.get("type", ""))
		if type == "ui.save":
			gates[uid] = {
				"ok": current.can_save,
				"reason": "请先完成当前选择" if current.pending_choice != null else "尚未开始学期"
			}
		elif current.pending_choice != null and type.begins_with("ui."):
			gates[uid] = {"ok": false, "reason": "请先完成当前选择"}
	page.apply_gating(gates)


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
	var result := session.submit(
		CommandContext.new(str(current.run_id), current.revision),
		GameAction.new(StringName(type), payload)
	)
	if not result.accepted:
		_report_error(result.error)
		refresh()
		return
	_ui_screen = ""
	notice = _persistence_notice(result.persistence, result.profile_merge, result.profile_cleanup)
	if result.save_error != null:
		notice += " · " + UiStyle.error_text(result.save_error)
	refresh()
	if page is BattleScreen:
		page.consume_events(result.events, str(result.view.run_id), result.revision)


func _navigate(type: String, payload: Dictionary) -> void:
	match type:
		"ui.menu":
			_ui_screen = "menu"
		"ui.new_run", "ui.retry":
			var current := session.get_view()
			if current.run_id != null:
				if current.terminal_summary == null:
					notice = "已有进行中的学期，请继续或在地图中放弃后重开。"
					refresh()
					return
				_setup_defaults.default_character_id = str(current.run.character_id)
				var saved := session.save_and_exit()
				if not _handle_save(saved) or session.get_view().run_id != null:
					refresh()
					return
			_ui_screen = "setup"
		"ui.start_run":
			_setup_defaults.default_seed = str(payload.get("seed", "0"))
			var started := session.start_run(
				StartRunRequest.new(
					str(payload.get("character_id", "")),
					StringName(str(payload.get("difficulty", "normal"))),
					str(payload.get("manifest_id", "")),
					str(payload.get("seed", "0"))
				)
			)
			if started.accepted:
				_ui_screen = ""
				notice = (
					"学期开始。选择地图上的第一个节点。 "
					+ _persistence_notice(
						started.persistence, started.profile_merge, started.profile_cleanup
					)
				)
				if started.save_error != null:
					notice += " · " + UiStyle.error_text(started.save_error)
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
			notice = "已返回当前学期。"
		"ui.settings":
			_back_screen = _ui_screen
			_ui_screen = "settings"
		"ui.back":
			_ui_screen = _back_screen
		"ui.save":
			_handle_save(session.save_current())
		"ui.save_settings":
			var changed := session.update_settings(payload)
			if changed.ok:
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
