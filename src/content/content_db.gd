class_name ContentDB
extends RefCounted
##
## 只读内容库（《初步架构设计》§3；《接口文档》§6）。
##
## 公开接口按《接口文档》§6：
##   load(manifest_id) -> Result<ContentInfo>
##   get_definition(kind, id) -> Result<只读定义>
##   get_candidates(query) -> Array<String>（只过滤，不随机抽取；按 ID 稳定排序）
##
## 加载流程（《类与方法设计》ContentDB 节）：_parse_files → _validate_definitions
##   → _validate_references → _apply_manifest → _build_indexes；全部通过后才发布新 ContentInfo，
##   失败时保留原可用索引，不发布半套内容。
##
## 类型契约：Godot 的 JSON 解析把一切数字给成 float，读整数请走 run_int / battle_int / status_int。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")

const DEFINITIONS_DIR := "res://data/definitions/"
const MANIFESTS_DIR := "res://data/manifests/"

## kind → 定义文件名。unit / scene / status / event 随对应功能落地时再加，
## 本阶段不预建空文件（《初步架构设计》§7）。
const KIND_FILES := {
	GameConstants.KIND_CHARACTER: "characters.json",
	GameConstants.KIND_CARD: "cards.json",
	GameConstants.KIND_RELIC: "relics.json",
	GameConstants.KIND_TASK: "tasks.json",
	GameConstants.KIND_ENCOUNTER: "encounters.json",
	GameConstants.KIND_EVENT: "events.json",
	GameConstants.KIND_UNIT: "units.json",
	GameConstants.KIND_SCENE: "scenes.json",
}

const CARD_TYPES: Array[String] = [
	GameConstants.CARD_WORK,
	GameConstants.CARD_STRATEGY,
	GameConstants.CARD_ABILITY,
	GameConstants.CARD_COOPERATION,
	GameConstants.CARD_SCENE,
]

const KNOWN_OPS: Array[String] = [
	GameConstants.OP_COMPLETE,
	GameConstants.OP_RELAX,
	GameConstants.OP_DRAW,
	GameConstants.OP_DISCARD,
	GameConstants.OP_GAIN_STATUS,
	GameConstants.OP_WORK_FLAT_BONUS,
	GameConstants.OP_SUMMON_UNIT,
	GameConstants.OP_ESTABLISH_SCENE,
	GameConstants.OP_RESTORE_WORK,
	GameConstants.OP_PRESSURE,
	GameConstants.OP_GAIN_FOCUS,
	GameConstants.OP_HEAL,
	GameConstants.OP_LOSE_VITALITY,
	GameConstants.OP_REMOVE_STATUS,
	GameConstants.OP_RECALL_FROM_DISCARD,
	GameConstants.OP_RETAIN_HAND_CARD,
]

## 事件 op：权威实现是 src/run/run_service.gd 的 EVENT_OPS。这里只做内容校验，
## 不 preload run_service.gd（会形成 content→run→content 的循环依赖）。防漂移由测试钉住。
const EVENT_OPS: Array[String] = [
	GameConstants.EVENT_OP_GAIN_MONEY,
	GameConstants.EVENT_OP_HEAL,
	GameConstants.EVENT_OP_LOSE_VITALITY,
	GameConstants.EVENT_OP_GAIN_CARD,
	GameConstants.EVENT_OP_GAIN_RELIC,
	GameConstants.EVENT_OP_UPGRADE_CARD,
	GameConstants.EVENT_OP_REMOVE_CARD,
	GameConstants.EVENT_OP_CAREER,
]

## 敌方意图（task.phases[].intents[]）的已知字段：权威读取处是 src/battle/battle_engine.gd 的
## _run_enemy_skill / _run_enemy_pressure / _intent_holder。未知键以前被静默忽略，现在加载期报错。
const INTENT_KNOWN_FIELDS: Array[String] = [
	"index",                # 意图序号（≥1，同阶段内唯一）
	"text_key",             # 文案键（界面用；引擎不读）
	"pressure",             # 单体压力
	"pressure_times",       # 压力段数（默认 1）
	"pressure_all",         # 全体压力
	"shield",               # 任务屏障
	"work_restore",         # 恢复未完成量
	"extra_requirements",   # 任务额外要求层数
	"gain_status",          # 施加状态
	"add_card",             # 加入特殊牌
]
const INTENT_GAIN_STATUS_FIELDS: Array[String] = ["status", "stacks", "target"]
const INTENT_STATUS_TARGETS: Array[String] = ["player", "unit", "task"]
const INTENT_ADD_CARD_FIELDS: Array[String] = ["card", "count", "zone"]
## 引擎（_add_temporary_card → BattleState.add_card）支持的入牌区；resolving 不是可写区。
const INTENT_ADD_CARD_ZONES: Array[String] = [
	GameConstants.ZONE_DRAW,
	GameConstants.ZONE_HAND,
	GameConstants.ZONE_DISCARD,
	GameConstants.ZONE_EXHAUST,
]

## 引擎尚未接线的状态 → 缺什么。写进内容只会静默无效，加载期直接拒绝。
const UNWIRED_STATUS_GAPS := {
	"plagiarism_shield": "屏障吸收结算（应像 task.shield 一样先吸收完成量、并随敌方准备清零）",
}

## 饰品 hook（relics.json 的 hooks[]）已知字段：权威解释在 src/battle/card_rules.gd 的
## matched_relic_hooks / relic_cost_hooks 与 src/battle/battle_engine.gd 的 _run_relic_hooks。
## 未知键、未接线时点一律加载期报错——否则只会静默不生效。
const HOOK_KNOWN_FIELDS: Array[String] = [
	"at",                   # 时点（GameConstants.RELIC_HOOK_POINTS）
	"rounds",               # 只对该回合序号生效（仅 round_start / draw）
	"card_type",            # 卡面类型过滤（work/strategy/ability/cooperation/scene）
	"definition_id",        # 卡定义过滤（升级前后同一定义）
	"limit",                # 限次：{per, times}
	"effects",              # 时点触发时执行的效果列表（round_start / draw / card_resolved）
	"discount",             # cost_quote：专注费用减免
	"skip_vitality_cost",   # cost_quote：免除精力支付
	"kinds",                # shop_price：作用品类（card / relic）
	"multiplier_percent",   # shop_price：价格百分比（80 = ×0.8）
	"rounding",             # shop_price：取整方式（ceil / floor）
]

const LIMIT_PERIODS: Array[String] = ["round", "instance_round", "battle"]

const REQUIRED_SECTIONS: Array[String] = [
	"run",
	"battle",
	"statuses",
	"difficulty_overrides",
	"encounters",
	"rewards",
	"shop",
]

const REQUIRED_RUN_KEYS: Array[String] = [
	"starting_vitality",
	"starting_money",
	"starter_deck_size",
	"minimum_deck_size",
	"max_card_upgrades",
	"relic_slots",
	"term_count",
	"nodes_per_term",
	"term_heal_percent",
	"rest_heal_percent",
]

const REQUIRED_BATTLE_KEYS: Array[String] = [
	"base_focus_per_turn",
	"focus_cap",
	"base_draw_per_turn",
	"hand_limit",
	"base_retention_count",
	"unit_slots",
	"scene_slots",
	"unit_action_vitality_cost",
	"minimum_vitality_after_payment",
	"minimum_ddl",
	"cooperation_exam_relax",
	"scene_exam_draw",
	"scene_exam_relax",
]

const CARD_WEIGHT_GROUPS: Array[String] = ["normal", "elite", "boss", "term"]
const RELIC_WEIGHT_GROUPS: Array[String] = ["general", "boss"]

const RARITY_IDS: Array[String] = [
	GameConstants.RARITY_WHITE,
	GameConstants.RARITY_BLUE,
	GameConstants.RARITY_PURPLE,
	GameConstants.RARITY_GOLD,
]

