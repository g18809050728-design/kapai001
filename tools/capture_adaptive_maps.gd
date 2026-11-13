extends SceneTree

## Run with a real renderer and isolated APPDATA using verify_adaptive_maps.py.
## Annual checkpoints use real RunService commands; battle wins are injected
## controlled outcomes to isolate route/UI behavior, not natural playthroughs.
const OUT := "res://artifacts/verification/adaptive-maps-20261113/visual"
var _output := OUT
const ExperiencePage = preload("res://src/ui/experience_page.gd")
const Forecast = preload("res://src/run/route_forecast.gd")
var _service: RunService
var _run: RunState
var _rng: Dictionary
var _snapshots: Array = []
var _screens: Array = []
var _failures: Array[String] = []
var _page: UiExperiencePage
var _seed := ""


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("Adaptive map PNG capture requires a real renderer, not --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	var catalog := ContentDB.new("res://data/four_year")
	var loaded := catalog.load("campus_four_year")
	if not loaded.ok:
		push_error("Cannot load capture content: " + str(loaded.error))
		quit(1)
		return
	_service = RunService.new(catalog)
	for seed in ["7", "42"]:
		_seed = seed
		_collect_years()
	if _snapshots.is_empty():
		_failures.append("No service-backed annual checkpoints were generated")
	var paper := ColorRect.new()
	paper.color = UiStyle.PAPER
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(paper)
	_page = ExperiencePage.new()
	_page.screen = "map"
	_page.theme = UiStyle.make_theme()
	root.add_child(_page)
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.offset_left = 12
	_page.offset_right = -12
	_page.offset_top = 8
	_page.offset_bottom = -8
	for snapshot in _snapshots:
		for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
			root.size = dimensions
			for scale in [100, 125, 150]:
				UiStyle.text_scale = scale / 100.0
				_page.screen = str(snapshot.screen)
				_page.render(snapshot.view)
				await _frames(12)
				var label := "seed%s-y%d-%s-%dx%d-text%d" % [snapshot.seed, snapshot.view.term, snapshot.checkpoint, dimensions.x, dimensions.y, scale]
				if _page.screen != "map":
					await _save(label, snapshot)
					continue
				var reachable: Array = snapshot.view.get("reachable_node_ids", [])
				if not reachable.is_empty():
					_page._buttons["node:" + str(reachable[0])].grab_focus()
					_page.press("node:" + str(reachable[0]))
					await _frames(8)
				await _save(label + "-selected", snapshot)
				_page.press("map:overview")
				await _frames(8)
				await _save(label + "-overview", snapshot)
				_page.press("map:overview")
				await _frames(4)
	_page.free()
	UiStyle.text_scale = 1.0
	var file := FileAccess.open(_output.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		_failures.append("Cannot write PNG capture metadata")
	else:
		file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "display": DisplayServer.get_name(), "scope": "Real rendered UI from frozen RunService annual maps; controlled battle outcomes, not natural balance or full G8 acceptance", "inputs": _input_hashes(), "screenshots": _screens, "failures": _failures}, "\t"))
		file.close()
	for failure in _failures:
		push_error(failure)
	print("ADAPTIVE_MAP_CAPTURE=", JSON.stringify({"screens": _screens.size(), "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _collect_years() -> void:
	var created := _service.create(StartRunRequest.new("P02", &"normal", "campus_four_year", _seed))
	if created == null or not created.ok:
		_failures.append("Seed " + _seed + " cannot create annual map")
		return
	_accept(created)
	var recorded := {}
	for step in 900:
		if not _run.outcome.is_empty():
			break
		var pending: Dictionary = _run.campaign.pending
		if not pending.is_empty():
			var kind := str(pending.kind)
			if kind in ["direction", "destination"] and not recorded.has(kind):
				_snapshots.append({"seed": _seed, "checkpoint": "before-" + kind, "screen": "campaign", "view": _service.make_view(_run)})
				recorded[kind] = true
			var payload := {"offer_id": pending.offer_id, "option_id": "skip"}
			if kind == "direction":
				payload.option_id = "theory"
			elif kind == "destination":
				payload.option_id = "research"
			elif kind == "grand":
				payload.option_id = "resources"
			elif kind == "service":
				var subtype := str(CampaignProgression.metadata(_run, str(pending.source_node_id)).get("subtype", ""))
				payload.option_id = "progress" if subtype == "ST" else ("money" if subtype in ["C", "I"] else "skip")
			if not _apply("choose_campaign", payload):
				return
			continue
		if not _run.active_battle_id.is_empty():
			if not _accept(_service.settle_battle(_run, {"battle_id": _run.active_battle_id, "result": "won", "remaining_vitality": mini(60, _run.max_vitality)}, _rng)):
				return
			continue
		if _run.pending_reward != null and not _run.pending_reward.is_complete():
			for item in _run.pending_reward.items:
				if item.status == "pending":
					if not _apply("skip_reward", {"offer_id": _run.pending_reward.offer_id, "item_id": item.item_id}):
						return
					break
			continue
		var current := _run.find_node(_run.current_node_id)
		if current != null and current.status == "active":
			if current.kind == "event" and str(current.context.event.resolved_option_id).is_empty():
				if not _apply("choose_event", {"event_instance_id": current.context.event.event_instance_id, "option_id": "leave"}):
					return
			elif current.kind == "rest" and not current.context.get("used", false):
				if not _apply("take_rest", {"node_id": current.node_id, "option_id": "heal"}):
					return
			else:
				if not _apply("leave_node", {"node_id": current.node_id}):
					return
			continue
		var key := str(_run.term)
		if not recorded.has(key):
			_snapshots.append({"seed": _seed, "checkpoint": "annual", "screen": "map", "view": _service.make_view(_run)})
			recorded[key] = true
		if _run.term == 1 and current != null and current.layer == 1 and not recorded.has("first-fork"):
			_snapshots.append({"seed": _seed, "checkpoint": "first-fork", "screen": "map", "view": _service.make_view(_run)})
			recorded["first-fork"] = true
		# One middle checkpoint per seed exercises completed/current/future states.
		if _run.term == 3 and current != null and current.layer == 6 and not recorded.has("middle"):
			_snapshots.append({"seed": _seed, "checkpoint": "middle", "screen": "map", "view": _service.make_view(_run)})
			recorded.middle = true
		var reachable := _run.reachable_node_ids()
		if reachable.is_empty():
			_failures.append("No reachable route for seed %s year %d" % [_seed, _run.term])
			return
		var chosen := _safe_choice(reachable)
		if chosen.is_empty():
			_failures.append("No safe capture route for seed %s year %d" % [_seed, _run.term])
			return
		if not _apply("enter_node", {"node_id": chosen}):
			return
	for year in range(1, 5):
		if not recorded.has(str(year)):
			_failures.append("Missing year %d for seed %s" % [year, _seed])


func _safe_choice(reachable: Array) -> String:
	for candidate in reachable:
		var queue: Array = [candidate]
		var seen := {}
		while not queue.is_empty():
			var id := str(queue.pop_front())
			if seen.has(id):
				continue
			seen[id] = true
			var node := _run.find_node(id)
			if node == null or node.kind == "elite":
				continue
			if node.kind == "boss":
				return str(candidate)
			queue.append_array(node.next_ids)
	return ""


func _apply(type: String, payload: Dictionary) -> bool:
	return _accept(_service.apply(_run, GameAction.new(StringName(type), payload), _rng))


func _accept(result: GameResult) -> bool:
	if result == null or not result.ok:
		_failures.append("Controlled capture route failed: " + str(result.error.to_dictionary() if result != null and result.error != null else "null result"))
		return false
	_run = result.data.state
	_rng = result.data.rng_states
	return true


func _save(label: String, snapshot: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(_output.path_join(label + ".png"))
	var selected := str(_page._choices.get("map:node", ""))
	var viewport_rect := _page._scroll.get_global_rect()
	var selected_visible := false
	if _page._buttons.has("node:" + selected):
		selected_visible = viewport_rect.encloses(_page._buttons["node:" + selected].get_global_rect())
	var overview_visible := false
	var overview := _page.find_child("MapOverview", true, false) as Control
	if is_instance_valid(overview):
		overview_visible = viewport_rect.encloses(overview.get_global_rect())
	_screens.append({"file": label + ".png", "seed": snapshot.seed, "year": snapshot.view.term, "checkpoint": snapshot.checkpoint, "screen": snapshot.screen, "size": [root.size.x, root.size.y], "text_scale": roundi(UiStyle.text_scale * 100), "overview": _page._map_overview if snapshot.screen == "map" else false, "overview_fully_visible": overview_visible, "selected_fully_visible": selected_visible, "selected_id": selected, "current_id": snapshot.view.current_node_id, "node_count": snapshot.view.nodes.size(), "frozen_nodes_sha256": JSON.stringify(snapshot.view.nodes).sha256_text(), "forecast": Forecast.describe(snapshot.view.nodes, selected), "save_error": error})
	if snapshot.screen == "map" and _page._map_overview and not overview_visible:
		_failures.append("Full map overview is clipped: " + label)
	if snapshot.screen == "map" and not _page._map_overview and not selected.is_empty() and not selected_visible:
		_failures.append("Selected node is clipped: " + label)
	if error != OK:
		_failures.append("PNG save failed: " + label)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _input_hashes() -> Dictionary:
	var hashes := {}
	for path in ["src/run/route_forecast.gd", "src/run/annual_map_generator.gd", "src/run/campaign_progression.gd", "src/run/run_service.gd", "src/ui/route_canvas.gd", "src/ui/map_node_stamp.gd", "src/ui/experience_page.gd", "tools/capture_adaptive_maps.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes
