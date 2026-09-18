class_name CardDB
extends RefCounted
##
## 卡牌配置表（点数与融牌新体系）。
##
## 与旧版的差异（《设计元素表》「点数与融牌规则」R01~R24、「卡牌重构」）：
##   · 每张牌有 1~10 点，点数与费用独立；点数只参与相邻关系与累计点数（R04）。
##   · 攻击牌不再自带回能，能量改由融牌提供（R01、M02）。
##   · 即时牌分别配置倍数／因数／同点三套强化（chain），只读取本次命中的那一类层数（R06~R11）。
##   · 追击改用「本次是否为倍数关系」判定（M19），不再统计本回合攻击牌次数。
##   · 场景牌走统一 scene 字段；仆从／场景可配置场上监听 monitor（M33、M36）。
##   · 临时衍生牌（echo_slip / short_order）不进主牌组，不可融、不可保留（M31）。
##
## 数值状态：点数为设计表首版建议；三套强化曲线在 v0.3 中明确「尚未全部定稿」，
## 此处给出可测试的首版曲线，均为原型数值，不是已平衡数值。
##

const T = preload("res://src/core/battle_types.gd")

## 原子操作 op 取值：
##   gain_energy   {amount}
##   gain_shield   {amount}
##   damage        {amount, alt?, alt_when?}   alt_when: "target_has_shield" | "mult_relation"
##   draw          {amount}
##   summon        {attack, hp, taunt}
##   scene         {effect_id, triggers?}      triggers = -1 表示本战常驻直到替换
##   modify_point  {amount}                    需要 options.hand_target 与 options.point_delta
##   set_point                                 把目标手牌点数改为本牌点数（映片）
##   extra_keep    {amount}
##   tutor         {range, range_add?}         查看牌库顶若干张，选 1 张
##   command       {amount?}                   让一只已就绪仆从立即攻击
##   buff_attack / minion_shield / heal_minion / generate_temp  —— 场上监听专用
const OP_GAIN_ENERGY := "gain_energy"
const OP_GAIN_SHIELD := "gain_shield"
const OP_DAMAGE := "damage"
const OP_DRAW := "draw"
const OP_SUMMON := "summon"
const OP_SCENE := "scene"
const OP_MODIFY_POINT := "modify_point"
const OP_SET_POINT := "set_point"
const OP_EXTRA_KEEP := "extra_keep"
const OP_TUTOR := "tutor"
const OP_COMMAND := "command"
const OP_BUFF_ATTACK := "buff_attack"
const OP_MINION_SHIELD := "minion_shield"
const OP_HEAL_MINION := "heal_minion"
const OP_GENERATE_TEMP := "generate_temp"

## 场上监听的两种事件来源（M36：只监听出牌前已在场的来源）。
const MON_FUSE := "fuse"
const MON_CHAIN := "chain"

