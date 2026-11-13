extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _forecast: GDScript


func run() -> Array[String]:
	if not ResourceLoader.exists("res://src/run/route_forecast.gd"):
		_check(false, "RouteForecast implementation exists")
		return _failures
	_forecast = load("res://src/run/route_forecast.gd")
	if _forecast == null or not _forecast.can_instantiate():
		_check(false, "RouteForecast compiles")
		return _failures
	_forecasts()
	await _resource_slots()
	await _canvas_layout()
	await _selection_and_navigation()
	await _middle_focus()
	await _production_readonly()
	await _dense_production_layout()
	print("ADAPTIVE_MAP_UI_CHECKS=", _checks)
	return _failures


static func graph() -> Array:
	return [
		_node("start", 1, 3, "normal", "N", ["shop", "risk"]),
		_node("shop", 2, 1, "shop", "S", ["rest"]),
		_node("risk", 2, 5, "elite", "K", ["lab"]),
		_node("rest", 3, 1, "rest", "R", ["merge"]),
		_node("lab", 3, 5, "rest", "LAB", ["merge"]),
		_node("merge", 4, 3, "event", "E", ["last"]),
		_node("last", 5, 3, "boss", "B", []),
		_node("unrelated", 2, 3, "elite", "EL", ["lab"]),
		_node("future", 2, 3, "shop", "S", [], 2),
	]


static func _node(id: String, layer: int, column: int, kind: String, subtype: String, next: Array, term: int = 1) -> Dictionary:
	return {"node_id": id, "term": term, "layer": layer, "column": column, "kind": kind, "subtype": subtype, "title": "用于检验长名称的校园路线节点" + id, "next_ids": next, "status": "unvisited"}


static func map_view() -> Dictionary:
	return {"run_id": "handmade-map", "revision": 7, "term": 1, "year_title": "大一探索", "year_layers": 5, "relic_layers": [2, 4], "map_influence": "已完成经历只有限影响机会，其他方向仍可选择。", "nodes": graph(), "current_node_id": "start", "reachable_node_ids": ["shop", "risk"], "cards": [], "relics": []}


func _forecasts() -> void:
	var nodes := graph()
	var before := nodes.duplicate(true)
	var result: Dictionary = _forecast.describe(nodes, "start")
	_check(result.node_ids.size() == 6 and not result.node_ids.has("last") and not result.node_ids.has("unrelated") and not result.node_ids.has("future"), "highlight is selected node and actual next three layers only")
	for metric in ["shop", "rest", "service", "risk", "competition"]:
		_check(result.minimums[metric] == 0 and result.maximums[metric] == 1, "mutually exclusive forks have honest 0–1 " + metric)
	_check(result.minimums.steps == 3 and result.maximums.steps == 3 and result.path_count == 2, "reconverging paths count steps per route, not union")
	_check(not result.forced_risk and result.text.contains("可能") and result.text.contains("0–1"), "optional risk and services are described as possibilities")
	var risky: Dictionary = _forecast.describe(nodes, "unrelated", 2)
	_check(risky.minimums.service == 1 and risky.maximums.service == 1, "laboratory is a service opportunity, not safe rest")
	var forced := [_node("a", 1, 3, "normal", "N", ["b", "c"]), _node("b", 2, 1, "elite", "EL", []), _node("c", 2, 5, "elite", "K", [])]
	var danger: Dictionary = _forecast.describe(forced, "a")
	_check(danger.forced_risk and danger.minimums.risk == 1 and danger.text.contains("必经"), "different risky forks still force one risk")
	_check(_forecast.describe(nodes, "last").maximums.steps == 0, "terminal has no invented future")
	_check(_forecast.describe(nodes, "missing").node_ids.is_empty(), "unknown selection has empty forecast")
	_check(_forecast.describe(nodes, "start", 0).node_ids == ["start"], "zero depth includes only selected node")
	_check(nodes == before, "forecast preserves input metadata and edges")
	var broken := [_node("a", 1, 3, "normal", "N", ["missing", "b"]), _node("b", 2, 2, "shop", "S", [])]
	var partial: Dictionary = _forecast.describe(broken, "a")
	_check(not partial.complete and partial.minimums.shop == 0, "missing graph edges cannot become guaranteed services")
	var unknown_risk := [_node("a", 1, 3, "normal", "N", ["missing", "b"]), _node("b", 2, 2, "elite", "EL", [])]
	var uncertain: Dictionary = _forecast.describe(unknown_risk, "a")
	_check(not uncertain.forced_risk and not uncertain.text.contains("也有避开路线") and uncertain.text.contains("无法保证"), "incomplete branches cannot promise a route avoiding risk")
	_check(not partial.text.contains("这段路线没有精英"), "unknown branches cannot promise absence of risk")
	_check(result.layers.size() == 3 and result.layers[0].node_ids == ["shop", "risk"], "forecast publishes actual possibilities separately for each next layer")
	var future_link := [_node("a", 1, 3, "normal", "N", ["future"]), _node("future", 2, 3, "shop", "S", [], 2)]
	_check(not _forecast.describe(future_link, "a").node_ids.has("future"), "forecast cannot reveal future years through a cross-year edge")


