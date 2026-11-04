extends RefCounted

const EXPECTED_RELICS := [
	"A25", "A26", "A27", "A28", "A29", "A30", "A31", "A32",
	"A33", "A34", "A35", "A36", "A37", "A38", "A39", "A40",
	"A41", "A42", "A43", "A44", "A45", "A46", "A47", "A48",
]
const RELIC_NAMES := {
	"A25": "课表夹", "A26": "清晨闹钟", "A27": "旧教材", "A28": "课程群置顶",
	"A29": "便利贴清单", "A30": "雨天折伞", "A31": "学生证挂绳", "A32": "自习室座位卡",
	"A33": "分层文件夹", "A34": "试剂记录本", "A35": "读书会笔记", "A36": "日历提醒",
	"A37": "资料检索卡", "A38": "错题贴", "A39": "静音键盘", "A40": "讨论纪要",
	"A41": "分工白板", "A42": "番茄钟", "A43": "能量补给包", "A44": "提交检查单",
	"A45": "复盘录音", "A46": "校园资源地图", "A47": "完整行动计划", "A48": "毕业导览册",
}


class AbilityCatalog:
	extends ContentDB

	func get_definition(kind: String, id: String) -> GameResult:
		var result := super.get_definition(kind, id)
		if result.ok and kind == "card" and id == "K13":
			result.data.type = "ability"
		return result


class FreeCooperationCatalog:
	extends ContentDB

	func get_definition(kind: String, id: String) -> GameResult:
		var result := super.get_definition(kind, id)
		if result.ok and kind == "card" and id == "K43":
			result.data.cost = 0
		return result


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := ContentDB.new()
	var loaded := catalog.load("campus_mvp")
	_check(loaded.ok, "production manifest loads", failures)
	if not loaded.ok:
		return failures
	var enabled: Array = catalog.get_info().enabled.relic
	for relic_id: String in EXPECTED_RELICS:
		_check(enabled.has(relic_id), "%s is enabled" % relic_id, failures)
		_check(catalog.get_definition("relic", relic_id).ok, "%s resolves" % relic_id, failures)
	for deferred_id in ["A49", "A50", "A51", "A52"]:
		_check(not enabled.has(deferred_id), "%s remains deferred" % deferred_id, failures)
	_check_content_and_ui(catalog, failures)
	var engine := BattleEngine.new(catalog)
	_check_prepare_relics(engine, failures)
	_check_card_relics(engine, failures)
	_check_discounts(engine, catalog, failures)
	_check_legacy_cost_behavior(failures)
	_check_special_windows(engine, failures)
	_check_ability_relics(failures)
	if failures.is_empty():
		print("RELIC_EXPANSION_SUITE=passed")
	return failures


func _check_content_and_ui(catalog: ContentDB, failures: Array[String]) -> void:
	for relic_id: String in EXPECTED_RELICS:
		var found := catalog.get_definition("relic", relic_id)
		if not found.ok:
			continue
		var definition: Dictionary = found.data
		_check(
			UiStyle.label(str(definition.name_key)) == RELIC_NAMES[relic_id],
			"%s has its Chinese name" % relic_id,
			failures
		)
		_check(
			str(definition.get("availability", "")) == "drop",
			"%s is a drop, not a starter" % relic_id,
			failures
		)
		var expected_rarity := (
			"white" if int(relic_id.trim_prefix("A")) <= 32
			else "blue" if int(relic_id.trim_prefix("A")) <= 40
			else "purple" if int(relic_id.trim_prefix("A")) <= 46
			else "gold"
		)
		_check(
			str(definition.get("rarity", "")) == expected_rarity,
			"%s has rarity %s" % [relic_id, expected_rarity],
			failures
		)
		var description := UiContentText.describe_relic(definition)
		_check(
			not description.is_empty() and not description.contains("hook"),
			"%s has player-readable effect text" % relic_id,
			failures
		)
	for case in [
		{"id": "A38", "phrases": ["困倦", "抵消 1 层", "每战"]},
		{"id": "A39", "phrases": ["DDL≤3", "完成量 +2", "每回合"]},
		{"id": "A45", "phrases": ["进入下一阶段", "抽牌", "放松"]},
		{"id": "A46", "phrases": ["工作牌", "策略牌", "能力牌", "合作牌", "场景牌"]},
	]:
		var definition := catalog.get_definition("relic", case.id)
		if not definition.ok:
			continue
		var text := UiContentText.describe_relic(definition.data)
		for phrase: String in case.phrases:
			_check(text.contains(phrase), "%s text contains %s" % [case.id, phrase], failures)
	var legacy_discount := catalog.get_definition("relic", "A04")
	if legacy_discount.ok:
		_check(
			not UiContentText.describe_relic(legacy_discount.data).contains("仅实际减免时计次"),
			"A04 text does not claim zero-cost cards leave its use unspent", failures
		)
	for relic_id in ["A31", "A44"]:
		var actual_discount := catalog.get_definition("relic", relic_id)
		if actual_discount.ok:
			_check(
				UiContentText.describe_relic(actual_discount.data).contains("仅实际减免时计次"),
				"%s text states actual-discount counting" % relic_id, failures
			)
	for rarity in ["white", "blue", "purple", "gold"]:
		var pool := catalog.get_candidates({"kind": "relic", "rarity": rarity, "availability": "drop"})
		for relic_id: String in EXPECTED_RELICS:
			var definition := catalog.get_definition("relic", relic_id)
			if definition.ok and definition.data.rarity == rarity:
				_check(pool.has(relic_id), "%s is selectable in %s rewards" % [relic_id, rarity], failures)
	var rules := catalog.get_definition("ruleset", catalog.get_info().ruleset_id)
	if rules.ok:
		_check(
			rules.data.shop.relic_stock.keys().all(func(key): return key in ["white", "blue"]),
			"shop stock uses only white and blue relics",
			failures
		)


