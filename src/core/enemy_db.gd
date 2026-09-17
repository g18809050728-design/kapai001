class_name EnemyDB
extends RefCounted
##
## 敌人与遭遇配置。严格对应规格 §8「唯一遭遇：遗迹入口」。
##

const T = preload("res://src/core/battle_types.gd")

## 敌人定义。behaviors 按「行为游标」顺序排列，next 指下一格（循环）。
const ENEMIES := {
	"practice_golem": {
		"id": "practice_golem",
		"name": "练习魔像",
		"max_hp": T.GOLEM_MAX_HP,
		"initial_shield": 0,
		"behaviors": [
			{"kind": T.IntentKind.ATTACK, "value": 6, "next": 1},
			{"kind": T.IntentKind.DEFEND, "value": 8, "next": 2},
			{"kind": T.IntentKind.ATTACK, "value": 10, "next": 0},
		],
	},
}

## 唯一遭遇（§8）。
const ENCOUNTER := {
	"id": "ruins_gate",
	"title": "遗迹入口 · 石制守卫",
	"environment": "昏暗入口、碎石与石柱",
	"enemy_id": "practice_golem",
	"first_turn_hint": "敌人本轮将攻击 6；若手中有格挡，可获得护盾抵消伤害。",
}


static func get_enemy(def_id: String) -> Dictionary:
	return ENEMIES.get(def_id, {})


static func enemy_name(def_id: String) -> String:
	var e: Dictionary = ENEMIES.get(def_id, {})
	return e.get("name", "?")


static func behaviors(def_id: String) -> Array:
	var e: Dictionary = ENEMIES.get(def_id, {})
	return e.get("behaviors", [])


static func encounter() -> Dictionary:
	return ENCOUNTER