## 《常量与规则配置》§3：statuses 只存已确定的层数上限与数值系数；
## 护卫是存在标记、查重护盾是任务屏障值，故意不设上限条目。
const STATUS_IDS_WITHOUT_LIMIT: Array[String] = [
	GameConstants.STATUS_GUARD,
	GameConstants.STATUS_PLAGIARISM_SHIELD,
]

const WEIGHT_POOL_TOTAL: int = 100

var ruleset_id: String = ""
var schema_version: int = -1
var manifest_id: String = ""
var content_version: String = ""
var content_hash: String = ""
## 最近一次失败对应的 GameConstants.ERROR_* 码；成功时为空串。
var last_error_code: String = ""

var _ruleset: Dictionary = {}
var _definitions: Dictionary = {}   # kind -> {id -> Dictionary}
var _enabled: Dictionary = {}       # kind -> {id -> true}
var _loaded_paths: PackedStringArray = PackedStringArray()
var _loaded: bool = false


# ── 加载 ──────────────────────────────────────────────────

## Result<ContentInfo>。manifest_id 缺省用 MVP 清单。
func load(requested_manifest: String = "") -> Dictionary:
	var target_manifest := requested_manifest
	if target_manifest.is_empty():
		target_manifest = GameConstants.MANIFEST_MVP

	var previous := _capture_state()
	_reset()
	var err := _load_ruleset()
	if err != OK:
		return _fail(previous, last_error_code, "error.content.ruleset_unreadable", {"error": err})

	var ruleset_problems := validate()
	if not ruleset_problems.is_empty():
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return _fail(previous, last_error_code, "error.content.ruleset_invalid", {"problems": ruleset_problems})

	err = _parse_files()
	if err != OK:
		return _fail(previous, last_error_code, "error.content.definitions_unreadable", {"error": err})

	var problems := _validate_definitions()
	if not problems.is_empty():
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return _fail(previous, last_error_code, "error.content.invalid_definitions", {"problems": problems})

	err = _apply_manifest(target_manifest)
	if err != OK:
		return _fail(previous, last_error_code, "error.content.manifest_unreadable", {"error": err})

	var reference_problems := _validate_references()
	if not reference_problems.is_empty():
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return _fail(previous, last_error_code, "error.content.broken_references", {"problems": reference_problems})

	_build_indexes()
	manifest_id = target_manifest
	content_hash = _compute_content_hash()
	_loaded = true
	return Result.ok(content_info())


func is_loaded() -> bool:
	return _loaded


func content_info() -> Dictionary:
	var counts := {}
	for kind in _enabled:
		counts[kind] = (_enabled[kind] as Dictionary).size()
	return {
		"content_version": content_version,
		"content_hash": content_hash,
		"manifest_id": manifest_id,
		"ruleset_id": ruleset_id,
		"counts": counts,
	}


func ruleset() -> Dictionary:
	return _ruleset


# ── 查询 ──────────────────────────────────────────────────

## Result<只读定义>。只返回启用清单内的定义。
func get_definition(kind: String, id: String) -> Dictionary:
	if not is_enabled(kind, id):
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.content.unknown_definition", {
			"kind": kind,
			"id": id,
		})
	return Result.ok(_definitions[kind][id])


func definition(kind: String, id: String) -> Dictionary:
	if not is_enabled(kind, id):
		return {}
	return _definitions[kind][id]


func is_enabled(kind: String, id: String) -> bool:
	if not _enabled.has(kind):
		return false
	return (_enabled[kind] as Dictionary).has(id)


func enabled_ids(kind: String) -> Array:
	if not _enabled.has(kind):
		return []
	var ids: Array = (_enabled[kind] as Dictionary).keys()
	ids.sort()
	return ids


## 只过滤、不抽取（《接口文档》§6）。query 支持：
##   kind（必填）、rarity（可空）、tags（全部命中）、excluded_ids、term（可空）、
##   exclude_tag（实现补充：奖励池用它排除 basic 标签，见《统一设计文档》「基础标签不进随机奖励池」）
## 返回按 ID 稳定排序的 Array<String>。
func get_candidates(query: Dictionary) -> Array:
	var kind := String(query.get("kind", ""))
	var result := []
	if not _enabled.has(kind):
		return result
	var rarity: Variant = query.get("rarity")
	var required_tags: Array = query.get("tags", [])
	var excluded: Array = query.get("excluded_ids", [])
	var term: Variant = query.get("term")
	var exclude_tag := String(query.get("exclude_tag", ""))

	for id in (_enabled[kind] as Dictionary).keys():
		var definition: Dictionary = _definitions[kind][id]
		if excluded.has(id):
			continue
		if rarity != null and String(rarity) != "":
			var definition_rarity: Variant = definition.get("rarity")
			if definition_rarity == null or String(definition_rarity) != String(rarity):
				continue
		var tags: Array = definition.get("tags", [])
		var tags_ok := true
		for tag in required_tags:
			if not tags.has(tag):
				tags_ok = false
				break
		if not tags_ok:
			continue
		if not exclude_tag.is_empty() and tags.has(exclude_tag):
			continue
		if term != null and definition.has("terms"):
			var terms: Array = definition["terms"]
			if terms.size() >= 2 and (int(term) < int(terms[0]) or int(term) > int(terms[1])):
				continue
		result.append(String(id))
	result.sort()
	return result


# ── 规则配置读取 ──────────────────────────────────────────

func section(name: String) -> Dictionary:
	var value: Variant = _ruleset.get(name)
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func run_value(key: String, fallback: Variant = null) -> Variant:
	return section("run").get(key, fallback)


func battle_value(key: String, fallback: Variant = null) -> Variant:
	return section("battle").get(key, fallback)


func run_int(key: String, fallback: int = 0) -> int:
	return _as_int(section("run").get(key), fallback)


func battle_int(key: String, fallback: int = 0) -> int:
	return _as_int(section("battle").get(key), fallback)


func difficulty(difficulty_id: String) -> Dictionary:
	var entry: Variant = section("difficulty_overrides").get(difficulty_id)
	if typeof(entry) == TYPE_DICTIONARY:
		return entry
	return {}


func difficulty_int(difficulty_id: String, key: String, fallback: int = 0) -> int:
	return _as_int(difficulty(difficulty_id).get(key), fallback)


func status_entry(status_id: String) -> Dictionary:
	var entry: Variant = section("statuses").get(status_id)
	if typeof(entry) == TYPE_DICTIONARY:
		return entry
	return {}


func status_int(status_id: String, key: String, fallback: int = 0) -> int:
	return _as_int(status_entry(status_id).get(key), fallback)


func has_status_definition(status_id: String) -> bool:
	return section("statuses").has(status_id)


## 《常量与规则配置》§3：_percent 为整数百分比，100 表示原值。
func scaled_by_percent(base: int, percent_value: int) -> int:
	return int(floor(float(base) * float(percent_value) / 100.0))


# ── 规则配置结构校验 ──────────────────────────────────────

func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if _ruleset.is_empty():
		problems.append("rulesets.json 尚未加载")
		return problems

	for name in REQUIRED_SECTIONS:
		if typeof(_ruleset.get(name)) != TYPE_DICTIONARY:
			problems.append("缺少小节：%s" % name)
	if ruleset_id.is_empty():
		problems.append("ruleset_id 为空")

	_check_required_keys(section("run"), REQUIRED_RUN_KEYS, "run", problems)
	_check_required_keys(section("battle"), REQUIRED_BATTLE_KEYS, "battle", problems)
	_check_difficulties(problems)
	_check_statuses(problems)
	_check_reward_weights(problems)
	return problems