func _check_prepare_relics(engine: BattleEngine, failures: Array[String]) -> void:
	var cases := [
		{"id": "A25", "round": 1, "field": "relax", "delta": 3},
		{"id": "A26", "round": 2, "field": "focus", "delta": 1},
		{"id": "A30", "round": 2, "field": "vitality", "delta": 2},
		{"id": "A36", "round": 1, "field": "focus", "delta": 1},
		{"id": "A42", "round": 2, "field": "focus", "delta": 1},
		{"id": "A43", "round": 3, "field": "vitality", "delta": 4},
		{"id": "A47", "round": 1, "field": "focus", "delta": 1},
	]
	for case: Dictionary in cases:
		var control := _begin(engine, [], _copies("K01", 10))
		var with_relic := _begin(engine, [case.id], _copies("K01", 10))
		_check(control.ok and with_relic.ok, "%s prepares" % case.id, failures)
		if not control.ok or not with_relic.ok:
			continue
		for round_number in range(2, int(case.round) + 1):
			control = _end_turn(engine, control)
			with_relic = _end_turn(engine, with_relic)
			_check(control.ok and with_relic.ok, "%s survives round %d" % [case.id, round_number], failures)
			if not control.ok or not with_relic.ok:
				break
		if not control.ok or not with_relic.ok:
			continue
		var field: String = case.field
		_check(
			int(with_relic.data.state.player[field]) - int(control.data.state.player[field]) == int(case.delta),
			"%s gives %d %s on round %d" % [case.id, case.delta, field, case.round],
			failures
		)
		_check(
			_trigger_count(with_relic, case.id, "round_start") == 1,
			"%s triggers in preparation" % case.id,
			failures
		)
		if case.id in ["A36", "A42", "A47"]:
			var extra := 2 if case.id == "A47" else 1
			_check(
				with_relic.data.state.zones.hand.size() - control.data.state.zones.hand.size() == extra,
				"%s draws %d extra cards after base draw" % [case.id, extra],
				failures
			)
			_check(_trigger_count(with_relic, case.id, "draw") == 1, "%s draw hook triggers" % case.id, failures)
	var a30 := _begin(engine, ["A30"], _copies("K01", 10))
	var a42 := _begin(engine, ["A42"], _copies("K01", 10))
	if a30.ok and a42.ok:
		for round_number in range(2, 5):
			a30 = _end_turn(engine, a30)
			a42 = _end_turn(engine, a42)
			if not a30.ok or not a42.ok:
				break
			if round_number == 4:
				_check(_trigger_count(a30, "A30") == 1, "A30 also heals on round 4", failures)
				_check(_trigger_count(a42, "A42", "draw") == 1, "A42 also draws on round 4", failures)
	var a43 := _begin(engine, ["A43"], _copies("K01", 10))
	if a43.ok:
		a43 = _end_turn(engine, a43)
		if a43.ok:
			a43 = _end_turn(engine, a43)
			if a43.ok:
				_check(int(a43.data.state.player.relax) == 4, "A43 grants 4 relax on round 3", failures)


