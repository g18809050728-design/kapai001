class_name BattleState
extends RefCounted
##
## 战斗状态数据容器。对应规格 §10「推荐数据与逻辑边界」中的 BattleState / 各 Instance 字段。
## 纯数据，不含规则；所有变更由 BattleEngine 负责。
##

const T = preload("res://src/core/battle_types.gd")

# ── 战斗元信息 ─────────────────────────────────────────────
var battle_id: String = ""
var rng_seed: int = 0
var phase: int = T.Phase.IDLE
var turn: int = 0
var result: int = T.Result.NONE

# ── 玩家 ───────────────────────────────────────────────────
var player_max_hp: int = T.PLAYER_MAX_HP
var player_hp: int = T.PLAYER_MAX_HP
var player_shield: int = 0
var energy: int = 0
var max_energy: int = T.MAX_ENERGY

# ── 卡牌区域（§6.3：各区互斥，同一实例只能位于一个区域）──────
## instance_id -> {"def_id": String, "zone": int}
var instances: Dictionary = {}
var draw_pile: Array[int] = []
var hand: Array[int] = []
var discard_pile: Array[int] = []
var resolve_zone: Array[int] = []
var _next_instance_id: int = 1

# ── 玩家场上 ───────────────────────────────────────────────
## 随从：[{"card_instance": int, "slot": int, "attack": int, "hp": int,
##          "max_hp": int, "taunt": bool, "can_attack": bool}]
var minions: Array = []
## 场景：{"card_instance": int, "effect_id": String, "triggers": int}；空字典表示无场景
var scene: Dictionary = {}

## 本回合已成功使用的攻击牌数（§6.2 步骤 1 清零，§7 追击读取）
var attacks_played_this_turn: int = 0

# ── 敌人 ───────────────────────────────────────────────────
var enemy_def_id: String = ""
var enemy_name: String = ""
var enemy_max_hp: int = 0
var enemy_hp: int = 0
var enemy_shield: int = 0
var enemy_cursor: int = 0
## 已公开的意图，展示后锁定：{"kind": int, "value": int}
var enemy_intent: Dictionary = {}

# ── 记录与日志 ─────────────────────────────────────────────
var log_lines: Array[String] = []


# ══ 卡牌实例辅助 ═══════════════════════════════════════════

func create_instance(def_id: String, zone: int) -> int:
	var iid := _next_instance_id
	_next_instance_id += 1
	instances[iid] = {"def_id": def_id, "zone": zone}
	return iid


func def_id_of(instance_id: int) -> String:
	var rec: Dictionary = instances.get(instance_id, {})
	return rec.get("def_id", "")


func zone_of(instance_id: int) -> int:
	var rec: Dictionary = instances.get(instance_id, {})
	return rec.get("zone", -1)


## 移动卡牌实例到目标区域。调用方负责把 id 从旧区域的数组里移除。
func set_zone(instance_id: int, zone: int) -> void:
	if instances.has(instance_id):
		instances[instance_id]["zone"] = zone


func hand_def_ids() -> Array:
	var out: Array = []
	for iid in hand:
		out.append(def_id_of(iid))
	return out


func find_in_hand(def_id: String) -> int:
	for iid in hand:
		if def_id_of(iid) == def_id:
			return iid
	return -1


func find_in_draw(def_id: String) -> int:
	for iid in draw_pile:
		if def_id_of(iid) == def_id:
			return iid
	return -1


func living_minions() -> Array:
	var out: Array = []
	for m in minions:
		if int(m["hp"]) > 0:
			out.append(m)
	return out


## 按槽位从左到右排序后的存活随从（§5.2 / §6.7：自动攻击与嘲讽都按槽位顺序）。
func living_minions_ordered() -> Array:
	var out := living_minions()
	out.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	return out


func leftmost_taunt_minion() -> Dictionary:
	for m in living_minions_ordered():
		if bool(m["taunt"]):
			return m
	return {}


func free_minion_slots() -> Array:
	var used: Array = []
	for m in living_minions():
		used.append(int(m["slot"]))
	var out: Array = []
	for s in range(T.MINION_SLOTS):
		if not used.has(s):
			out.append(s)
	return out


func minion_at_slot(slot: int) -> Dictionary:
	for m in minions:
		if int(m["slot"]) == slot:
			return m
	return {}


func battle_over() -> bool:
	return result != T.Result.NONE
