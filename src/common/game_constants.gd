class_name GameConstants
extends RefCounted
## Stable identifiers only. Tunable values live in data/definitions/rulesets.json.

const RULESETS_PATH: String = "res://data/definitions/rulesets.json"
const RULESET_SCHEMA_VERSION: int = 1

const DIFFICULTY_RELAXED: String = "relaxed"
const DIFFICULTY_NORMAL: String = "normal"
const DIFFICULTY_HARD: String = "hard"
const MANIFEST_MVP: String = "mvp"
const MANIFEST_FULL: String = "full"

const CARD_WORK: String = "work"
const CARD_STRATEGY: String = "strategy"
const CARD_ABILITY: String = "ability"
const CARD_COOPERATION: String = "cooperation"
const CARD_SCENE: String = "scene"
const RARITY_WHITE: String = "white"
const RARITY_BLUE: String = "blue"
const RARITY_PURPLE: String = "purple"
const RARITY_GOLD: String = "gold"
const TAG_BASIC: String = "basic"
const TAG_SPECIAL: String = "special"
const TAG_TEMPORARY: String = "temporary"
const AVAILABILITY_STARTER: String = "starter"

const PHASE_INITIALIZING: String = "initializing"
const PHASE_PLAYER_PREPARE: String = "player_prepare"
const PHASE_DRAW: String = "draw"
const PHASE_PLAYER_ACTION: String = "player_action"
const PHASE_ALLY_ACTION: String = "ally_action"
const PHASE_DISCARD: String = "discard"
const PHASE_ENEMY_PREPARE: String = "enemy_prepare"
const PHASE_ENEMY_SKILL: String = "enemy_skill"
const PHASE_ENEMY_PRESSURE: String = "enemy_pressure"
const PHASE_ROUND_END: String = "round_end"
const PHASE_AWAITING_CHOICE: String = "awaiting_choice"
const PHASE_FINISHED: String = "finished"

const SCREEN_MENU: String = "menu"
const SCREEN_MAP: String = "map"
const SCREEN_BATTLE: String = "battle"
const SCREEN_REWARD: String = "reward"
const SCREEN_SHOP: String = "shop"
const SCREEN_EVENT: String = "event"
const SCREEN_REST: String = "rest"
const SCREEN_TERM: String = "term"
const SCREEN_ENDING: String = "ending"
const SCREEN_SUMMARY: String = "summary"

const ACTION_PLAY_CARD: String = "play_card"
const ACTION_CONFIRM_CHOICE: String = "confirm_choice"
const ACTION_SET_ALLY_TARGET: String = "set_ally_target"
const ACTION_END_TURN: String = "end_turn"
const ACTION_ENTER_NODE: String = "enter_node"
const ACTION_CLAIM_REWARD: String = "claim_reward"
const ACTION_SKIP_REWARD: String = "skip_reward"
const ACTION_BUY_ITEM: String = "buy_item"
const ACTION_REMOVE_CARD: String = "remove_card"
const ACTION_CHOOSE_EVENT: String = "choose_event"
const ACTION_TAKE_REST: String = "take_rest"
const ACTION_LEAVE_NODE: String = "leave_node"
const ACTION_CHOOSE_TERM_OPTION: String = "choose_term_option"
const ACTION_CHOOSE_ENDING: String = "choose_ending"
const ACTION_ABANDON_RUN: String = "abandon_run"

const EXAM_INDEPENDENT_ANSWER: String = "independent_answer"
const EXAM_FIXED_ROOM: String = "fixed_exam_room"
const ZONE_DRAW: String = "draw"
const ZONE_HAND: String = "hand"
const ZONE_DISCARD: String = "discard"
const ZONE_EXHAUST: String = "exhaust"
const ZONE_RESOLVING: String = "resolving"

const STATUS_INSPIRATION: String = "inspiration"
const STATUS_COMPILE: String = "compile"
const STATUS_EXPERIMENT_DATA: String = "experiment_data"
const STATUS_CITATION: String = "citation"
const STATUS_REVIEW: String = "review"
const STATUS_FLOW: String = "flow"
const STATUS_ANXIETY: String = "anxiety"
const STATUS_PROCRASTINATION: String = "procrastination"
const STATUS_DROWSINESS: String = "drowsiness"
const STATUS_GUARD: String = "guard"
const STATUS_EXTRA_REQUIREMENTS: String = "extra_requirements"
const STATUS_PLAGIARISM_SHIELD: String = "plagiarism_shield"

const RNG_MAP: String = "map"
const RNG_REWARD: String = "reward"
const RNG_EVENT: String = "event"
const RNG_BATTLE: String = "battle"
const SAVE_CURRENT_RUN: String = "current_run"
const SAVE_PROFILE: String = "profile"
const SAVE_SETTINGS: String = "settings"
const PERSISTENCE_NOT_ATTEMPTED: String = "not_attempted"
const PERSISTENCE_SAVED: String = "saved"
const PERSISTENCE_FAILED: String = "failed"
const OUTCOME_WON: String = "won"
const OUTCOME_LOST: String = "lost"
const OUTCOME_ABANDONED: String = "abandoned"
const REASON_VITALITY_DEPLETED: String = "vitality_depleted"
const REASON_DEADLINE_EXPIRED: String = "deadline_expired"