func _check_card_relics(engine: BattleEngine, failures: Array[String]) -> void:
	for case in [
		{"id": "A28", "card": "K43", "field": "relax", "delta": 3},
		{"id": "A29", "card": "K01", "field": "relax", "delta": 1},
		{"id": "A32", "card": "K51", "field": "relax", "delta": 3},
		{"id": "A34", "card": "K02", "field": "hand", "delta": 2},
		{"id": "A35", "card": "K43", "field": "hand", "delta": 1},
		{"id": "A37", "card": "K51", "field": "hand", "delta": 2},
		{"id": "A41", "card": "K43", "field": "focus", "delta": 1},
	]:
		var control := _begin(engine, [], _copies(case.card, 10))
		var with_relic := _begin(engine, [case.id], _copies(case.card, 10))
		_check(control.ok and with_relic.ok, "%s starts for card trigger" % case.id, failures)
		if not control.ok or not with_relic.ok:
			continue
		control = _play(engine, control, case.card)
		with_relic = _play(engine, with_relic, case.card)
		_check(control.ok and with_relic.ok, "%s resolves its matching card" % case.id, failures)
		if not control.ok or not with_relic.ok:
			continue
		var field: String = case.field
		var actual: int = (
			with_relic.data.state.zones.hand.size() - control.data.state.zones.hand.size()
			if field == "hand"
			else int(with_relic.data.state.player[field]) - int(control.data.state.player[field])
		)
		_check(
			actual == int(case.delta),
			"%s adds %d %s after %s" % [case.id, case.delta, field, case.card],
			failures
		)
		_check(
			_trigger_count(with_relic, case.id, "card_resolved") == 1,
			"%s triggers on its matching card" % case.id,
			failures
		)
	var a33 := _begin(engine, ["A33"], _copies("K01", 10))
	if a33.ok:
		for index in 3:
			a33 = _play(engine, a33, "K01")
			_check(a33.ok, "A33 work card %d resolves" % (index + 1), failures)
			if not a33.ok:
				break
			_check(
				int(a33.data.state.player.relax) == mini(index + 1, 2),
				"A33 rewards only the first two work cards",
				failures
			)
			_check(
				_trigger_count(a33, "A33", "card_resolved") == (1 if index < 2 else 0),
				"A33 per-round limit is respected",
				failures
			)
	var a29 := _begin(engine, ["A29"], _copies("K01", 10))
	if a29.ok:
		a29 = _play(engine, a29, "K01")
		if a29.ok:
			a29 = _play(engine, a29, "K01")
			if a29.ok:
				_check(int(a29.data.state.player.relax) == 1, "A29 only rewards first work", failures)
				_check(_trigger_count(a29, "A29") == 0, "A29 does not retrigger", failures)


