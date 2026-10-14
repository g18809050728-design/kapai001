class_name BattleState
extends RefCounted
##
## 战斗状态聚合（《数据库与实体关系设计》§6 战斗实体）。
##
## 纯数据 + 结构不变量；所有规则变更由 BattleEngine 负责（引擎在后续阶段实现）。
##
## 关键约定：
##   · 牌区的唯一权威是 CardZones。BattleCard **不**另存 zone 字段，
##     避免出现「卡记录在手牌、数组在弃牌」的双写矛盾。
##   · 运行实例 ID 由 RunState 分配（run_id + 单调序号），战斗内不自造 ID。
##   · 阶段转换会创建新的 task_id，旧目标不会自动指向新阶段。
##   · resolution 只是内存暂态；稳定存档里它必须为 null。
##

const GameConstants := preload("res://src/common/game_constants.gd")

const PHASE_IDS: Array[String] = [
	GameConstants.PHASE_INITIALIZING,
	GameConstants.PHASE_PLAYER_PREPARE,
	GameConstants.PHASE_DRAW,
	GameConstants.PHASE_PLAYER_ACTION,
	GameConstants.PHASE_ALLY_ACTION,
	GameConstants.PHASE_DISCARD,
	GameConstants.PHASE_ENEMY_PREPARE,
	GameConstants.PHASE_ENEMY_SKILL,
	GameConstants.PHASE_ENEMY_PRESSURE,
	GameConstants.PHASE_ROUND_END,
	GameConstants.PHASE_AWAITING_CHOICE,
	GameConstants.PHASE_FINISHED,
]


## 每战恰好一个。不复制钱包和永久牌组。
class PlayerBattleState:
	var entity_id: String = ""
	var vitality: int = 0
	var max_vitality: int = 0
	var relax: int = 0
	var focus: int = 0


## 战斗牌实例。origin_card_id 非空指向本局 RunCard；null 表示临时衍生牌。
class BattleCard:
	var card_id: String = ""
	var definition_id: String = ""
	var origin_card_id: Variant = null
	var upgrade_level: int = 0
	var modifiers: Dictionary = {}


## 五个有序 ID 数组；每张 BattleCard 在且只在一个数组里。
class CardZones:
	const GameConstants := preload("res://src/common/game_constants.gd")

	var draw: Array = []
	var hand: Array = []
	var discard: Array = []
	var exhaust: Array = []
	var resolving: Array = []

	func zone_ids() -> Array[String]:
		return [
			GameConstants.ZONE_DRAW,
			GameConstants.ZONE_HAND,
			GameConstants.ZONE_DISCARD,
			GameConstants.ZONE_EXHAUST,
			GameConstants.ZONE_RESOLVING,
		]

	func is_known_zone(zone: String) -> bool:
		return zone_ids().has(zone)

	## 返回该区的**数组本身**（引擎内部按引用增删）。未知区返回空数组。
	func list_for(zone: String) -> Array:
		if zone == GameConstants.ZONE_DRAW:
			return draw
		if zone == GameConstants.ZONE_HAND:
			return hand
		if zone == GameConstants.ZONE_DISCARD:
			return discard
		if zone == GameConstants.ZONE_EXHAUST:
			return exhaust
		if zone == GameConstants.ZONE_RESOLVING:
			return resolving
		return []

	func zone_of(card_id: String) -> String:
		for zone in zone_ids():
			if list_for(zone).has(card_id):
				return zone
		return ""

	## 从所在区移除并返回原区名；不在任何区返回空串。
	func remove(card_id: String) -> String:
		for zone in zone_ids():
			var list := list_for(zone)
			var index := list.find(card_id)
			if index >= 0:
				list.remove_at(index)
				return zone
		return ""

	func counts() -> Dictionary:
		var result := {}
		for zone in zone_ids():
			result[zone] = list_for(zone).size()
		return result

	func total() -> int:
		var sum := 0
		for zone in zone_ids():
			sum += list_for(zone).size()
		return sum


class UnitState:
	var unit_id: String = ""
	var definition_id: String = ""
	var vitality: int = 0
	var max_vitality: int = 0
	var relax: int = 0
	var cooperation: int = 0
	var entered_order: int = 0
	var last_acted_round: int = 0
	var actions_taken: int = 0
	var target_id: Variant = null


