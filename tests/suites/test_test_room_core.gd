extends RefCounted

## Test-room core suite: isolation, start/edit/undo, outcomes, snapshot roundtrip.

var _failures: Array[String] = []
var _root: String = ""


func run() -> Array[String]:
	_root = "user://test-room-core-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	var session := GameSession.new(SaveStore.new(_root + "/saves"))
	session.test_service().store = TestStore.new(_root + "/room")
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
	_check(bool(view.switches.get("ignore_relic_slots", false)), "free mode ignores relic slots by default")
	_check(bool(view.switches.get("ignore_unit_slots", false)), "free mode ignores unit slots by default")
	_check(bool(view.switches.get("allow_empty_tasks", false)), "free mode allows empty tasks by default")
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
	for relic_id in ["FY_Y1_1", "FY_Y1_2", "FY_Y1_3"]:
		var added_relic := session.apply_test_patch(
			_context(session), {"ops": [{"op": "add_relic", "relic_id": relic_id}]}
		)
		_check(added_relic.accepted, "relic adds: " + _error_text(added_relic.error))
	var fourth_relic := session.apply_test_patch(
		_context(session), {"ops": [{"op": "add_relic", "relic_id": "FY_Y1_4"}]}
	)
	_check(not fourth_relic.accepted, "fourth relic is blocked while slots are enforced")
	var relic_switch := session.apply_test_patch(
		_context(session),
		{"ops": [{"op": "set_switch", "key": "ignore_relic_slots", "value": true}]}
	)
	_check(relic_switch.accepted, "relic-slot switch applies: " + _error_text(relic_switch.error))
	fourth_relic = session.apply_test_patch(
		_context(session), {"ops": [{"op": "add_relic", "relic_id": "FY_Y1_4"}]}
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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)