func _check_required_keys(source: Dictionary, keys: Array[String], label: String, problems: PackedStringArray) -> void:
	for key in keys:
		if not source.has(key):
			problems.append("%s 缺少字段：%s" % [label, key])


func _check_difficulties(problems: PackedStringArray) -> void:
	var baseline := run_int("starting_vitality", -1)
	var ids: Array[String] = [
		GameConstants.DIFFICULTY_RELAXED,
		GameConstants.DIFFICULTY_NORMAL,
		GameConstants.DIFFICULTY_HARD,
	]
	for difficulty_id in ids:
		var entry := difficulty(difficulty_id)
		if entry.is_empty():
			problems.append("difficulty_overrides 缺少难度：%s" % difficulty_id)
			continue
		for key in ["starting_vitality", "ddl_offset", "pressure_percent"]:
			if not entry.has(key):
				problems.append("难度 %s 缺少字段：%s" % [difficulty_id, key])
		if not entry.has("starting_vitality") or not entry.has("pressure_percent"):
			continue
		var percent := _as_int(entry["pressure_percent"], -1)
		if percent <= 0:
			problems.append("难度 %s 的 pressure_percent 必须是正整数百分比" % difficulty_id)
		if difficulty_id != GameConstants.DIFFICULTY_RELAXED:
			var vitality := _as_int(entry["starting_vitality"], -1)
			if vitality != baseline:
				problems.append("难度 %s 起始精力 %d 与 run.starting_vitality %d 不一致" % [
					difficulty_id, vitality, baseline,
				])


func _check_statuses(problems: PackedStringArray) -> void:
	var statuses := section("statuses")
	var known := _known_status_ids()
	for status_id in known:
		if statuses.has(status_id):
			if typeof(statuses[status_id]) != TYPE_DICTIONARY:
				problems.append("statuses.%s 必须是对象" % status_id)
		elif not STATUS_IDS_WITHOUT_LIMIT.has(status_id):
			problems.append("statuses 缺少状态：%s" % status_id)
	for raw_id in statuses.keys():
		var status_id := String(raw_id)
		if not known.has(status_id):
			problems.append("statuses 出现未定义状态：%s" % status_id)


func _known_status_ids() -> Array[String]:
	return [
		GameConstants.STATUS_INSPIRATION,
		GameConstants.STATUS_COMPILE,
		GameConstants.STATUS_EXPERIMENT_DATA,
		GameConstants.STATUS_CITATION,
		GameConstants.STATUS_REVIEW,
		GameConstants.STATUS_FLOW,
		GameConstants.STATUS_ANXIETY,
		GameConstants.STATUS_PROCRASTINATION,
		GameConstants.STATUS_DROWSINESS,
		GameConstants.STATUS_EXTRA_REQUIREMENTS,
		GameConstants.STATUS_GUARD,
		GameConstants.STATUS_PLAGIARISM_SHIELD,
	]


func _check_reward_weights(problems: PackedStringArray) -> void:
	var rewards := section("rewards")
	_check_weight_table(rewards.get("card_rarity_weights"), CARD_WEIGHT_GROUPS, "rewards.card_rarity_weights", problems)
	_check_weight_table(rewards.get("relic_rarity_weights"), RELIC_WEIGHT_GROUPS, "rewards.relic_rarity_weights", problems)


func _check_weight_table(raw_table: Variant, groups: Array[String], label: String, problems: PackedStringArray) -> void:
	if typeof(raw_table) != TYPE_DICTIONARY:
		problems.append("%s 缺失" % label)
		return
	var table: Dictionary = raw_table
	for group in groups:
		_check_weight_group(table.get(group), "%s.%s" % [label, group], problems)


func _check_weight_group(raw_group: Variant, label: String, problems: PackedStringArray) -> void:
	if typeof(raw_group) != TYPE_DICTIONARY:
		problems.append("%s 缺失" % label)
		return
	var group: Dictionary = raw_group
	var total := 0
	for rarity in RARITY_IDS:
		if not group.has(rarity):
			problems.append("%s 缺少品质：%s" % [label, rarity])
			continue
		var weight: Variant = group[rarity]
		if not _is_integral_number(weight) or float(weight) < 0.0:
			problems.append("%s.%s 必须是非负整数权重" % [label, rarity])
			continue
		total += _as_int(weight, 0)
	if total != WEIGHT_POOL_TOTAL:
		problems.append("%s 权重合计 %d，完整池应为 %d" % [label, total, WEIGHT_POOL_TOTAL])


# ── 定义结构校验 ──────────────────────────────────────────

func _validate_definitions() -> PackedStringArray:
	var problems := PackedStringArray()
	for kind in _definitions:
		var by_id: Dictionary = _definitions[kind]
		for raw_id in by_id:
			var id := String(raw_id)
			var definition: Dictionary = by_id[raw_id]
			if id.is_empty():
				problems.append("%s 存在空 ID 的定义" % kind)
				continue
			if String(definition.get("id", "")) != id:
				problems.append("%s 定义 %s 的 id 字段与索引不一致" % [kind, id])
			if String(definition.get("name_key", "")).is_empty():
				problems.append("%s %s 缺少 name_key" % [kind, id])
			match kind:
				GameConstants.KIND_CARD:
					_validate_card(id, definition, problems)
				GameConstants.KIND_CHARACTER:
					_validate_character(id, definition, problems)
				GameConstants.KIND_TASK:
					_validate_task(id, definition, problems)
				GameConstants.KIND_ENCOUNTER:
					_validate_encounter(id, definition, problems)
				GameConstants.KIND_RELIC:
					_validate_relic(id, definition, problems)
				GameConstants.KIND_UNIT:
					_validate_unit(id, definition, problems)
				GameConstants.KIND_SCENE:
					_validate_scene(id, definition, problems)
	_validate_event_definitions(problems)
	return problems