class TaskState:
	var task_id: String = ""
	var definition_id: String = ""
	var phase_key: String = ""
	var work_remaining: int = 0
	var work_max: int = 0
	var shield: int = 0
	var intent_cursor: int = 0
	## 当前公开意图（Dictionary；intents.json 的定义对象副本）。
	var intent_snapshot: Variant = null
	var entered_order: int = 0
	var eligible_round: int = 0


class StatusState:
	var status_id: String = ""
	var definition_id: String = ""
	var holder_id: String = ""
	## 来源记成值而不是强引用：已退场单位/旧首领仍能留下历史来源。
	var source: Dictionary = {}
	var stacks: int = 0
	var expiry: String = ""


## 战斗内场景（文档实体名 SceneState；Godot 原生已有 SceneState，故加 Battle 前缀避开）。
class BattleSceneState:
	var scene_id: String = ""
	var definition_id: String = ""
	var established_round: int = 0
	var pending_random_result: Variant = null


## 触发限次计数器：组合键唯一。回合计数到期重置，战斗计数保留。
class TriggerCounter:
	var scope: String = ""
	var owner_key: String = ""
	var trigger_key: String = ""
	var count: int = 0
	var round: Variant = null


## 效果内选择的结算游标。仅内存暂态，稳定存档中必须为 null。
class ResolutionState:
	var action: Dictionary = {}
	var effect_cursor: int = 0
	var queue: Array = []
	var locked_target_ids: Array = []
	var choice: Variant = null
	## 最近一次效果内选择实际生效的数量，按 kind 记（discard=实际弃置张数、
	## recall=实际入手张数、purify=实际移除层数）。「抽实际弃牌数+1」这类后置效果
	## 读它，不另起一套规则。仅内存暂态，稳定存档随 resolution 一起为 null。
	var choice_counts: Dictionary = {}


var battle_id: String = ""
var node_id: String = ""
var encounter_id: String = ""
var phase: String = GameConstants.PHASE_INITIALIZING
var round_index: int = 1
var ddl: int = 0

var player: PlayerBattleState = null
var card_by_id: Dictionary = {}    # card_id -> BattleCard
var zones: CardZones = CardZones.new()
var units: Array = []              # Array[UnitState]，最多 unit_slots 个存活单位
var tasks: Array = []              # Array[TaskState]
var statuses: Dictionary = {}      # status_id -> StatusState
var scene: BattleSceneState = null       # 每战 0 或 1
var counters: Dictionary = {}      # counter_key -> TriggerCounter
var resolution: ResolutionState = null

## 战斗作用域上下文（由 BattleInput 注入；《数据库与实体关系设计》§6 的补充运行字段）。
var character_id: String = ""
var difficulty: String = ""
var relics: Array = []              # 已装备饰品定义 ID
var exam_limits: Array = []         # independent_answer / fixed_exam_room
var outcome: Variant = null         # BattleOutcome；未结束时为 null
## 本次结束回合声明保留的手牌 ID（K19 等效果放宽保留上限）。弃牌阶段读它并跳过
## 这些牌，读完即清空；encode_battle 不写出，故不进入稳定快照。
var retained_card_ids: Array = []
var next_entity_seq: int = 1        # 战斗内自造实例 ID 的单调序号
var next_order_seq: int = 1         # 入场顺序的单调序号
## 子实体工厂。跨脚本**不能**用 BattleState.InnerClass.new()——Godot 不暴露这条路径，
## 一律走这些工厂（BattleEngine 同样只用工厂造实体）。
static func create_player(entity_id: String = "", vitality: int = 0, max_vitality: int = 0) -> PlayerBattleState:
	var player := PlayerBattleState.new()
	player.entity_id = entity_id
	player.vitality = vitality
	player.max_vitality = max_vitality
	return player


static func create_unit(unit_id: String = "", definition_id: String = "", vitality: int = 0, max_vitality: int = 0) -> UnitState:
	var unit := UnitState.new()
	unit.unit_id = unit_id
	unit.definition_id = definition_id
	unit.vitality = vitality
	unit.max_vitality = max_vitality
	return unit


static func create_task(task_id: String = "", definition_id: String = "", phase_key: String = "", work_max: int = 0) -> TaskState:
	var task := TaskState.new()
	task.task_id = task_id
	task.definition_id = definition_id
	task.phase_key = phase_key
	task.work_max = work_max
	task.work_remaining = work_max
	return task