const CARDS := {
        # ── 基础即时牌（原型牌组 8 张）────────────────────────────
        "slash": {
                "id": "slash",
                "name": "斩击",
                "type": T.CardType.ATTACK,
                "cost": 0,
                "points": 2,
                "target": T.TargetType.SINGLE_ENEMY,
                "desc": "造成 5 伤害（不再自带回能）",
                "count": 3,
                "ops": [{"op": OP_DAMAGE, "amount": 5}],
                "chain": {
                        "mult": [{"op": OP_DAMAGE, "amount": 2, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 2, "per_level": true}],
                        "same": [{"op": OP_DAMAGE, "amount": 3, "per_level": true}],
                },
        },
        "block": {
                "id": "block",
                "name": "格挡",
                "type": T.CardType.DEFENSE,
                "cost": 0,
                "points": 3,
                "target": T.TargetType.SELF,
                "desc": "获得 6 护盾",
                "count": 2,
                "ops": [{"op": OP_GAIN_SHIELD, "amount": 6}],
                "chain": {
                        "mult": [{"op": OP_GAIN_SHIELD, "amount": 2, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 2, "per_level": true}],
                        "same": [{"op": OP_GAIN_SHIELD, "amount": 3, "per_level": true}],
                },
        },
        "energy_blast": {
                "id": "energy_blast",
                "name": "能量冲击",
                "type": T.CardType.SKILL,
                "cost": 3,
                "points": 6,
                "target": T.TargetType.SINGLE_ENEMY,
                "desc": "造成 12 伤害",
                "count": 2,
                "ops": [{"op": OP_DAMAGE, "amount": 12}],
                "chain": {
                        "mult": [{"op": OP_DAMAGE, "amount": 4, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 4, "per_level": true}],
                        "same": [{"op": OP_DAMAGE, "amount": 6, "per_level": true}],
                },
        },
        "meditate": {
                "id": "meditate",
                "name": "调息",
                "type": T.CardType.DEFENSE,
                "cost": 0,
                "points": 1,
                "target": T.TargetType.SELF,
                "desc": "获得 2 护盾（取消免费回能）",
                "count": 1,
                "ops": [{"op": OP_GAIN_SHIELD, "amount": 2}],
                "chain": {
                        "mult": [{"op": OP_GAIN_SHIELD, "amount": 1, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 1, "per_level": true}],
                        "same": [{"op": OP_GAIN_SHIELD, "amount": 2, "per_level": true}],
                },
        },
        # ── 特殊功能牌（原型牌组 6 张）────────────────────────────
        "tune": {
                "id": "tune",
                "name": "调律",
                "type": T.CardType.SKILL,
                "cost": 1,
                "points": 4,
                "target": T.TargetType.OTHER_HAND,
                "desc": "将另一张手牌的有效点数 +1 或 -1，本回合有效（仍在 1~10 内）",
                "count": 2,
                "ops": [{"op": OP_MODIFY_POINT, "amount": 1}],
                "chain": {
                        "mult": [{"op": OP_MODIFY_POINT, "amount": 1, "per_level": true}],
                        "factor": [{"op": OP_DRAW, "amount": 1, "per_level": true}],
                        "same": [{"op": OP_GAIN_SHIELD, "amount": 3, "per_level": true}],
                },
        },
        "seal": {
                "id": "seal",
                "name": "封存",
                "type": T.CardType.SKILL,
                "cost": 1,
                "points": 3,
                "target": T.TargetType.NONE,
                "desc": "本回合结束时额外保留 1 张手牌；下回合仍正常抽 5 张",
                "count": 1,
                "ops": [{"op": OP_EXTRA_KEEP, "amount": 1}],
                "chain": {
                        "mult": [{"op": OP_DRAW, "amount": 1, "per_level": true}],
                        "factor": [{"op": OP_EXTRA_KEEP, "amount": 1, "per_level": true}],
                        "same": [{"op": OP_GAIN_SHIELD, "amount": 4, "per_level": true}],
                },
        },
        "search": {
                "id": "search",
                "name": "检索",
                "type": T.CardType.SKILL,
                "cost": 1,
                "points": 6,
                "target": T.TargetType.NONE,
                "desc": "查看抽牌堆顶 3 张，选 1 张加入手牌，其余按原顺序置于牌库底",
                "count": 2,
                "ops": [{"op": OP_TUTOR, "range": 3}],
                "chain": {
                        "mult": [{"op": OP_TUTOR, "range_add": 1, "per_level": true}],
                        "factor": [{"op": OP_DRAW, "amount": 1, "per_level": true}],
                        "same": [{"op": OP_GAIN_SHIELD, "amount": 3, "per_level": true}],
                },
        },
        "command": {
                "id": "command",
                "name": "指令",
                "type": T.CardType.SKILL,
                "cost": 1,
                "points": 8,
                "target": T.TargetType.READY_MINION,
                "desc": "让一只已就绪且本轮未攻击的仆从立即攻击（消耗其原回合结束攻击机会）",
                "count": 1,
                "ops": [{"op": OP_COMMAND, "amount": 0}],
                "chain": {
                        "mult": [{"op": OP_COMMAND, "amount": 2, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 3, "per_level": true}],
                        "same": [{"op": OP_DRAW, "amount": 1, "per_level": true}],
                },
        },
        # ── 仆从牌（原型牌组 4 张）────────────────────────────────
        "striker": {
                "id": "striker",
                "name": "突击兵",
                "type": T.CardType.MINION,
                "cost": 2,
                "points": 4,
                "target": T.TargetType.MINION_SLOT,
                "desc": "召唤 3 攻击 / 4 生命随从；每回合首次达到倍数第 2 层时，本轮攻击 +2",
                "count": 1,
                "ops": [{"op": OP_SUMMON, "attack": 3, "hp": 4, "taunt": false}],
                "monitor": {
                        "event": MON_CHAIN,
                        "relation": T.ChainRelation.MULTIPLE,
                        "level": 2,
                        "desc": "倍数第 2 层：本轮攻击 +2",
                        "ops": [{"op": OP_BUFF_ATTACK, "amount": 2}],
                },
                "chain": {},
        },
        "guardian": {
                "id": "guardian",
                "name": "守卫",
                "type": T.CardType.MINION,
                "cost": 3,
                "points": 9,
                "target": T.TargetType.MINION_SLOT,
                "desc": "召唤 2 攻击 / 7 生命嘲讽随从；每回合首次形成同点时本单位获得 3 护盾",
                "count": 1,
                "ops": [{"op": OP_SUMMON, "attack": 2, "hp": 7, "taunt": true}],
                "monitor": {
                        "event": MON_CHAIN,
                        "relation": T.ChainRelation.SAME,
                        "level": 1,
                        "desc": "同点：本单位获得 3 护盾",
                        "ops": [{"op": OP_MINION_SHIELD, "amount": 3}],
                },
                "chain": {},
        },
        "artificer": {
                "id": "artificer",
                "name": "铸能工匠",
                "type": T.CardType.MINION,
                "cost": 2,
                "points": 6,
                "target": T.TargetType.MINION_SLOT,
                "desc": "召唤 1 攻击 / 5 生命随从；每回合首次融实体牌时额外获得 1 能量",
                "count": 1,
                "ops": [{"op": OP_SUMMON, "attack": 1, "hp": 5, "taunt": false}],
                "monitor": {
                        "event": MON_FUSE,
                        "desc": "融牌：额外获得 1 能量",
                        "ops": [{"op": OP_GAIN_ENERGY, "amount": 1}],
                },
                "chain": {},
        },
        "hornist": {
                "id": "hornist",
                "name": "战术号手",
                "type": T.CardType.MINION,
                "cost": 2,
                "points": 4,
                "target": T.TargetType.MINION_SLOT,
                "desc": "召唤 1 攻击 / 5 生命随从；每回合首次形成同点时生成 1 张临时「短令」",
                "count": 1,
                "ops": [{"op": OP_SUMMON, "attack": 1, "hp": 5, "taunt": false}],
                "monitor": {
                        "event": MON_CHAIN,
                        "relation": T.ChainRelation.SAME,
                        "level": 1,
                        "desc": "同点：生成 1 张临时「短令」",
                        "ops": [{"op": OP_GENERATE_TEMP, "def_id": "short_order"}],
                },
                "chain": {},
        },
        # ── 场景牌（原型牌组 2 张）────────────────────────────────
        "mirror_hall": {
                "id": "mirror_hall",
                "name": "镜像回廊",
                "type": T.CardType.SCENE,
                "cost": 2,
                "points": 4,
                "target": T.TargetType.SCENE_SLOT,
                "desc": "场景常驻：每回合首次形成相邻同点时，生成 1 张临时「映片」（点数=触发牌点数）",
                "count": 1,
                "ops": [{"op": OP_SCENE, "effect_id": "mirror_hall", "triggers": -1}],
                "monitor": {
                        "event": MON_CHAIN,
                        "relation": T.ChainRelation.SAME,
                        "level": 1,
                        "desc": "同点：生成 1 张临时「映片」",
                        "ops": [{"op": OP_GENERATE_TEMP, "def_id": "echo_slip", "point_from_trigger": true}],
                },
                "chain": {},
        },
        "charge_matrix": {
                "id": "charge_matrix",
                "name": "蓄能矩阵",
                "type": T.CardType.SCENE,
                "cost": 2,
                "points": 10,
                "target": T.TargetType.SCENE_SLOT,
                "desc": "场景常驻：每回合首次达到倍数第 2 层时获得 1 能量",
                "count": 1,
                "ops": [{"op": OP_SCENE, "effect_id": "charge_matrix", "triggers": -1}],
                "monitor": {
                        "event": MON_CHAIN,
                        "relation": T.ChainRelation.MULTIPLE,
                        "level": 2,
                        "desc": "倍数第 2 层：获得 1 能量",
                        "ops": [{"op": OP_GAIN_ENERGY, "amount": 1}],
                },
                "chain": {},
        },
        # ── 候选池：保留的旧卡，本次不在原型牌组内（count = 0）──────
        "shield_break": {
                "id": "shield_break",
                "name": "破盾击",
                "type": T.CardType.ATTACK,
                "cost": 0,
                "points": 7,
                "target": T.TargetType.SINGLE_ENEMY,
                "desc": "造成 3 伤害；目标在结算前有护盾时改为 7",
                "count": 0,
                "ops": [{"op": OP_DAMAGE, "amount": 3, "alt": 7, "alt_when": "target_has_shield"}],
                "chain": {
                        "mult": [{"op": OP_DAMAGE, "amount": 2, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 3, "per_level": true}],
                        "same": [{"op": OP_DAMAGE, "amount": 3, "per_level": true}],
                },
        },
        "follow_up": {
                "id": "follow_up",
                "name": "追击",
                "type": T.CardType.ATTACK,
                "cost": 0,
                "points": 4,
                "target": T.TargetType.SINGLE_ENEMY,
                "desc": "造成 3 伤害；本次是倍数关系时改为 6（不再统计攻击牌次数）",
                "count": 0,
                "ops": [{"op": OP_DAMAGE, "amount": 3, "alt": 6, "alt_when": "mult_relation"}],
                "chain": {
                        "mult": [{"op": OP_DAMAGE, "amount": 3, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 2, "per_level": true}],
                        "same": [{"op": OP_DAMAGE, "amount": 3, "per_level": true}],
                },
        },
        "counter_stance": {
                "id": "counter_stance",
                "name": "攻守转换",
                "type": T.CardType.SKILL,
                "cost": 2,
                "points": 5,
                "target": T.TargetType.SINGLE_ENEMY,
                "desc": "造成 5 伤害，然后获得 5 护盾",
                "count": 0,
                "ops": [{"op": OP_DAMAGE, "amount": 5}, {"op": OP_GAIN_SHIELD, "amount": 5}],
                "chain": {
                        "mult": [{"op": OP_DAMAGE, "amount": 3, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 3, "per_level": true}],
                        "same": [{"op": OP_DRAW, "amount": 1, "per_level": true}],
                },
        },
        "tactical_draw": {
                "id": "tactical_draw",
                "name": "战术整理",
                "type": T.CardType.SKILL,
                "cost": 2,
                "points": 8,
                "target": T.TargetType.NONE,
                "desc": "抽 2 张牌",
                "count": 0,
                "ops": [{"op": OP_DRAW, "amount": 2}],
                "chain": {
                        "mult": [{"op": OP_DRAW, "amount": 1, "per_level": true}],
                        "factor": [{"op": OP_GAIN_SHIELD, "amount": 3, "per_level": true}],
                        "same": [{"op": OP_DRAW, "amount": 1, "per_level": true}],
                },
        },
        "energy_spring": {
                "id": "energy_spring",
                "name": "能量涌泉",
                "type": T.CardType.SCENE,
                "cost": 2,
                "points": 10,
                "target": T.TargetType.SCENE_SLOT,
                "desc": "接下来 3 个玩家回合开始时额外获得 1 能量（旧版到期式场景）",
                "count": 0,
                "ops": [{"op": OP_SCENE, "effect_id": "energy_spring", "triggers": T.SCENE_SPRING_TRIGGERS}],
                "chain": {},
        },
        # ── 临时衍生牌（M31 / A10：不进主牌组，不可融、不可保留）────
        "echo_slip": {
                "id": "echo_slip",
                "name": "映片",
                "type": T.CardType.SKILL,
                "cost": 1,
                "points": 4,
                "temp": true,
                "target": T.TargetType.OTHER_HAND,
                "desc": "临时牌：将另一张手牌的有效点数改为本牌点数，本回合有效",
                "count": 0,
                "ops": [{"op": OP_SET_POINT}],
                "chain": {},
        },
        "short_order": {
                "id": "short_order",
                "name": "短令",
                "type": T.CardType.SKILL,
                "cost": 1,
                "points": 4,
                "temp": true,
                "target": T.TargetType.READY_MINION,
                "desc": "临时牌：让一只已就绪且本轮未攻击的仆从立即攻击",
                "count": 0,
                "ops": [{"op": OP_COMMAND, "amount": 0}],
                "chain": {},
        },
}

