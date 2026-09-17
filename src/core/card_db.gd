class_name CardDB
extends RefCounted
##
## 卡牌配置表。严格对应规格 §7「卡牌配置」的 11 种卡 / 合计 20 张。
##
## 每张卡的效果以「有序原子操作列表」表达（ops），因为规则层按描述顺序执行、
## 且一旦进入终局要停止后续效果（§6.4）。
## 特别注意 §7 的判定说明：
##   - 「攻击牌」是类型判定，技能即使造成伤害也不计入攻击牌次数。
##   - 追击读取本回合「此前」已成功使用的攻击牌数。
##   - 破盾击根据本次伤害结算「前」目标是否有护盾决定伤害。
##

const T = preload("res://src/core/battle_types.gd")

## 原子操作 op 取值：
##   gain_energy   {amount}
##   gain_shield   {amount}
##   damage        {amount, alt?, alt_when?}   alt_when: "target_has_shield" | "attacked_this_turn"
##   draw          {amount}
##   summon        {attack, hp, taunt}
##   scene_spring  {triggers}
const OP_GAIN_ENERGY := "gain_energy"
const OP_GAIN_SHIELD := "gain_shield"
const OP_DAMAGE := "damage"
const OP_DRAW := "draw"
const OP_SUMMON := "summon"
const OP_SCENE_SPRING := "scene_spring"

const CARDS := {
	"slash": {
		"id": "slash",
		"name": "斩击",
		"type": T.CardType.ATTACK,
		"cost": 0,
		"target": T.TargetType.SINGLE_ENEMY,
		"desc": "获得 1 能量，然后造成 5 伤害",
		"count": 4,
		"ops": [
			{"op": OP_GAIN_ENERGY, "amount": 1},
			{"op": OP_DAMAGE, "amount": 5},
		],
	},
	"shield_break": {
		"id": "shield_break",
		"name": "破盾击",
		"type": T.CardType.ATTACK,
		"cost": 0,
		"target": T.TargetType.SINGLE_ENEMY,
		"desc": "获得 1 能量，然后造成 3 伤害；目标有护盾时改为 7",
		"count": 1,
		"ops": [
			{"op": OP_GAIN_ENERGY, "amount": 1},
			{"op": OP_DAMAGE, "amount": 3, "alt": 7, "alt_when": "target_has_shield"},
		],
	},
	"follow_up": {
		"id": "follow_up",
		"name": "追击",
		"type": T.CardType.ATTACK,
		"cost": 0,
		"target": T.TargetType.SINGLE_ENEMY,
		"desc": "获得 1 能量，然后造成 3 伤害；此前使用过攻击牌时改为 6",
		"count": 2,
		"ops": [
			{"op": OP_GAIN_ENERGY, "amount": 1},
			{"op": OP_DAMAGE, "amount": 3, "alt": 6, "alt_when": "attacked_this_turn"},
		],
	},
	"block": {
		"id": "block",
		"name": "格挡",
		"type": T.CardType.DEFENSE,
		"cost": 0,
		"target": T.TargetType.SELF,
		"desc": "获得 6 护盾",
		"count": 3,
		"ops": [
			{"op": OP_GAIN_SHIELD, "amount": 6},
		],
	},
	"meditate": {
		"id": "meditate",
		"name": "调息",
		"type": T.CardType.DEFENSE,
		"cost": 0,
		"target": T.TargetType.SELF,
		"desc": "获得 2 护盾和 1 能量",
		"count": 2,
		"ops": [
			{"op": OP_GAIN_SHIELD, "amount": 2},
			{"op": OP_GAIN_ENERGY, "amount": 1},
		],
	},
	"energy_blast": {
		"id": "energy_blast",
		"name": "能量冲击",
		"type": T.CardType.SKILL,
		"cost": 3,
		"target": T.TargetType.SINGLE_ENEMY,
		"desc": "造成 12 伤害",
		"count": 2,
		"ops": [
			{"op": OP_DAMAGE, "amount": 12},
		],
	},
	"counter_stance": {
		"id": "counter_stance",
		"name": "攻守转换",
		"type": T.CardType.SKILL,
		"cost": 2,
		"target": T.TargetType.SINGLE_ENEMY,
		"desc": "造成 5 伤害，然后获得 5 护盾",
		"count": 1,
		"ops": [
			{"op": OP_DAMAGE, "amount": 5},
			{"op": OP_GAIN_SHIELD, "amount": 5},
		],
	},
	"tactical_draw": {
		"id": "tactical_draw",
		"name": "战术整理",
		"type": T.CardType.SKILL,
		"cost": 2,
		"target": T.TargetType.NONE,
		"desc": "抽 2 张牌",
		"count": 1,
		"ops": [
			{"op": OP_DRAW, "amount": 2},
		],
	},
	"energy_spring": {
		"id": "energy_spring",
		"name": "能量涌泉",
		"type": T.CardType.SCENE,
		"cost": 2,
		"target": T.TargetType.SCENE_SLOT,
		"desc": "接下来 3 个玩家回合开始时额外获得 1 能量",
		"count": 1,
		"ops": [
			{"op": OP_SCENE_SPRING, "triggers": T.SCENE_SPRING_TRIGGERS},
		],
	},
	"striker": {
		"id": "striker",
		"name": "突击兵",
		"type": T.CardType.MINION,
		"cost": 2,
		"target": T.TargetType.MINION_SLOT,
		"desc": "召唤 3 攻击 / 4 生命随从",
		"count": 1,
		"ops": [
			{"op": OP_SUMMON, "attack": 3, "hp": 4, "taunt": false},
		],
	},
	"guardian": {
		"id": "guardian",
		"name": "守卫",
		"type": T.CardType.MINION,
		"cost": 3,
		"target": T.TargetType.MINION_SLOT,
		"desc": "召唤 2 攻击 / 7 生命嘲讽随从",
		"count": 2,
		"ops": [
			{"op": OP_SUMMON, "attack": 2, "hp": 7, "taunt": true},
		],
	},
}

## 效果的显示名，用于场景牌等持续效果展示。
const EFFECT_NAME := {
	"energy_spring": "能量涌泉",
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


static func is_attack_card(def_id: String) -> bool:
	return card_type(def_id) == T.CardType.ATTACK


## 展开「初始数量」得到固定 20 张牌组（顺序固定，洗牌由规则层用随机种子完成）。
static func initial_deck() -> Array:
	var deck: Array = []
	# 按 CARDS 的声明顺序展开，保证每次重新挑战使用同一副牌。
	for def_id in CARDS.keys():
		var c: Dictionary = CARDS[def_id]
		for _i in range(int(c.get("count", 0))):
			deck.append(def_id)
	return deck


static func total_card_count() -> int:
	var n := 0
	for def_id in CARDS.keys():
		n += int(CARDS[def_id].get("count", 0))
	return n
