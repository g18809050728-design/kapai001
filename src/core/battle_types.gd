class_name BattleTypes
extends RefCounted
##
## 战斗公共类型与常量（纯数据，不依赖任何场景节点）。
## 对应规格：§6.1 初始状态、§6.5 能量规则、§10 推荐数据与逻辑边界。
##
## 新体系（《设计元素表》「点数与融牌规则」R01~R24、「获取与使用」A01~A21）在这里补充：
## 点数、三类相邻点数关系、融牌与临时衍生牌相关的常量与事件。
##

## 卡牌类型（§7：攻击、防御、技能、场景、随从五类）。
enum CardType { ATTACK, DEFENSE, SKILL, SCENE, MINION }

## 目标类型。
## OTHER_HAND / READY_MINION 是新体系特殊功能牌的目标（调律、映片、指令、短令）。
enum TargetType { SINGLE_ENEMY, SELF, NONE, SCENE_SLOT, MINION_SLOT, OTHER_HAND, READY_MINION }

## 卡牌实例所在区域（§6.3：各区互斥，同一实例只能位于一个区域）。
## RECALL_WAIT 待回收区（S05）、EXILED 临时牌离场（A10）为新体系区域。
## 融牌是「把手牌弃进弃牌堆」，不新增中间区域。
enum Zone {
        DRAW_PILE,
        HAND,
        DISCARD,
        RESOLVE,
        MINION_FIELD,
        SCENE_FIELD,
        RECALL_WAIT,
        EXILED,
}

## 相邻点数关系（R05~R13）：一次相邻比较最多命中其中一类。
enum ChainRelation { NONE, MULTIPLE, FACTOR, SAME }

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

# ── 新体系常量（点数与融牌）────────────────────────────────
## 每张卡的点数范围（R04：1~10，与费用独立）。
const POINTS_MIN := 1
const POINTS_MAX := 10
## R02：融一张牌获得的能量（首轮建议值，与点数无关）。
const FUSION_ENERGY := 1
## R14：累计点数的原型阈值。设计表明确「12 只是示例，不是已确认数值」。
const POINTS_THRESHOLD := 12
## R14 默认累计奖励（设计表：无场景指定时的基础奖励建议）。
const CUMULATIVE_EXTRA_DRAW := 1
## 封存（S03）额外保留上限。
const MAX_EXTRA_KEEP := 2

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
        Zone.RECALL_WAIT: "待回收区",
        Zone.EXILED: "离场区",
}

## 相邻关系的显示名。
const CHAIN_NAME := {
        ChainRelation.NONE: "无关系",
        ChainRelation.MULTIPLE: "倍数",
        ChainRelation.FACTOR: "因数",
        ChainRelation.SAME: "同点",
}

## 战斗事件类型。规则层只产生事件，界面负责播放（§10）。
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
const EV_BATTLE_ENDED := "battle_ended"
const EV_LOG := "log"

# ── 新体系事件 ─────────────────────────────────────────────
## 融牌（M21）：把手牌弃进弃牌堆；不算出牌、不计点、不改变上一张。
const EV_CARD_FUSED := "card_fused"
## 点数与三类相邻链（M22~M28）。
const EV_POINTS_TOTAL_CHANGED := "points_total_changed"
const EV_CHAIN_UPDATED := "chain_updated"
const EV_CUMULATIVE_TRIGGERED := "cumulative_triggered"
## 手牌点数修正（调律 / 映片，R18：只影响未来出牌）。
const EV_POINT_MODIFIED := "point_modified"
## 临时衍生牌（M31 / A09 / A10）。
const EV_TEMP_CARD_ADDED := "temp_card_added"
const EV_TEMP_CARD_EXPIRED := "temp_card_expired"
const EV_TEMP_CARD_FAILED := "temp_card_failed"
const EV_CARD_EXILED := "card_exiled"
## 场上监听与同名每回合首次触发（M34 / M36）。
const EV_FIRST_TRIGGER := "first_trigger"
const EV_MINION_SHIELD_GAINED := "minion_shield_gained"
const EV_MINION_SHIELD_CLEARED := "minion_shield_cleared"
const EV_MINION_BUFFED := "minion_buffed"
const EV_MINION_HEALED := "minion_healed"
const EV_MINION_COMMANDED := "minion_commanded"
## 检索（S04）：打出后需要玩家从查看的牌里选择一张。
const EV_TUTOR_OPENED := "tutor_opened"
const EV_TUTOR_RESOLVED := "tutor_resolved"