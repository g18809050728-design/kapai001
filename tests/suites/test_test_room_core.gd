extends RefCounted

## Test-room core suite: isolation, start/edit/undo, outcomes, snapshot roundtrip.

var _failures: Array[String] = []
var _root: String = ""


func run() -> Array[String]:
	_root = "user://test-room-core-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	_check_unified_entry()
	var session := GameSession.new(SaveStore.new(_root + "/saves"))
	session.test_service().store = TestStore.new(_root + "/room")
	_check_snapshot_saving()
	_check_snapshot_card_resume()
	_check_snapshot_deletion(session)
	_check_live_character_switch()
	_check_character_loadout_switch()
	_check_all_year_nodes()
	_check_runtime_switches()
	_check_map_continuation()
	_check_map_year_endings()
	var options := session.get_test_room_options()
	_check(options.ok, "test room options load")
	if options.ok:
		_check(options.data.characters.size() >= 4, "four characters are offered")
		_check(options.data.encounters.size() > 0, "encounters are offered")
		_check(options.data.switches.size() >= 10, "switches are offered")
	var started := session.start_test_room(
		{"character_id": "P01", "encounter_id": "N01", "seed": "42"}
	)
	_check(started.accepted, "test battle starts: " + _error_text(started.error))
	if not started.accepted:
		return _failures
	_check(session.has_test_room(), "test context is active")
	_check(session.get_view().screen == GameConstants.SCREEN_MENU, "formal session stays untouched")
	var view := session.get_test_view()
	_check(str(view.screen) == "test_room_battle", "test battle view")
	_check(view.battle.tasks.size() > 0, "encounter tasks exist")
	_check(view.battle.hand.size() > 0, "initial hand was drawn")
	_check((view.battle.zones_public.get("draw", []) as Array).size() > 0, "draw pile is public")
	_check((view.battle.get("draw_order", []) as Array).size() > 0, "test view exposes real draw order")
	_check(not str(view.test.test_id).is_empty(), "test id assigned")
	_check(not view.switches.values().has(true), "new single battle starts with every debug override off")
	if options.ok:
		_check(options.data.scenes.size() > 0, "scenes are offered")
		var has_phases := false
		for task in options.data.tasks:
			if not (task.get("phases", []) as Array).is_empty():
				has_phases = true
		_check(has_phases, "task phases are offered")
	var focus_before := int(view.battle.player.focus)
	var applied := session.apply_test_patch(
		_context(session), {"ops": [{"op": "set_player_field", "field": "focus", "value": focus_before + 7}]}
	)
	_check(applied.accepted, "focus patch applies: " + _error_text(applied.error))
	view = session.get_test_view()
	_check(int(view.battle.player.focus) == focus_before + 7, "focus changed")
	_check(int(view.test.revision) == 1, "revision increments once")
	var hand_before: int = view.battle.hand.size()
	applied = session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{"op": "add_card", "definition_id": "R3-P01-01", "zone": "hand", "count": 1},
			]
		}
	)
	_check(applied.accepted, "card add applies: " + _error_text(applied.error))
	view = session.get_test_view()
	_check(view.battle.hand.size() == hand_before + 1, "card added to hand")
	var player_id := str(view.battle.player.entity_id)
	applied = session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{"op": "add_status", "status_id": "inspiration", "target_id": player_id, "stacks": 2},
			]
		}
	)
	_check(applied.accepted, "status applies: " + _error_text(applied.error))
	view = session.get_test_view()
	_check(_has_status(view.battle.statuses, "inspiration", player_id), "status added")
	var rejected := session.apply_test_patch(
		_context(session), {"ops": [{"op": "not_a_real_op"}]}
	)
	_check(not rejected.accepted, "unknown op is rejected")
	_check(
		str(rejected.error.code) == "TEST_PATCH_INVALID",
		"unknown op error code: " + str(rejected.error.code)
	)
	var rounds_before := int(view.battle.round_index)
	var ended := session.submit_test_action(
		_context(session), {"type": "end_turn", "payload": {}}
	)
	_check(ended.accepted, "end turn accepted: " + _error_text(ended.error))
	view = session.get_test_view()
	_check(int(view.battle.round_index) == rounds_before + 1, "round advanced through real rules")
	var undone := session.step_test_history(_context(session), "undo")
	_check(undone.accepted, "undo accepted: " + _error_text(undone.error))
	view = session.get_test_view()
	_check(int(view.battle.round_index) == rounds_before, "undo restored previous round")
	_check(int(view.test.branch_id) == 1, "undo creates a new branch")
	var first_task_id := str(view.battle.tasks[0].task_id)
	var switch_off := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "set_switch", "key": "allow_empty_tasks", "value": false}]}
	)
	_check(switch_off.accepted, "empty-enemy switch can be disabled: " + _error_text(switch_off.error))
	var blocked_empty := session.apply_test_patch(
		_context(session), {"ops": [{"op": "remove_task", "task_id": first_task_id}]}
	)
	_check(not blocked_empty.accepted, "empty enemy is blocked while the switch is off")
	_check(
		blocked_empty.error != null and str(blocked_empty.error.code) == "TEST_LIMIT_REACHED",
		"empty enemy reports the required switch: " + _error_text(blocked_empty.error)
	)
	var switch_on := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "set_switch", "key": "allow_empty_tasks", "value": true}]}
	)
	_check(switch_on.accepted, "empty-enemy switch applies: " + _error_text(switch_on.error))
	view = session.get_test_view()
	for task in view.battle.tasks.duplicate():
		var remove := session.apply_test_patch(
			_context(session), {"ops": [{"op": "remove_task", "task_id": str(task.task_id)}]}
		)
		_check(remove.accepted, "task removal applies: " + _error_text(remove.error))
	view = session.get_test_view()
	_check(view.battle.tasks.is_empty(), "empty enemy state allowed")
	var won := session.set_test_outcome(_context(session), "won")
	_check(won.accepted, "manual outcome applies: " + _error_text(won.error))
	view = session.get_test_view()
	_check(str(view.result.source) == "manual", "manual result recorded")
	_check(str(view.screen) == "test_room_result", "result screen")
	var cleared := session.set_test_outcome(_context(session), "clear")
	_check(cleared.accepted, "manual outcome clears: " + _error_text(cleared.error))
	view = session.get_test_view()
	_check(str(view.result.source) == "none", "result cleared")
	_check(str(view.battle.phase) == "player_action", "battle can continue")
	var hand_before_rule := int(view.battle.hand.size())
	var drew := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "run_rule_op", "rule": "draw", "args": {"count": 1}}]}
	)
	_check(drew.accepted, "real draw rule op applies: " + _error_text(drew.error))
	view = session.get_test_view()
	_check(int(view.battle.hand.size()) == hand_before_rule + 1, "real draw moves a card to hand")
	var gained := session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{
					"op": "run_rule_op",
					"rule": "gain_status",
					"args": {
						"status_id": "work_boost",
						"target_id": str(view.battle.player.entity_id),
						"stacks": 1,
					},
				},
			]
		}
	)
	_check(gained.accepted, "real status rule op applies: " + _error_text(gained.error))
	view = session.get_test_view()
	_check(
		_has_status(view.battle.statuses, "work_boost", str(view.battle.player.entity_id)),
		"real status rule op added the status"
	)
	var ddl_before := int(view.battle.ddl)
	var freeze_set := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "set_switch", "key": "freeze_ddl", "value": true}]}
	)
	_check(freeze_set.accepted, "freeze_ddl switch applies: " + _error_text(freeze_set.error))
	var frozen_turn := session.submit_test_action(
		_context(session), {"type": "end_turn", "payload": {}}
	)
	_check(frozen_turn.accepted, "frozen turn ends: " + _error_text(frozen_turn.error))
	view = session.get_test_view()
	_check(int(view.battle.ddl) == ddl_before, "freeze_ddl keeps DDL unchanged")
	var enforce_slots := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "set_switch", "key": "ignore_relic_slots", "value": false}]}
	)
	_check(enforce_slots.accepted, "relic-slot enforcement can be enabled: " + _error_text(enforce_slots.error))
	for relic_id in ["RX-C01", "RX-C02", "RX-C03"]:
		var added_relic := session.apply_test_patch(
			_context(session), {"ops": [{"op": "add_relic", "relic_id": relic_id}]}
		)
		_check(added_relic.accepted, "relic adds: " + _error_text(added_relic.error))
	var fourth_relic := session.apply_test_patch(
		_context(session), {"ops": [{"op": "add_relic", "relic_id": "RX-C04"}]}
	)
	_check(not fourth_relic.accepted, "fourth relic is blocked while slots are enforced")
	var relic_switch := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "set_switch", "key": "ignore_relic_slots", "value": true}]}
	)
	_check(relic_switch.accepted, "relic-slot switch applies: " + _error_text(relic_switch.error))
	fourth_relic = session.apply_test_patch(
		_context(session), {"ops": [{"op": "add_relic", "relic_id": "RX-C04"}]}
	)
	_check(fourth_relic.accepted, "fourth relic applies after the switch: " + _error_text(fourth_relic.error))
	var focus_set := session.apply_test_patch(
		_context(session), {"ops": [{"op": "set_player_field", "field": "focus", "value": 5}]}
	)
	_check(focus_set.accepted, "focus prepares for the pending-choice case")
	var add_choice_card := session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{"op": "add_card", "definition_id": "R3-P01-16", "zone": "hand", "count": 1},
				{"op": "add_card", "definition_id": "R3-P01-01", "zone": "discard", "count": 1},
			]
		}
	)
	_check(add_choice_card.accepted, "choice fixture cards apply: " + _error_text(add_choice_card.error))
	view = session.get_test_view()
	var choice_card_id := ""
	for card in view.battle.hand:
		if str(card.get("definition_id", "")) == "R3-P01-16":
			choice_card_id = str(card.get("card_id", ""))
	var played := session.submit_test_action(
		_context(session), {"type": "play_card", "payload": {"card_instance_id": choice_card_id}}
	)
	_check(played.accepted, "choice card plays: " + _error_text(played.error))
	view = session.get_test_view()
	_check(view.pending_choice is Dictionary, "playing the retrieve card creates a pending choice")
	if view.pending_choice is Dictionary:
		var pending_context := _context(session)
		var rolled := session.apply_test_patch(
			pending_context,
			{
				"resolution_policy": "rollback",
				"ops": [{"op": "adjust_player_field", "field": "focus", "delta": 1}],
			}
		)
		_check(rolled.accepted, "rollback edit applies during a pending choice: " + _error_text(rolled.error))
		view = session.get_test_view()
		_check(view.pending_choice == null, "rollback edit clears the pending choice")
		_check(int(view.test.branch_id) == int(pending_context.branch_id) + 1, "rollback edit branches")
		_check(int(view.test.revision) == 0, "rollback edit starts revision zero")
	var preset := session.save_test_preset("core-preset")
	_check(preset.ok, "preset saves: " + _error_text(preset.error))
	var preset_id := str(preset.data.id) if preset.ok else ""
	_check(
		session.list_test_files("preset").any(func(entry): return str(entry.id) == preset_id),
		"preset is listed in the isolated store"
	)
	var snapshot := session.save_test_snapshot("core-check")
	_check(snapshot.ok, "snapshot saves: " + _error_text(snapshot.error))
	var snapshot_id := str(snapshot.data.id) if snapshot.ok else ""
	var closed := session.close_test_room()
	_check(closed.accepted, "test room closes")
	_check(not session.has_test_room(), "test context cleared")
	var files := session.list_test_files("snapshot")
	_check(
		files.any(func(entry): return str(entry.id) == snapshot_id),
		"snapshot is listed in the isolated store"
	)
	var loaded := session.load_test_snapshot(snapshot_id)
	_check(loaded.accepted, "snapshot loads: " + _error_text(loaded.error))
	_check(session.has_test_room(), "loaded snapshot activates a test context")
	view = session.get_test_view()
	_check(view.battle.hand.size() > 0, "loaded snapshot keeps cards")
	var arbitrary_time := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "set_round", "round_index": 7}, {"op": "set_ddl", "ddl": 3}]}
	)
	_check(arbitrary_time.accepted, "exact round and DDL apply: " + _error_text(arbitrary_time.error))
	view = session.get_test_view()
	_check(int(view.battle.round_index) == 7 and int(view.battle.ddl) == 3, "exact time is stored")
	var chapter_added := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "add_card", "definition_id": "R3-P02-18", "zone": "chapter", "count": 1}]}
	)
	_check(chapter_added.accepted, "chapter card adds: " + _error_text(chapter_added.error))
	view = session.get_test_view()
	_check((view.battle.chapter_cards as Array).size() == 1, "chapter exposes its card")
	var chapter_card_id := str(view.battle.chapter_cards[0].card_id)
	var chapter_to_hand := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "move_instance", "instance_id": chapter_card_id, "zone": "hand"}]}
	)
	_check(chapter_to_hand.accepted, "chapter card moves to hand: " + _error_text(chapter_to_hand.error))
	var scene_added := session.apply_test_patch(
		_context(session), {"ops": [{"op": "add_scene", "scene_id": "L01"}]}
	)
	_check(scene_added.accepted, "arbitrary scene adds: " + _error_text(scene_added.error))
	view = session.get_test_view()
	_check(
		typeof(view.battle.scene) == TYPE_DICTIONARY
		and str(view.battle.scene.get("definition_id", "")) == "L01",
		"scene is callable"
	)
	var custom_card := {
		"id": "TEST.card.free",
		"name_key": "自由测试卡",
		"type": "work",
		"cost": 1,
		"target": "task",
		"effects": [{"op": "complete", "amount": 7}],
		"permanent": true,
	}
	var custom_added := session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{
					"op": "upsert_definition",
					"kind": "card",
					"id": "TEST.card.free",
					"definition": custom_card,
				}
			]
		}
	)
	_check(custom_added.accepted, "custom card definition applies: " + _error_text(custom_added.error))
	custom_added = session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "add_card", "definition_id": "TEST.card.free", "zone": "hand", "count": 1}]}
	)
	_check(custom_added.accepted, "custom card can be called: " + _error_text(custom_added.error))
	view = session.get_test_view()
	var custom_in_hand := false
	for card in view.battle.hand:
		if str(card.get("definition_id", "")) == "TEST.card.free":
			custom_in_hand = true
	_check(custom_in_hand, "custom card can be called into hand")
	var undo_custom := session.step_test_history(_context(session), "undo")
	_check(undo_custom.accepted, "custom card undo: " + _error_text(undo_custom.error))
	var custom_after_undo := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "add_card", "definition_id": "TEST.card.free", "zone": "hand", "count": 1}]}
	)
	_check(
		custom_after_undo.accepted,
		"custom definition survives undo: " + _error_text(custom_after_undo.error)
	)
	var custom_task := {
		"id": "TEST.task.free",
		"name_key": "自由测试任务",
		"phases": [
			{
				"phase_key": "main",
				"work_max": 12,
				"intents": [{"pressure": 1}],
			},
			{
				"phase_key": "enraged",
				"work_max": 20,
				"intents": [{"pressure": 3, "shield": 2}],
			},
		],
	}
	var custom_task_added := session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{
					"op": "upsert_definition",
					"kind": "task",
					"id": "TEST.task.free",
					"definition": custom_task,
				}
			]
		}
	)
	_check(custom_task_added.accepted, "custom task definition applies: " + _error_text(custom_task_added.error))
	custom_task_added = session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "add_task", "definition_id": "TEST.task.free"}]}
	)
	_check(custom_task_added.accepted, "custom task can be called: " + _error_text(custom_task_added.error))
	view = session.get_test_view()
	var custom_task_id := ""
	for task in view.battle.tasks:
		if str(task.get("definition_id", "")) == "TEST.task.free":
			custom_task_id = str(task.task_id)
	_check(not custom_task_id.is_empty(), "custom task is in the battle")
	if not custom_task_id.is_empty():
		var phase_changed := session.apply_test_patch(
			_context(session),
			{"ops": [{"op": "set_task_phase", "task_id": custom_task_id, "phase_key": "enraged"}]}
		)
		_check(phase_changed.accepted, "task phase changes: " + _error_text(phase_changed.error))
		var intent_changed := session.apply_test_patch(
			_context(session),
			{
				"ops": [
					{
						"op": "set_task_intent",
						"task_id": custom_task_id,
						"intent": {"pressure": 9, "shield": 4},
					}
				]
			}
		)
		_check(intent_changed.accepted, "task intent changes: " + _error_text(intent_changed.error))
		view = session.get_test_view()
		for task in view.battle.tasks:
			if str(task.task_id) == custom_task_id:
				_check(int(task.work_max) == 20, "phase change updates work")
				_check(int((task.intent_snapshot as Dictionary).get("pressure", 0)) == 9, "intent override is stored")
	_check(
		not FileAccess.file_exists(_root + "/saves/current_run.json"),
		"test room never writes formal current_run"
	)
	session.close_test_room()
	session.free()
	return _failures