const ERROR_INVALID_ARGUMENT: String = "INVALID_ARGUMENT"
const ERROR_RUN_ACTIVE: String = "RUN_ACTIVE"
const ERROR_RUN_NOT_FOUND: String = "RUN_NOT_FOUND"
const ERROR_STALE_STATE: String = "STALE_STATE"
const ERROR_WRONG_PHASE: String = "WRONG_PHASE"
const ERROR_INVALID_TARGET: String = "INVALID_TARGET"
const ERROR_INSUFFICIENT_RESOURCE: String = "INSUFFICIENT_RESOURCE"
const ERROR_LIMIT_REACHED: String = "LIMIT_REACHED"
const ERROR_CHOICE_PENDING: String = "CHOICE_PENDING"
const ERROR_ALREADY_RESOLVED: String = "ALREADY_RESOLVED"
const ERROR_CONTENT_INVALID: String = "CONTENT_INVALID"
const ERROR_SAVE_NOT_FOUND: String = "SAVE_NOT_FOUND"
const ERROR_SAVE_CORRUPT: String = "SAVE_CORRUPT"
const ERROR_VERSION_MISMATCH: String = "VERSION_MISMATCH"
const ERROR_SAVE_IO_ERROR: String = "SAVE_IO_ERROR"
const ERROR_RESOLUTION_ERROR: String = "RESOLUTION_ERROR"

# ── 内容类别（kind，《接口文档》§6）─────────────────────────
const KIND_CHARACTER: String = "character"
const KIND_CARD: String = "card"
const KIND_UNIT: String = "unit"
const KIND_SCENE: String = "scene"
const KIND_RELIC: String = "relic"
const KIND_STATUS: String = "status"
const KIND_TASK: String = "task"
const KIND_ENCOUNTER: String = "encounter"
const KIND_EVENT: String = "event"
const KIND_RULESET: String = "ruleset"

# ── 卡牌目标类型 ──────────────────────────────────────────
const TARGET_SELF: String = "self"
const TARGET_TASK: String = "task"
const TARGET_UNIT: String = "unit"
const TARGET_HAND_CARD: String = "hand_card"
const TARGET_DISCARD_CARD: String = "discard_card"

# ── 效果 op（内容 JSON 的唯一写法）────────────────────────
const OP_COMPLETE: String = "complete"
const OP_RELAX: String = "relax"
const OP_DRAW: String = "draw"
const OP_DISCARD: String = "discard"
const OP_GAIN_STATUS: String = "gain_status"
const OP_WORK_FLAT_BONUS: String = "work_flat_bonus"
const OP_SUMMON_UNIT: String = "summon_unit"
const OP_ESTABLISH_SCENE: String = "establish_scene"
const OP_RESTORE_WORK: String = "restore_work"
const OP_PRESSURE: String = "pressure"
const OP_GAIN_FOCUS: String = "gain_focus"
const OP_HEAL: String = "heal"
const OP_LOSE_VITALITY: String = "lose_vitality"
const OP_REMOVE_STATUS: String = "remove_status"

# ── 触发计数周期（BattleState.counter_key 的 scope）─────────
const COUNTER_SCOPE_ROUND: String = "round"
const COUNTER_SCOPE_INSTANCE_ROUND: String = "instance_round"
const COUNTER_SCOPE_BATTLE: String = "battle"

# ── 考试替代面 ────────────────────────────────────────────
const EXAM_FACE_PREPARE: String = "prepare"
const EXAM_FACE_RECALL: String = "recall"

# ── 战斗结局原因 ──────────────────────────────────────────
const REASON_TASKS_COMPLETED: String = "tasks_completed"

# ── 事件 op（权威实现在 src/run/run_service.gd 的 EVENT_OPS；此处供内容层校验）──
const EVENT_OP_GAIN_MONEY: String = "gain_money"
const EVENT_OP_HEAL: String = "heal"
const EVENT_OP_LOSE_VITALITY: String = "lose_vitality"
const EVENT_OP_GAIN_CARD: String = "gain_card"
const EVENT_OP_GAIN_RELIC: String = "gain_relic"
const EVENT_OP_UPGRADE_CARD: String = "upgrade_card"
const EVENT_OP_REMOVE_CARD: String = "remove_card"
const EVENT_OP_CAREER: String = "career"


# ── 效果 op（增量，步骤 4：卡牌 op 与条件系统）────────────
const OP_RECALL_FROM_DISCARD: String = "recall_from_discard"
const OP_RETAIN_HAND_CARD: String = "retain_hand_card"

# ── 效果内选择种类（ChoiceRequest.kind）───────────────────
const CHOICE_DISCARD: String = "discard"
const CHOICE_RECALL: String = "recall"
const CHOICE_PURIFY: String = "purify"