func _check_discounts(
	engine: BattleEngine, catalog: ContentDB, failures: Array[String]
) -> void:
	var strategy_cards := _copies("K13", 5)
	strategy_cards.append_array(_copies("K02", 5))
	var a31 := _begin(engine, ["A31"], strategy_cards)
	_check(a31.ok, "A31 starts", failures)
	if a31.ok:
		_promote_hand(a31.data.state)
		var free_id := _find_card(a31.data.state, "K13")
		var paid_id := _find_card(a31.data.state, "K02")
		var before: Dictionary = a31.data.state.to_dictionary()
		var quote := engine.calculate_cost(a31.data.state, paid_id)
		var preview := engine.preview(
			a31.data.state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": paid_id, "target_ids": []})
		)
		_check(quote.ok and int(quote.data.cost) == 0, "A31 quotes first paid strategy as free", failures)
		_check(preview.ok and a31.data.state.to_dictionary() == before, "A31 preview has no side effects", failures)
		a31 = _play_id(engine, a31, free_id)
		_check(a31.ok and _trigger_count(a31, "A31") == 0, "A31 does not consume on zero cost", failures)
		if a31.ok:
			a31 = _play(engine, a31, "K02")
			_check(a31.ok and _trigger_count(a31, "A31") == 1, "A31 discounts paid strategy", failures)
			if a31.ok:
				var second_id := _find_card(a31.data.state, "K02")
				quote = engine.calculate_cost(a31.data.state, second_id)
				_check(quote.ok and int(quote.data.cost) == 1, "A31 only discounts once", failures)
				var encoded := BattleCodec.encode(a31.data.state)
				_check(encoded.ok, "A31 count can be encoded at stable boundary", failures)
				if encoded.ok:
					var restored := BattleCodec.decode(encoded.data, catalog)
					_check(restored.ok, "A31 count can be restored", failures)
					if restored.ok:
						_check(
							restored.data.counters == a31.data.state.counters,
							"A31 counter survives codec roundtrip",
							failures
						)
						quote = engine.calculate_cost(restored.data, second_id)
						_check(quote.ok and int(quote.data.cost) == 1, "A31 remains spent after restore", failures)
	var work_cards := _copies("K06", 3)
	work_cards.append_array(_copies("K01", 7))
	var a44 := _begin(engine, ["A44"], work_cards)
	_check(a44.ok, "A44 starts", failures)
	if a44.ok:
		_promote_hand(a44.data.state)
		a44 = _play(engine, a44, "K06")
		_check(a44.ok and _trigger_count(a44, "A44") == 0, "A44 does not consume on zero cost", failures)
		if a44.ok:
			var first_id := _find_card(a44.data.state, "K01")
			var quote := engine.calculate_cost(a44.data.state, first_id)
			_check(quote.ok and int(quote.data.cost) == 0, "A44 quotes first paid work free", failures)
			a44 = _play_id(engine, a44, first_id)
			_check(a44.ok and _trigger_count(a44, "A44") == 1, "A44 discounts paid work", failures)
			if a44.ok:
				var second_id := _find_card(a44.data.state, "K01")
				quote = engine.calculate_cost(a44.data.state, second_id)
				_check(quote.ok and int(quote.data.cost) == 1, "A44 only discounts once per round", failures)
	for relic_order in [["A31", "A08"], ["A08", "A31"]]:
		var mixed_cards := _copies("K10", 2)
		mixed_cards.append_array(_copies("K02", 8))
		var stacked := _begin(engine, relic_order, mixed_cards)
		if not stacked.ok:
			_check(false, "A31 and A08 start in both slot orders", failures)
			continue
		_promote_hand(stacked.data.state)
		stacked = _play(engine, stacked, "K10")
		_check(
			stacked.ok and _trigger_count(stacked, "A08", "cost_quote") == 1
			and _trigger_count(stacked, "A31") == 0,
			"A31 stays available when A08 waives only vitality", failures
		)
		if stacked.ok:
			stacked = _play(engine, stacked, "K02")
			_check(
				stacked.ok and _trigger_count(stacked, "A31", "cost_quote") == 1,
				"A31 discounts the next paid strategy after A08", failures
			)
	var scene_cards := _copies("K01", 9)
	scene_cards.append("K53")
	var scene_discount := _begin(engine, ["A44"], scene_cards)
	if scene_discount.ok:
		_promote_hand(scene_discount.data.state)
		scene_discount = _play(engine, scene_discount, "K53")
		if scene_discount.ok:
			var first_work_id := _find_card(scene_discount.data.state, "K01")
			var first_quote := engine.calculate_cost(scene_discount.data.state, first_work_id)
			_check(
				first_quote.ok and int(first_quote.data.cost) == 0
				and first_quote.data.sources.is_empty(),
				"A44 leaves an L03-free first work card to the scene", failures
			)
			scene_discount = _play_id(engine, scene_discount, first_work_id)
			_check(
				scene_discount.ok and _trigger_count(scene_discount, "A44") == 0,
				"A44 is not spent by the scene discount", failures
			)
			if scene_discount.ok:
				var next_work_id := _find_card(scene_discount.data.state, "K01")
				var next_quote := engine.calculate_cost(scene_discount.data.state, next_work_id)
				_check(
					next_quote.ok and int(next_quote.data.cost) == 0
					and next_quote.data.sources.size() == 1
					and str(next_quote.data.sources[0].relic_id) == "A44",
					"A44 discounts the next paid work card after L03", failures
				)


func _check_legacy_cost_behavior(failures: Array[String]) -> void:
	var catalog := FreeCooperationCatalog.new()
	var loaded := catalog.load("campus_mvp")
	_check(loaded.ok, "isolated free-cooperation catalog loads", failures)
	if not loaded.ok:
		return
	var engine := BattleEngine.new(catalog)
	var a04 := _begin(engine, ["A04"], _copies("K43", 10))
	_check(a04.ok, "A04 starts with a zero-focus cooperation fixture", failures)
	if not a04.ok:
		return
	var quote := engine.calculate_cost(a04.data.state, _find_card(a04.data.state, "K43"))
	_check(
		quote.ok and int(quote.data.cost) == 0 and quote.data.sources.size() == 1,
		"A04 still quotes on a zero-focus cooperation card", failures
	)
	a04 = _play(engine, a04, "K43")
	_check(
		a04.ok and _trigger_count(a04, "A04", "cost_quote") == 1,
		"A04 consumes its battle use on a zero-focus cooperation card", failures
	)
	if a04.ok:
		quote = engine.calculate_cost(a04.data.state, _find_card(a04.data.state, "K43"))
		_check(
			quote.ok and quote.data.sources.is_empty(),
			"A04 does not quote again after its zero-focus use", failures
		)