func _context(session: GameSession) -> Dictionary:
	var view := session.get_test_view()
	var test_state: Dictionary = view.get("test", {})
	return {
		"test_id": str(test_state.get("test_id", "")),
		"branch_id": int(test_state.get("branch_id", 0)),
		"expected_revision": int(test_state.get("revision", 0)),
	}


func _has_status(statuses: Array, status_id: String, target_id: String) -> bool:
	for status in statuses:
		if str(status.get("status_id", "")) == status_id and str(status.get("target_id", "")) == target_id:
			return true
	return false


func _error_text(error: ApiError) -> String:
	return "" if error == null else "%s/%s %s" % [error.code, error.message_key, JSON.stringify(error.details)]


func _check_unified_entry() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/unified-saves"))
	var service := session.test_service()
	service.store = TestStore.new(_root + "/unified-room")
	for invalid in [0, 5, -1, 1.5, "1", true, null]:
		var rejected := session.start_test_room({"start_year": invalid, "seed": "42"})
		_check(not rejected.accepted and rejected.error != null
			and rejected.error.code == GameConstants.ERROR_INVALID_ARGUMENT and not session.has_test_room(),
			"invalid starting year leaves the experiment closed: %s" % [invalid])
	for year in range(1, 5):
		var started := session.start_test_room({"character_id": "P02", "seed": "42", "start_year": year})
		_check(started.accepted, "unified map starts in year %d: %s" % [year, _error_text(started.error)])
		if not started.accepted:
			continue
		var view := session.get_test_view()
		_check(view.screen == "test_room_campus" and view.run.screen == "map" and int(view.run.term) == year,
			"unified entry opens the selected annual map")
		_check(service.state.run.current_node_id.is_empty() and service.state.run.active_battle_id.is_empty(),
			"map entry has no active node or battle")
		_check(service.state.run.campaign.years.size() == 4 and not view.run.reachable_node_ids.is_empty(),
			"all four annual maps exist and the selected map has a reachable start")
		_check(not view.switches.values().has(true), "unified entry keeps ordinary rules by default")
		var normal := RunService.new(service.base_catalog).create({
			"manifest_id": TestRoomService.MANIFEST_ID, "character_id": "P02", "seed": "42"})
		_check(normal.ok, "normal run comparison starts")
		if normal.ok:
			var expected: RunState = normal.data.state
			_check(service.state.run.money == expected.money and service.state.run.vitality == expected.vitality
				and service.state.run.max_vitality == expected.max_vitality, "map uses normal initial resources")
			_check(service.state.run.cards.map(func(card): return card.definition_id)
				== expected.cards.map(func(card): return card.definition_id), "map uses the character's normal starter deck")
		var saved := session.save_test_snapshot("统一校园实验")
		var preset := session.save_test_preset("校园地图起点")
		_check(saved.ok and preset.ok, "map can save a snapshot and preset")
		session.close_test_room()
		if saved.ok:
			_check(session.load_test_snapshot(str(saved.data.id)).accepted, "map snapshot loads after JSON round trip")
			_check(session.get_test_view().run.screen == "map" and int(session.get_test_view().run.term) == year,
				"loaded map preserves selected year")
			var again := session.save_test_snapshot("测试快照")
			_check(again.ok and str(again.data.id) == str(saved.data.id), "map save updates the loaded snapshot")
			var restarted := session.restart_test_battle(_context(session), "initial", "same")
			_check(restarted.accepted, "map restart preserves the annual start configuration: " + _error_text(restarted.error))
			_check(int(session.get_test_view().run.term) == year and session.get_test_view().run.screen == "map",
				"map restart returns to the configured annual map")
			session.close_test_room()
		if preset.ok:
			var loaded := session.load_test_preset(str(preset.data.id))
			_check(loaded.accepted, "map preset starts after JSON round trip: " + _error_text(loaded.error))
			if loaded.accepted:
				_check(int(session.get_test_view().run.term) == year, "preset retains its start year")
			session.close_test_room()
	var direct := session.start_test_room({"seed": "42", "start_year": 1, "node_key": "y1l1s0"})
	_check(direct.accepted, "unified config can enter a concrete battle node")
	if direct.accepted:
		_check(service.state.run != null and not service.state.run.active_battle_id.is_empty(),
			"direct battle belongs to the campus experiment")
		_check(session.set_test_outcome(_context(session), "won").accepted, "direct battle can resolve")
		var view := session.get_test_view()
		_check(view.screen == "test_room_campus" and view.run.screen in ["reward", "map"],
			"unified direct battle resolves through campus rewards/map")
		session.close_test_room()
	_check(session.get_view().screen == GameConstants.SCREEN_MENU, "unified experiments preserve the formal session")
	session.free()