func _canvas_layout() -> void:
	var script: GDScript = load("res://src/ui/route_canvas.gd")
	var canvas = script.new()
	canvas.configure(graph().filter(func(node): return node.term == 1), ["shop", "risk"], "start")
	canvas.size = Vector2(840, 600)
	(Engine.get_main_loop() as SceneTree).root.add_child(canvas)
	canvas.arrange()
	_check(is_equal_approx(canvas.positions.shop.x, canvas.positions.rest.x) and is_equal_approx(canvas.positions.risk.x, canvas.positions.lab.x), "stable columns align across different layers")
	_check(canvas.positions.shop.x < canvas.positions.start.x and canvas.positions.start.x < canvas.positions.risk.x, "column values determine horizontal order")
	var x: float = canvas.positions.shop.x
	canvas.nodes.reverse()
	canvas.arrange()
	_check(is_equal_approx(x, canvas.positions.shop.x), "array reordering cannot move frozen columns")
	canvas.configure(graph().filter(func(node): return node.term == 1), ["shop", "risk"], "start", "shop", 3)
	canvas.arrange()
	_check(canvas.forecast_node_ids.has("merge") and not canvas.forecast_node_ids.has("risk"), "selected subtree highlight excludes unrelated branch")
	canvas.free()
	await _frames()


func _resource_slots() -> void:
	# In-memory textures exercise optional slots without producing any new assets.
	var saved_textures := UiStyle._textures.duplicate()
	var texture := GradientTexture2D.new()
	texture.gradient = Gradient.new()
	var canvas = load("res://src/ui/route_canvas.gd").new()
	canvas.overview = true
	(Engine.get_main_loop() as SceneTree).root.add_child(canvas)
	canvas.size = Vector2(840, 240)
	for year in range(1, 5):
		var nodes := [_node("asset", 1, 3, "normal", "N", [], year)]
		var slot := "map.background.y%d" % year
		UiStyle._textures[slot] = null
		canvas.configure(nodes, [], "")
		_check(canvas.get("background_texture") == null, "missing year background preserves native fallback")
		UiStyle._textures[slot] = texture
		canvas.configure(nodes, [], "")
		_check(canvas.get("background_texture") == texture, "registered year background is consumed: " + slot)
	var types := ["N", "E", "S", "EL", "K", "R", "L", "LAB", "C", "T", "I", "ST", "B"]
	var icon_nodes: Array = []
	for subtype in types:
		UiStyle._textures["map.node." + subtype] = texture
		icon_nodes.append(_node(subtype, icon_nodes.size() + 1, 3, "normal", subtype, []))
	canvas.configure(icon_nodes, [], "")
	canvas.arrange()
	var positions: Dictionary = canvas.positions.duplicate(true)
	var icons: Variant = canvas.get("node_textures")
	_check(icons is Dictionary and icons.size() == types.size(), "all documented map.node subtype slots are consumed")
	await _frames()
	for subtype in types:
		UiStyle._textures["map.node." + subtype] = null
	canvas.configure(icon_nodes, [], "")
	canvas.arrange()
	_check(canvas.positions == positions, "optional icons cannot change columns or node hit targets")
	canvas.free()
	var page = load("res://src/ui/experience_page.gd").new()
	page.screen = "map"
	(Engine.get_main_loop() as SceneTree).root.add_child(page)
	page.size = Vector2(960, 600)
	var map_data := map_view()
	map_data.nodes = icon_nodes
	for subtype in types:
		UiStyle._textures["map.node." + subtype] = texture
	page.render(map_data)
	await _frames()
	var native_positions := {}
	for subtype in types:
		var button: Button = page._buttons["node:" + subtype]
		_check(button.get("node_texture") == texture, "detailed stamp consumes optional icon: " + subtype)
		native_positions[subtype] = button.get_rect()
		UiStyle._textures["map.node." + subtype] = null
	page.render(map_data)
	await _frames()
	for subtype in types:
		var button: Button = page._buttons["node:" + subtype]
		_check(button.get("node_texture") == null and button.get_rect() == native_positions[subtype], "detailed native fallback preserves label and hit target: " + subtype)
	page.free()
	page = load("res://src/ui/experience_page.gd").new()
	page.screen = "campaign"
	(Engine.get_main_loop() as SceneTree).root.add_child(page)
	page.size = Vector2(960, 600)
	var variants := {"direction": ["theory", "engineering", "competition", "practice"], "destination": ["job", "exam", "research", "abroad"]}
	for kind in variants:
		for id in variants[kind]:
			UiStyle._textures["map.destination." + str(id)] = null
		var data := map_view()
		data.campaign_offer = {"offer_id": "asset-" + kind, "kind": kind, "previews": {}}
		page.render(data)
		await _frames()
		for id in variants[kind]:
			var matching := false
			for art in page.find_children("*", "TextureRect", true, false):
				if art.get_meta("resource_slot", "") == "map.destination." + str(id):
					matching = not str(art.get_meta("art_id", "")).begins_with("map.destination.") and art.texture != null
			_check(matching, "missing optional choice artwork uses existing fallback: " + str(id))
			UiStyle._textures["map.destination." + str(id)] = texture
		page.render(data)
		await _frames()
		for id in variants[kind]:
			var matching := false
			for art in page.find_children("*", "TextureRect", true, false):
				if art.get_meta("resource_slot", "") == "map.destination." + str(id):
					matching = art.texture == texture
			_check(matching, "registered optional choice artwork overrides legacy illustration: " + str(id))
	page.free()
	UiStyle._textures = saved_textures
	await _frames()


