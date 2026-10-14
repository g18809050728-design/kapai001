extends RefCounted
##
## 核心状态层验收：Ids / RunState / BattleState / SessionState。
## 依据《数据库与实体关系设计》§3 标识、§5 局内实体、§6 战斗实体、§9 校验。
##

const Ids := preload("res://src/common/ids.gd")
const RunState := preload("res://src/run/run_state.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const SessionState := preload("res://src/app/session_state.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const GameConstants := preload("res://src/common/game_constants.gd")


func run(h) -> void:
	h.begin("Ids · 运行实例 ID")
	_ids(h)
	h.begin("RunState · 永久牌与饰品")
	_run_state(h)
	h.begin("BattleState · 牌区唯一权威")
	_battle_state(h)
	h.begin("SessionState · revision 与随机快照")
	_session_state(h)


# ── Ids ───────────────────────────────────────────────────

func _ids(h) -> void:
	var same := Ids.run_id_from_seed(20261013)
	h.eq("同种子得到同 run_id", Ids.run_id_from_seed(20261013), same)
	h.eq("run_id 长度固定（R + 16 位十六进制）", same.length(), 17)
	h.check("不同种子得到不同 run_id", Ids.run_id_from_seed(20261014) != same)
	h.check("负数种子也生成合法 run_id", Ids.run_id_from_seed(-9223372036854775807).length() == 17)
	h.check("实例 ID 带 run_id 前缀", Ids.instance_id(same, 7).begins_with(same))
	h.check("不同序号得到不同实例 ID", Ids.instance_id(same, 7) != Ids.instance_id(same, 8))


# ── RunState ──────────────────────────────────────────────

func _run_state(h) -> void:
	var run := _new_run()

	# §10 验收案例 1：同一张牌（K01）的四个永久实例拥有不同 ID
	var first := run.add_card("K01", 0, "starter")
	var second := run.add_card("K01", 0, "starter")
	var third := run.add_card("K01", 0, "starter")
	var fourth := run.add_card("K01", 0, "starter")
	var ids := [first.card_id, second.card_id, third.card_id, fourth.card_id]
	h.eq("同定义四张牌 ID 互不相同", ids.size(), _unique(ids).size())
	h.eq("按定义能查回四张", run.cards_of_definition("K01").size(), 4)

	# 升级一张不影响另外三张
	first.upgrade_level = 1
	var untouched := 0
	for card in [second, third, fourth]:
		if card.upgrade_level == 0:
			untouched += 1
	h.eq("升级一张不影响其余三张", untouched, 3)

	# 实例 ID 单调递增且删除后不复用
	var seq_before := run.next_instance_seq
	var removed_id := first.card_id
	h.check("删除永久牌成功", run.remove_card(removed_id))
	var replacement := run.add_card("K02", 0, "reward")
	h.check("已删除的实例 ID 不复用", replacement.card_id != removed_id)
	h.eq("序号继续递增", run.next_instance_seq, seq_before + 1)
	h.check("删除后其它牌不受影响", run.has_card(second.card_id))

	# 饰品：槽位分配 0..5，满了返回 null
	var slots_ok := true
	var slot_set := {}
	for index in range(6):
		var relic := run.equip_relic("A%02d" % (index + 1), 6, index)
		if relic == null or relic.slot != index:
			slots_ok = false
		slot_set[relic.slot] = true
	h.check("六个饰品占用槽位 0~5", slots_ok and slot_set.size() == 6)
	h.check("槽位满时返回 null", run.equip_relic("A99", 6) == null)
	h.eq("合法 RunState 无校验问题", run.validate(6).size(), 0)

	# 反例：同名饰品重复、金钱为负、精力超上限、槽位越界
	var duplicated := _new_run()
	duplicated.equip_relic("A01", 6)
	duplicated.equip_relic("A01", 6)
	h.check("同名饰品重复被抓出", _mentions(duplicated.validate(6), "同名饰品重复"))

	var broke := _new_run()
	broke.money = -1
	h.check("负钱被抓出", _mentions(broke.validate(6), "金钱为负"))

	var overfilled := _new_run()
	overfilled.vitality = 99
	h.check("精力超上限被抓出", _mentions(overfilled.validate(6), "超过上限"))

	var out_of_slot := _new_run()
	var stray := out_of_slot.equip_relic("A01", 6)
	stray.slot = 9
	h.check("饰品槽位越界被抓出", _mentions(out_of_slot.validate(6), "槽位越界"))
	h.check("空 run_id 被抓出", _mentions(RunState.new().validate(6), "run_id 为空"))


# ── BattleState ───────────────────────────────────────────

func _battle_state(h) -> void:
	var battle := _valid_battle()
	h.eq("合法 BattleState 无校验问题", battle.validate(3).size(), 0)

	var card_id := "R1234#3"
	h.eq("初始在抽牌堆", battle.zone_of(card_id), GameConstants.ZONE_DRAW)
	h.check("移动到手牌成功", battle.move_card(card_id, GameConstants.ZONE_HAND))
	h.eq("移动后在且只在手牌", battle.zone_of(card_id), GameConstants.ZONE_HAND)
	h.eq("原区不再持有该牌", battle.card_ids_in(GameConstants.ZONE_DRAW).has(card_id), false)
	h.eq("牌区总数等于登记卡数", battle.zones.total(), battle.card_by_id.size())
	h.eq("移动后仍然合法", battle.validate(3).size(), 0)
	h.check("未知牌区被拒绝", not battle.move_card(card_id, "limbo"))
	h.check("未知卡被拒绝", not battle.move_card("no_such_card", GameConstants.ZONE_HAND))
	h.check("重复 card_id 不被接受", battle.add_card(card_id, "K01", GameConstants.ZONE_DRAW) == null)

	# 反例：牌不在任何牌区
	var leaked := _valid_battle()
	leaked.zones.remove("R1234#3")
	h.check("牌不在任何牌区被抓出", _mentions(leaked.validate(3), "不在任何牌区"))

	# 反例：牌区引用了不存在的卡
	var dangling := _valid_battle()
	dangling.zones.list_for(GameConstants.ZONE_HAND).append("R1234#999")
	h.check("牌区引用不存在的卡被抓出", _mentions(dangling.validate(3), "不存在的卡"))

	# 反例：单位超槽位
	var crowded := _valid_battle()
	for index in range(4):
		var unit = BattleState.create_unit()
		unit.unit_id = "R1234#u%d" % index
		unit.definition_id = "F0%d" % (index + 1)
		unit.vitality = 3
		unit.max_vitality = 3
		crowded.units.append(unit)
	h.check("单位超槽位被抓出", _mentions(crowded.validate(3), "超过槽位"))

	# 反例：状态持有者不属于本战
	var orphan := _valid_battle()
	var status = BattleState.create_status()
	status.status_id = "R1234#s1"
	status.definition_id = GameConstants.STATUS_INSPIRATION
	status.holder_id = "R1234#ghost"
	status.stacks = 1
	orphan.statuses[status.status_id] = status
	h.check("状态持有者不属于本战被抓出", _mentions(orphan.validate(3), "不属于本战"))

	# 反例：未知阶段、缺玩家、round 从 0 开始
	var bad_phase := _valid_battle()
	bad_phase.phase = "thinking"
	h.check("未知阶段被抓出", _mentions(bad_phase.validate(3), "未知阶段"))
	var no_player := _valid_battle()
	no_player.player = null
	h.check("缺玩家被抓出", _mentions(no_player.validate(3), "缺少 PlayerBattleState"))
	var bad_round := _valid_battle()
	bad_round.round_index = 0
	h.check("round 必须从 1 开始", _mentions(bad_round.validate(3), "必须从 1 开始"))

	# 触发计数器：组合键必须自洽
	var counted := _valid_battle()
	var key := BattleState.counter_key("battle", "R1234#3", "K01_play")
	var counter = BattleState.create_counter()
	counter.scope = "battle"
	counter.owner_key = "R1234#3"
	counter.trigger_key = "K01_play"
	counted.counters[key] = counter
	h.eq("键自洽的计数器无问题", counted.validate(3).size(), 0)
	counter.trigger_key = "K02_play"
	h.check("键不一致被抓出", _mentions(counted.validate(3), "键不一致"))


# ── SessionState ──────────────────────────────────────────

func _session_state(h) -> void:
	var db := ContentDB.new()
	db.load(GameConstants.MANIFEST_MVP)
	var relic_slots: int = db.run_int("relic_slots", 6)
	var unit_slots: int = db.battle_int("unit_slots", 3)

	var session := _valid_session()
	h.eq("合法 SessionState 无校验问题", session.validate().size(), 0)
	h.check("无战斗时 has_battle 为 false", not session.has_battle())
	h.eq("RunState 层也合法", session.run.validate(relic_slots).size(), 0)
	h.check("规则配置的槽位读到实数", unit_slots == 3 and relic_slots == 6)

	session.battle = _valid_battle()
	h.check("挂上战斗后 has_battle 为 true", session.has_battle())
	h.eq("带战斗的会话仍然合法", session.validate().size(), 0)

	var mismatched := _valid_session()
	mismatched.run.run_id = "Rother"
	h.check("run_id 不一致被抓出", _mentions(mismatched.validate(), "不一致"))

	var no_streams := _valid_session()
	var streams: Dictionary = no_streams.random_snapshot["streams"]
	streams.erase(GameConstants.RNG_BATTLE)
	h.check("随机流缺失被抓出", _mentions(no_streams.validate(), "缺少流"))

	var corrupt := _valid_session()
	corrupt.random_snapshot["algorithm_version"] = 999
	h.check("随机快照不可恢复被抓出", _mentions(corrupt.validate(), "无法恢复"))

	var empty := SessionState.new()
	h.check("空会话被拒", not empty.validate().is_empty())


# ── 工具 ──────────────────────────────────────────────────

func _new_run() -> RunState:
	var run := RunState.new()
	run.run_id = Ids.run_id_from_seed(1234)
	run.character_id = "P01"
	run.ruleset_id = "campus_v1"
	run.difficulty = GameConstants.DIFFICULTY_NORMAL
	run.manifest_id = GameConstants.MANIFEST_MVP
	run.max_vitality = 72
	run.vitality = 72
	run.money = 60
	return run


func _valid_battle() -> BattleState:
	var battle := BattleState.new()
	battle.battle_id = "R1234#1"
	battle.node_id = "N1"
	battle.encounter_id = "N01"
	battle.phase = GameConstants.PHASE_PLAYER_ACTION
	battle.round_index = 1
	battle.ddl = 10
	var player = BattleState.create_player()
	player.entity_id = "R1234#2"
	player.vitality = 72
	player.max_vitality = 72
	battle.player = player
	battle.add_card("R1234#3", "K01", GameConstants.ZONE_DRAW, "R1234#9")
	return battle


func _valid_session() -> SessionState:
	var run := _new_run()
	var session := SessionState.new()
	session.run_id = run.run_id
	session.run = run
	session.revision = 0
	var source := RandomSourceScript.new(1234)
	session.random_snapshot = source.export_state()
	return session


func _unique(items: Array) -> Array:
	var seen := {}
	for item in items:
		seen[item] = true
	return seen.keys()


func _mentions(problems: PackedStringArray, needle: String) -> bool:
	for problem in problems:
		if problem.find(needle) >= 0:
			return true
	return false
