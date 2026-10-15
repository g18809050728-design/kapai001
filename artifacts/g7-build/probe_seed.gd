extends SceneTree

func _initialize() -> void:
	for seed_value in range(12):
		var session := GameSession.new(SaveStore.new("user://g7-seed-probe-%s-%s" % [Time.get_ticks_usec(), seed_value]))
		session.update_settings({"autosave": false})
		session.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", str(seed_value)))
		var view := session.get_view()
		session.submit(CommandContext.new(view.run_id, view.revision), GameAction.new(&"enter_node", {"node_id": view.run.reachable_node_ids[0]}))
		var cards: Array[String] = []
		for card in session.get_view().battle.hand:
			cards.append(str(card.definition_id))
		print(seed_value, " ", cards)
		session.free()
	quit()
