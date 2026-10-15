extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	await _reward_details_and_scroll()
	await _shop_scroll()
	await _collection_and_upgrades()
	return _failures


func _reward_details_and_scroll() -> void:
	var catalog := ContentDB.new()
	_check(catalog.load("campus_mvp").ok, "production catalog loads")
	var service := RunService.new(catalog)
	var created := service.create(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	if not created.ok:
		_check(false, "production reward view can be created")
		return
	var state: RunState = created.data.state
	state.pending_reward = RewardOffer.new(
		{
			"offer_id": "feedback",
			"source_node_id": "feedback_node",
			"items":
			[
				{
					"item_id": "cards",
					"kind": "card",
					"status": "pending",
					"candidates": ["K05", "K43", "K51"],
					"skippable": true
				},
				{
					"item_id": "relics",
					"kind": "relic",
					"status": "pending",
					"candidates": ["A05", "A15", "A08"],
					"skippable": true
				}
			]
		}
	)
	var before := state.to_dictionary()
	var data := service.make_view(state)
	_check(state.to_dictionary() == before, "reward details do not enter persisted state")
	var detail: Dictionary = data.pending_reward.items[0].candidate_details.K05
	_check(
		detail.cost == 2 and detail.effects[0].amount == 14,
		"reward view exposes real costs and effects"
	)
	detail.effects[0].amount = 999
	_check(
		(
			service.make_view(state).pending_reward.items[0].candidate_details.K05.effects[0].amount
			== 14
		),
		"reward details are independent copies"
	)
	data = service.make_view(state)
	var page := UiFlowPage.new()
	page.screen = "reward"
	page.theme = UiStyle.make_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(page)
	page.size = Vector2(820, 450)
	page.render(data)
	await _frames()
	var text := _visible_text(page)
	_check(
		text.contains("专注 2") and text.contains("完成量 14") and text.contains("本回合打出过查资料时额外 +4"),
		"reward shows cost, complete effect and bonus condition before selection"
	)
	_check(
		text.contains("合作值 2") and text.contains("考试替代效果") and text.contains("每回合准备"),
		"cooperation and scene reward details include their actual behavior"
	)
	_check(
		text.contains("第 3/6 回合") and text.contains("80%") and text.contains("免除精力费用"),
		"relic rewards show triggers and effects"
	)
	var scroll: ScrollContainer = page.get_child(0)
	scroll.scroll_vertical = 240
	var position := scroll.scroll_vertical
	_check(position > 0, "reward content really scrolls")
	page.press("reward:cards:pick:K05")
	page.press("reward:cards:pick:K43")
	await _frames()
	scroll = page.get_child(0)
	_check(
		abs(scroll.scroll_vertical - position) <= 1,
		"rapid local reward selections preserve scroll after layout"
	)
	page.render(data)
	await _frames()
	scroll = page.get_child(0)
	_check(
		abs(scroll.scroll_vertical - position) <= 1, "same-page session refresh preserves scroll"
	)
	data.current_node_id = "different_node"
	page.render(data)
	await _frames()
	scroll = page.get_child(0)
	_check(scroll.scroll_vertical == 0, "different node resets scroll")
	page.free()


func _shop_scroll() -> void:
	var shell: GameShell = _helpers.start_fixture_shell(
		"user://g7-scroll-%s" % Time.get_ticks_usec()
	)
	var session: GameSession = shell.session
	shell.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
	if not _helpers.finish_battle(shell):
		_check(false, "scroll regression reaches rewards")
		shell.free()
		return
	for step in range(4):
		if session.get_view().screen != &"reward":
			break
		for item in session.get_view().run.pending_reward.items:
			if item.status == "pending":
				shell.press("reward:%s:skip" % item.item_id)
				break
	for node in session.get_view().run.nodes:
		if int(node.layer) == 2 and node.kind == "event":
			shell.press("node:" + str(node.node_id))
			break
	shell.press("event:option:leave")
	_check(session.get_view().screen == &"map", "single successor waits on map")
	shell.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
	await _frames()
	var scroll: ScrollContainer = shell.page.get_child(0)
	scroll.scroll_vertical = 180
	var position := scroll.scroll_vertical
	_check(position > 0, "shop content really scrolls")
	_check(_visible_text(shell.page).contains("完成量"), "shop shows card effects before buying")
	var revision: int = session.get_view().revision
	var stock_id: String = session.get_view().run.shop.stocks[0].stock_id
	shell.press("shop:buy:" + stock_id)
	await _frames()
	scroll = shell.page.get_child(0)
	_check(session.get_view().revision == revision + 1, "shop purchase succeeds through session")
	_check(abs(scroll.scroll_vertical - position) <= 1, "shop purchase keeps scroll position")
	shell.press("shop:save")
	await _frames()
	scroll = shell.page.get_child(0)
	_check(abs(scroll.scroll_vertical - position) <= 1, "manual save keeps scroll position")
	shell.free()


func _collection_and_upgrades() -> void:
	var shell: GameShell = _helpers.start_fixture_shell(
		"user://g7-collections-%s" % Time.get_ticks_usec()
	)
	await _frames()
	var before: String = _helpers.fingerprint(shell.session)
	var first_id: String = shell.session.get_view().run.reachable_node_ids[0]
	var page := shell.page as UiFlowPage
	var button: Button = page._buttons["node:" + first_id]
	_check(button.get_global_rect().end.y < 600, "next station is visible in first screen")
	var scroll: ScrollContainer = page.get_child(0)
	scroll.scroll_vertical = 160
	var offset := scroll.scroll_vertical
	_check(shell.press("inspect:deck"), "map deck inspection is available")
	await _frames()
	_check(
		button.focus_mode == Control.FOCUS_NONE,
		"collection panel isolates background keyboard focus"
	)
	_check(
		_visible_text(page._inspector).contains("完成量"), "deck inspection includes actual effects"
	)
	_check(page.press("inspect:close"), "collection panel closes")
	_check(scroll.scroll_vertical == offset, "closing collection preserves page scroll")
	_check(shell.press("inspect:relics"), "relic inspection is available")
	_check(
		_visible_text(page._inspector).contains("每回合限"), "relic inspection includes trigger limits"
	)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	shell.get_tree().root.push_input(escape, true)
	_check(not is_instance_valid(page._inspector), "Esc closes collection panel")
	_check(
		_helpers.fingerprint(shell.session) == before,
		"collection inspection preserves entire state and RNG"
	)
	var data: Dictionary = shell.session.get_view().run.duplicate(true)
	data.rest = {"options": [{"option_id": "upgrade", "needs_card": true}]}
	page.screen = "rest"
	page.render(data)
	_check(not _visible_text(page).contains("升级后："), "rest hides unselected card targets")
	_check(page.press("rest:option:upgrade"), "rest upgrade option can be selected")
	var text := _visible_text(page)
	_check(
		text.contains("当前：") and text.contains("升级后："),
		"upgrade selection compares both levels before submission"
	)
	page.screen = "summary"
	data.outcome = "won"
	page.render(data)
	_check(
		_visible_text(page).contains("第二学期尚未开放"),
		"winning summary explains current semester boundary"
	)
	shell.free()


func _frames() -> void:
	for frame in range(5):
		await (Engine.get_main_loop() as SceneTree).process_frame


func _visible_text(node: Node) -> String:
	if node is CanvasItem and not node.is_visible_in_tree():
		return ""
	var value: String = node.text + "\n" if node is Label else ""
	for child in node.get_children():
		value += _visible_text(child)
	return value


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("G7 feedback: " + message)
