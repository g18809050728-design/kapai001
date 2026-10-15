extends SceneTree

func _initialize() -> void:
	var db := ContentDB.new()
	var loaded := db.load("campus_mvp")
	assert(loaded.ok)
	var svc := RunService.new(db)
	var created := svc.create({"character_id": "P01", "difficulty": "normal", "manifest_id": "campus_mvp", "seed": "42"}, {})
	assert(created.ok)
	var step: RunStep = created.data
	for suffix in ["t1l1_normal", "t1l2_event", "t1l3_shop", "t1l4_elite", "t1l5_rest", "t1l6_boss"]:
		var id := "%s|%s" % [step.state.run_id, suffix]
		var entered := svc.apply(step.state, {"type": "enter_node", "payload": {"node_id": id}}, step.rng_states)
		assert(entered.ok, str(entered.error.message_key) if not entered.ok else "")
		step = entered.data
		var node := step.state.find_node(id)
		if step.battle_input != null:
			var settled := svc.settle_battle(step.state, {"battle_id": id, "result": "won", "remaining_vitality": 60, "reason": "smoke"}, step.rng_states)
			assert(settled.ok)
			step = settled.data
			if step.state.outcome == "won":
				assert(step.run_summary != null)
				break
			for item in step.state.pending_reward.items:
				var claimed := svc.apply(step.state, {"type": "claim_reward", "payload": {"offer_id": step.state.pending_reward.offer_id, "item_id": item.item_id, "candidate_id": item.candidates[0]}}, step.rng_states)
				assert(claimed.ok)
				step = claimed.data
		elif node.kind == "event":
			var event: Variant = node.context.event
			var selected := svc.apply(step.state, {"type": "choose_event", "payload": {"event_instance_id": event.event_instance_id, "option_id": "leave", "selection_ids": []}}, step.rng_states)
			assert(selected.ok, str(selected.error.message_key) if not selected.ok else "")
			step = selected.data
		elif node.kind == "rest":
			var rested := svc.apply(step.state, {"type": "take_rest", "payload": {"node_id": id, "option_id": "heal"}}, step.rng_states)
			assert(rested.ok)
			step = rested.data
		var viewed := svc.make_view(step.state)
		assert(not viewed.is_empty())
		var left := svc.apply(step.state, {"type": "leave_node", "payload": {"node_id": id}}, step.rng_states)
		assert(left.ok, str(left.error.message_key) if not left.ok else "")
		step = left.data
	assert(step.state.outcome == "won")
	assert(step.state.node_path.size() == 6)
	print("G4 RunService smoke passed: 6 nodes, final summary, production catalog")
	quit()