func _check_snapshot_card_resume() -> void:
	for character in ["P01", "P02", "P03", "P04"]:
		_check_restored_card_actions(character, false)
	_check_restored_card_actions("P01", true)


func _check_restored_card_actions(character: String, campus: bool) -> void:
	var label := "%s-%s" % [character, "campus" if campus else "legacy"]
	var control := GameSession.new(SaveStore.new(_root + "/resume-saves-" + label))
	var store := TestStore.new(_root + "/resume-room-" + label)
	control.test_service().store = store
	var config := {"character_id": character, "seed": "42"}
	if campus:
		config["start_year"] = 1
	else:
		config["encounter_id"] = "N01"
	var started := control.start_test_room(config)
	_check(started.accepted, "start card resume fixture " + label)
	if not started.accepted:
		control.free()
		return
	if campus:
		var node_id: String = control.get_test_view().run.reachable_node_ids[0]
		_check(control.submit_test_action(_context(control), {"type": "enter_node", "payload": {"node_id": node_id}}).accepted,
			"enter campus battle for card resume")
	var added := control.apply_test_patch(_context(control), {"ops": [
		{"op": "set_player_field", "field": "focus", "value": 50},
		{"op": "add_card", "definition_id": "R3-" + character + "-01", "zone": "hand"},
	]})
	_check(added.accepted, "prepare card resume fixture " + label)
	var card_id: String = control.test_service().state.battle.zones.hand.back()
	_check(control.apply_test_patch(_context(control), {"ops": [
		{"op": "set_card_field", "scope": "instance", "target": card_id, "field": "upgrade_level", "value": 1},
	]}).accepted, "upgrade resume card " + label)
	var before: Dictionary = control.get_test_view().battle
	var files := {
		"snapshot": control.save_test_snapshot("resume snapshot"),
		"record": control.save_test_record("resume record"),
	}
	var face := control.test_service().engine.resolve_face(control.test_service().state.battle, card_id)
	var payload := {"card_instance_id": card_id}
	if face.ok and face.data.target == "task":
		payload["target_ids"] = [control.test_service().state.battle.tasks[0].task_id]
	var draft := {"type": "play_card", "payload": payload}
	var played := control.submit_test_action(_context(control), draft)
	_check(played.accepted, "control plays upgraded card " + label + ": " + _error_text(played.error))
	var expected := control.test_service().state.core_snapshot()
	for kind in files:
		var saved: GameResult = files[kind]
		_check(saved.ok, "save card resume " + label + " " + kind)
		if not saved.ok:
			continue
		var resumed := GameSession.new(SaveStore.new(_root + "/resumed-saves-" + label + kind))
		resumed.test_service().store = store
		var loaded := resumed.load_test_snapshot(str(saved.data.id)) if kind == "snapshot" else resumed.load_test_record(str(saved.data.id))
		_check(loaded.accepted, "load card resume " + label + " " + kind + ": " + _error_text(loaded.error))
		if loaded.accepted:
			var restored: Dictionary = resumed.get_test_view().battle
			_check(SnapshotCodec.canonical_json(restored.hand) == SnapshotCodec.canonical_json(before.hand),
				"restored hand preserves faces, costs and upgrades " + label + " " + kind)
			_check(SnapshotCodec.canonical_json(restored.zones_public) == SnapshotCodec.canonical_json(before.zones_public),
				"restored pile cards preserve faces and costs " + label + " " + kind)
			var preview := resumed.preview_test_action(_context(resumed), draft)
			_check(preview.ok and preview.data.can_submit, "restored card is playable " + label + " " + kind)
			var action := resumed.submit_test_action(_context(resumed), draft)
			_check(action.accepted, "play restored upgraded card " + label + " " + kind + ": " + _error_text(action.error))
			if action.accepted:
				var actual := resumed.test_service().state.core_snapshot()
				for key in ["battle", "rng", "run", "run_rng", "pending_choice"]:
					_check(SnapshotCodec.canonical_json(actual[key]) == SnapshotCodec.canonical_json(expected[key]),
						"restored play matches uninterrupted " + key + " " + label + " " + kind)
			resumed.close_test_room()
		resumed.free()
	control.close_test_room()
	control.free()


