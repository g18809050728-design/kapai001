class_name RunState
extends RefCounted
##
## 当前局的权威状态（《数据库与实体关系设计》§5 局内实体）。
##
## 本版范围：RunState 自身字段 + RunCard（永久牌）+ OwnedRelic（饰品）+ NodeState（地图节点）
## + RewardOffer / ShopState / EventState / TermSettlement / RunSummary（挂在节点或局上）。
## 实例 ID 由本类分配；战斗节点由 RunService 开战、由 settle_battle 写回精力。
##
## 归属（《初步架构设计》§4）：RunState 由 RunService 写。战斗中 vitality 只是入场值，
## 权威精力在 BattleState，战斗结束后一次性写回。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Ids := preload("res://src/common/ids.gd")
const RunCopy := preload("res://src/run/run_copy.gd")
const RunMap := preload("res://src/run/run_map.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")


## 永久牌实例。card_id 是运行实例 ID，definition_id 是策划编号（如 K01）。
## 永久卡进入战斗时生成新的 battle_card_id，不把本 ID 带进战斗牌区。
class RunCard:
	var card_id: String = ""
	var definition_id: String = ""
	var upgrade_level: int = 0
	var acquired_from: String = ""


## 已拥有饰品。同局 definition_id 唯一、slot 唯一且 0 ≤ slot < 饰品槽数。
class OwnedRelic:
	var relic_id: String = ""
	var definition_id: String = ""
	var slot: int = -1
	var acquired_order: int = 0


var run_id: String = ""
var character_id: String = ""
var ruleset_id: String = ""
var difficulty: String = ""
var manifest_id: String = ""
var term: int = 1
var money: int = 0
var vitality: int = 0
var max_vitality: int = 0
## 运行实例 ID 的单调序号；随快照保存，读档后继续递增，不复用已删实例的 ID。
var next_instance_seq: int = 1

var cards: Array = []                 # Array[RunCard] 永久牌组
var relics: Array = []                # Array[OwnedRelic]
var career_progress: Dictionary = {}  # track -> 0..3，四轨不独立发 ID
## 已结算的战斗 ID；结算幂等用（《接口文档》§5 settle_battle）
var settled_battle_ids: Dictionary = {}

# ── 地图与节点（RunService 写）──────────────────────────────
## 整局地图骨架（Array[RunNodeState]，RunMap.build 生成）。
var nodes: Array = []
## 已进入但尚未完成的节点；空串表示在学期入口（可进第 1 层）。
var current_node_id: String = ""
## 已完成节点的 node_id 顺序（整局累计，便于界面显示已走路线）。
var node_path: Array = []
## 当前待处理奖励（RewardOffer 或 null）；处理完才允许离开节点。
var pending_reward = null
## 当前学期结算（TermSettlement 或 null）；全部步骤完成后推进到下一学期。
var settlement = null
## 局结束时的摘要（RunSummary 或 null）；生成后只允许 choose_ending 补 ending_id。
var run_summary = null
## 待合并进 Profile 的同一份摘要（《数据库与实体关系设计》§7/§8 三步提交）；
## 恒等于 run_summary 或 null，Profile 合并成功后由存档层清空。
var pending_profile_summary = null
## 已出现（含离开）的事件定义 ID；同局同 ID 至多出现一次。
var seen_event_ids: Dictionary = {}
## 全局删牌次数：商店删牌价格 = first_removal_price + increment × 本值；事件删卡不计数。
var removals_used: int = 0
## 第 5 学期开始前选择的履历方向（research / competition / internship）。
var career_direction: String = ""
## 已进入、尚未 settle_battle 的战斗（一个战斗节点一场；空串表示无进行中战斗）。
var active_battle_id: String = ""
var active_encounter_id: String = ""
## 局结局："" / won / lost / abandoned。
var outcome: String = ""
# ── 实例 ID ───────────────────────────────────────────────

## 分配一个运行实例 ID。不消费任何随机流（《数据库与实体关系设计》§3）。
func allocate_instance_id() -> String:
	var allocated := Ids.instance_id(run_id, next_instance_seq)
	next_instance_seq += 1
	return allocated


# ── 永久牌组 ──────────────────────────────────────────────

func add_card(definition_id: String, upgrade_level: int = 0, acquired_from: String = "") -> RunCard:
	var card := RunCard.new()
	card.card_id = allocate_instance_id()
	card.definition_id = definition_id
	card.upgrade_level = upgrade_level
	card.acquired_from = acquired_from
	cards.append(card)
	return card


func find_card(card_id: String) -> RunCard:
	for card in cards:
		if card.card_id == card_id:
			return card
	return null


func has_card(card_id: String) -> bool:
	return find_card(card_id) != null


## 删除永久牌。ID 不复用（allocate_instance_id 只增不减）。
func remove_card(card_id: String) -> bool:
	for index in range(cards.size()):
		if cards[index].card_id == card_id:
			cards.remove_at(index)
			return true
	return false