## 效果显示名（场景牌等持续效果展示）。
const EFFECT_NAME := {
        "energy_spring": "能量涌泉",
        "mirror_hall": "镜像回廊",
        "charge_matrix": "蓄能矩阵",
}


static func get_card(def_id: String) -> Dictionary:
        return CARDS.get(def_id, {})


static func has_card(def_id: String) -> bool:
        return CARDS.has(def_id)


static func card_name(def_id: String) -> String:
        var c: Dictionary = CARDS.get(def_id, {})
        return c.get("name", "?")


static func card_type(def_id: String) -> int:
        var c: Dictionary = CARDS.get(def_id, {})
        return c.get("type", -1)


static func card_points(def_id: String) -> int:
        var c: Dictionary = CARDS.get(def_id, {})
        return int(c.get("points", 0))


static func is_attack_card(def_id: String) -> bool:
        return card_type(def_id) == T.CardType.ATTACK


## 临时衍生牌（M31）：不能融牌、不能保留、用后或回合结束移出战斗。
static func is_temp(def_id: String) -> bool:
        var c: Dictionary = CARDS.get(def_id, {})
        return bool(c.get("temp", false))


## 场上监听配置；无监听返回空字典。
static func monitor(def_id: String) -> Dictionary:
        var c: Dictionary = CARDS.get(def_id, {})
        return c.get("monitor", {})


