extends RefCounted

const OUT := "res://artifacts/verification/settings-result-20261106/visual"
var capture_enabled := false
var _failures: Array[String] = []
var _captures: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	_check_queue_order()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for frame in 3:
			await tree.process_frame
		await _check_settings(dimensions)
		await _check_draw_sequence(dimensions)
		await _check_battle_and_map(dimensions)
		await _check_final_blow(dimensions)
	tree.root.size = old_size
	await tree.create_timer(0.12).timeout
	if capture_enabled:
		var file := FileAccess.open(OUT.path_join("capture.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_captures, "\t"))
	print("BATTLE_MAP_FEEDBACK=", JSON.stringify({"failures": _failures, "captures": _captures.size(), "scope": "real four-year session commands; isolated saves; controlled no-focus display and map geometry"}))
	return _failures


func _check_settings(dimensions: Vector2i) -> void:
	var session := GameSession.new(SaveStore.new("user://settings-state-%s" % Time.get_ticks_usec()))
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("settings")
	await _frames(shell, 3)
	var applied := session.get_presentation_settings()
	_check(shell.page._buttons["settings:speed:" + str(applied.animation_speed)].get_meta("setting_selected", false), "saved animation speed is visibly selected")
	_check(shell.page._buttons["settings:motion:false"].text.contains("已选"), "standard motion has a persistent selection marker")
	_check(shell.page._settings_status.text.begins_with("已生效"), "unchanged settings show applied status")
	await _save(shell, "settings-current-" + str(dimensions.x))
	var speed := 4 if int(applied.animation_speed) != 4 else 1
	shell.press("settings:speed:" + str(speed))
	shell.press("settings:motion:true")
	_check(session.get_presentation_settings() == applied, "draft speed and motion do not change applied preferences")
	_check(shell.page._settings_status.text.contains("尚未应用"), "changed preferences show pending status")
	_check(shell.page._buttons["settings:motion:true"].button_pressed and not shell.page._buttons["settings:motion:false"].button_pressed, "only the selected motion option stays pressed")
	_check(shell.page._buttons["settings:speed:" + str(speed)].button_pressed, "draft speed is clearly selected")
	await _save(shell, "settings-pending-" + str(dimensions.x))
	shell.press("settings:autosave:false")
	shell.press("settings:audio:true")
	_check(shell.page._buttons["settings:autosave:false"].button_pressed and shell.page._buttons["settings:audio:true"].button_pressed, "autosave and sound use the same selected state")
	shell.press("settings:apply")
	_check(shell.page._settings_status.text.begins_with("已生效"), "applying settings clears pending status")
	_check(_all_labels(shell.page).contains("动画关闭（减少动态）"), "current summary describes actual reduced motion behavior")
	_check(session.get_presentation_settings().animation_speed == speed, "reduced motion preserves selected speed preference")
	var slider: HSlider = shell.page.body.find_children("VolumeMaster", "HSlider", true, false)[0]
	slider.value = 41
	_check(shell.page._settings_status.text.contains("尚未应用"), "volume preview updates pending status immediately")
	shell.press("settings:apply")
	shell.show_screen("menu")
	shell.show_screen("settings")
	_check(shell.page._buttons["settings:speed:" + str(speed)].button_pressed and shell.page._settings_status.text.begins_with("已生效"), "reopening settings restores applied selection and status")
	await _save(shell, "settings-applied-" + str(dimensions.x))
	shell.free()
	UiStyle.text_scale = 1.0
	UiStyle.reduced_motion = false


func _all_labels(node: Node) -> String:
	var text := str(node.text) + "\n" if node is Label else ""
	for child in node.get_children():
		text += _all_labels(child)
	return text


func _check_queue_order() -> void:
	var animator := BattleEventAnimator.new()
	var presented: Array[int] = []
	animator.event_presented.connect(func(event: Dictionary, _text: String): presented.append(int(event.index)))
	var events: Array = []
	for index in 3:
		events.append({"index": index, "type": "card_drawn", "source_id": "", "target_ids": ["card%d" % index], "data": {}})
	animator.play(events, "queue-fixture", 1)
	_check(presented == [0] and animator.pending_type_count("card_drawn") == 2, "draw batch presents one card and queues the next two")
	animator.advance(0.1)
	_check(presented == [0], "next draw waits for the current card flight")
	animator.advance(0.48)
	_check(presented == [0, 1], "second card draws after the first flight")
	animator.advance(1.0)
	_check(presented == [0, 1, 2], "draws preserve published event order")
	animator.play(events, "queue-fixture", 1)
	_check(presented == [0, 1, 2], "repeated draw batch never duplicates movement")
	var finished: Array = []
	animator.queue_finished.connect(func(): finished.append(true))
	animator.advance(0.3)
	_check(finished.is_empty(), "queue completion waits for the last card to land")
	animator.advance(0.3)
	_check(finished.size() == 1, "queue finishes after the final flight duration")


func _check_battle_and_map(dimensions: Vector2i) -> void:
	var suffix := str(dimensions.x)
	var session := GameSession.new(SaveStore.new("user://battle-map-feedback-%s-%s" % [suffix, Time.get_ticks_usec()]))
	session.update_settings({"autosave": false})
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "0")).accepted, "start actual four-year fixture")
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	await _frames(shell, 3)
	var map_page := shell.page as UiExperiencePage
	var map_view := map_page.view.duplicate(true)
	var source: Dictionary = map_view.nodes.filter(func(node): return int(node.layer) == 7)[0]
	map_view.current_node_id = source.node_id
	map_view.reachable_node_ids = source.next_ids.duplicate()
	source.status = "completed"
	map_view.revision += 1
	map_page.render(map_view)
	await _frames(shell, 14)
	_check(map_page._buttons["node:" + str(source.node_id)].get_meta("current_node", false), "map identifies the actual current node")
	_check(map_view.reachable_node_ids.size() <= 2, "displayed next options use only the source node successors")
	await _save(shell, "map-current-and-branches-" + suffix)
	shell.refresh()
	_check(_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])), "enter real four-year battle")
	await _frames(shell, 3)
	var battle := shell.page as BattleScreen
	battle._finish_event_presentation()
	# The no-focus state is an isolated input fixture; preview still validates real costs.
	var focus: int = session._state.battle.player.focus
	session._state.battle.player.focus = 0
	shell.refresh()
	await _frames(shell, 3)
	battle = shell.page as BattleScreen
	var blocked_id := ""
	for card in battle.view.hand:
		if int(card.effective_cost) > 0:
			blocked_id = str(card.card_id)
			break
	_check(not blocked_id.is_empty(), "no-focus fixture has a card with positive cost")
	if not blocked_id.is_empty():
		var before: String = _helpers.fingerprint(session)
		var control: Button = battle._buttons["card:" + blocked_id]
		_check(control.disabled, "real preview disables an unaffordable card")
		var point := control.get_global_rect().get_center()
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			shell.get_tree().root.push_input(event, true)
		await _frames(shell, 2)
		_check(battle.display_snapshot().panel.is_empty(), "unaffordable card click never opens introduction at " + suffix)
		_check(not battle._feedback_text.is_empty(), "unaffordable click gives a visible preview reason at " + suffix)
		_check(before == _helpers.fingerprint(session), "no-focus click preserves full state, revision and RNG at " + suffix)
		await _save(shell, "no-focus-feedback-" + suffix)
	session._state.battle.player.focus = focus
	shell.refresh()
	await _frames(shell, 2)
	battle = shell.page as BattleScreen
	var work_id := ""
	for card in battle.view.hand:
		if str(card.definition_id) in ["R3-C-01", "R3-P01-02"]:
			work_id = str(card.card_id)
			break
	_check(not work_id.is_empty(), "production starting hand contains a real work card")
	if not work_id.is_empty():
		var original_card := battle._hand_card_control(work_id)
		var original_center := battle._stage_center(original_card)
		var current := session.get_view()
		var result := session.submit(CommandContext.new(str(current.run_id), current.revision), GameAction.new(&"play_card", {"card_instance_id": work_id, "target_ids": [str(current.battle.tasks[0].task_id)], "replace_unit_id": null}))
		_check(result.accepted, "work card executes through the actual session")
		shell.refresh()
		battle = shell.page as BattleScreen
		if result.accepted:
			battle.consume_events(result.events, str(result.view.run_id), result.revision)
			_check(battle._presentation._departing.get(work_id) == original_card, "played card keeps the actual original hand control")
			_check(battle._stage_center(original_card).distance_to(original_center) < 1.0, "played card remains at its original position before discard")
			await _capture_events(shell, ["card_played", "completion_applied", "card_resolved"], suffix)
	var end_view := session.get_view()
	var ended := session.submit(CommandContext.new(str(end_view.run_id), end_view.revision), GameAction.new(&"end_turn", {"retained_card_ids": []}))
	_check(ended.accepted, "end turn produces actual discard and draw events")
	shell.refresh()
	battle = shell.page as BattleScreen
	if ended.accepted and battle != null:
		battle.consume_events(ended.events, str(ended.view.run_id), ended.revision)
		await _capture_events(shell, ["card_discarded", "pressure_applied", "card_drawn"], suffix)
		var stable: String = _helpers.fingerprint(session)
		battle.animation_enabled = false
		battle._animator.animation_enabled = false
		battle._clear_event_visuals()
		_check(battle._animator.pending_count() == 0, "animation off immediately drains outstanding presentation")
		_check(stable == _helpers.fingerprint(session), "skipping effects preserves actual four-year state and RNG")
	await _frames(shell, 2)
	shell.free()


