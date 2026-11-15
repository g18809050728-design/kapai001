extends RefCounted

## Detached route checkpoints; all actions after setup use public GameSession/UI.
var helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var failures: Array[String] = []


func room(subtype: String, event_id: String = "", familiar: bool = false) -> GameShell:
	var session := GameSession.new(SaveStore.new("user://event-polish-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]))
	session.update_settings({"autosave": false, "presentation": {"reduced_motion": true, "animation_speed": 0}})
	session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42"))
	var run := session._state.run
	run.campaign = CampaignService.initial()
	run.nodes = CampaignMap.build(run.run_id)
	run.money = 200
	run.vitality = 40
	if not event_id.is_empty():
		for id in ["V01", "V03", "V04", "V10"]:
			if id != event_id:
				run.seen_event_ids.append(id)
	if familiar:
		run.campaign.visited_types = ["N", "R", "L", "E"]
		run.campaign.exploration = 4
	var destination: RunNodeState
	for node in run.nodes:
		if str(CampaignMap.metadata(node.node_id).subtype) == subtype:
			destination = node
			break
	if destination == null:
		failures.append("Missing controlled room: " + subtype)
		return null
	var path: Array = []
	for year in range(1, destination.term + 1):
		var first: RunNodeState = run.nodes.filter(func(node): return node.term == year and node.layer == 1)[0]
		if year == destination.term:
			for entrance in run.nodes.filter(func(node): return node.term == year and node.layer == 1):
				var approach := _path_to(run, entrance.node_id, destination.node_id)
				if not approach.is_empty():
					path.append_array(approach)
					break
		else:
			var node := first
			while true:
				path.append(node.node_id)
				if node.next_ids.is_empty():
					break
				node = run.find_node(node.next_ids[0])
	path.erase(destination.node_id)
	for id in path:
		var node := run.find_node(id)
		node.status = "completed"
		if node.kind in ["normal", "elite", "boss"]:
			node.context = {"settled": true}
			run.settled_battle_ids.append(id)
		run.node_path.append(id)
		run.current_node_id = id
	run.term = destination.term
	if run.term > 1:
		run.campaign.direction = "theory"
	if run.term == 4:
		run.campaign.destination = "job"
	if not run.validate().is_empty():
		failures.append("Invalid route checkpoint " + subtype + ": " + str(run.validate()))
	var shell: GameShell = helpers.attach_shell(session)
	shell.show_screen("")
	if not helpers.enter_node(shell, destination.node_id):
		failures.append("Public enter_node failed: " + subtype)
	if not event_id.is_empty() and str(session.get_view().run.get("event", {}).get("definition_id", "")) != event_id:
		failures.append("Wrong event ID: " + event_id)
	if familiar:
		if not shell.press("event:option:leave"):
			failures.append("Could not finish event for familiar checkpoint")
		# The shared fixture pauses shell auto-advance for command A/B checks.
		# Complete the resolved node through the public command before capture.
		var current := session.get_view()
		var completed := session.submit(CommandContext.new(str(current.run_id), current.revision), GameAction.new(&"leave_node", {"node_id": current.node.node_id}))
		if not completed.accepted:
			failures.append("Public leave_node did not trigger familiar checkpoint")
		shell.refresh()
		if str(session.get_view().run.get("campaign_offer", {}).get("kind", "")) != "familiar":
			failures.append("Expected real pending familiar offer")
	return shell


func _path_to(run: RunState, id: String, destination: String) -> Array:
	if id == destination:
		return [id]
	for next in run.find_node(id).next_ids:
		var path := _path_to(run, next, destination)
		if not path.is_empty():
			path.push_front(id)
			return path
	return []