func _check_snapshot_saving() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/save-saves"))
	var store := TestStore.new(_root + "/save-room")
	session.test_service().store = store
	var config := {"character_id": "P01", "encounter_id": "N01", "seed": "42"}
	_check(session.start_test_room(config).accepted, "start snapshot-save experiment")
	var saved := session.save_test_snapshot("原快照名称")
	_check(saved.ok, "first ordinary save creates a snapshot")
	if not saved.ok:
		session.close_test_room()
		session.free()
		return
	var id := str(saved.data.id)
	var path := str(saved.data.path)
	var service := session.test_service()
	var core_before := service.state.core_snapshot()
	for index in 5:
		var repeated := session.save_test_snapshot("原快照名称")
		_check(repeated.ok and str(repeated.data.id) == id, "consecutive save reuses snapshot %d" % index)
	_check(store.list("snapshot").size() == 1, "consecutive saves leave exactly one snapshot")
	_check(service.state.core_snapshot() == core_before, "saving does not change experimental state or RNG")
	_check(session.apply_test_patch(_context(session), {"ops": [
		{"op": "set_player_field", "field": "focus", "value": 17},
	]}).accepted, "edit between snapshot saves")
	var edited := session.save_test_snapshot("测试快照")
	var stored := store.load_file("snapshot", id)
	_check(edited.ok and str(edited.data.id) == id and store.list("snapshot").size() == 1,
		"saving edited experiment updates the same snapshot")
	_check(stored.ok and int(stored.data.payload.core.battle.player.focus) == 17,
		"snapshot contains the most recent edit")
	_check(stored.ok and str(stored.data.name) == "原快照名称", "ordinary save preserves snapshot name")
	_check(session.step_test_history(_context(session), "undo").accepted, "undo after saving")
	_check(str(session.save_test_snapshot("测试快照").data.id) == id, "undo retains snapshot binding")
	_check(session.restore_test_checkpoint(_context(session), str(service.state.checkpoints[0].id)).accepted,
		"restore a checkpoint after saving")
	_check(str(session.save_test_snapshot("测试快照").data.id) == id, "checkpoint restore retains snapshot binding")
	for origin in ["current", "initial"]:
		_check(session.restart_test_battle(_context(session), origin, "same").accepted,
			"restart experiment from " + origin)
		_check(str(session.save_test_snapshot("测试快照").data.id) == id,
			"restart retains snapshot binding: " + origin)
	var record := session.save_test_record("独立记录")
	var preset := session.save_test_preset("独立预设")
	session.close_test_room()
	# A fresh service must bind to the filename actually loaded, including legacy files.
	var loaded_session := GameSession.new(SaveStore.new(_root + "/save-saves"))
	loaded_session.test_service().store = store
	_check(loaded_session.load_test_snapshot(id).accepted, "load snapshot in a fresh service")
	var resumed := loaded_session.save_test_snapshot("测试快照")
	_check(resumed.ok and str(resumed.data.id) == id and store.list("snapshot").size() == 1,
		"load then save updates the loaded file")
	_check(resumed.ok and str(resumed.data.name) == "原快照名称", "loaded snapshot keeps its name")
	# A real temporary-path obstruction must preserve the previous snapshot and binding.
	var hash_before := FileAccess.get_sha256(path)
	DirAccess.make_dir_recursive_absolute(path + ".tmp")
	var failed := loaded_session.save_test_snapshot("测试快照")
	_check(not failed.ok and failed.error.code == GameConstants.ERROR_TEST_IO_ERROR,
		"failed overwrite reports actual filesystem error")
	_check(FileAccess.get_sha256(path) == hash_before and store.list("snapshot").size() == 1,
		"failed overwrite preserves previous bytes and snapshot count")
	DirAccess.remove_absolute(path + ".tmp")
	_check(str(loaded_session.save_test_snapshot("测试快照").data.id) == id,
		"retry after write failure retains snapshot binding")
	loaded_session.close_test_room()
	loaded_session.free()
	_check(session.start_test_room(config).accepted, "start a separate experiment with identical setup")
	var separate := session.save_test_snapshot("新实验")
	_check(separate.ok and str(separate.data.id) != id and store.list("snapshot").size() == 2,
		"new experiment creates its own snapshot without replacing the previous one")
	_check(FileAccess.get_sha256(path) == hash_before, "separate experiment preserves old snapshot bytes")
	session.close_test_room()
	if record.ok and preset.ok:
		_check(session.load_test_record(str(record.data.id)).accepted, "load record as separate experiment")
		var record_snapshot := session.save_test_snapshot("记录实验")
		_check(record_snapshot.ok and str(record_snapshot.data.id) != id and store.list("snapshot").size() == 3,
			"record load creates a distinct snapshot")
		session.close_test_room()
		_check(session.load_test_preset(str(preset.data.id)).accepted, "load preset as separate experiment")
		var preset_snapshot := session.save_test_snapshot("预设实验")
		_check(preset_snapshot.ok and str(preset_snapshot.data.id) != id and store.list("snapshot").size() == 4,
			"preset load creates a distinct snapshot")
		session.close_test_room()
	session.free()