func _check_draw_sequence(dimensions: Vector2i) -> void:
	var session := GameSession.new(SaveStore.new("user://draw-sequence-%s" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "0"))
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	await _frames(shell, 3)
	_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0]))
	var battle := shell.page as BattleScreen
	battle.set_process(false)
	# Sample a 125 ms flight deterministically even when the first texture
	# upload takes longer than one flight. The production Tween is stepped
	# with its actual fourfold durations; rendering continues while paused.
	shell.get_tree().paused = true
	_check(is_equal_approx(battle.effect_speed(), 4.0) and is_equal_approx(battle._animator.speed_scale, 4.0), "1x setting applies the requested fourfold effect and queue speed")
	var stable: String = _helpers.fingerprint(session)
	var pending: Array = battle.display_snapshot().pending_hand_cards.duplicate()
	_check(pending.size() == battle.view.hand.size() and pending.size() > 1, "initial draw batch hides the entire new hand at " + str(dimensions.x))
	var controls := {}
	for id in pending:
		var card := battle._hand_card_control(id)
		controls[id] = card
		_check(card.modulate.a == 0.0 and card.focus_mode == Control.FOCUS_NONE, "pending hand card is invisible and cannot receive focus")
	await _save(shell, "draw-before-" + str(dimensions.x))
	for ordinal in 2:
		for step in 100:
			if str(battle._animator.last_event.get("type", "")) == "card_drawn" and battle._presentation.is_pending(str(battle._animator.last_event.target_ids[0])):
				break
			battle._animator.advance(10.0)
		await _frames(shell, 2)
		var id := str(battle._animator.last_event.target_ids[0])
		if not is_instance_valid(controls[id]):
			_check(false, "draw control survives first-frame layout")
			shell.get_tree().paused = false
			shell.free()
			return
		var moving: Control = controls[id]
		_check(moving.get_meta("card_in_flight", false) and moving.modulate.a == 1.0, "draw flies the real opaque hand control")
		var flights := battle._stage.get_children().filter(func(child): return child.get_meta("card_in_flight", false))
		_check(flights.size() == 1 and flights[0] == moving, "only one actual card flies at a time")
		var selected := battle.selection_snapshot()
		battle._on_card_pressed(id)
		_check(battle.selection_snapshot() == selected, "in-flight card cannot be selected")
		for other_id in battle.display_snapshot().pending_hand_cards:
			if other_id != id:
				_check(controls[other_id].modulate.a == 0.0, "later draws stay hidden until their turn")
		var flight: Tween = battle._presentation._flights[id].tween
		flight.custom_step(0.05)
		_check(battle._presentation.is_pending(id), "card remains pending during its flight")
		await _save(shell, "draw-%d-moving-%s" % [ordinal, dimensions.x])
		flight.custom_step(0.08)
		_check(not battle._presentation.is_pending(id) and moving == battle._hand_card_control(id) and moving.modulate.a == 1.0, "same real card becomes the hand card only after landing")
		_check(not moving.get_meta("card_in_flight", false), "landing retires movement")
		await _save(shell, "draw-%d-landed-%s" % [ordinal, dimensions.x])
		battle._animator.advance(10.0)
	var event_batch: Array = session.get_view().event_log.filter(func(event): return int(event.get("revision", -1)) == int(battle.view.revision))
	var pending_before: Array = battle.display_snapshot().pending_hand_cards.duplicate()
	battle.consume_events(event_batch, str(battle.view.run_id), int(battle.view.revision))
	_check(battle.display_snapshot().pending_hand_cards == pending_before, "duplicate batch does not re-hide landed cards or duplicate pending draws")
	await _frames(shell, 2)
	battle.animation_enabled = false
	for id in controls:
		_check(controls[id].modulate.a == 1.0 and not controls[id].get_meta("draw_pending", false) and not controls[id].get_meta("card_in_flight", false), "animation off reveals all remaining cards and restores their slots")
	_check(battle._animator.pending_count() == 0 and battle.display_snapshot().active_visual_effects == 0, "animation off cleans all pending flights")
	_check(stable == _helpers.fingerprint(session), "sequential draw and skip preserve complete state and RNG")
	# Rebuilds must also restore a card that is temporarily outside its slot.
	battle.animation_enabled = true
	var id := str(battle.view.hand[0].card_id)
	var single_draw := [{"index": 999, "type": "card_drawn", "source_id": "", "target_ids": [id], "data": {}}]
	battle.consume_events(single_draw, str(battle.view.run_id), int(battle.view.revision) + 100)
	await _frames(shell, 2)
	_check(battle._hand_card_control(id).get_meta("card_in_flight", false), "redraw fixture starts a real hand flight")
	battle._render_from_local()
	_check(battle._hand_card_control(id).modulate.a == 1.0 and battle.display_snapshot().pending_hand_cards.is_empty(), "local rebuild restores every hand slot and pending card")
	battle.consume_events(single_draw, str(battle.view.run_id), int(battle.view.revision) + 101)
	await _frames(shell, 2)
	var root := shell.get_tree().root
	root.size = Vector2i(960, 600) if dimensions.x == 1280 else Vector2i(1280, 800)
	await _frames(shell, 4)
	_check(battle.display_snapshot().pending_hand_cards.is_empty() and battle.display_snapshot().active_visual_effects == 0, "resize settles pending presentation and removes temporary slots")
	for card in battle.view.hand:
		_check(battle._hand_card_control(str(card.card_id)).modulate.a == 1.0, "resized hand has no hidden cards")
	_check(stable == _helpers.fingerprint(session), "rebuild and resize leave the production session unchanged")
	root.size = dimensions
	await _frames(shell, 3)
	shell.get_tree().paused = false
	shell.free()