## 指定关系对应的强化 op 列表（未配置返回空数组）。
static func chain_ops(def_id: String, relation: int) -> Array:
        var c: Dictionary = CARDS.get(def_id, {})
        var chain: Dictionary = c.get("chain", {})
        var key := ""
        if relation == T.ChainRelation.MULTIPLE:
                key = "mult"
        elif relation == T.ChainRelation.FACTOR:
                key = "factor"
        elif relation == T.ChainRelation.SAME:
                key = "same"
        if key == "":
                return []
        return chain.get(key, [])


## 把带 per_level 标记的 op 按层数展开成实际数值（R21：不重放，只提高本牌对应效果强度）。
static func scaled_ops(ops: Array, level: int) -> Array:
        var out: Array = []
        for raw in ops:
                var op: Dictionary = (raw as Dictionary).duplicate()
                if bool(op.get("per_level", false)):
                        op.erase("per_level")
                        for k in ["amount", "range_add", "range"]:
                                if op.has(k):
                                        op[k] = int(op[k]) * level
                out.append(op)
        return out


static func op_label(op: Dictionary) -> String:
        var kind := String(op.get("op", ""))
        var n := int(op.get("amount", 0))
        match kind:
                OP_DAMAGE:
                        return "伤害 +%d" % n
                OP_GAIN_SHIELD:
                        return "护盾 +%d" % n
                OP_DRAW:
                        return "抽牌 +%d" % n
                OP_TUTOR:
                        return "多查看 %d 张" % int(op.get("range_add", 0))
                OP_MODIFY_POINT:
                        return "调整幅度 +%d" % n
                OP_EXTRA_KEEP:
                        return "额外保留 +%d" % n
                OP_COMMAND:
                        return "该次攻击 +%d" % n
                OP_GAIN_ENERGY:
                        return "能量 +%d" % n
                OP_MINION_SHIELD:
                        return "仆从护盾 +%d" % n
                OP_BUFF_ATTACK:
                        return "本轮攻击 +%d" % n
                OP_HEAL_MINION:
                        return "恢复 %d 生命" % n
        return kind