func _check_snapshot_deletion(session: GameSession) -> void:
	var store := TestStore.new(_root + "/delete-room")
	for kind in ["snapshot", "preset", "record"]:
		_check(store.save(kind, "keep", "保留", {}).ok, "create isolated " + kind)
	var created := store.save("snapshot", "remove-me", "待删除", {})
	_check(created.ok, "create snapshot to delete")
	var record_path := store.base_path + "/records/keep.json"
	var record_hash := FileAccess.get_sha256(record_path)
	for id in ["", "../records/keep", "..\\records\\keep", "/keep", "C:/keep", "user://saves/keep", "x".repeat(81)]:
		var invalid := store.remove("snapshot", id)
		_check(not invalid.ok and invalid.error.code == GameConstants.ERROR_TEST_FILE_INVALID,
			"snapshot deletion rejects unsafe ID: " + id)
	_check(FileAccess.get_sha256(record_path) == record_hash, "unsafe deletion preserves sibling files")
	var missing := store.remove("snapshot", "missing")
	_check(not missing.ok and missing.error.code == GameConstants.ERROR_SAVE_NOT_FOUND,
		"missing snapshot is reported rather than claiming deletion")
	var blocked_path := store.base_path + "/snapshots/blocked.json"
	DirAccess.make_dir_recursive_absolute(blocked_path)
	var blocked := store.remove("snapshot", "blocked")
	_check(not blocked.ok and blocked.error.code == GameConstants.ERROR_TEST_IO_ERROR,
		"directory at snapshot path reports IO failure")
	_check(DirAccess.dir_exists_absolute(blocked_path), "deletion never removes a directory")
	var removed := store.remove("snapshot", "remove-me")
	_check(removed.ok and not FileAccess.file_exists(str(created.data.path)), "selected snapshot file is deleted")
	for kind in ["snapshot", "preset", "record"]:
		_check(store.load_file(kind, "keep").ok, "deletion preserves other " + kind)
	var corrupt_path := store.base_path + "/snapshots/corrupt.json"
	var corrupt := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt.store_string("not a snapshot")
	corrupt.close()
	_check(store.remove("snapshot", "corrupt").ok and not FileAccess.file_exists(corrupt_path),
		"corrupt snapshot can be deleted without parsing")
	var original_store := session.test_service().store
	session.test_service().store = store
	_check(session.has_method("delete_test_snapshot"), "session exposes snapshot deletion")
	if not session.has_method("delete_test_snapshot"):
		session.test_service().store = original_store
		return
	_check(session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"}).accepted,
		"start active experiment for deletion isolation")
	var snapshot := session.save_test_snapshot("active")
	var state_before := SnapshotCodec.canonical_json(session.test_service().state.core_snapshot())
	var journal_before := session.test_service().state.journal.duplicate(true)
	var checkpoints_before := session.test_service().state.checkpoints.duplicate(true)
	var revision_before := session.get_view().revision
	var result: GameResult = session.call("delete_test_snapshot", str(snapshot.data.id))
	_check(result.ok, "snapshot deletes through the public session API")
	_check(SnapshotCodec.canonical_json(session.test_service().state.core_snapshot()) == state_before
		and session.test_service().state.journal == journal_before
		and session.test_service().state.checkpoints == checkpoints_before,
		"deletion preserves full active experiment, history and RNG")
	_check(session.get_view().revision == revision_before, "deletion preserves formal revision")
	session.close_test_room()
	result = session.call("delete_test_snapshot", "keep")
	_check(result.ok and store.list("snapshot").is_empty(), "snapshot can be deleted with no active experiment")
	session.test_service().store = original_store


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _check_live_character_switch() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/character-saves"))
	session.test_service().store = TestStore.new(_root + "/character-room")
	var started := session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"})
	_check(started.accepted, "character experiment starts")
	if not started.accepted:
		return
	var before := session.get_test_view()
	var changed := session.apply_test_patch(_context(session), {"ops": [
		{"op": "set_character", "character_id": "P04", "keep_deck": true, "keep_relics": true}
	]})
	_check(changed.accepted, "live character switch applies: " + _error_text(changed.error))
	var after := session.get_test_view()
	_check(str(after.config.character_id) == "P04" and session.test_service().state.battle.character_id == "P04", "live character reaches view and rules")
	_check(after.battle.zones_public == before.battle.zones_public, "character switch preserves card zones")
	_check(after.battle.tasks == before.battle.tasks, "character switch preserves enemies")
	var undone := session.step_test_history(_context(session), "undo")
	_check(undone.accepted and str(session.get_test_view().config.character_id) == "P01", "character switch is undoable")
	session.close_test_room()


