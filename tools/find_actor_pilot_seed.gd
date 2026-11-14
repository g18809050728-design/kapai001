extends SceneTree

func _initialize() -> void:
	for seed_number in range(1, 151):
		var session := GameSession.new(SaveStore.new("user://actor-seed-%d-%d" % [Time.get_ticks_usec(), seed_number]))
		session.update_settings({"autosave": false})
		var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", str(seed_number)))
		if not started.accepted:
			session.free()
			continue
		var view := session.get_view()
		var result := session.submit(CommandContext.new(str(view.run_id), view.revision), GameAction.new(&"enter_node", {"node_id": str(view.run.reachable_node_ids[0])}))
		if result.accepted and result.view.battle is Dictionary:
			var ids: Array = result.view.battle.tasks.map(func(t): return t.definition_id)
			print("PILOT_SEED_PROBE=", JSON.stringify({"seed": seed_number, "ids": ids}))
			if ids == ["N01"]:
				print("PILOT_SEED_SELECTED=", seed_number)
				session.free()
				quit(0)
				return
		session.free()
	quit(1)