## 三类关系的可读摘要（卡面第二行用）。
static func chain_summary(def_id: String) -> String:
        var parts: Array = []
        var pairs := [
                [T.ChainRelation.MULTIPLE, "倍数"],
                [T.ChainRelation.FACTOR, "因数"],
                [T.ChainRelation.SAME, "同点"],
        ]
        for p in pairs:
                var ops := chain_ops(def_id, int(p[0]))
                if ops.is_empty():
                        continue
                var labels: Array = []
                for op in ops:
                        var o: Dictionary = (op as Dictionary).duplicate()
                        o.erase("per_level")
                        labels.append(op_label(o))
                parts.append("%s：%s/层" % [String(p[1]), "、".join(labels)])
        return "  ｜  ".join(parts)


## 展开「初始数量」得到原型牌组（顺序固定，洗牌由规则层用随机种子完成）。
static func initial_deck() -> Array:
        var deck: Array = []
        for def_id in CARDS.keys():
                var c: Dictionary = CARDS[def_id]
                if bool(c.get("temp", false)):
                        continue
                for _i in range(int(c.get("count", 0))):
                        deck.append(def_id)
        return deck


static func total_card_count() -> int:
        var n := 0
        for def_id in CARDS.keys():
                var c: Dictionary = CARDS[def_id]
                if bool(c.get("temp", false)):
                        continue
                n += int(c.get("count", 0))
        return n


## 原型牌组结构统计（M37：8 基础即时 + 6 功能 + 4 仆从 + 2 场景）。
static func deck_structure() -> Dictionary:
        var out := {"instant": 0, "function": 0, "minion": 0, "scene": 0}
        for def_id in initial_deck():
                match card_type(String(def_id)):
                        T.CardType.MINION:
                                out["minion"] = int(out["minion"]) + 1
                        T.CardType.SCENE:
                                out["scene"] = int(out["scene"]) + 1
                        _:
                                if card_points(String(def_id)) > 0 and is_function_card(String(def_id)):
                                        out["function"] = int(out["function"]) + 1
                                else:
                                        out["instant"] = int(out["instant"]) + 1
        return out


## 功能牌判定：带特殊操作（点数修正、额外保留、检索、指令）的即时牌。
static func is_function_card(def_id: String) -> bool:
        for op in get_card(def_id).get("ops", []):
                var kind := String(op.get("op", ""))
                if kind in [OP_MODIFY_POINT, OP_SET_POINT, OP_EXTRA_KEEP, OP_TUTOR, OP_COMMAND]:
                        return true
        return false