func _check_special_windows(engine: BattleEngine, failures: Array[String]) -> void:
	var control := _begin(engine, [], _copies("K01", 10), "N14")
	var a38 := _begin(engine, ["A38"], _copies("K01", 10), "N14")
	if control.ok and a38.ok:
		control = _end_turn(engine, control)
		a38 = _end_turn(engine, a38)
		_check(control.ok and a38.ok, "A38 drowsiness turn resolves", failures)
		if control.ok and a38.ok:
			_check(
				_status_gain_count(control, "drowsiness") == 1
				and _status_gain_count(a38, "drowsiness") == 0,
				"A38 prevents the first drowsiness stack before it lands",
				failures
			)
			_check(_trigger_count(a38, "A38", "before_status_gain") == 1, "A38 triggers once", failures)
	var capped := _begin(engine, ["A38"], _copies("K01", 10), "N14")
	if capped.ok:
		var capped_state: BattleState = capped.data.state
		var player_id := str(capped_state.player.entity_id)
		capped_state.statuses.append({
			"status_id": "drowsiness", "instance_id": "seeded_cap", "source_id": "",
			"target_id": player_id, "stacks": 2, "expiry": "next_player_action_end"
		})
		var cap_events: Array[RuleEvent] = []
		var no_gain := engine._gain_status_on_target(
			capped_state, {"status": "drowsiness", "stacks": 1, "target": "player"},
			player_id, cap_events
		)
		var zero_gain_event := false
		for event: RuleEvent in cap_events:
			if event.type == &"status_gained" and int(event.data.get("amount", -1)) == 0:
				zero_gain_event = true
		_check(
			no_gain.ok and int(capped_state.statuses[0].stacks) == 2 and zero_gain_event
			and cap_events.size() == 1,
			"A38 preserves the existing zero-gain status event at cap", failures
		)
		capped_state.statuses[0].stacks = 1
		var benefit_events: Array[RuleEvent] = []
		var prevented := engine._gain_status_on_target(
			capped_state, {"status": "drowsiness", "stacks": 1, "target": "player"},
			player_id, benefit_events
		)
		_check(
			prevented.ok and int(capped_state.statuses[0].stacks) == 1
			and benefit_events.size() == 1
			and benefit_events[0].type == &"relic_triggered",
			"A38 remains unused until it can prevent a stack", failures
		)
	var normal := _begin(engine, [], _copies("K01", 10))
	var a39 := _begin(engine, ["A39"], _copies("K01", 10))
	if normal.ok and a39.ok:
		normal.data.state.ddl = 3
		a39.data.state.ddl = 3
		normal = _play(engine, normal, "K01")
		a39 = _play(engine, a39, "K01")
		_check(normal.ok and a39.ok, "A39 first work segment resolves", failures)
		if normal.ok and a39.ok:
			_check(
				int(normal.data.state.tasks[0].work_remaining)
				- int(a39.data.state.tasks[0].work_remaining) == 2,
				"A39 adds exactly 2 completion at DDL 3",
				failures
			)
			_check(_trigger_count(a39, "A39", "work_segment") == 1, "A39 triggers on first segment", failures)
			normal = _play(engine, normal, "K01")
			a39 = _play(engine, a39, "K01")
			if normal.ok and a39.ok:
				_check(
				int(normal.data.state.tasks[0].work_remaining)
				- int(a39.data.state.tasks[0].work_remaining) == 2,
				"A39 does not boost second work card",
				failures
				)
	var early := _begin(engine, ["A39"], _copies("K01", 10))
	if early.ok:
		early.data.state.ddl = 4
		early = _play(engine, early, "K01")
		_check(early.ok and _trigger_count(early, "A39") == 0, "A39 waits until DDL 3", failures)
	for relic_order in [["A39", "A01"], ["A01", "A39"]]:
		var same_window := _begin(engine, relic_order, _copies("K01", 10))
		if not same_window.ok:
			_check(false, "A39 and A01 start in both slot orders", failures)
			continue
		same_window.data.state.ddl = 3
		same_window = _play(engine, same_window, "K01")
		if not same_window.ok:
			_check(false, "A39 and A01 resolve in both slot orders", failures)
			continue
		var triggered: Array[String] = []
		for event: RuleEvent in same_window.data.events:
			if event.type == &"relic_triggered" and str(event.data.get("relic_id", "")) in ["A39", "A01"]:
				triggered.append(str(event.data.relic_id))
		_check(triggered == relic_order, "A39 and A01 follow relic slot order", failures)
	var a40_control := _begin(engine, [], _copies("K44", 10))
	var a40 := _begin(engine, ["A40"], _copies("K44", 10))
	if a40_control.ok and a40.ok:
		_check(_trigger_count(a40, "A40") == 0, "A40 needs an ally action", failures)
		a40_control = _play(engine, a40_control, "K44")
		a40 = _play(engine, a40, "K44")
		if a40_control.ok and a40.ok:
			_check(_trigger_count(a40, "A40") == 0, "A40 does not fire on summoning", failures)
			_check(
				a40_control.data.state.units.size() == 1 and a40.data.state.units.size() == 1,
				"A40 summoned one ally", failures
			)
			if a40_control.data.state.units.size() != 1 or a40.data.state.units.size() != 1:
				return
			a40_control.data.state.units[0].vitality = 1
			a40.data.state.units[0].vitality = 1
			a40_control = _end_turn(engine, a40_control)
			a40 = _end_turn(engine, a40)
			if a40_control.ok and a40.ok:
				_check(
					_trigger_count(a40, "A40", "unit_action_completed") == 1,
					"A40 rewards a completed ally action",
					failures
				)
				_check(
					int(a40.data.state.player.vitality)
					- int(a40_control.data.state.player.vitality) == 2,
					"A40 relax absorbs two pressure before next preparation",
					failures
				)
				var departed := false
				for event: RuleEvent in a40.data.events:
					if event.type == &"unit_departed" and str(event.data.get("reason", "")) == "exhausted":
						departed = true
				_check(a40.data.state.units.is_empty() and departed, "A40 fires after ally exhaustion", failures)
	var a40_victory := _begin(engine, ["A40"], _copies("K44", 10))
	if a40_victory.ok:
		a40_victory = _play(engine, a40_victory, "K44")
		if a40_victory.ok:
			a40_victory.data.state.tasks[0].work_remaining = 1
			a40_victory = _end_turn(engine, a40_victory)
			var trigger_index := -1
			var finish_index := -1
			if a40_victory.ok:
				for event_index in a40_victory.data.events.size():
					var event: RuleEvent = a40_victory.data.events[event_index]
					if event.type == &"relic_triggered" and str(event.data.get("relic_id", "")) == "A40":
						trigger_index = event_index
					elif event.type == &"battle_finished":
						finish_index = event_index
			_check(
				a40_victory.ok and a40_victory.data.state.phase == "finished"
				and _trigger_count(a40_victory, "A40") == 1
				and trigger_index >= 0 and trigger_index < finish_index,
				"A40 resolves after the last ally action and before battle victory", failures
			)
	var optional_victory := _begin(engine, ["A40"], _copies("K44", 10))
	if optional_victory.ok:
		optional_victory = _play(engine, optional_victory, "K44")
		if optional_victory.ok:
			optional_victory.data.state.tasks[0].work_remaining = 1
			var setup_events: Array[RuleEvent] = []
			var summoned := engine._summon_tasks(
				optional_victory.data.state, "", {"task": "Q0A_3_1", "count": 1}, setup_events
			)
			_check(summoned.ok, "A40 optional-task victory setup", failures)
			if summoned.ok:
				optional_victory = _end_turn(engine, optional_victory)
				var optional_trigger_index := -1
				var optional_finish_index := -1
				if optional_victory.ok:
					for event_index in optional_victory.data.events.size():
						var event: RuleEvent = optional_victory.data.events[event_index]
						if event.type == &"relic_triggered" and str(event.data.get("relic_id", "")) == "A40":
							optional_trigger_index = event_index
						elif event.type == &"battle_finished":
							optional_finish_index = event_index
				_check(
					optional_victory.ok and optional_victory.data.state.phase == "finished"
					and optional_victory.data.state.tasks.size() == 1
					and str(optional_victory.data.state.tasks[0].definition_id) == "Q0A_3_1"
					and _trigger_count(optional_victory, "A40") == 1
					and optional_trigger_index >= 0 and optional_trigger_index < optional_finish_index,
					"A40 resolves before victory with an optional task remaining", failures
				)
	for case in [
		{"id": "A45", "focus": 0, "relax": 3},
		{"id": "A48", "focus": 2, "relax": 0},
	]:
		var baseline := _begin(engine, [], _copies("K01", 10), "B01")
		var with_relic := _begin(engine, [case.id], _copies("K01", 10), "B01")
		if not baseline.ok or not with_relic.ok:
			_check(false, "%s enters the boss fight" % case.id, failures)
			continue
		baseline.data.state.tasks[0].work_remaining = 1
		with_relic.data.state.tasks[0].work_remaining = 1
		baseline = _play(engine, baseline, "K01")
		with_relic = _play(engine, with_relic, "K01")
		_check(baseline.ok and with_relic.ok, "%s stage transition resolves" % case.id, failures)
		if not baseline.ok or not with_relic.ok:
			continue
		_check(
			str(with_relic.data.state.tasks[0].phase_key) == "integrals",
			"%s enters the new boss stage before reward" % case.id,
			failures
		)
		_check(
			_trigger_count(with_relic, case.id, "stage_entered") == 1,
			"%s rewards the first stage transition" % case.id,
			failures
		)
		_check(
			int(with_relic.data.state.player.focus) - int(baseline.data.state.player.focus) == int(case.focus),
			"%s stage focus is correct" % case.id,
			failures
		)
		_check(
			int(with_relic.data.state.player.relax) - int(baseline.data.state.player.relax) == int(case.relax),
			"%s stage relax is correct" % case.id,
			failures
		)
		_check(
			with_relic.data.state.zones.hand.size() - baseline.data.state.zones.hand.size() == 2,
			"%s draws two cards on transition" % case.id,
			failures
		)
		var last := _begin(engine, [case.id], _copies("K01", 10))
		if last.ok:
			last.data.state.tasks[0].work_remaining = 1
			last = _play(engine, last, "K01")
			_check(
				last.ok and last.data.state.phase == "finished"
				and _trigger_count(last, case.id) == 0,
				"%s ignores direct victory" % case.id, failures
			)
		var ally_stage := _begin(engine, [case.id], _copies("K44", 10), "E03")
		if ally_stage.ok:
			ally_stage = _play(engine, ally_stage, "K44")
			if ally_stage.ok:
				ally_stage.data.state.tasks[0].work_remaining = 1
				ally_stage.data.state.tasks[0].shield = 0
				ally_stage = _end_turn(engine, ally_stage)
				var advance_index := -1
				var stage_trigger_index := -1
				if ally_stage.ok:
					for event_index in ally_stage.data.events.size():
						var event: RuleEvent = ally_stage.data.events[event_index]
						if event.type == &"task_advanced":
							advance_index = event_index
						elif event.type == &"relic_triggered" and str(event.data.get("relic_id", "")) == case.id:
							stage_trigger_index = event_index
				_check(
					ally_stage.ok and str(ally_stage.data.state.tasks[0].phase_key) == "integrate"
					and _trigger_count(ally_stage, case.id, "stage_entered") == 1
					and advance_index >= 0 and advance_index < stage_trigger_index,
					"%s rewards ally-driven stage transition" % case.id, failures
				)
		var ally_victory := _begin(engine, [case.id], _copies("K44", 10))
		if ally_victory.ok:
			ally_victory = _play(engine, ally_victory, "K44")
			if ally_victory.ok:
				ally_victory.data.state.tasks[0].work_remaining = 1
				ally_victory = _end_turn(engine, ally_victory)
				_check(
					ally_victory.ok and ally_victory.data.state.phase == "finished"
					and _trigger_count(ally_victory, case.id) == 0,
					"%s ignores ally-driven direct victory" % case.id, failures
				)