func _check_character_loadout_switch() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/loadout-saves"))
	session.test_service().store = TestStore.new(_root + "/loadout-room")
	_check(session.start_test_room({"character_id": "P02", "node_key": "y1l1s0", "seed": "42"}).accepted,
		"loadout switch starts in a map battle")
	var service := session.test_service()
	if service.state == null or service.state.run == null:
		_check(false, "loadout switch has a persistent test run")
		return
	var prepared := session.apply_test_patch(_context(session), {"ops": [
		{"op": "set_v3_field", "path": "paper.open", "value": true},
		{"op": "set_v3_field", "path": "paper.progress", "value": 4},
		{"op": "set_v3_field", "path": "synergy", "value": 5},
		{"op": "add_card", "definition_id": "R3-P02-11", "zone": "chapter"},
		{"op": "add_unit", "definition_id": "F01"},
		{"op": "add_relic", "relic_id": "RX-P02-01"},
		{"op": "add_relic", "relic_id": "RX-C01"},
		{"op": "add_card", "definition_id": "R3-P02-10", "zone": "hand"},
	]})
	_check(prepared.accepted, "prepare old character resources and chapter")
	var ability_card := ""
	for card in service.state.battle.card_by_id.values():
		if card.definition_id == "R3-P02-10":
			ability_card = str(card.card_id)
	var played := session.submit_test_action(_context(session), {"type": "play_card", "payload": {"card_instance_id": ability_card, "target_ids": []}})
	_check(played.accepted and not service.state.battle.v3.get("abilities", []).is_empty(), "real old character ability is active before switching")
	var player_id := str(service.state.battle.player.entity_id)
	_check(session.apply_test_patch(_context(session), {"ops": [
		{"op": "add_status", "status_id": "inspiration", "target_id": player_id, "stacks": 2},
		{"op": "add_status", "status_id": "anxiety", "target_id": player_id, "stacks": 1},
		{"op": "set_counter", "key": BattleState.counter_key(&"round", ability_card, &"v3_play"), "value": 1},
	]}).accepted, "prepare sourced and unrelated statuses and a played card counter")
	var sourced_status := ""
	for status in service.state.battle.statuses:
		if status.status_id == "inspiration":
			sourced_status = str(status.instance_id)
	_check(session.apply_test_patch(_context(session), {"ops": [
		{"op": "set_status_field", "instance_id": sourced_status, "field": "source_id", "value": ability_card},
	]}).accepted, "old card is recorded as the inspiration source")
	var before := service.state.core_snapshot()
	var old_card_id := str(service.state.battle.zones.hand[0])
	for character_id in ["P04", "P01", "P03", "P02"]:
		var context := _context(session)
		var patch := {"ops": [{"op": "set_character", "character_id": character_id}]}
		var hash_before := service.state.state_hash()
		var preview := session.preview_test_patch(context, patch)
		_check(preview.ok and preview.data.can_submit and service.state.state_hash() == hash_before,
			"character replacement preview is read only: " + character_id)
		var tasks_before := service.state.battle.tasks.duplicate(true)
		var resources_before := service.state.battle.player.duplicate(true)
		var round_before := service.state.battle.round_index
		var ddl_before := service.state.battle.ddl
		var rng_before := service.state.rng.duplicate(true)
		var changed := session.apply_test_patch(context, patch)
		_check(changed.accepted, "default character replacement applies: " + character_id + " " + _error_text(changed.error))
		if not changed.accepted:
			continue
		var state := service.state
		var expected: Array = service.base_catalog.get_definition("ruleset", service.base_catalog.get_info().ruleset_id).data.run.common_starter_cards.duplicate()
		expected.append_array(service.base_catalog.get_definition("character", character_id).data.starter_cards)
		var run_definitions := state.run.cards.map(func(card): return str(card.definition_id))
		var battle_definitions := state.battle.card_by_id.values().map(func(card): return str(card.definition_id))
		expected.sort()
		run_definitions.sort()
		battle_definitions.sort()
		_check(run_definitions == expected and battle_definitions == expected,
			"battle and permanent decks match the new character starter: " + character_id)
		_check(state.battle.zones.hand.size() == before.battle.zones.hand.size(), "replacement keeps the current hand count")
		_check(state.battle.zones.discard.is_empty() and state.battle.zones.exhaust.is_empty()
			and state.battle.v3.get("paper", {}).get("chapters", []).is_empty(), "old discard, exhaust and chapters are removed")
		_check(state.battle.v3.get("paper", {}).get("progress", 0) == 0
			and state.battle.v3.get("synergy", 0) == 0 and state.battle.v3.get("abilities", []).is_empty()
			and state.battle.units.is_empty(), "old character resources, abilities and partners are cleared")
		_check(state.battle.tasks == tasks_before and state.battle.player == resources_before
			and state.battle.round_index == round_before and state.battle.ddl == ddl_before
			and state.rng == rng_before, "switch preserves enemies, resources, timing and RNG")
		_check(state.battle.source_registry[player_id].definition_id == character_id,
			"player source registry follows the new character")
		_check(not state.battle.counters.has(BattleState.counter_key(&"round", ability_card, &"v3_play"))
			and not state.battle.statuses.any(func(status): return status.status_id == "inspiration")
			and state.battle.statuses.any(func(status): return status.status_id == "anxiety"),
			"old card counter and sourced status clear while unrelated status stays")
		for card in state.battle.card_by_id.values():
			_check(state.run.cards.any(func(permanent): return permanent.card_id == card.origin_card_id and permanent.definition_id == card.definition_id), "replacement cards reference their permanent run instances")
		var pool := RewardGenerator.new(service.catalog).card_candidates(state.run, 100, RandomSource.new("switch-pool"))
		_check(pool.ok and not pool.data.is_empty(), "new character reward pool is available")
		if pool.ok:
			for id in pool.data:
				var owner := str(service.catalog.get_definition("card", id).data.get("owner", ""))
				_check(owner in ["", "C", character_id], "reward pool excludes other characters: " + str(id))
		if character_id == "P04":
			_check(state.battle.relics == ["RX-C01"], "old exclusive relic removed and common relic kept")
			var after := state.core_snapshot()
			var hash_after := state.state_hash()
			var failed := session.apply_test_patch(_context(session), {"ops": [
				{"op": "set_character", "character_id": "P01"},
				{"op": "set_player_field", "field": "focus", "value": -1},
			]})
			_check(not failed.accepted and service.state.state_hash() == hash_after,
				"a later invalid operation atomically rolls back the whole character replacement")
			var old_play := session.submit_test_action(_context(session), {"type": "play_card", "payload": {"card_instance_id": old_card_id, "target_ids": []}})
			_check(not old_play.accepted and service.state.state_hash() == hash_after, "stale old hand input cannot play after replacement")
			_check(session.step_test_history(_context(session), "undo").accepted, "complete character replacement undoes")
			_check(service.state.battle.to_dictionary() == before.battle and service.state.run.to_dictionary() == before.run,
				"undo restores complete decks, chapters, partners and exclusive resources")
			_check(session.step_test_history(_context(session), "redo").accepted, "complete character replacement redoes")
			_check(service.state.battle.to_dictionary() == after.battle and service.state.run.to_dictionary() == after.run,
				"redo restores the same replacement instance IDs")
	_check(not service.state.battle.card_by_id.has(old_card_id), "old hand instance cannot survive replacement")
	_check(service.state.battle.zones.hand.any(func(id): return service.state.battle.card_by_id[id].definition_id == "R3-P02-01"),
		"switching to P02 places its opening card in hand")
	var snapshot := session.save_test_snapshot("switched-character")
	_check(snapshot.ok, "replaced character snapshot saves")
	var saved_deck := service.state.run.cards.duplicate(true)
	session.close_test_room()
	if snapshot.ok:
		_check(session.load_test_snapshot(str(snapshot.data.id)).accepted, "replaced character snapshot loads")
		_check(service.state.run.cards == saved_deck and service.state.battle.character_id == "P02", "snapshot preserves synchronized character and deck")
		var jumped := session.apply_test_patch(_context(session), {"ops": [{"op": "enter_node", "node_key": "y1l1s0"}]})
		_check(jumped.accepted and service.state.battle.character_id == "P02", "next map battle retains the switched character")
		_check(service.state.battle.card_by_id.values().all(func(card): return saved_deck.any(func(permanent): return permanent.card_id == card.origin_card_id and permanent.definition_id == card.definition_id)),
			"next battle uses the synchronized permanent deck")
	session.close_test_room()