func cards_of_definition(definition_id: String) -> Array:
	var matched := []
	for card in cards:
		if card.definition_id == definition_id:
			matched.append(card)
	return matched


# ── 饰品 ──────────────────────────────────────────────────

## 装备饰品：占用最小编号空槽。槽位已满返回 null，调用方按规则回退（例如折算金钱）。
func equip_relic(definition_id: String, relic_slots: int, acquired_order: int = 0) -> OwnedRelic:
	var used := {}
	for relic in relics:
		used[relic.slot] = true
	var slot := -1
	for candidate in range(relic_slots):
		if not used.has(candidate):
			slot = candidate
			break
	if slot < 0:
		return null
	var relic := OwnedRelic.new()
	relic.relic_id = allocate_instance_id()
	relic.definition_id = definition_id
	relic.slot = slot
	relic.acquired_order = acquired_order
	relics.append(relic)
	return relic


## 满槽替换：新饰品占用被替换者的槽位（《统一设计文档》§10.1「满饰品槽必须先选替换或放弃」）。
func replace_relic(relic_id: String, definition_id: String, acquired_order: int = 0) -> OwnedRelic:
	var old := find_relic(relic_id)
	if old == null:
		return null
	var slot := old.slot
	remove_relic(relic_id)
	var relic := OwnedRelic.new()
	relic.relic_id = allocate_instance_id()
	relic.definition_id = definition_id
	relic.slot = slot
	relic.acquired_order = acquired_order
	relics.append(relic)
	return relic


func remove_relic(relic_id: String) -> bool:
	for index in range(relics.size()):
		if relics[index].relic_id == relic_id:
			relics.remove_at(index)
			return true
	return false


func find_relic(relic_id: String) -> OwnedRelic:
	for relic in relics:
		if relic.relic_id == relic_id:
			return relic
	return null


func has_relic_definition(definition_id: String) -> bool:
	for relic in relics:
		if relic.definition_id == definition_id:
			return true
	return false


# ── 履历 ──────────────────────────────────────────────────

func career_of(track: String) -> int:
	return int(career_progress.get(track, 0))


## 履历加值，封顶 cap（《统一设计文档》§10.3「总值封顶，不能重复刷取」）。返回实际加值。
func add_career(track: String, amount: int, cap: int) -> int:
	if amount <= 0:
		return 0
	var before := career_of(track)
	var after := mini(cap, before + amount)
	career_progress[track] = after
	return after - before


# ── 地图与节点 ────────────────────────────────────────────

func find_node(node_id: String) -> RunNodeState:
	return RunMap.find(nodes, node_id)


func nodes_of_term(term_value: int) -> Array:
	return RunMap.of_term(nodes, term_value)


func current_node() -> RunNodeState:
	if current_node_id.is_empty():
		return null
	return find_node(current_node_id)


## 当前可进入的节点（《接口文档》§3.2：enter_node 只能进入地图当前可达节点）。
## 规则：局未结束、没有待完成学期结算、当前节点已完成时，可达 = 它的 next_ids；
## 还没进入任何节点时可达 = 本学期的第 1 层。
func reachable_node_ids() -> Array:
	if not outcome.is_empty():
		return []
	if settlement != null and not settlement.is_complete():
		return []
	var node := current_node()
	if node == null:
		return RunMap.first_layer_ids(nodes, term)
	if node.is_completed():
		return node.next_ids.duplicate()
	return []


func is_run_over() -> bool:
	return not outcome.is_empty()


# ── 工作副本 ──────────────────────────────────────────────

## 深拷贝可变状态（《数据库与实体关系设计》§3；失败操作保留原状态靠这个保证）。
## 内容定义只读共享，不在这里复制。
func copy_for_write() -> RunState:
	var copied: RunState = load("res://src/run/run_state.gd").new()
	copied.run_id = run_id
	copied.character_id = character_id
	copied.ruleset_id = ruleset_id
	copied.difficulty = difficulty
	copied.manifest_id = manifest_id
	copied.term = term
	copied.money = money
	copied.vitality = vitality
	copied.max_vitality = max_vitality
	copied.next_instance_seq = next_instance_seq
	for card in cards:
		var card_copy := RunCard.new()
		card_copy.card_id = card.card_id
		card_copy.definition_id = card.definition_id
		card_copy.upgrade_level = card.upgrade_level
		card_copy.acquired_from = card.acquired_from
		copied.cards.append(card_copy)
	for relic in relics:
		copied.relics.append(RunCopy.value(relic))
	copied.career_progress = career_progress.duplicate()
	copied.settled_battle_ids = settled_battle_ids.duplicate()
	copied.nodes = RunCopy.array(nodes)
	copied.current_node_id = current_node_id
	copied.node_path = node_path.duplicate()
	copied.pending_reward = RunCopy.value(pending_reward)
	copied.settlement = RunCopy.value(settlement)
	copied.run_summary = RunCopy.value(run_summary)
	# 不变量：pending_profile_summary 与 run_summary 是同一对象（或都为 null），保持这个关系。
	copied.pending_profile_summary = copied.run_summary if pending_profile_summary != null else null
	copied.seen_event_ids = seen_event_ids.duplicate()
	copied.removals_used = removals_used
	copied.career_direction = career_direction
	copied.active_battle_id = active_battle_id
	copied.active_encounter_id = active_encounter_id
	copied.outcome = outcome
	return copied