func _check_ability_relics(failures: Array[String]) -> void:
	var catalog := AbilityCatalog.new()
	_check(catalog.load("campus_mvp").ok, "isolated ability catalog loads", failures)
	if catalog.get_info() == null:
		return
	var engine := BattleEngine.new(catalog)
	var control := _begin(engine, [], _copies("K13", 10))
	var a27 := _begin(engine, ["A27"], _copies("K13", 10))
	if control.ok and a27.ok:
		control = _play(engine, control, "K13")
		a27 = _play(engine, a27, "K13")
		_check(control.ok and a27.ok, "A27 resolves isolated ability", failures)
		if control.ok and a27.ok:
			_check(
				a27.data.state.zones.hand.size() - control.data.state.zones.hand.size() == 1,
				"A27 draws after first ability",
				failures
			)
			_check(_trigger_count(a27, "A27") == 1, "A27 triggers on ability", failures)
	var mixed := ["K01", "K01", "K02", "K02", "K13", "K13", "K43", "K43", "K51", "K51"]
	var baseline := _begin(engine, [], mixed)
	var a46 := _begin(engine, ["A46"], mixed)
	_check(baseline.ok and a46.ok, "A46 starts with all five card types", failures)
	if not baseline.ok or not a46.ok:
		return
	_promote_hand(baseline.data.state)
	_promote_hand(a46.data.state)
	baseline.data.state.player.focus = 10
	a46.data.state.player.focus = 10
	for definition_id in ["K01", "K02", "K13", "K43", "K51"]:
		baseline = _play(engine, baseline, definition_id)
		a46 = _play(engine, a46, definition_id)
		_check(baseline.ok and a46.ok, "A46 resolves type of %s" % definition_id, failures)
		if not baseline.ok or not a46.ok:
			return
		_check(
			_trigger_count(a46, "A46", "card_resolved") == 1,
			"A46 rewards type of %s once" % definition_id,
			failures
		)
	_check(
		int(a46.data.state.player.relax) - int(baseline.data.state.player.relax) == 10,
		"A46 grants 2 relax for each of five types",
		failures
	)
	a46 = _play(engine, a46, "K13")
	_check(a46.ok and _trigger_count(a46, "A46") == 0, "A46 does not repeat an ability type", failures)