func _selection_and_navigation() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for scale in [1.0, 1.25, 1.5]:
			UiStyle.text_scale = scale
			var page = load("res://src/ui/experience_page.gd").new()
			page.screen = "map"
			tree.root.add_child(page)
			page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			page.theme = UiStyle.make_theme()
			var data := map_view()
			var before := data.duplicate(true)
			var actions: Array = []
			page.action_requested.connect(func(action): actions.append(action))
			page.render(data)
			await _frames(12)
			_check(page.button_disabled("map:enter"), "enter requires explicit reachable selection")
			_check(not page.button_uids().has("node:future"), "future years are not displayed")
			_check(_all_text(page).contains(data.map_influence) or page.header.get_child(0).tooltip_text.contains(data.map_influence), "experience influence banner or compact title tooltip comes from view")
			_check(page.press("node:unrelated"), "unreachable node remains inspectable")
			await _frames()
			_check(page.button_disabled("map:enter") and _all_text(page).contains("路线预告"), "inspect unreachable node without enabling enter")
			_check(page.press("node:shop"), "reachable node button selects locally")
			await _frames()
			_check(not page.button_disabled("map:enter") and page.action_draft("map:enter").payload.node_id == "shop", "enter draft targets exact selected reachable ID")
			_check(page.press("map:overview"), "overview toggle has stable keyboard accessible button")
			await _frames(12)
			_check(page.find_children("MapOverview", "Control", true, false).size() == 1, "overview shows actual whole-year graph")
			var overview: Control = page.find_child("MapOverview", true, false)
			_check(overview.get_global_rect().end.y <= page._scroll.get_global_rect().end.y, "full overview fits viewport at each text scale and size")
			_check(page.press("map:current"), "locate current works from overview")
			await _frames(12)
			_check(page._choices.get("map:node") == "shop", "locate preserves selection")
			page.press("map:overview")
			await _frames()
			var button: Button = page._buttons["node:shop"]
			button.grab_focus()
			var right := InputEventKey.new()
			right.keycode = KEY_RIGHT
			right.pressed = true
			Input.parse_input_event(right)
			await _frames()
			var focused: Control = tree.root.gui_get_focus_owner()
			_check(focused != null and focused.get_meta("uid", "") == "node:unrelated", "Right key follows horizontal column neighbor")
			var accept := InputEventAction.new()
			accept.action = &"ui_accept"
			accept.pressed = true
			Input.parse_input_event(accept)
			await _frames()
			accept = InputEventAction.new()
			accept.action = &"ui_accept"
			accept.pressed = false
			Input.parse_input_event(accept)
			await _frames()
			_check(page._choices.get("map:node") == "unrelated", "keyboard accepts real focused node as local selection")
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			page._input(escape)
			await _frames()
			_check(page.button_disabled("map:enter"), "Escape clears map selection")
			_check(actions.is_empty() and data == before, "viewing, focus, overview, locate and cancel emit no domain commands or writes")
			var canvas: Control = page.find_child("RouteMap", true, false)
			_check(canvas != null and canvas.size.x <= page._scroll.size.x, "seven columns fit viewport at requested text scale")
			var node_buttons: Array = page.button_uids().filter(func(uid): return str(uid).begins_with("node:"))
			for uid in node_buttons:
				var node_button: Button = page._buttons[uid]
				_check(node_button.get_theme_font_size("font_size") >= roundi(14 * scale), "node type and state respect text scale")
				for other_uid in node_buttons:
					if uid != other_uid:
						_check(not node_button.get_rect().intersects(page._buttons[other_uid].get_rect()), "short nodes do not overlap")
			page._choices["map:node"] = "missing"
			page.view.reachable_node_ids.append("missing")
			page.refresh_local()
			_check(page.button_disabled("map:enter"), "stale reachable list cannot enter a missing node")
			page.free()
			await _frames()
	UiStyle.text_scale = 1.0
	tree.root.size = old_size