# ── 校验 ──────────────────────────────────────────────────

## 校验本聚合（《数据库与实体关系设计》§9 必查项中属于 RunState 的部分）。
## relic_slots 由 ContentDB 传入——本类不维护第二份数值表。
func validate(relic_slots: int) -> PackedStringArray:
	var problems := PackedStringArray()
	if run_id.is_empty():
		problems.append("run_id 为空")
	if character_id.is_empty():
		problems.append("character_id 为空")
	if difficulty.is_empty():
		problems.append("difficulty 为空")
	if ruleset_id.is_empty():
		problems.append("ruleset_id 为空")
	if term < 1:
		problems.append("term 必须从 1 开始：%d" % term)
	if money < 0:
		problems.append("金钱为负：%d" % money)
	if vitality < 0:
		problems.append("精力为负：%d" % vitality)
	if max_vitality <= 0:
		problems.append("最大精力必须为正：%d" % max_vitality)
	if vitality > max_vitality:
		problems.append("精力 %d 超过上限 %d" % [vitality, max_vitality])
	if next_instance_seq < 1:
		problems.append("next_instance_seq 必须从 1 开始：%d" % next_instance_seq)
	if removals_used < 0:
		problems.append("删牌次数为负：%d" % removals_used)
	if not outcome.is_empty() and not [GameConstants.OUTCOME_WON, GameConstants.OUTCOME_LOST, GameConstants.OUTCOME_ABANDONED].has(outcome):
		problems.append("非法局结局：%s" % outcome)

	var seen_ids := {}
	for card in cards:
		if card.card_id.is_empty():
			problems.append("永久牌缺少实例 ID：%s" % card.definition_id)
		elif seen_ids.has(card.card_id):
			problems.append("重复实例 ID：%s" % card.card_id)
		seen_ids[card.card_id] = true
		if card.definition_id.is_empty():
			problems.append("永久牌缺少定义 ID（实例 %s）" % card.card_id)
		if card.upgrade_level < 0:
			problems.append("升级等级为负：%s" % card.card_id)

	var used_slots := {}
	var used_definitions := {}
	for relic in relics:
		if relic.relic_id.is_empty():
			problems.append("饰品缺少实例 ID：%s" % relic.definition_id)
		elif seen_ids.has(relic.relic_id):
			problems.append("重复实例 ID：%s" % relic.relic_id)
		seen_ids[relic.relic_id] = true
		if relic.slot < 0 or relic.slot >= relic_slots:
			problems.append("饰品槽位越界：%s -> %d（槽数 %d）" % [relic.definition_id, relic.slot, relic_slots])
		if used_slots.has(relic.slot):
			problems.append("饰品槽位重复：%d" % relic.slot)
		used_slots[relic.slot] = true
		if used_definitions.has(relic.definition_id):
			problems.append("同名饰品重复：%s" % relic.definition_id)
		used_definitions[relic.definition_id] = true

	# 地图：节点 ID 唯一、kind/status 合法、学期/层合法、边只能前进
	var seen_nodes := {}
	for raw_node in nodes:
		var node: RunNodeState = raw_node
		if node.node_id.is_empty():
			problems.append("节点缺少 ID")
		elif seen_nodes.has(node.node_id):
			problems.append("重复节点 ID：%s" % node.node_id)
		seen_nodes[node.node_id] = true
		if not RunNodeState.KIND_IDS.has(node.kind):
			problems.append("非法节点类型：%s -> %s" % [node.node_id, node.kind])
		if not RunNodeState.STATUS_IDS.has(node.status):
			problems.append("非法节点状态：%s -> %s" % [node.node_id, node.status])
		if node.term < 1 or node.layer < 1:
			problems.append("节点学期/层非法：%s" % node.node_id)
	for raw_node in nodes:
		var node: RunNodeState = raw_node
		for raw_next in node.next_ids:
			var next: RunNodeState = find_node(String(raw_next))
			if next == null:
				problems.append("节点边指向不存在的节点：%s -> %s" % [node.node_id, raw_next])
			elif next.term != node.term or next.layer <= node.layer:
				problems.append("节点边没有向前：%s -> %s" % [node.node_id, raw_next])
	if not current_node_id.is_empty() and find_node(current_node_id) == null:
		problems.append("current_node_id 指向不存在的节点：%s" % current_node_id)
	if pending_reward != null and find_node(pending_reward.source_node_id) == null:
		problems.append("奖励来源节点不存在：%s" % pending_reward.source_node_id)
	return problems