func _begin(
	engine: BattleEngine, relics: Array, card_ids: Array, encounter_id: String = "N01"
) -> GameResult:
	var cards: Array[Dictionary] = []
	for index in card_ids.size():
		cards.append(
			{
				"card_id": "origin_%02d" % index,
				"definition_id": card_ids[index],
				"upgrade_level": 0,
			}
		)
	return engine.begin(
		{
			"battle_id": "relic_expansion_%s" % encounter_id,
			"node_id": "relic_expansion_node",
			"encounter_id": encounter_id,
			"character_id": "P01",
			"difficulty": "normal",
			"vitality": 180,
			"max_vitality": 200,
			"cards": cards,
			"relics": relics,
			"rng_state": RandomSource.new("relic-expansion-seed").export_state().to_dictionary(),
		}
	)


func _copies(definition_id: String, count: int) -> Array[String]:
	var cards: Array[String] = []
	for _index in count:
		cards.append(definition_id)
	return cards


func _promote_hand(state: BattleState) -> void:
	state.zones.hand = state.card_by_id.keys()
	state.zones.draw.clear()
	state.zones.discard.clear()


func _find_card(state: BattleState, definition_id: String) -> String:
	for card_id in state.zones.hand:
		if str(state.card_by_id[card_id].definition_id) == definition_id:
			return str(card_id)
	return ""


