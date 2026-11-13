extends SceneTree

const OUT := "res://artifacts/verification/visual-cohesion-20261113/session-loops-b.json"
const VISUAL_OUT := "res://artifacts/verification/visual-cohesion-20261113/production-b"
var session: GameSession
var commands: Array = []
var failures: Array[String] = []
var best_route: Array = []
var best_score := -10000
var purchased := false
var visited := {}
var wins := 0
var rewards := 0
var visual_shell: GameShell
var captured: Dictionary = {}
var captures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	session = GameSession.new(SaveStore.new("user://playable-session-loops"))
	session.update_settings({"autosave": false})
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted, "start production seed 42")
	if DisplayServer.get_name() != "headless":
		session.update_settings({"presentation":{"reduced_motion":true,"animation_speed":0}})
		visual_shell = GameShell.new()
		visual_shell.session = session
		root.add_child(visual_shell)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VISUAL_OUT))
	var initial := session.get_view()
	var nodes := {}
	for node in initial.run.nodes:
		nodes[str(node.node_id)] = node
	for id in initial.run.reachable_node_ids:
		_route(nodes, str(id), [], {})
	var route := best_route.duplicate()
	for step in 400:
		var view := session.get_view()
		await _capture_room(str(view.screen))
		if view.terminal_summary != null:
			_check(false, "normal play ended before completing both room loops")
			break
		if view.pending_choice != null:
			var choice: ChoiceRequest = view.pending_choice
			var selected: Array = []
			for index in choice.min_count:
				selected.append(choice.candidates[index].id)
			if not _submit("confirm_choice", {"choice_id": choice.choice_id, "selected_ids": selected}):
				break
		elif view.battle != null:
			if not _fight(view.battle):
				break
		elif view.screen == &"reward":
			var offer: Dictionary = view.run.pending_reward
			for item in offer.items:
				if item.status == "pending":
					if _submit("claim_reward", {"offer_id": offer.offer_id, "item_id": item.item_id, "candidate_id": str(item.candidates[0])}):
						rewards += 1
					break
		elif view.screen == &"campaign":
			var offer: Dictionary = view.run.campaign_offer
			var payload := {"offer_id": offer.offer_id, "option_id": "skip"}
			if offer.kind == "relic":
				payload.option_id = "claim"
				payload.candidate_id = str(offer.candidates[0])
			if not _submit("choose_campaign", payload):
				break
		elif view.screen != &"shop" and view.node is Dictionary and view.node.status == "active" and _can("leave_node", {"node_id": view.node.node_id}):
			# Resolved events/rests retain their room screen until explicitly left.
			if not _submit("leave_node", {"node_id": view.node.node_id}):
				break
		elif view.screen == &"shop":
			visited.shop = true
			if not purchased:
				for stock in view.run.shop.stocks:
					var payload := {"shop_id": view.run.shop.shop_id, "stock_id": stock.stock_id}
					if _can("buy_item", payload):
						purchased = _submit("buy_item", payload)
						break
			if not _submit("leave_node", {"node_id": view.run.current_node_id}):
				break
		elif view.screen == &"event":
			visited.event = true
			if not _submit("choose_event", {"event_instance_id": view.run.event.event_instance_id, "option_id": "leave"}):
				break
		elif view.screen == &"rest":
			visited.rest = true
			var payload := {"node_id": view.run.current_node_id, "option_id": "heal"}
			if not _can("take_rest", payload):
				payload.option_id = "upgrade"
				for card in view.run.cards:
					payload.card_instance_id = str(card.card_id)
					if _can("take_rest", payload):
						break
			if not _submit("take_rest", payload):
				break
		else:
			if wins > 0 and rewards > 0 and purchased and visited.has_all(["shop", "event", "rest"]):
				break
			if route.is_empty():
				_check(false, "planned public route exhausted")
				break
			if not _submit("enter_node", {"node_id": str(route.pop_front())}):
				break
	_check(wins > 0 and rewards > 0, "real battle and reward loop completed")
	_check(purchased and visited.has_all(["shop", "event", "rest"]), "real shop, event and rest loop completed")
	var report := {"scope": "P01 seed 42, production GameSession commands only; no state edits or injected outcomes; automated decisions, not a natural four-year acceptance", "planned_route": best_route, "wins": wins, "rewards": rewards, "purchased": purchased, "visited": visited, "commands": commands, "captures":captures, "final_view": session.get_view().run, "failures": failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PRODUCTION_SESSION_LOOPS=", JSON.stringify({"wins": wins, "rewards": rewards, "purchased": purchased, "visited": visited, "commands": commands.size(), "failures": failures}))
	for failure in failures:
		push_error(failure)
	if is_instance_valid(visual_shell):
		visual_shell.free()
		for frame in 4:
			await process_frame
	session.free()
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)


