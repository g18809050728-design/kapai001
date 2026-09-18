class_name BattleState
extends RefCounted
##
## 战斗状态数据容器。对应规格 §10「推荐数据与逻辑边界」中的 BattleState / 各 Instance 字段。
## 纯数据，不含规则；所有变更由 BattleEngine 负责。
##
## 新体系（《设计元素表》点数与融牌规则）在此补充：
##   待回收 recall_wait、离场 exiled；
##   上一张点数与三类相邻链层数、回合点数总和、同名每回合首次触发记录；
##   手牌点数修正（点数字段挂在实例上，临时修改不写回历史快照）。
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")

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
## instance_id -> {"def_id": String, "zone": int, "point_mod": int, "temp": bool, "point_override": int}
var instances: Dictionary = {}
var draw_pile: Array[int] = []
var hand: Array[int] = []
var discard_pile: Array[int] = []
var resolve_zone: Array[int] = []
## 待回收区（S05 / SC03）：下回合开始时加入手牌
var recall_wait: Array[int] = []
## 离场区（A10）：临时衍生牌用后或回合结束移出战斗，不洗回
var exiled: Array[int] = []
var _next_instance_id: int = 1

# ── 玩家场上 ───────────────────────────────────────────────
## 随从：[{"card_instance": int, "slot": int, "attack": int, "hp": int,
##          "max_hp": int, "shield": int, "taunt": bool, "can_attack": bool}]
var minions: Array = []
## 场景：{"card_instance": int, "effect_id": String, "triggers": int}；空字典表示无场景。
## triggers < 0 表示本战常驻直到被替换（M32 / SC01~SC06）。
var scene: Dictionary = {}

# ── 点数与新体系回合状态（M22~M28）─────────────────────────
## 上一张成功打出的牌的有效点数；0 表示本回合还没有基准。
var last_point: int = 0
## 三类相邻链的连续层数，彼此独立、互不混层（R11）。
var mult_level: int = 0
var factor_level: int = 0
var same_level: int = 0
## 本回合累计点数总和（R14，融牌与自动攻击不计入）。
var points_total: int = 0
## 本回合已触发的累计档位数。
var cumulative_triggers: int = 0
## 累计奖励：下个玩家回合额外抽牌数（无场景指定时的默认奖励）。
var next_turn_extra_draw: int = 0
## 本回合封存带来的额外保留张数（S03）。
var extra_keep: int = 0
## 同名卡每回合首次触发记录（M34）：key -> true，回合开始清空。
var first_used: Dictionary = {}
## 检索（S04）等待玩家选择：{"kind","queue","index","revealed",...}；空表示无待选择。
var pending_choice: Dictionary = {}

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

func create_instance(def_id: String, zone: int, temp: bool = false,
                point_override: int = -1) -> int:
        var iid := _next_instance_id
        _next_instance_id += 1
        var rec := {"def_id": def_id, "zone": zone, "point_mod": 0, "temp": temp}
        if point_override > 0:
                rec["point_override"] = point_override
        instances[iid] = rec
        return iid


func def_id_of(instance_id: int) -> String:
        var rec: Dictionary = instances.get(instance_id, {})
        return rec.get("def_id", "")


func zone_of(instance_id: int) -> int:
        var rec: Dictionary = instances.get(instance_id, {})
        return rec.get("zone", -1)


func set_zone(instance_id: int, zone: int) -> void:
        if instances.has(instance_id):
                instances[instance_id]["zone"] = zone


func record(instance_id: int) -> Dictionary:
        return instances.get(instance_id, {})


## 临时衍生牌判定（牌定义标记或实例标记任一成立）。
func is_temp(instance_id: int) -> bool:
        var rec: Dictionary = instances.get(instance_id, {})
        if rec.is_empty():
                return false
        return bool(rec.get("temp", false)) or CardDB.is_temp(String(rec.get("def_id", "")))


## 实例的有效点数（R04 / R18）：原始点数 + 本回合临时修正，夹在 1~10。
func effective_points(instance_id: int) -> int:
        var rec: Dictionary = instances.get(instance_id, {})
        if rec.is_empty():
                return 0
        return effective_points_of(rec)


func effective_points_of(rec: Dictionary) -> int:
        var base := CardDB.card_points(String(rec.get("def_id", "")))
        if rec.has("point_override"):
                base = int(rec["point_override"])
        var v := base + int(rec.get("point_mod", 0))
        return clampi(v, T.POINTS_MIN, T.POINTS_MAX)


## 本回合临时点数修正（离开手牌 / 回合结束时清除，R18：不追溯已出牌记录）。
func clear_point_modifiers() -> void:
        for iid in instances.keys():
                instances[iid]["point_mod"] = 0


## 回合开始清空组合状态（R12：新回合清空上一张与各链层数）。
func reset_turn_chain() -> void:
        last_point = 0
        mult_level = 0
        factor_level = 0
        same_level = 0
        points_total = 0
        cumulative_triggers = 0
        extra_keep = 0
        first_used.clear()


func chain_level(relation: int) -> int:
        if relation == T.ChainRelation.MULTIPLE:
                return mult_level
        if relation == T.ChainRelation.FACTOR:
                return factor_level
        if relation == T.ChainRelation.SAME:
                return same_level
        return 0


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


## 按槽位从左到右排序后的存活随从（§5.2 / §6.7）。
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


## 已就绪且本轮尚未攻击的仆从（S07 指令 / 短令的合法目标）。
func ready_minions() -> Array:
        var out: Array = []
        for m in living_minions_ordered():
                if bool(m["can_attack"]):
                        out.append(m)
        return out


func ready_minion_slots() -> Array:
        var out: Array = []
        for m in ready_minions():
                out.append(int(m["slot"]))
        return out


## 受伤的存活仆从（MN08 修补匠的治疗目标）。
func wounded_minions() -> Array:
        var out: Array = []
        for m in living_minions_ordered():
                if int(m["hp"]) < int(m["max_hp"]):
                        out.append(m)
        return out


func battle_over() -> bool:
        return result != T.Result.NONE


## 同名每回合首次触发（M34）：同名卡全队共享，回合开始重置。
func try_first_trigger(def_id: String, key: String) -> bool:
        var k := "%s|%s" % [def_id, key]
        if first_used.has(k):
                return false
        first_used[k] = true
        return true