func _check_all_year_nodes() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/node-saves"))
	session.test_service().store = TestStore.new(_root + "/node-room")
	var nodes := session.get_test_node_options("42")
	_check(nodes.size() > 70, "complete node list is available")
	var years := {}
	var room_kinds := {}
	var shop_key := ""
	var first_battle_key := ""
	for node in nodes:
		years[node.year] = true
		room_kinds[node.kind] = true
		if node.kind == "shop":
			shop_key = node.key
		if node.kind == "normal" and first_battle_key.is_empty():
			first_battle_key = node.key
	_check(years.size() == 4 and room_kinds.size() == 6, "all years and node types are listed")
	if shop_key.is_empty() or first_battle_key.is_empty():
		return
	var started := session.start_test_room({"character_id": "P01", "node_key": shop_key, "seed": "42"})
	_check(started.accepted, "can open directly from setup into a campus shop: " + _error_text(started.error))
	if not started.accepted:
		return
	var view := session.get_test_view()
	_check(view.screen == "test_room_campus" and view.run.screen == "shop", "campus run view exposes the real shop")
	var rich := session.apply_test_patch(_context(session), {"ops": [{"op": "set_money", "value": 999}]})
	_check(rich.accepted and session.get_test_view().run.money == 999, "shop sees edited money")
	var shop: Dictionary = session.get_test_view().run.shop
	if not shop.get("stocks", []).is_empty():
		var stock: Dictionary = shop.stocks[0]
		var bought := session.submit_test_action(_context(session), {"type": "buy_item", "payload": {"shop_id": shop.shop_id, "stock_id": stock.stock_id}})
		_check(bought.accepted and session.get_test_view().run.money < 999, "campus shop purchase uses real rules: " + _error_text(bought.error))
	var snapshot := session.save_test_snapshot("校园房间")
	_check(snapshot.ok, "campus snapshot saves")
	var repeated_snapshot := session.save_test_snapshot("校园房间")
	_check(repeated_snapshot.ok and str(repeated_snapshot.data.id) == str(snapshot.data.id)
		and session.list_test_files("snapshot").size() == 1, "campus saves also reuse one snapshot")
	var opened := session.apply_test_patch(_context(session), {"ops": [{"op": "enter_node", "node_key": first_battle_key}]})
	_check(opened.accepted and session.get_test_view().screen == "test_room_battle", "jump from shop to battle: " + _error_text(opened.error))
	var undone := session.step_test_history(_context(session), "undo")
	_check(undone.accepted and session.get_test_view().run.screen == "shop", "undo restores campus room")
	# Exercise the entry builder for every listed key using a single disposable run.
	# This avoids saving a full history for each entry while checking the same rules.
	var service := session.test_service()
	var selector := RunService.new(service.catalog)
	var entered_count := 0
	for node in nodes:
		var moved := selector.enter_test_node(service.state.run, service.state.run.run_id + "|" + str(node.key), service.state.run_rng)
		_check(moved.ok, "enter generated node %s: %s" % [node.key, _error_text(moved.error)])
		if moved.ok:
			entered_count += 1
			_check(moved.data.state.term == node.year, "node switches to the selected year")
			if moved.data.battle_input is Dictionary:
				var begun := service.engine.begin(moved.data.battle_input)
				_check(begun.ok, "battle initializes for %s: %s" % [node.key, _error_text(begun.error)])
	print("TEST ROOM opened %d/%d generated nodes" % [entered_count, nodes.size()])
	_check(session.get_view().screen == GameConstants.SCREEN_MENU, "formal session remains isolated across node jumps")
	session.close_test_room()
	if snapshot.ok:
		var loaded := session.load_test_snapshot(str(snapshot.data.id))
		_check(loaded.accepted and session.get_test_view().run.screen == "shop", "snapshot restores the same campus room: " + _error_text(loaded.error))
		session.close_test_room()


func _check_runtime_switches() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/switch-saves"))
	var started := session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"})
	_check(started.accepted, "test battle opens for runtime switch verification")
	if not started.accepted:
		return
	var edits := session.apply_test_patch(_context(session), {"ops": [
		{"op": "add_card", "definition_id": "R3-C-01", "zone": "hand"},
		{"op": "set_player_field", "field": "focus", "value": 0},
		{"op": "set_ddl", "ddl": 1},
		{"op": "set_switch", "key": "no_cost", "value": true},
		{"op": "set_switch", "key": "keep_hand", "value": true},
		{"op": "set_switch", "key": "freeze_ddl", "value": true},
		{"op": "set_switch", "key": "freeze_enemy", "value": true},
	]})
	_check(edits.accepted, "sandbox switch and resource edits apply")
	var service := session.test_service()
	var battle := service.state.battle
	var card_id := str(battle.zones.hand.back())
	var base_cost := BattleEngine.new(service.base_catalog).calculate_cost(battle, card_id)
	var test_cost := service.engine.calculate_cost(battle, card_id)
	_check(base_cost.ok and test_cost.ok and int(base_cost.data.cost) > 0 and int(test_cost.data.cost) == 0, "sandbox free cost does not affect the formal battle engine")
	var old_hand: Array = battle.zones.hand.duplicate()
	var vitality := int(battle.player.vitality)
	var turn := session.submit_test_action(_context(session), {"type": "end_turn", "payload": {}})
	_check(turn.accepted, "end turn with test switches: " + _error_text(turn.error))
	battle = service.state.battle
	_check(battle.round_index == 2 and battle.ddl == 1 and battle.outcome == null, "frozen deadline allows the next round")
	_check(int(battle.player.vitality) == vitality, "enemy pressure is suspended")
	_check(old_hand.all(func(id): return battle.zones.hand.has(id)), "keep hand preserves the actual hand through round change")
	session.close_test_room()