func _validate_card(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "card %s" % id
	if not CARD_TYPES.has(String(definition.get("type", ""))):
		problems.append("%s 的 type 非法：%s" % [label, definition.get("type")])
	if _as_int(definition.get("cost"), -1) < 0:
		problems.append("%s 的 cost 必须是非负整数" % label)
	if String(definition.get("target", "")).is_empty():
		problems.append("%s 缺少 target" % label)
	var rarity: Variant = definition.get("rarity")
	if rarity != null and not RARITY_IDS.has(String(rarity)):
		problems.append("%s 的 rarity 非法：%s" % [label, rarity])
	_validate_vitality_cost(definition.get("vitality_cost"), label, problems)
	var unplayable := bool(definition.get("unplayable", false))
	if definition.has("unplayable") and typeof(definition["unplayable"]) != TYPE_BOOL:
		problems.append("%s 的 unplayable 必须是布尔" % label)
	# 不可打出的牌允许空 effects（X01 无任何效果）；其余牌仍必须非空，防止半张牌。
	if not (unplayable and typeof(definition.get("effects")) == TYPE_ARRAY and (definition.get("effects") as Array).is_empty()):
		_validate_effect_list(definition.get("effects"), "%s.effects" % label, problems)
	if definition.has("pre_effects"):
		_validate_effect_list(definition.get("pre_effects"), "%s.pre_effects" % label, problems)
	_validate_limit(definition.get("limit"), label, problems)
	var upgrade: Variant = definition.get("upgrade")
	if typeof(upgrade) == TYPE_DICTIONARY:
		if (upgrade as Dictionary).has("effects"):
			_validate_effect_list((upgrade as Dictionary).get("effects"), "%s.upgrade.effects" % label, problems)
		if (upgrade as Dictionary).has("pre_effects"):
			_validate_effect_list((upgrade as Dictionary).get("pre_effects"), "%s.upgrade.pre_effects" % label, problems)
		if (upgrade as Dictionary).has("vitality_cost"):
			_validate_vitality_cost((upgrade as Dictionary).get("vitality_cost"), "%s.upgrade" % label, problems)


func _validate_character(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "character %s" % id
	var starter_cards: Variant = definition.get("starter_cards")
	if typeof(starter_cards) != TYPE_ARRAY or (starter_cards as Array).is_empty():
		problems.append("%s 的 starter_cards 必须是非空数组" % label)
	if String(definition.get("starter_relic_id", "")).is_empty():
		problems.append("%s 缺少 starter_relic_id" % label)
	var passive: Variant = definition.get("passive")
	if typeof(passive) != TYPE_DICTIONARY:
		problems.append("%s 缺少 passive" % label)
		return
	var passive_dict: Dictionary = passive
	var passive_trigger := String(passive_dict.get("trigger", ""))
	if passive_trigger.is_empty():
		problems.append("%s.passive 缺少 trigger" % label)
	elif not GameConstants.PASSIVE_TRIGGERS.has(passive_trigger):
		problems.append("%s.passive.trigger 引擎未接线：%s（可选：%s）" % [label, passive_trigger, ", ".join(GameConstants.PASSIVE_TRIGGERS)])
	if _as_int(passive_dict.get("count"), 0) < 1:
		problems.append("%s.passive.count 必须 ≥ 1" % label)
	_validate_effect_list(passive_dict.get("effects"), "%s.passive.effects" % label, problems)
	_validate_limit(passive_dict.get("limit"), "%s.passive" % label, problems)


func _validate_relic(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "relic %s" % id
	var rarity: Variant = definition.get("rarity")
	if rarity != null and not RARITY_IDS.has(String(rarity)):
		problems.append("%s 的 rarity 非法：%s" % [label, rarity])
	if String(definition.get("availability", "")).is_empty() and rarity == null:
		problems.append("%s 既没有 rarity 也没有 availability" % label)
	var hooks: Variant = definition.get("hooks")
	var has_hooks := typeof(hooks) == TYPE_ARRAY and not (hooks as Array).is_empty()
	if hooks != null:
		_validate_relic_hooks(id, hooks, problems)
	var raw_effects: Variant = definition.get("effects")
	var has_effects := typeof(raw_effects) == TYPE_ARRAY and not (raw_effects as Array).is_empty()
	# 纯 hook 饰品（如 A04 的费用减免）允许不写 effects；两者都没有才是半个饰品。
	if not has_effects and not has_hooks:
		problems.append("%s 必须至少有 effects 或 hooks 之一" % label)
	elif has_effects:
		_validate_effect_list(raw_effects, "%s.effects" % label, problems)
	_validate_limit(definition.get("limit"), label, problems)


func _validate_task(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "task %s" % id
	if _as_int(definition.get("ddl"), 0) < 1:
		problems.append("%s 的 ddl 必须 ≥ 1" % label)
	var terms: Variant = definition.get("terms")
	if typeof(terms) != TYPE_ARRAY or (terms as Array).size() != 2:
		problems.append("%s 的 terms 必须是 [起始学期, 结束学期]" % label)
	var phases: Variant = definition.get("phases")
	if typeof(phases) != TYPE_ARRAY or (phases as Array).is_empty():
		problems.append("%s 的 phases 必须是非空数组" % label)
		return
	var seen_phases := {}
	for raw_phase in phases:
		if typeof(raw_phase) != TYPE_DICTIONARY:
			problems.append("%s 存在非对象的 phase" % label)
			continue
		var phase: Dictionary = raw_phase
		var phase_key := String(phase.get("phase_key", ""))
		if phase_key.is_empty():
			problems.append("%s 存在缺少 phase_key 的 phase" % label)
		elif seen_phases.has(phase_key):
			problems.append("%s 的 phase_key 重复：%s" % [label, phase_key])
		seen_phases[phase_key] = true
		if _as_int(phase.get("work"), 0) < 1:
			problems.append("%s.%s 的 work 必须 ≥ 1" % [label, phase_key])
		var intents: Variant = phase.get("intents")
		if typeof(intents) != TYPE_ARRAY or (intents as Array).is_empty():
			problems.append("%s.%s 的 intents 必须是非空数组" % [label, phase_key])
			continue
		var seen_index := {}
		for raw_intent in intents:
			if typeof(raw_intent) != TYPE_DICTIONARY:
				problems.append("%s.%s 存在非对象的 intent" % [label, phase_key])
				continue
			var intent: Dictionary = raw_intent
			var index := _as_int(intent.get("index"), -1)
			if index < 1:
				problems.append("%s.%s 存在 index < 1 的 intent" % [label, phase_key])
			elif seen_index.has(index):
				problems.append("%s.%s 的 intent index 重复：%d" % [label, phase_key, index])
			seen_index[index] = true
			if intent.size() <= 2:
				problems.append("%s.%s 的 intent %d 没有任何效果字段" % [label, phase_key, index])
			_validate_intent(intent, "%s.%s 的 intent %d" % [label, phase_key, index], problems)


func _validate_encounter(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "encounter %s" % id
	var tasks: Variant = definition.get("tasks")
	if typeof(tasks) != TYPE_ARRAY or (tasks as Array).is_empty():
		problems.append("%s 的 tasks 必须是非空数组" % label)
	if String(definition.get("kind", "")).is_empty():
		problems.append("%s 缺少 kind" % label)


func _validate_effect_list(raw_effects: Variant, label: String, problems: PackedStringArray) -> void:
	if typeof(raw_effects) != TYPE_ARRAY or (raw_effects as Array).is_empty():
		problems.append("%s 必须是非空数组" % label)
		return
	var choice_ops_allowed := label.begins_with("card ")
	for raw_effect in raw_effects:
		if typeof(raw_effect) != TYPE_DICTIONARY:
			problems.append("%s 存在非对象的 effect" % label)
			continue
		var effect: Dictionary = raw_effect
		var op := String(effect.get("op", ""))
		if not KNOWN_OPS.has(op):
			problems.append("%s 存在未知 op：%s" % [label, op])
			continue
		if op == GameConstants.OP_COMPLETE or op == GameConstants.OP_RELAX or op == GameConstants.OP_WORK_FLAT_BONUS:
			if _as_int(effect.get("amount"), -1) < 0:
				problems.append("%s 的 %s.amount 必须是非负整数" % [label, op])
		if op == GameConstants.OP_DRAW or op == GameConstants.OP_DISCARD:
			if _as_int(effect.get("amount"), -1) < 1:
				problems.append("%s 的 %s.amount 必须 ≥ 1" % [label, op])
		if op == GameConstants.OP_GAIN_STATUS:
			_check_status_wiring(label, String(effect.get("status", "")), "gain_status", problems)
			if _as_int(effect.get("stacks"), 0) < 1:
				problems.append("%s 的 gain_status.stacks 必须 ≥ 1" % label)
		if op == GameConstants.OP_REMOVE_STATUS:
			var status_id := String(effect.get("status", ""))
			var category := String(effect.get("category", ""))
			if status_id.is_empty() and category.is_empty():
				problems.append("%s 的 remove_status 需要 status 或 category" % label)
			if not category.is_empty() and category != GameConstants.STATUS_CATEGORY_NEGATIVE:
				problems.append("%s 的 remove_status.category 非法：%s" % [label, category])
			if not status_id.is_empty():
				_check_status_wiring(label, status_id, "remove_status", problems)
			if _as_int(effect.get("amount"), -1) < 1:
				problems.append("%s 的 remove_status.amount 必须 ≥ 1" % label)
		if op == GameConstants.OP_DISCARD and effect.has("up_to") and typeof(effect["up_to"]) != TYPE_BOOL:
			problems.append("%s 的 discard.up_to 必须是布尔" % label)
		if op == GameConstants.OP_DRAW and effect.has("per_discarded") and _as_int(effect.get("per_discarded"), 0) < 1:
			problems.append("%s 的 draw.per_discarded 必须 ≥ 1" % label)
		if op == GameConstants.OP_RECALL_FROM_DISCARD:
			if _as_int(effect.get("amount"), -1) < 1:
				problems.append("%s 的 recall_from_discard.amount 必须 ≥ 1" % label)
			if String(effect.get("zone_from", GameConstants.ZONE_DISCARD)) != GameConstants.ZONE_DISCARD or String(effect.get("zone_to", GameConstants.ZONE_HAND)) != GameConstants.ZONE_HAND:
				problems.append("%s 的 recall_from_discard 只支持 zone_from=discard / zone_to=hand" % label)
		if op == GameConstants.OP_RETAIN_HAND_CARD and _as_int(effect.get("amount"), -1) < 1:
			problems.append("%s 的 retain_hand_card.amount 必须 ≥ 1" % label)
		var bonus: Variant = effect.get("bonus_if")
		if typeof(bonus) == TYPE_DICTIONARY:
			_validate_bonus_if(bonus, label, problems)
		if not choice_ops_allowed and _effect_requires_choice(effect):
			problems.append("%s 的 %s 需要在出牌结算里挂起待选，只能写在卡牌 effects / upgrade 里" % [label, op])


## bonus_if 条件：至少写一个已实现条件键（status+min_stacks / played_definition[+scope] / ddl_lte）。
func _validate_bonus_if(bonus: Dictionary, label: String, problems: PackedStringArray) -> void:
	var conditions := 0
	if bonus.has("status"):
		conditions += 1
		if String(bonus.get("status", "")).is_empty():
			problems.append("%s 的 bonus_if.status 不能为空" % label)
		else:
			_check_status_wiring(label, String(bonus.get("status", "")), "bonus_if", problems)
		if bonus.has("min_stacks") and _as_int(bonus.get("min_stacks"), 0) < 1:
			problems.append("%s 的 bonus_if.min_stacks 必须 ≥ 1" % label)
	if bonus.has("played_definition"):
		conditions += 1
		if String(bonus.get("played_definition", "")).is_empty():
			problems.append("%s 的 bonus_if.played_definition 不能为空" % label)
		if String(bonus.get("scope", GameConstants.COUNTER_SCOPE_ROUND)) != GameConstants.COUNTER_SCOPE_ROUND:
			problems.append("%s 的 bonus_if.scope 只支持 round（本回合）" % label)
	if bonus.has("ddl_lte"):
		conditions += 1
		if _as_int(bonus.get("ddl_lte"), -1) < 0:
			problems.append("%s 的 bonus_if.ddl_lte 必须 ≥ 0" % label)
	if conditions == 0:
		problems.append("%s 的 bonus_if 缺少条件（status / played_definition / ddl_lte）" % label)
	if _as_int(bonus.get("amount"), 0) < 1:
		problems.append("%s 的 bonus_if.amount 必须 ≥ 1" % label)


## 需要挂起效果内选择的 op：只能写在卡牌 effects / upgrade 里（引擎只在出牌结算里实现）。
func _effect_requires_choice(effect: Dictionary) -> bool:
	var op := String(effect.get("op", ""))
	if op == GameConstants.OP_DISCARD or op == GameConstants.OP_RECALL_FROM_DISCARD:
		return true
	if op == GameConstants.OP_REMOVE_STATUS and not String(effect.get("category", "")).is_empty():
		return true
	return false


## 状态引用总闸：先看引擎有没有接线（没有就别写进内容），再看 rulesets 里有没有定义。
## 「未接线」= WIRED_STATUS_IDS 里没有它，引擎没有任何代码结算它 → 写了只会静默无效。
func _check_status_wiring(owner_id: String, status_id: String, where: String, problems: PackedStringArray) -> void:
	if status_id.is_empty():
		problems.append("%s 的 %s 缺少 status" % [owner_id, where])
		return
	if not GameConstants.WIRED_STATUS_IDS.has(status_id):
		problems.append("%s 的 %s 引用了引擎尚未接线的状态：%s（缺：%s）。宁可加载失败，也不要静默无效。" % [
			owner_id, where, status_id, String(UNWIRED_STATUS_GAPS.get(status_id, "引擎没有结算它的代码")),
		])
		return
	if not has_status_definition(status_id):
		problems.append("%s 的 %s 引用了未定义状态：%s" % [owner_id, where, status_id])


## 卡的主动精力代价：非负整数（JSON 数字是 float，必须是整数值）。
func _validate_vitality_cost(raw_value: Variant, label: String, problems: PackedStringArray) -> void:
	if raw_value == null:
		return
	if not _is_integral_number(raw_value) or _as_int(raw_value, -1) < 0:
		problems.append("%s 的 vitality_cost 必须是非负整数" % label)


## 敌方意图：未知字段一律报错（以前静默忽略），已知字段逐个查数量与引用。
func _validate_intent(intent: Dictionary, where: String, problems: PackedStringArray) -> void:
	for raw_key in intent.keys():
		if not INTENT_KNOWN_FIELDS.has(String(raw_key)):
			problems.append("%s 存在未知字段：%s（已知字段：%s）" % [where, raw_key, ", ".join(INTENT_KNOWN_FIELDS)])
	for key in ["shield", "work_restore", "extra_requirements", "pressure", "pressure_all", "pressure_times"]:
		if intent.has(key) and _as_int(intent.get(key), -1) < 1:
			problems.append("%s 的 %s 必须是 ≥ 1 的整数" % [where, key])
	if intent.has("gain_status"):
		_validate_intent_gain_status(intent["gain_status"], where, problems)
	if intent.has("add_card"):
		_validate_intent_add_card(intent["add_card"], where, problems)


func _validate_intent_gain_status(raw_spec: Variant, where: String, problems: PackedStringArray) -> void:
	if typeof(raw_spec) != TYPE_DICTIONARY:
		problems.append("%s 的 gain_status 必须是对象" % where)
		return
	var spec: Dictionary = raw_spec
	for raw_key in spec.keys():
		if not INTENT_GAIN_STATUS_FIELDS.has(String(raw_key)):
			problems.append("%s 的 gain_status 存在未知字段：%s" % [where, raw_key])
	var target := String(spec.get("target", "player"))
	if not INTENT_STATUS_TARGETS.has(target):
		problems.append("%s 的 gain_status.target 非法：%s（可选：%s）" % [where, target, ", ".join(INTENT_STATUS_TARGETS)])
	_check_status_wiring(where, String(spec.get("status", "")), "gain_status", problems)
	if spec.has("stacks") and _as_int(spec.get("stacks"), 0) < 1:
		problems.append("%s 的 gain_status.stacks 必须 ≥ 1" % where)


func _validate_intent_add_card(raw_spec: Variant, where: String, problems: PackedStringArray) -> void:
	if typeof(raw_spec) != TYPE_DICTIONARY:
		problems.append("%s 的 add_card 必须是对象" % where)
		return
	var spec: Dictionary = raw_spec
	for raw_key in spec.keys():
		if not INTENT_ADD_CARD_FIELDS.has(String(raw_key)):
			problems.append("%s 的 add_card 存在未知字段：%s" % [where, raw_key])
	if String(spec.get("card", "")).is_empty():
		problems.append("%s 的 add_card 缺少 card" % where)
	if spec.has("count") and _as_int(spec.get("count"), 0) < 1:
		problems.append("%s 的 add_card.count 必须 ≥ 1" % where)
	var zone := String(spec.get("zone", GameConstants.ZONE_DISCARD))
	if not INTENT_ADD_CARD_ZONES.has(zone):
		problems.append("%s 的 add_card.zone 非法：%s（可选：%s）" % [where, zone, ", ".join(INTENT_ADD_CARD_ZONES)])


func _validate_limit(raw_limit: Variant, label: String, problems: PackedStringArray) -> void:
	if raw_limit == null:
		return
	if typeof(raw_limit) != TYPE_DICTIONARY:
		problems.append("%s 的 limit 必须是对象" % label)
		return
	var limit: Dictionary = raw_limit
	if not LIMIT_PERIODS.has(String(limit.get("per", ""))):
		problems.append("%s 的 limit.per 非法：%s" % [label, limit.get("per")])
	if _as_int(limit.get("times"), 0) < 1:
		problems.append("%s 的 limit.times 必须 ≥ 1" % label)


# ── 引用校验 ──────────────────────────────────────────────

func _validate_references() -> PackedStringArray:
	var problems := PackedStringArray()
	for kind in _enabled:
		for id in (_enabled[kind] as Dictionary).keys():
			var definition: Dictionary = _definitions[kind][id]
			match kind:
				GameConstants.KIND_CHARACTER:
					for card_id in (definition.get("starter_cards", []) as Array):
						_require(GameConstants.KIND_CARD, String(card_id), "character %s 的起始牌" % id, problems)
					_require(GameConstants.KIND_RELIC, String(definition.get("starter_relic_id", "")), "character %s 的初始饰品" % id, problems)
				GameConstants.KIND_ENCOUNTER:
					for task_id in (definition.get("tasks", []) as Array):
						_require(GameConstants.KIND_TASK, String(task_id), "encounter %s 的任务" % id, problems)
				GameConstants.KIND_TASK:
					for raw_phase in (definition.get("phases", []) as Array):
						var phase: Dictionary = raw_phase
						for raw_intent in (phase.get("intents", []) as Array):
							var intent: Dictionary = raw_intent
							var added: Variant = intent.get("add_card")
							if typeof(added) == TYPE_DICTIONARY:
								_require(GameConstants.KIND_CARD, String((added as Dictionary).get("card", "")), "task %s 意图加入的牌" % id, problems)
				GameConstants.KIND_CARD:
					_check_card_effect_references(id, definition.get("effects", []), problems)
					var upgrade: Variant = definition.get("upgrade")
					if typeof(upgrade) == TYPE_DICTIONARY:
						_check_card_effect_references(id, (upgrade as Dictionary).get("effects", []), problems)
				GameConstants.KIND_RELIC:
					_check_card_effect_references(id, definition.get("effects", []), problems)
				GameConstants.KIND_SCENE:
					_check_scene_effect_references(id, definition, problems)
	_check_event_references_enabled(problems)
	return problems


func _check_card_effect_references(owner_id: String, raw_effects: Variant, problems: PackedStringArray) -> void:
	if typeof(raw_effects) != TYPE_ARRAY:
		return
	for raw_effect in (raw_effects as Array):
		if typeof(raw_effect) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = raw_effect
		# 召唤/换场引用校验（本版只用这两种新 op 做跨内容引用）。
		if String(effect.get("op", "")) == GameConstants.OP_SUMMON_UNIT:
			_require(GameConstants.KIND_UNIT, String(effect.get("unit", "")), "%s 召唤的单位" % owner_id, problems)
			continue
		if String(effect.get("op", "")) == GameConstants.OP_ESTABLISH_SCENE:
			_require(GameConstants.KIND_SCENE, String(effect.get("scene", "")), "%s 建立的场景" % owner_id, problems)
			continue
		# 状态引用（gain_status / remove_status / bonus_if）在 _validate_effect_list 里统一校验：
		# 那里对卡牌、饰品、场景、单位、被动、upgrade.pre_effects 全都跑到。


func _require(kind: String, id: String, what: String, problems: PackedStringArray) -> void:
	if id.is_empty() or not is_enabled(kind, id):
		problems.append("%s 指向未启用的 %s：%s" % [what, kind, id])


# ── 读文件 ────────────────────────────────────────────────

func _reset() -> void:
	_ruleset = {}
	_definitions = {}
	_enabled = {}
	_loaded_paths = PackedStringArray()
	ruleset_id = ""
	schema_version = -1
	manifest_id = ""
	content_version = ""
	content_hash = ""
	last_error_code = ""
	_loaded = false


func _load_ruleset() -> Error:
	var parsed := {}
	var err := _read_json_object(GameConstants.RULESETS_PATH, parsed)
	if err != OK:
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return err
	var raw_version: Variant = parsed.get("schema_version")
	if not _is_number(raw_version):
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return ERR_INVALID_DATA
	schema_version = _as_int(raw_version, -1)
	if schema_version != GameConstants.RULESET_SCHEMA_VERSION:
		last_error_code = GameConstants.ERROR_VERSION_MISMATCH
		return ERR_INVALID_DATA
	ruleset_id = String(parsed.get("ruleset_id", ""))
	_ruleset = parsed
	_loaded_paths.append(GameConstants.RULESETS_PATH)
	return OK


func _parse_files() -> Error:
	for kind in KIND_FILES:
		var path := DEFINITIONS_DIR + String(KIND_FILES[kind])
		if not FileAccess.file_exists(path):
			last_error_code = GameConstants.ERROR_CONTENT_INVALID
			return ERR_FILE_NOT_FOUND
		var parsed := {}
		var err := _read_json_object(path, parsed)
		if err != OK:
			last_error_code = GameConstants.ERROR_CONTENT_INVALID
			return err
		if String(parsed.get("kind", "")) != kind:
			last_error_code = GameConstants.ERROR_CONTENT_INVALID
			return ERR_INVALID_DATA
		var raw_definitions: Variant = parsed.get("definitions")
		if typeof(raw_definitions) != TYPE_ARRAY:
			last_error_code = GameConstants.ERROR_CONTENT_INVALID
			return ERR_INVALID_DATA
		var by_id := {}
		for raw_definition in (raw_definitions as Array):
			if typeof(raw_definition) != TYPE_DICTIONARY:
				last_error_code = GameConstants.ERROR_CONTENT_INVALID
				return ERR_INVALID_DATA
			var definition: Dictionary = raw_definition
			var id := String(definition.get("id", ""))
			if id.is_empty() or by_id.has(id):
				last_error_code = GameConstants.ERROR_CONTENT_INVALID
				return ERR_INVALID_DATA
			by_id[id] = definition
		_definitions[kind] = by_id
		_loaded_paths.append(path)
	return OK


func _apply_manifest(target_manifest: String) -> Error:
	var path := MANIFESTS_DIR + target_manifest + ".json"
	if not FileAccess.file_exists(path):
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return ERR_FILE_NOT_FOUND
	var parsed := {}
	var err := _read_json_object(path, parsed)
	if err != OK:
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return err
	if String(parsed.get("manifest_id", "")) != target_manifest:
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return ERR_INVALID_DATA
	var declared_ruleset := String(parsed.get("ruleset_id", ""))
	if not declared_ruleset.is_empty() and declared_ruleset != ruleset_id:
		last_error_code = GameConstants.ERROR_VERSION_MISMATCH
		return ERR_INVALID_DATA
	content_version = String(parsed.get("content_version", ""))
	var raw_enabled: Variant = parsed.get("enabled")
	if typeof(raw_enabled) != TYPE_DICTIONARY:
		last_error_code = GameConstants.ERROR_CONTENT_INVALID
		return ERR_INVALID_DATA
	var enabled: Dictionary = raw_enabled
	_enabled = {}
	for kind in enabled:
		var bucket := {}
		for raw_id in (enabled[kind] as Array):
			var id := String(raw_id)
			if not _definitions.has(kind) or not (_definitions[kind] as Dictionary).has(id):
				last_error_code = GameConstants.ERROR_CONTENT_INVALID
				return ERR_INVALID_DATA
			bucket[id] = true
		_enabled[kind] = bucket
	_loaded_paths.append(path)
	return OK


func _build_indexes() -> void:
	# 定义按 kind → id 索引，启动时重建；不把派生索引复制进存档
	# （《数据库与实体关系设计》§7 内存索引）。
	for kind in _definitions:
		var source: Dictionary = _definitions[kind]
		var filtered := {}
		if _enabled.has(kind):
			for id in (_enabled[kind] as Dictionary).keys():
				filtered[id] = source[id]
		_definitions[kind] = filtered


func _compute_content_hash() -> String:
	var parts := PackedStringArray()
	var paths: Array = _loaded_paths.duplicate()
	paths.sort()
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		parts.append("%s:%s" % [path, file.get_as_text().sha256_text()])
		file.close()
	return "\n".join(parts).sha256_text()


## 加载失败时保留原可用索引，不发布半套内容（《类与方法设计》ContentDB 节）。
func _capture_state() -> Dictionary:
	return {
		"ruleset": _ruleset,
		"definitions": _definitions,
		"enabled": _enabled,
		"ruleset_id": ruleset_id,
		"schema_version": schema_version,
		"manifest_id": manifest_id,
		"content_version": content_version,
		"content_hash": content_hash,
		"last_error_code": last_error_code,
		"loaded_paths": _loaded_paths,
		"loaded": _loaded,
	}


func _restore_state(state: Dictionary) -> void:
	_ruleset = state["ruleset"]
	_definitions = state["definitions"]
	_enabled = state["enabled"]
	ruleset_id = state["ruleset_id"]
	schema_version = state["schema_version"]
	manifest_id = state["manifest_id"]
	content_version = state["content_version"]
	content_hash = state["content_hash"]
	last_error_code = state["last_error_code"]
	_loaded_paths = state["loaded_paths"]
	_loaded = state["loaded"]


## 先取失败结果，再回滚已发布状态，最后把失败码留给调用方读。
func _fail(previous: Dictionary, code: String, message_key: String, details: Dictionary) -> Dictionary:
	var result := Result.fail(code, message_key, details)
	_restore_state(previous)
	last_error_code = code
	return result

func _read_json_object(path: String, target: Dictionary) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return ERR_PARSE_ERROR
	if typeof(json.data) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	var source: Dictionary = json.data
	target.clear()
	for key in source.keys():
		target[key] = source[key]
	return OK


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_integral_number(value: Variant) -> bool:
	if not _is_number(value):
		return false
	return float(value) == floor(float(value))


func _as_int(value: Variant, fallback: int) -> int:
	if _is_integral_number(value):
		return int(round(float(value)))
	return fallback

func _validate_unit(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "unit %s" % id
	if _as_int(definition.get("vitality"), 0) < 1:
		problems.append("%s 的 vitality 必须 ≥ 1" % label)
	if _as_int(definition.get("cooperation"), -1) < 0:
		problems.append("%s 的 cooperation 必须 ≥ 0" % label)
	var support: Variant = definition.get("support")
	if support != null and typeof(support) != TYPE_DICTIONARY:
		problems.append("%s 的 support 必须是对象或 null" % label)
	var entry: Variant = definition.get("entry_effects")
	if entry != null:
		_validate_effect_list(entry, "%s.entry_effects" % label, problems)

func _validate_scene(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "scene %s" % id
	if definition.has("prepare_effects"):
		_validate_effect_list(definition.get("prepare_effects"), "%s.prepare_effects" % label, problems)
	if definition.has("round_end_effects"):
		_validate_effect_list(definition.get("round_end_effects"), "%s.round_end_effects" % label, problems)
	var random_spec: Variant = definition.get("prepare_random")
	if typeof(random_spec) == TYPE_DICTIONARY:
		var options: Variant = (random_spec as Dictionary).get("options")
		if typeof(options) != TYPE_ARRAY or (options as Array).is_empty():
			problems.append("%s.prepare_random.options 必须是非空数组" % label)
		else:
			for raw_option in (options as Array):
				if typeof(raw_option) != TYPE_DICTIONARY:
					problems.append("%s.prepare_random 存在非对象选项" % label)
					continue
				_validate_effect_list((raw_option as Dictionary).get("effects"), "%s.prepare_random.effects" % label, problems)

func _check_scene_effect_references(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	_check_card_effect_references(id, definition.get("prepare_effects", []), problems)
	_check_card_effect_references(id, definition.get("round_end_effects", []), problems)
	var random_spec: Variant = definition.get("prepare_random")
	if typeof(random_spec) == TYPE_DICTIONARY:
		var options: Variant = (random_spec as Dictionary).get("options", [])
		if typeof(options) == TYPE_ARRAY:
			for raw_option in (options as Array):
				if typeof(raw_option) == TYPE_DICTIONARY:
					_check_card_effect_references(id, (raw_option as Dictionary).get("effects", []), problems)

func _validate_event_definitions(problems: PackedStringArray) -> void:
	var by_id: Dictionary = _definitions.get(GameConstants.KIND_EVENT, {})
	for raw_id in by_id:
		_validate_event(String(raw_id), by_id[raw_id], problems)


func _validate_event(id: String, definition: Dictionary, problems: PackedStringArray) -> void:
	var label := "event %s" % id
	if not definition.has("terms") and not definition.has("allowed_terms"):
		problems.append("%s 必须声明 terms 或 allowed_terms" % label)
	var options: Variant = definition.get("options")
	if typeof(options) != TYPE_ARRAY or (options as Array).is_empty():
		problems.append("%s 的 options 必须是非空数组" % label)
		return
	var seen_options := {}
	var has_leave_option := false
	for raw_option in (options as Array):
		if typeof(raw_option) != TYPE_DICTIONARY:
			problems.append("%s 存在非对象的 option" % label)
			continue
		var option: Dictionary = raw_option
		var option_id := String(option.get("option_id", ""))
		if option_id.is_empty():
			problems.append("%s 存在缺少 option_id 的选项" % label)
		elif seen_options.has(option_id):
			problems.append("%s 的 option_id 重复：%s" % [label, option_id])
		seen_options[option_id] = true
		if String(option.get("label_key", "")).is_empty():
			problems.append("%s.%s 缺少 label_key" % [label, option_id])
		if typeof(option.get("cost", {})) != TYPE_DICTIONARY:
			problems.append("%s.%s 的 cost 必须是对象" % [label, option_id])
		var effects: Variant = option.get("effects")
		if typeof(effects) != TYPE_ARRAY:
			problems.append("%s.%s 的 effects 必须是数组" % [label, option_id])
			continue
		if (effects as Array).is_empty():
			has_leave_option = true
		for raw_effect in (effects as Array):
			if typeof(raw_effect) != TYPE_DICTIONARY:
				problems.append("%s.%s 存在非对象的 effect" % [label, option_id])
				continue
			var effect: Dictionary = raw_effect
			var op := String(effect.get("op", ""))
			if not EVENT_OPS.has(op):
				problems.append("%s.%s 存在未知事件 op：%s" % [label, option_id, op])
				continue
			_validate_event_effect(effect, "%s.%s 的 %s" % [label, option_id, op], problems)
	if not has_leave_option:
		problems.append("%s 缺少「离开，无变化」选项（effects 为空数组）" % label)


## 事件效果字段校验（只覆盖引擎真会读的字段；未知键留给后续统一收口）。
func _validate_event_effect(effect: Dictionary, where: String, problems: PackedStringArray) -> void:
	var op := String(effect.get("op", ""))
	if op == GameConstants.EVENT_OP_GAIN_CARD:
		if effect.has("card_pool"):
			var pool: Variant = effect.get("card_pool")
			if typeof(pool) != TYPE_ARRAY or (pool as Array).is_empty():
				problems.append("%s 的 card_pool 必须是非空数组" % where)
			else:
				for raw_card_id in (pool as Array):
					if String(raw_card_id).is_empty():
						problems.append("%s 的 card_pool 存在空 ID" % where)
			if effect.has("rarity"):
				problems.append("%s 不能同时写 card_pool 与 rarity（候选来源只能有一个）" % where)
		var selection_count := _as_int(effect.get("selection_count"), 1)
		if effect.has("selection_count") and selection_count < 1:
			problems.append("%s 的 selection_count 必须 ≥ 1" % where)
		elif selection_count > 1:
			problems.append("%s 的 selection_count=%d 引擎本版不支持（只发 1 张，不静默只发 1 张）" % [where, selection_count])
		if effect.has("card_pool") and _as_int(effect.get("selection_count"), 1) > (effect.get("card_pool") as Array).size():
			problems.append("%s 的 card_pool 少于 selection_count" % where)
	elif op == GameConstants.EVENT_OP_REMOVE_CARD:
		if effect.has("tag_filter") and not GameConstants.EVENT_FILTER_TAGS.has(String(effect.get("tag_filter", ""))):
			problems.append("%s 的 tag_filter 非法：%s（可选：%s）" % [where, effect.get("tag_filter"), ", ".join(GameConstants.EVENT_FILTER_TAGS)])
	elif op == GameConstants.EVENT_OP_UPGRADE_CARD:
		if effect.has("type_filter") and not CARD_TYPES.has(String(effect.get("type_filter", ""))):
			problems.append("%s 的 type_filter 非法：%s（可选：%s）" % [where, effect.get("type_filter"), ", ".join(CARD_TYPES)])


## 饰品 hook 逐条校验：时点、过滤、限次、字段集合、以及各时点必须写的字段。
func _validate_relic_hooks(relic_id: String, hooks: Variant, problems: PackedStringArray) -> void:
	if typeof(hooks) != TYPE_ARRAY or (hooks as Array).is_empty():
		problems.append("relic %s 的 hooks 必须是非空数组" % relic_id)
		return
	var list: Array = hooks
	for index in range(list.size()):
		var where := "relic %s 的 hook %d" % [relic_id, index]
		if typeof(list[index]) != TYPE_DICTIONARY:
			problems.append("%s 必须是对象" % where)
			continue
		var hook: Dictionary = list[index]
		for raw_key in hook.keys():
			if not HOOK_KNOWN_FIELDS.has(String(raw_key)):
				problems.append("%s 存在未知字段：%s（已知字段：%s）" % [where, raw_key, ", ".join(HOOK_KNOWN_FIELDS)])
		var at := String(hook.get("at", ""))
		if not GameConstants.RELIC_HOOK_POINTS.has(at):
			problems.append("%s 的 at 非法：%s（可选：%s）" % [where, at, ", ".join(GameConstants.RELIC_HOOK_POINTS)])
			continue
		if hook.has("card_type") and not CARD_TYPES.has(String(hook.get("card_type", ""))):
			problems.append("%s 的 card_type 非法：%s" % [where, hook.get("card_type")])
		if hook.has("rounds"):
			var rounds: Variant = hook.get("rounds")
			if not GameConstants.HOOK_ROUND_FILTERED.has(at):
				problems.append("%s 的 rounds 只对 %s 有效" % [where, ", ".join(GameConstants.HOOK_ROUND_FILTERED)])
			elif typeof(rounds) != TYPE_ARRAY or (rounds as Array).is_empty():
				problems.append("%s 的 rounds 必须是非空数组" % where)
			else:
				for raw_round in (rounds as Array):
					if _as_int(raw_round, 0) < 1:
						problems.append("%s 的 rounds 必须都是 ≥ 1 的整数" % where)
		if at == GameConstants.HOOK_SHOP_PRICE:
			var kinds: Variant = hook.get("kinds")
			if typeof(kinds) != TYPE_ARRAY or (kinds as Array).is_empty():
				problems.append("%s 必须写非空的 kinds（%s）" % [where, ", ".join(GameConstants.SHOP_PRICE_KINDS)])
			else:
				for raw_kind in (kinds as Array):
					if not GameConstants.SHOP_PRICE_KINDS.has(String(raw_kind)):
						problems.append("%s 的 kinds 非法：%s" % [where, raw_kind])
			if _as_int(hook.get("multiplier_percent"), 0) < 1:
				problems.append("%s 的 multiplier_percent 必须 ≥ 1（100 = 原价）" % where)
			if not GameConstants.SHOP_PRICE_ROUNDINGS.has(String(hook.get("rounding", ""))):
				problems.append("%s 的 rounding 非法：%s（可选：%s）" % [where, hook.get("rounding"), ", ".join(GameConstants.SHOP_PRICE_ROUNDINGS)])
			for key in ["effects", "limit", "rounds", "card_type", "definition_id"]:
				if hook.has(key):
					problems.append("%s 不接受 %s（shop_price 只作用于报价）" % [where, key])
			continue
		if at == GameConstants.HOOK_COST_QUOTE:
			var discount := _as_int(hook.get("discount"), 0)
			var skip_vitality := bool(hook.get("skip_vitality_cost", false))
			if discount <= 0 and not skip_vitality:
				problems.append("%s 需要 discount ≥ 1 或 skip_vitality_cost=true" % where)
			if hook.has("effects"):
				problems.append("%s 不接受 effects（费用类 hook 只改报价）" % where)
			if not hook.has("limit"):
				problems.append("%s 必须写 limit（《统一设计文档》§8：所有「首次」都有明确周期）" % where)
			if skip_vitality and not hook.has("definition_id"):
				problems.append("%s 的 skip_vitality_cost 必须同时写 definition_id（写清哪张牌免支付）" % where)
			if not hook.has("card_type") and not hook.has("definition_id"):
				problems.append("%s 必须写 card_type 或 definition_id（写清作用对象，避免无差别减免）" % where)
			continue
		# round_start / draw / card_resolved：靠 effects 生效
		var effects: Variant = hook.get("effects")
		if typeof(effects) != TYPE_ARRAY or (effects as Array).is_empty():
			problems.append("%s 必须写非空 effects" % where)
		else:
			_validate_effect_list(effects, "%s.effects" % where, problems)
		if hook.has("discount") or hook.has("skip_vitality_cost"):
			problems.append("%s 的 discount/skip_vitality_cost 只对 cost_quote 有效" % where)
		if hook.has("limit"):
			_validate_limit(hook.get("limit"), where, problems)


## 只对清单里已启用的 event 做引用校验（与其它 kind 一致）：未启用的事件允许引用尚未落地的定义。
func _check_event_references_enabled(problems: PackedStringArray) -> void:
	if not _enabled.has(GameConstants.KIND_EVENT):
		return
	var events: Dictionary = _definitions.get(GameConstants.KIND_EVENT, {})
	for id in (_enabled[GameConstants.KIND_EVENT] as Dictionary).keys():
		var definition: Dictionary = events[id]
		for raw_option in (definition.get("options", []) as Array):
			var option: Dictionary = raw_option
			for raw_effect in (option.get("effects", []) as Array):
				var effect: Dictionary = raw_effect
				var op := String(effect.get("op", ""))
				if op == GameConstants.EVENT_OP_GAIN_CARD:
					for card_id in (effect.get("card_pool", []) as Array):
						_require(GameConstants.KIND_CARD, String(card_id), "event %s 的显式卡池" % id, problems)
				elif op == GameConstants.EVENT_OP_GAIN_RELIC:
					var relic_id := String(effect.get("relic_id", ""))
					if not relic_id.is_empty():
						_require(GameConstants.KIND_RELIC, relic_id, "event %s 指定的饰品" % id, problems)
