class_name BattleTypes
extends RefCounted
##
## 战斗公共类型与常量（纯数据，不依赖任何场景节点）。
## 对应规格：§6.1 初始状态、§6.5 能量规则、§10 推荐数据与逻辑边界。
##

## 卡牌类型（§7：攻击、防御、技能、场景、随从五类）。
enum CardType { ATTACK, DEFENSE, SKILL, SCENE, MINION }

## 目标类型。
enum TargetType { SINGLE_ENEMY, SELF, NONE, SCENE_SLOT, MINION_SLOT }

## 卡牌实例所在区域（§6.3：各区互斥，同一实例只能位于一个区域）。
enum Zone { DRAW_PILE, HAND, DISCARD, RESOLVE, MINION_FIELD, SCENE_FIELD }

## 战斗状态机（§10.1）。
enum Phase {
	IDLE,
	PLAYER_TURN_START,
	PLAYER_ACTION,
	KEEP_SELECT,
	MINION_ATTACK,
	ENEMY_PHASE,
	BATTLE_END,
}

## 终局结果（§6.9）。
enum Result { NONE, VICTORY, DEFEAT }

## 敌方意图种类（§8.1）。
enum IntentKind { ATTACK, DEFEND }

## 承受伤害 / 造成伤害的主体。
enum Side { PLAYER, ENEMY, MINION }

## 数值上限与初始值。
const MAX_ENERGY := 10
const MAX_HAND := 10
const MINION_SLOTS := 2
const DRAW_PER_TURN := 5
const PLAYER_MAX_HP := 60
const GOLEM_MAX_HP := 35
const SCENE_SPRING_TRIGGERS := 3

## 卡牌类型的显示名（§4.1：同时显示类型文字，避免仅依赖颜色区分）。
const CARD_TYPE_NAME := {
	CardType.ATTACK: "攻击",
	CardType.DEFENSE: "防御",
	CardType.SKILL: "技能",
	CardType.SCENE: "场景",
	CardType.MINION: "随从",
}

## 区域显示名。
const ZONE_NAME := {
	Zone.DRAW_PILE: "抽牌堆",
	Zone.HAND: "手牌",
	Zone.DISCARD: "弃牌堆",
	Zone.RESOLVE: "结算区",
	Zone.MINION_FIELD: "随从区",
	Zone.SCENE_FIELD: "场景区",
}

## 战斗事件类型。规则层只产生事件，界面负责播放（§10：规则执行返回有序事件供界面播放）。
const EV_BATTLE_STARTED := "battle_started"
const EV_TURN_STARTED := "turn_started"
const EV_PHASE_CHANGED := "phase_changed"
const EV_SHIELD_CLEARED := "shield_cleared"
const EV_ENERGY_CHANGED := "energy_changed"
const EV_CARDS_DRAWN := "cards_drawn"
const EV_CARD_MOVED := "card_moved"
const EV_CARD_PLAYED := "card_played"
const EV_CARD_GAINED_ENERGY := "card_gained_energy"
const EV_DAMAGE := "damage"
const EV_SHIELD_GAINED := "shield_gained"
const EV_MINION_SUMMONED := "minion_summoned"
const EV_MINION_ATTACKED := "minion_attacked"
const EV_MINION_DIED := "minion_died"
const EV_SCENE_PLAYED := "scene_played"
const EV_SCENE_TRIGGERED := "scene_triggered"
const EV_SCENE_EXPIRED := "scene_expired"
const EV_INTENT_REVEALED := "intent_revealed"
const EV_INTENT_TARGET_CHANGED := "intent_target_changed"
const EV_ENEMY_ACTED := "enemy_acted"
const EV_ATTACK_CARD_USED := "attack_card_used"
const EV_BATTLE_ENDED := "battle_ended"
const EV_LOG := "log"