# ── 可净化负面状态（《统一设计文档》§3.6「可净化」列）─────
## 净化未指定状态时由玩家选焦虑/拖延/困倦之一，移除指定层数；
## 无状态仍可执行卡牌其余部分（同段 §3.6 文末约定）。
const STATUS_CATEGORY_NEGATIVE: String = "negative"
const NEGATIVE_STATUS_IDS: Array[String] = [
        STATUS_ANXIETY,
        STATUS_PROCRASTINATION,
        STATUS_DROWSINESS,
]

# ── 引擎内部触发键（不是对外协议；测试引用同一常量防漂移）──
const COUNTER_OWNER_PLAYED_PREFIX: String = "played:"
const COUNTER_TRIGGER_PLAYED: String = "played"
const COUNTER_OWNER_RETAIN: String = "effect:retain_hand_card"
const COUNTER_TRIGGER_RETAIN: String = "granted"

# ── 不可打出（X01 等临时/特殊牌）──────────────────────────
const ERROR_UNPLAYABLE: String = "UNPLAYABLE"

# ── 引擎已接线的状态（内容可安全使用）──────────────────────
## 「已接线」= 引擎真有代码在结算它：到期时点 + 至少一处数值读取。
## 未列出的状态（当前只有 plagiarism_shield：缺「屏障吸收完成量」结算）会被 ContentDB
## 加载期拒绝——宁可加载失败，也不要静默无效（与 [ENG-003] 同一条纪律）。
## 新增状态时必须同时补接线与本表，否则内容侧写不进去。
const WIRED_STATUS_IDS: Array[String] = [
        STATUS_INSPIRATION,          # 工作牌第一段每层 +completion_per_stack；打出工作牌/轮末清空
        STATUS_COMPILE,              # bonus_if.status 可读；本战保留
        STATUS_EXPERIMENT_DATA,      # bonus_if.status 可读；本战保留
        STATUS_CITATION,             # bonus_if.status 可读；本战保留
        STATUS_REVIEW,               # bonus_if.status 可读；本战保留
        STATUS_FLOW,                 # 工作第一段每层 +completion_per_stack；有层数时回合回能 +focus_bonus_when_present
        STATUS_ANXIETY,              # 准备每层少回 focus_penalty_per_stack 专注，随后清除
        STATUS_PROCRASTINATION,      # 抽牌每层少抽 draw_penalty_per_stack，随后清除
        STATUS_DROWSINESS,           # 工作牌第一段每层 -completion_penalty_per_stack，行动结束清除
        STATUS_EXTRA_REQUIREMENTS,   # 任务每层压力 +pressure_per_stack；可被指定效果移除
        STATUS_GUARD,                # 改向默认单体压力（单位；不给主角/任务加层）
]

# ── 饰品 hook（步骤 4：relics.json 的 hooks[]）──────────────
## hook 时点：引擎真会跑的六个点之一。未列出的 at 会被内容校验直接拒绝。
const HOOK_ROUND_START: String = "round_start"          # 玩家准备（清放松/算专注之后）
const HOOK_DRAW: String = "draw"                        # 抽牌阶段基础抽牌之后
const HOOK_CARD_RESOLVED: String = "card_resolved"      # 一张牌结算完成（进弃牌/消耗堆）之后
const HOOK_COST_QUOTE: String = "cost_quote"            # 出牌费用报价（减免/免除，不消费）
const HOOK_SHOP_PRICE: String = "shop_price"            # 商店报价（RunService/TransactionResolver）
const RELIC_HOOK_POINTS: Array[String] = [
        HOOK_ROUND_START,
        HOOK_DRAW,
        HOOK_CARD_RESOLVED,
        HOOK_COST_QUOTE,
        HOOK_SHOP_PRICE,
]
## 只有这些 hook 点可以挂「回合序号过滤」。
const HOOK_ROUND_FILTERED: Array[String] = [HOOK_ROUND_START, HOOK_DRAW]
const SHOP_PRICE_KINDS: Array[String] = ["card", "relic"]
const SHOP_PRICE_ROUNDINGS: Array[String] = ["ceil", "floor"]
const COUNTER_OWNER_RELIC_HOOK_PREFIX: String = "relic_hook:"
const COUNTER_TRIGGER_HOOK: String = "hook"

# ── 人物被动 trigger（《统一设计文档》§4）──────────────────
## 引擎真会触发的被动时点；未列出的 trigger 在内容校验期被拒（否则只会静默不触发）。
const PASSIVE_TRIGGER_WORK_RESOLVED: String = "work_card_resolved"
const PASSIVE_TRIGGER_COOPERATION_RESOLVED: String = "cooperation_card_resolved"
const PASSIVE_TRIGGERS: Array[String] = [
        PASSIVE_TRIGGER_WORK_RESOLVED,
        PASSIVE_TRIGGER_COOPERATION_RESOLVED,
]

# ── 事件目标过滤（events.json 的 remove_card / upgrade_card）──
const EVENT_FILTER_TAGS: Array[String] = [TAG_BASIC, TAG_SPECIAL, TAG_TEMPORARY]