func _capture_events(shell: GameShell, expected: Array, suffix: String) -> void:
	var battle := shell.page as BattleScreen
	battle.set_process(false)
	shell.get_tree().paused = true
	var stable: String = _helpers.fingerprint(shell.session)
	var found := {}
	for index in 200:
		await _frames(shell, 1)
		var kind := str(battle._animator.last_event.get("type", ""))
		if expected.has(kind) and not found.has(kind):
			found[kind] = true
			_check(battle.display_snapshot().active_visual_effects > 0, "actual " + kind + " has a visible event effect at " + suffix)
			if kind in ["card_resolved", "card_discarded"]:
				var id := battle._presentation.card_id(battle._animator.last_event)
				var flights := battle._stage.get_children().filter(func(child): return child.get_meta("event_card_id", "") == id and child.get_meta("card_in_flight", false))
				_check(flights.size() == 1, "discard has a single real moving card")
				if flights.size() == 1:
					_check(flights[0].get_meta("motion_from").distance_to(battle._previous_card_centers.get(id, Vector2(-999, -999))) < 1.0, "discard flies directly from the original card position")
			if kind == "completion_applied":
				var event := battle._animator.last_event
				var meter: Dictionary = battle._task_meters.get(str(event.target_ids[0]), {})
				if not meter.is_empty() and int(event.data.work_before) > int(event.data.work_after):
					_check(float(meter.label.get_meta("displayed_work", -1)) > float(event.data.work_after), "enemy work bar starts at the pre-hit amount")
					_step_effects(battle, 0.075)
					var middle := float(meter.label.get_meta("displayed_work", -1))
					_check(middle < float(event.data.work_before) and middle > float(event.data.work_after), "4x enemy damage has an intermediate value after 0.075 seconds")
					await _save(shell, "damage-middle-" + suffix)
					_step_effects(battle, 0.075)
					_check(float(meter.label.get_meta("displayed_work", -1)) > float(event.data.work_after), "4x enemy damage is still animating after 0.15 seconds")
			await _save(shell, kind + "-" + suffix)
		if battle._animator.pending_count() == 0:
			break
		if kind in ["card_played", "completion_applied", "pressure_applied", "card_drawn", "card_discarded", "card_resolved", "card_exhausted"]:
			_step_effects(battle, 0.35)
		battle._animator.advance(10.0)
	for kind in expected:
		_check(found.has(kind), "actual rule batch includes " + str(kind))
	_check(stable == _helpers.fingerprint(shell.session), "all visual effects preserve authoritative state/RNG at " + suffix)
	_step_effects(battle, 0.35)
	await _frames(shell, 2)
	_check(battle.display_snapshot().active_visual_effects == 0, "all transient visuals retire at " + suffix)
	battle._finish_event_presentation()
	shell.get_tree().paused = false
	battle.set_process(true)