func _check_map_continuation() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/route-saves"))
	var started := session.start_test_room({"character_id": "P01", "node_key": "y1l1s0", "seed": "42"})
	_check(started.accepted, "route battle starts: " + _error_text(started.error))
	if not started.accepted:
		return
	var service := session.test_service()
	service.store = TestStore.new(_root + "/route-room")
	var view := session.get_test_view()
	_check(not view.switches.no_cost and not view.switches.infinite_focus and not view.switches.keep_hand,
		"map battle defaults to formal costs and discard")
	var fixture := session.apply_test_patch(_context(session), {"ops": [{"op": "replace_encounter", "encounter_id": "N01"}]})
	_check(fixture.accepted, "prepare a single opponent for the real victory")
	if not fixture.accepted:
		return
	view = session.get_test_view()
	var edits: Array[Dictionary] = [
		{"op": "add_card", "definition_id": "R3-C-01", "zone": "hand"},
		{"op": "set_player_field", "field": "vitality", "value": 12},
	]
	for task in view.battle.tasks:
		edits.append({"op": "set_task_field", "task_id": task.task_id, "field": "work_remaining", "value": 1})
	var prepared := session.apply_test_patch(_context(session), {"ops": edits})
	_check(prepared.accepted, "prepare one-hit combat: " + _error_text(prepared.error))
	if not prepared.accepted:
		return
	var battle := service.state.battle
	var card_id := str(battle.zones.hand.back())
	var cost := BattleEngine.new(service.base_catalog).calculate_cost(battle, card_id)
	var paid_cost := service.engine.calculate_cost(battle, card_id)
	_check(cost.ok and paid_cost.ok and int(cost.data.cost) > 0 and paid_cost.data.cost == cost.data.cost,
		"map battle uses the same positive cost as the formal engine")
	var focus_before := int(battle.player.focus)
	var played := session.submit_test_action(_context(session), {"type": "play_card", "payload": {
		"card_instance_id": card_id, "target_ids": [battle.tasks[0].task_id],
	}})
	_check(played.accepted, "map attack uses real battle rules: " + _error_text(played.error))
	if not played.accepted:
		return
	var paid := played.events.any(func(event): return event.type == &"focus_changed" and event.data.get("reason") == "card_payment" and int(event.data.after) == focus_before - int(cost.data.cost))
	_check(paid, "map attack pays focus")
	_check(service.state.battle.outcome != null and service.state.battle.outcome.result == "won",
		"the real attack completes the encounter")
	view = session.get_test_view()
	_check(view.screen == "test_room_campus" and view.run.screen in ["reward", "map"],
		"battle victory opens normal rewards or the map")
	_check(view.run.vitality == 12, "battle vitality carries into the run")
	if view.run.screen == "reward":
		var saved := session.save_test_snapshot("map reward")
		_check(saved.ok, "a pending battle reward can be saved")
		if saved.ok:
			session.close_test_room()
			var loaded := session.load_test_snapshot(str(saved.data.id))
			_check(loaded.accepted, "a pending battle reward can be restored")
			if not loaded.accepted:
				return
			view = session.get_test_view()
		var offer: Dictionary = view.run.pending_reward
		for item in offer.items:
			if item.status != "pending":
				continue
			var skipped := session.submit_test_action(_context(session), {"type": "skip_reward", "payload": {
				"offer_id": offer.offer_id, "item_id": item.item_id,
			}})
			_check(skipped.accepted, "normal reward resolves: " + _error_text(skipped.error))
	view = session.get_test_view()
	if view.run.screen == "map" and view.run.reachable_node_ids.is_empty():
		var left := session.submit_test_action(_context(session), {"type": "leave_node", "payload": {"node_id": view.run.current_node_id}})
		_check(left.accepted, "completed reward can leave the battle node: " + _error_text(left.error))
		view = session.get_test_view()
	_check(view.run.screen == "map" and not view.run.reachable_node_ids.is_empty(), "completed node exposes the next map choices")
	if not view.run.reachable_node_ids.is_empty():
		var next := session.submit_test_action(_context(session), {"type": "enter_node", "payload": {"node_id": view.run.reachable_node_ids[0]}})
		_check(next.accepted, "a reachable next node opens through the map: " + _error_text(next.error))
	session.close_test_room()


func _check_map_year_endings() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/year-saves"))
	var service := session.test_service()
	var started := session.start_test_room({"character_id": "P01", "node_key": "y1l12s0", "seed": "42"})
	_check(started.accepted, "an arbitrary jump can start on a boss")
	if not started.accepted:
		return
	for year in range(1, 5):
		var won := session.set_test_outcome(_context(session), "won")
		_check(won.accepted, "boss of year %d can settle: %s" % [year, _error_text(won.error)])
		var pending: Dictionary = session.get_test_view().run.get("campaign_offer", {})
		_check(pending.get("kind") == "grand", "boss opens the grand reward")
		if pending.get("kind") != "grand":
			break
		var granted := _route_choice(session, pending, "resources")
		_check(granted.accepted, "grand reward follows the normal annual flow: " + _error_text(granted.error))
		if not granted.accepted:
			break
		if year == 4:
			_check(session.get_test_view().run.screen == "summary" and service.state.run.outcome == "won",
				"final boss reaches graduation summary")
			break
		var decision := "direction" if year == 1 else "destination" if year == 3 else ""
		if not decision.is_empty():
			pending = session.get_test_view().run.get("campaign_offer", {})
			_check(pending.get("kind") == decision, "the game asks for " + decision)
			if pending.get("kind") != decision:
				break
			var chosen := _route_choice(session, pending, "theory" if year == 1 else "job")
			_check(chosen.accepted, "annual choice applies: " + _error_text(chosen.error))
			if not chosen.accepted:
				break
		var run := service.state.run
		var annual: Dictionary = run.campaign.years[year]
		_check(run.term == year + 1 and run.reachable_node_ids().size() == 1, "next year has a reachable start")
		if year == 1:
			_check(annual.profile.direction == "theory", "actual direction affects the new map")
		elif year == 3:
			_check(annual.profile.destination == "job", "actual destination affects the new map")
		var boss_key := "y%dl%ds0" % [year + 1, annual.layers]
		var jumped := session.apply_test_patch(_context(session), {"ops": [{"op": "enter_node", "node_key": boss_key}]})
		_check(jumped.accepted, "jump to next year's boss: " + _error_text(jumped.error))
		if not jumped.accepted:
			break
	var replayed := session.apply_test_patch(_context(session), {"ops": [{"op": "enter_node", "node_key": "y1l12s0"}]})
	_check(replayed.accepted, "an already settled boss can be opened again")
	if replayed.accepted:
		var lost := session.set_test_outcome(_context(session), "lost")
		_check(lost.accepted and service.state.run.outcome == "lost", "replayed boss can settle again as a defeat")
	_check(session.get_view().screen == GameConstants.SCREEN_MENU, "annual test route leaves the formal session alone")
	session.close_test_room()


func _route_choice(session: GameSession, offer: Dictionary, option: String) -> ActionResult:
	return session.submit_test_action(_context(session), {"type": "choose_campaign", "payload": {
		"offer_id": offer.offer_id, "option_id": option,
	}})