static func create_status(status_id: String = "", definition_id: String = "", holder_id: String = "", stacks: int = 0) -> StatusState:
	var status := StatusState.new()
	status.status_id = status_id
	status.definition_id = definition_id
	status.holder_id = holder_id
	status.stacks = stacks
	return status


static func create_scene(scene_id: String = "", definition_id: String = "", established_round: int = 0) -> BattleSceneState:
	var built_scene := BattleSceneState.new()
	built_scene.scene_id = scene_id
	built_scene.definition_id = definition_id
	built_scene.established_round = established_round
	return built_scene


static func create_counter(scope: String = "", owner_key: String = "", trigger_key: String = "") -> TriggerCounter:
	var counter := TriggerCounter.new()
	counter.scope = scope
	counter.owner_key = owner_key
	counter.trigger_key = trigger_key
	return counter


static func create_resolution(action: Dictionary = {}) -> ResolutionState:
	var built_resolution := ResolutionState.new()
	built_resolution.action = action
	return built_resolution


# ── 牌 ────────────────────────────────────────────────────

## 登记一张战斗牌并放进指定牌区。card_id 由调用方从 RunState 分配。
func add_card(card_id: String, definition_id: String, zone: String, origin_card_id: Variant = null, upgrade_level: int = 0) -> BattleCard:
	if card_id.is_empty() or card_by_id.has(card_id) or not zones.is_known_zone(zone):
		return null
	var card := BattleCard.new()
	card.card_id = card_id
	card.definition_id = definition_id
	card.origin_card_id = origin_card_id
	card.upgrade_level = upgrade_level
	card_by_id[card_id] = card
	zones.list_for(zone).append(card_id)
	return card


func get_card(card_id: String) -> BattleCard:
	return card_by_id.get(card_id)


func zone_of(card_id: String) -> String:
	return zones.zone_of(card_id)


func cards_in(zone: String) -> Array:
	var result := []
	for card_id in zones.list_for(zone):
		result.append(card_by_id.get(card_id))
	return result


func card_ids_in(zone: String) -> Array:
	return zones.list_for(zone).duplicate()


## 把牌移到另一个区（先从原区移除）。未知区或牌不存在返回 false。
func move_card(card_id: String, zone: String) -> bool:
	if not card_by_id.has(card_id) or not zones.is_known_zone(zone):
		return false
	zones.remove(card_id)
	zones.list_for(zone).append(card_id)
	return true


# ── 实体查找 ──────────────────────────────────────────────

func find_unit(unit_id: String) -> UnitState:
	for unit in units:
		if unit.unit_id == unit_id:
			return unit
	return null


func find_task(task_id: String) -> TaskState:
	for task in tasks:
		if task.task_id == task_id:
			return task
	return null


func entity_ids() -> Array:
	var ids := []
	if player != null:
		ids.append(player.entity_id)
	for unit in units:
		ids.append(unit.unit_id)
	for task in tasks:
		ids.append(task.task_id)
	if scene != null:
		ids.append(scene.scene_id)
	return ids


static func counter_key(scope: String, owner_key: String, trigger_key: String) -> String:
	return "%s|%s|%s" % [scope, owner_key, trigger_key]


# ── 校验 ──────────────────────────────────────────────────