func _step_effects(battle: BattleScreen, seconds: float) -> void:
	for tween in battle._presentation._tweens.duplicate():
		if tween.is_valid():
			tween.custom_step(seconds)


func _check_final_blow(dimensions: Vector2i) -> void:
	for mode in ["animated", "natural", "disabled", "reduced", "finish", "resize"]:
		var session := GameSession.new(SaveStore.new("user://final-blow-%s" % Time.get_ticks_usec()))
		session.update_settings({"autosave": false})
		if mode == "reduced":
			session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 4}})
		session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "0"))
		var shell := _helpers.attach_shell(session) as GameShell
		shell.show_screen("")
		_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0]))
		# Controlled last-task fixture; the final play and reward handoff use real commands.
		session._state.battle.tasks.resize(1)
		session._state.battle.tasks[0].work_remaining = 1
		session._state.battle.tasks[0].shield = 0
		shell.refresh()
		await _frames(shell, 3)
		var battle := shell.page as BattleScreen
		if mode == "disabled":
			battle.animation_enabled = false
		var enabled := battle.animation_enabled
		var work_id := ""
		for card in battle.view.hand:
			if str(card.definition_id) in ["R3-C-01", "R3-P01-02"]:
				work_id = str(card.card_id)
				break
		shell.submit_action({"type": "play_card", "payload": {"card_instance_id": work_id, "target_ids": [str(battle.view.tasks[0].task_id)], "replace_unit_id": null}})
		_check(shell.last_error == null and session.get_view().battle == null, "final blow publishes reward state through the session")
		var stable: String = _helpers.fingerprint(session)
		if enabled:
			_check(shell.page == battle and shell._waiting_for_battle, "complete battlefield stays visible until final actions finish")
			_check(battle.button_disabled("battle:end_turn"), "final presentation locks old battle controls")
			shell.submit_action({"type": "end_turn", "payload": {}})
			shell.submit_action({"type": "ui.menu", "payload": {}})
			shell.refresh()
			_check(stable == _helpers.fingerprint(session) and shell.page == battle, "rapid commands and refresh cannot interrupt final actions")
			if mode == "finish":
				battle.animation_enabled = false
			elif mode == "resize":
				battle.size.x -= 8
				await _frames(shell, 3)
			elif mode == "animated":
				battle.set_process(false)
			var found := false
			var discarded := false
			if mode == "animated":
				for index in 100:
					var kind := str(battle._animator.last_event.get("type", ""))
					if kind == "completion_applied":
						found = battle.display_snapshot().active_visual_effects > 0
						_check(shell.page == battle, "lethal damage feedback plays before navigation")
						await _save(shell, "final-blow-" + str(dimensions.x))
					if kind == "card_resolved":
						discarded = battle.display_snapshot().active_visual_effects > 0
						_check(shell.page == battle, "final discard plays on the original battlefield")
						await _save(shell, "final-discard-" + str(dimensions.x))
					if battle._animator.pending_count() == 0:
						break
					if kind in ["card_played", "completion_applied", "card_resolved"]:
						await shell.get_tree().create_timer(0.29 if kind == "completion_applied" else 0.14).timeout
					battle._animator.advance(10.0)
				_check(found and discarded, "final lethal damage and card discard are both presented")
				# Queue completion alone cannot cut off a still-running visual.
				var hold := battle.create_tween()
				hold.tween_interval(0.20)
				battle._presentation._tweens.append(hold)
				battle._animator.advance(10.0)
				battle._process(0.0)
				_check(shell.page == battle, "navigation waits for actual Tween completion after the queue drains")
				battle.set_process(true)
				await shell.get_tree().create_timer(0.4).timeout
			elif mode == "natural":
				await shell.get_tree().create_timer(1.5).timeout
		_check(not shell.page is BattleScreen and not shell._waiting_for_battle, "result page opens after final actions or the explicit instant path")
		_check(stable == _helpers.fingerprint(session), "waiting and result navigation preserve state revision and RNG")
		if mode == "animated":
			await _save(shell, "final-result-" + str(dimensions.x))
		shell.free()
		UiStyle.reduced_motion = false


func _save(shell: GameShell, label: String) -> void:
	if not capture_enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await shell.get_tree().create_timer(0.01).timeout
	await RenderingServer.frame_post_draw
	var viewport := shell.get_tree().root
	var result := viewport.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
	_check(result == OK, "save rendered feedback capture")
	_captures.append({"name": label, "width": viewport.size.x, "height": viewport.size.y, "save_error": result})


func _frames(shell: GameShell, count: int) -> void:
	for index in count:
		await shell.get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