func _capture_room(room: String) -> void:
	if not is_instance_valid(visual_shell) or captured.has(room) or room not in ["map","battle","reward","shop","event","rest"]:
		return
	captured[room] = true
	for dimensions in [Vector2i(1280,800),Vector2i(960,600),Vector2i(1920,1080)]:
		root.size = dimensions
		visual_shell.show_screen("")
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var name := "%s-%d.png" % [room,dimensions.x]
		var result := root.get_texture().get_image().save_png(VISUAL_OUT.path_join(name))
		_check(result == OK,"capture " + name)
		captures.append({"file":VISUAL_OUT.path_join(name),"revision":session.get_view().revision,"size":[dimensions.x,dimensions.y],"save_error":result})


func _route(nodes: Dictionary, id: String, path: Array, seen: Dictionary) -> void:
	var node: Dictionary = nodes[id]
	path = path.duplicate()
	path.append(id)
	seen = seen.duplicate()
	seen[str(node.kind)] = true
	var score := -path.size()
	for kind in ["shop", "event", "rest"]:
		if seen.has(kind):
			score += 100
	if score > best_score:
		best_score = score
		best_route = path
	if int(node.layer) >= 10 or score >= 290:
		return
	for next in node.next_ids:
		_route(nodes, str(next), path, seen)


func _fight(battle: Dictionary) -> bool:
	var candidates: Array = []
	for card in battle.hand:
		var face: Dictionary = card.face
		var model := CardDisplayModel.from_card(card)
		var score := 100 if model.category == "attack" else (30 if model.category == "defense" else 50)
		if face.get("effects", []).any(func(effect): return effect.op in ["draw", "gain_focus"]):
			score = 80
		candidates.append({"card": card, "score": score})
	candidates.sort_custom(func(a, b): return a.score > b.score)
	for entry in candidates:
		var card: Dictionary = entry.card
		var targets: Array = []
		if card.face.get("target", "self") == "task" and not battle.tasks.is_empty():
			targets.append(str(battle.tasks[0].task_id))
		elif card.face.get("target", "self") == "unit" and not battle.units.is_empty():
			targets.append(str(battle.units[0].unit_id))
		var payload := {"card_instance_id": card.card_id, "target_ids": targets, "replace_unit_id": null}
		if _can("play_card", payload):
			return _submit("play_card", payload)
	return _submit("end_turn", {"retained_card_ids": []})


func _can(type: String, payload: Dictionary) -> bool:
	var preview := session.preview_action(ActionDraft.new(StringName(type), payload))
	return preview.ok and preview.data.can_submit


func _submit(type: String, payload: Dictionary) -> bool:
	var before := session.get_view()
	var result := session.submit(CommandContext.new(str(before.run_id), before.revision), GameAction.new(StringName(type), payload))
	_check(result.accepted, type + " " + JSON.stringify(payload) + ("" if result.accepted else " " + JSON.stringify(result.error.to_dictionary())))
	_check(not result.accepted or result.revision == before.revision + 1, type + " increments exactly one revision")
	var events: Array = []
	for event in result.events:
		events.append({"type": str(event.type), "source": event.source_id, "targets": event.target_ids, "data": event.data})
		if event.type == &"battle_finished" and event.data.get("result", "") == "won":
			wins += 1
	commands.append({"type": type, "payload": payload, "accepted": result.accepted, "revision": result.revision, "events": events})
	return result.accepted


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