## 结构不变量（《数据库与实体关系设计》§6 约束 + §9 必查项中属于本聚合的部分）。
## unit_slots 由 ContentDB 传入——本类不维护第二份数值表。
func validate(unit_slots: int) -> PackedStringArray:
	var problems := PackedStringArray()
	if battle_id.is_empty():
		problems.append("battle_id 为空")
	if encounter_id.is_empty():
		problems.append("encounter_id 为空")
	if not PHASE_IDS.has(phase):
		problems.append("未知阶段：%s" % phase)
	if round_index < 1:
		problems.append("round_index 必须从 1 开始：%d" % round_index)
	if ddl < 0:
		problems.append("DDL 为负：%d" % ddl)

	if player == null:
		problems.append("缺少 PlayerBattleState")
	else:
		if player.entity_id.is_empty():
			problems.append("玩家实体缺少 entity_id")
		if player.max_vitality <= 0:
			problems.append("玩家最大精力必须为正：%d" % player.max_vitality)
		if player.vitality < 0:
			problems.append("玩家精力为负：%d" % player.vitality)
		if player.vitality > player.max_vitality:
			problems.append("玩家精力 %d 超过上限 %d" % [player.vitality, player.max_vitality])
		if player.focus < 0:
			problems.append("专注为负：%d" % player.focus)

	# 牌区：每张牌在且只在一个区，且两边引用一致
	var placed := {}
	for zone in zones.zone_ids():
		var seen_in_zone := {}
		for card_id in zones.list_for(zone):
			if seen_in_zone.has(card_id):
				problems.append("同一牌区内重复：%s @ %s" % [card_id, zone])
			seen_in_zone[card_id] = true
			if placed.has(card_id):
				problems.append("同一张牌出现在多个牌区：%s" % card_id)
			placed[card_id] = true
			if not card_by_id.has(card_id):
				problems.append("牌区引用了不存在的卡：%s" % card_id)
	for card_id in card_by_id:
		if not placed.has(card_id):
			problems.append("卡不在任何牌区（遗漏）：%s" % card_id)

	# 本战实体名单的唯一来源：entity_ids()（主角 / 单位 / 任务 / 场景）。
	# 以前这里自己维护一份只收单位与任务的名单，于是主角持有的状态会被判成
	# 「状态持有者不属于本战」，任何战斗中存档都写不下去/读不回来（G1）。
	var known_ids := {}
	var duplicate_ids := {}
	for raw_entity_id in entity_ids():
		var entity_id := String(raw_entity_id)
		if entity_id.is_empty():
			continue
		if known_ids.has(entity_id):
			duplicate_ids[entity_id] = true
		known_ids[entity_id] = true

	# 单位
	if units.size() > unit_slots:
		problems.append("存活单位 %d 超过槽位 %d" % [units.size(), unit_slots])
	for unit in units:
		if unit.unit_id.is_empty():
			problems.append("单位缺少 unit_id：%s" % unit.definition_id)
		elif duplicate_ids.has(unit.unit_id):
			problems.append("重复单位 ID：%s" % unit.unit_id)
			duplicate_ids.erase(unit.unit_id)
		if unit.vitality < 0:
			problems.append("单位精力为负：%s" % unit.unit_id)
		if unit.vitality > unit.max_vitality:
			problems.append("单位精力 %d 超过上限 %d（%s）" % [unit.vitality, unit.max_vitality, unit.unit_id])

	# 任务
	for task in tasks:
		if task.task_id.is_empty():
			problems.append("任务缺少 task_id：%s" % task.definition_id)
		elif duplicate_ids.has(task.task_id):
			problems.append("重复任务 ID：%s" % task.task_id)
			duplicate_ids.erase(task.task_id)
		if task.work_remaining < 0:
			problems.append("任务剩余工作量 %d 不能为 0 以下" % task.work_remaining)
		if task.work_max <= 0:
			problems.append("任务工作量上限必须为正：%s" % task.task_id)

	# 状态的持有者必须属于本战
	for status_id in statuses:
		var status = statuses[status_id]
		if status.holder_id.is_empty() or not known_ids.has(status.holder_id):
			problems.append("状态持有者不属于本战：%s -> %s" % [status_id, status.holder_id])

	# 触发计数器的组合键唯一
	for key in counters:
		var counter = counters[key]
		if counter_key(counter.scope, counter.owner_key, counter.trigger_key) != key:
			problems.append("触发计数器键不一致：%s" % key)
	return problems


# ── 战斗内实例 ID 与深拷贝 ────────────────────────────────

## 战斗内自造实例 ID（阶段任务 / 单位 / 状态 / 选择）。
## battle_id 已含 run_id + 序号，故 ID 形式为 "<battle_id>|<prefix><n>"，稳定且不复用。
func allocate_entity_id(prefix: String) -> String:
	var allocated := "%s|%s%d" % [battle_id, prefix, next_entity_seq]
	next_entity_seq += 1
	return allocated


## 入场顺序（多个护卫取最早入场、协作回退最前任务都读它）。
func next_order() -> int:
	var order := next_order_seq
	next_order_seq += 1
	return order