func _play(engine: BattleEngine, step: GameResult, definition_id: String) -> GameResult:
	if not step.ok:
		return step
	return _play_id(engine, step, _find_card(step.data.state, definition_id))


func _play_id(engine: BattleEngine, step: GameResult, card_id: String) -> GameResult:
	if card_id.is_empty():
		return GameResult.failure(ApiError.new(GameConstants.ERROR_INVALID_TARGET, "test.card.not_in_hand"))
	var state: BattleState = step.data.state
	var face := engine.resolve_face(state, card_id)
	if not face.ok:
		return face
	var target_ids: Array[String] = []
	if str(face.data.get("target", "")) == "task" and not state.tasks.is_empty():
		target_ids.append(str(state.tasks[0].task_id))
	return engine.apply(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": card_id, "target_ids": target_ids}
		),
		step.data.rng_state
	)


func _end_turn(engine: BattleEngine, step: GameResult) -> GameResult:
	if not step.ok:
		return step
	return engine.apply(
		step.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		step.data.rng_state
	)


func _trigger_count(step: GameResult, relic_id: String, at: String = "") -> int:
	if not step.ok:
		return 0
	var count := 0
	for event: RuleEvent in step.data.events:
		if (
			event.type == &"relic_triggered"
			and str(event.data.get("relic_id", "")) == relic_id
			and (at.is_empty() or str(event.data.get("at", "")) == at)
		):
			count += 1
	return count


func _status_gain_count(step: GameResult, status_id: String) -> int:
	if not step.ok:
		return 0
	var count := 0
	for event: RuleEvent in step.data.events:
		if (
			event.type == &"status_gained"
			and str(event.data.get("status_definition_id", "")) == status_id
			and int(event.data.get("amount", 0)) > 0
		):
			count += 1
	return count


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("relic expansion: " + label)