func _production_readonly() -> void:
	# The behavior tests above need no generator; this additionally checks the real service boundary.
	var session = load("res://src/app/game_session.gd").new(SaveStore.new("user://adaptive-map-ui-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	var started = session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	_check(started != null and started.accepted, "production new annual map starts")
	if started != null and started.accepted:
		var before: Dictionary = {"run": session._state.run.to_dictionary(), "random": session._state.random_snapshot.duplicate(true), "revision": session._state.revision}
		var page = load("res://src/ui/experience_page.gd").new()
		page.screen = "map"
		(Engine.get_main_loop() as SceneTree).root.add_child(page)
		page.size = Vector2(960, 600)
		page.render(session.get_view().run)
		for node in page.view.nodes:
			page.press("node:" + str(node.node_id))
		page.press("map:overview")
		page.press("map:current")
		await _frames(12)
		_check(session._state.run.to_dictionary() == before.run and session._state.random_snapshot == before.random and session._state.revision == before.revision, "production browsing preserves full RunState, every RNG stream and revision")
		page.free()
	session.free()


func _dense_production_layout() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	var session = load("res://src/app/game_session.gd").new(SaveStore.new("user://density-ui-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	var started = session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	_check(started != null and started.accepted, "dense layout uses production RunService graph")
	if started == null or not started.accepted:
		session.free()
		return
	var data: Dictionary = session.get_view().run
	var counts := {}
	for node in data.nodes:
		counts[node.layer] = int(counts.get(node.layer, 0)) + 1
	_check(counts.values().max() >= 4, "production map exercises four or five simultaneous lanes")
	var frozen := data.duplicate(true)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for scale in [1.0, 1.25, 1.5]:
			UiStyle.text_scale = scale
			var page = load("res://src/ui/experience_page.gd").new()
			page.screen = "map"
			tree.root.add_child(page)
			page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			page.theme = UiStyle.make_theme()
			page.render(data)
			await _frames(12)
			var canvas = page.find_child("RouteMap", true, false)
			var buttons: Array = data.nodes.map(func(node): return page._buttons["node:" + str(node.node_id)])
			_check(buttons.size() == data.nodes.size(), "every production node retains exact UID")
			var left := INF
			var right := -INF
			for index in buttons.size():
				var button: Button = buttons[index]
				var rect := button.get_rect()
				left = minf(left, rect.position.x)
				right = maxf(right, rect.end.x)
				_check(rect.size.x <= 84 and rect.size.y <= 90, "dense nodes use compact stamps at every text scale")
				_check(rect.position.x >= 0 and rect.end.x <= canvas.size.x, "outermost frozen columns fit inside route canvas")
				_check(not button.disabled and button.focus_mode == Control.FOCUS_ALL, "all statuses remain inspectable and keyboard focusable")
				for other in range(index + 1, buttons.size()):
					_check(not rect.intersects(buttons[other].get_rect()), "dense production labels and hit targets never overlap")
			_check(right - left <= 700 and absf((left + right) * .5 - canvas.size.x * .5) <= 1, "route occupies a centered bounded width")
			_check(canvas.custom_minimum_size.y < 112 * (int(data.year_layers) - 1) + 104, "dense route has shorter row spacing")
			var routes: Dictionary = canvas.get("edge_paths")
			var expected_edges := 0
			var arrows: Array = []
			for node in data.nodes:
				expected_edges += node.next_ids.size()
			_check(routes.size() == expected_edges, "each actual dense graph connection has its own curved path")
			for route in routes.values():
				_check(route.size() > 4, "edges are sampled curves rather than straight chords")
				var tip: Vector2 = route[route.size() - 1]
				for other_tip in arrows:
					_check(tip.distance_to(other_tip) > 3, "converging routes have distinct directional arrow ports")
				arrows.append(tip)
				var clear := true
				for button in buttons:
					var label: Rect2 = button.call("label_rect")
					label.position += button.position
					for point in route:
						if label.grow(1).has_point(point):
							clear = false
				_check(clear, "every curved route avoids every dense node label")
			var selected := str(data.reachable_node_ids[0])
			page._buttons["node:" + selected].grab_focus()
			page.press("node:" + selected)
			await _frames(12)
			_check(page._buttons["node:" + selected].button_pressed and page._buttons["node:" + selected].has_focus(), "production selection preserves pressed state and keyboard focus")
			var selected_canvas = page.find_child("RouteMap", true, false)
			_check(page._scroll.size.y >= selected_canvas.row_height() * 2 + 12, "selected map leaves room for at least two full node rows")
			_check(not page.button_disabled("map:enter") and page.action_draft("map:enter").payload.node_id == selected, "production enter targets selected exact UID")
			page.press("map:overview")
			await _frames(12)
			var overview: Control = page.find_child("MapOverview", true, false)
			_check(page._scroll.get_global_rect().encloses(overview.get_global_rect()), "dense overview fits at both sizes and every text scale")
			_check(data == frozen, "dense UI leaves frozen graph and view unchanged")
			page.free()
			await _frames()
	UiStyle.text_scale = 1.0
	tree.root.size = old_size
	session.free()


func _middle_focus() -> void:
	UiStyle.text_scale = 1.5
	var page = load("res://src/ui/experience_page.gd").new()
	page.screen = "map"
	(Engine.get_main_loop() as SceneTree).root.add_child(page)
	page.size = Vector2(960, 600)
	var data := map_view()
	data.nodes = []
	for layer in range(1, 15):
		data.nodes.append(_node(str(layer), layer, 3, "normal", "N", [str(layer + 1)] if layer < 14 else []))
	data.current_node_id = "8"
	data.reachable_node_ids = ["9"]
	page.render(data)
	await _frames(16)
	var button: Button = page._buttons["node:9"]
	_check(absf(button.get_global_rect().get_center().y - page._scroll.get_global_rect().get_center().y) <= 2, "middle-year render centers next reachable node")
	page._scroll.scroll_vertical += 34
	var old_scroll: int = page._scroll.scroll_vertical
	page.press("node:9")
	await _frames(12)
	_check(absi(page._scroll.scroll_vertical - old_scroll) <= 1, "local selection retains manual map scroll")
	page.press("map:overview")
	await _frames(12)
	_check(page._scroll.scroll_vertical == 0, "opening overview reveals entire overview")
	var overview: Control = page.find_child("MapOverview", true, false)
	_check(overview.get_global_rect().end.y <= page._scroll.get_global_rect().end.y and overview.global_position.y >= page._scroll.global_position.y, "whole overview fits remaining viewport without clipping")
	page.press("map:overview")
	await _frames(12)
	_check(absi(page._scroll.scroll_vertical - old_scroll) <= 1, "closing overview restores previous detailed route position")
	page.press("map:current")
	await _frames(12)
	var current: Button = page._buttons["node:8"]
	_check(absf(current.get_global_rect().get_center().y - page._scroll.get_global_rect().get_center().y) <= 2, "locate current centers the actual current node")
	page._buttons["node:9"].grab_focus()
	page.press("node:9")
	await _frames(12)
	var selected: Button = page._buttons["node:9"]
	print("ADAPTIVE_MAP_FOCUS=", JSON.stringify({"selected_rect": selected.get_global_rect(), "viewport": page._scroll.get_global_rect(), "focused": selected.has_focus(), "scroll": page._scroll.scroll_vertical, "scope": page._map_focus_scope}))
	_check(selected.get_global_rect().position.y >= page._scroll.global_position.y and selected.get_global_rect().end.y <= page._scroll.get_global_rect().end.y, "focused selection remains fully visible after forecast changes viewport")
	page.free()
	UiStyle.text_scale = 1.0
	await _frames()


func _frames(count: int = 5) -> void:
	for index in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _all_text(node: Node) -> String:
	var value := str(node.get("text")) if node is Label or node is Button else ""
	for child in node.get_children():
		value += "\n" + _all_text(child)
	return value


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("adaptive map UI: " + message)