func has_exam_limit(limit_id: String) -> bool:
	return exam_limits.has(limit_id)


func has_relic(relic_id: String) -> bool:
	return relics.has(relic_id)


func statuses_of(holder_id: String) -> Array:
	var result := []
	for status_id in statuses:
		var status = statuses[status_id]
		if status.holder_id == holder_id:
			result.append(status)
	return result


func find_status(holder_id: String, definition_id: String) -> StatusState:
	for status_id in statuses:
		var status = statuses[status_id]
		if status.holder_id == holder_id and status.definition_id == definition_id:
			return status
	return null


## apply / preview 的工作副本：结算只改副本，失败或预览不污染调用方状态。
func copy_for_write() -> BattleState:
	var copy: BattleState = load("res://src/battle/battle_state.gd").new()
	copy.battle_id = battle_id
	copy.node_id = node_id
	copy.encounter_id = encounter_id
	copy.phase = phase
	copy.round_index = round_index
	copy.ddl = ddl
	copy.character_id = character_id
	copy.difficulty = difficulty
	copy.relics = relics.duplicate()
	copy.exam_limits = exam_limits.duplicate()
	copy.outcome = outcome
	copy.next_entity_seq = next_entity_seq
	copy.next_order_seq = next_order_seq
	copy.retained_card_ids = retained_card_ids.duplicate()

	copy.card_by_id = {}
	copy.zones = CardZones.new()
	for zone in zones.zone_ids():
		for card_id in zones.list_for(zone):
			copy.zones.list_for(zone).append(card_id)
	for card_id in card_by_id:
		var source = card_by_id[card_id]
		var target := BattleCard.new()
		target.card_id = source.card_id
		target.definition_id = source.definition_id
		target.origin_card_id = source.origin_card_id
		target.upgrade_level = source.upgrade_level
		target.modifiers = source.modifiers.duplicate(true)
		copy.card_by_id[card_id] = target

	if player != null:
		copy.player = create_player(player.entity_id, player.vitality, player.max_vitality)
		copy.player.relax = player.relax
		copy.player.focus = player.focus

	for unit in units:
		var copied_unit := create_unit(unit.unit_id, unit.definition_id, unit.vitality, unit.max_vitality)
		copied_unit.relax = unit.relax
		copied_unit.cooperation = unit.cooperation
		copied_unit.entered_order = unit.entered_order
		copied_unit.last_acted_round = unit.last_acted_round
		copied_unit.actions_taken = unit.actions_taken
		copied_unit.target_id = unit.target_id
		copy.units.append(copied_unit)

	for task in tasks:
		var copied_task := create_task(task.task_id, task.definition_id, task.phase_key, task.work_max)
		copied_task.work_remaining = task.work_remaining
		copied_task.shield = task.shield
		copied_task.intent_cursor = task.intent_cursor
		copied_task.intent_snapshot = task.intent_snapshot.duplicate(true)
		copied_task.entered_order = task.entered_order
		copied_task.eligible_round = task.eligible_round
		copy.tasks.append(copied_task)

	for status_id in statuses:
		var source_status = statuses[status_id]
		var copied_status := create_status(source_status.status_id, source_status.definition_id, source_status.holder_id, source_status.stacks)
		copied_status.source = source_status.source.duplicate(true)
		copied_status.expiry = source_status.expiry
		copy.statuses[status_id] = copied_status

	if scene != null:
		copy.scene = create_scene(scene.scene_id, scene.definition_id, scene.established_round)
		copy.scene.pending_random_result = scene.pending_random_result

	for key in counters:
		var source_counter = counters[key]
		var copied_counter := create_counter(source_counter.scope, source_counter.owner_key, source_counter.trigger_key)
		copied_counter.count = source_counter.count
		copied_counter.round = source_counter.round
		copy.counters[key] = copied_counter

	if resolution != null:
		copy.resolution = create_resolution(resolution.action.duplicate(true))
		copy.resolution.effect_cursor = resolution.effect_cursor
		copy.resolution.queue = resolution.queue.duplicate(true)
		copy.resolution.locked_target_ids = resolution.locked_target_ids.duplicate()
		if resolution.choice != null:
			copy.resolution.choice = (resolution.choice as Dictionary).duplicate(true)
		copy.resolution.choice_counts = resolution.choice_counts.duplicate(true)
	return copy