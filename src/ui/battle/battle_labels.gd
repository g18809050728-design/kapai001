class_name BattleLabels
extends RefCounted
##
## 战斗界面文案表（src/ui/battle 专用）：只做 key 或 id 到中文的翻译，不参与任何规则计算。
##
## 内容层目前只落了 name_key（如 card.k03.name），工程里还没有本地化文本表；
## 本表是界面层的回落表：命中给中文，未命中回落定义 ID，内容层新增条目时界面不会崩。
## 将来内容层若提供文本表，只需替换 name_of 的实现，调用方不动。
##
## 硬约束：本文件不读取 BattleState 或 RunState，也不做任何数值推导。
## 效果文案只把 face.effects 已有的 op 与数值翻成中文，数值原样照抄。
##

const GameConstants := preload("res://src/common/game_constants.gd")

const NAMES: Dictionary = {
    "card.k01.name": "写",
    "card.k02.name": "暂时休息",
    "card.k03.name": "寻找思路",
    "card.k04.name": "查资料",
    "card.k13.name": "编译",
    "card.k14.name": "打印Hello",
    "card.k43.name": "室友搭把手",
    "card.k44.name": "请教学霸",
    "card.k46.name": "组队分工",
    "card.k51.name": "回到自家",
    "card.k53.name": "找到自习室",
    "card.k56.name": "通宵教室",
    "character.p01.name": "林序·系统拆解者",
    "character.p01.passive": "每回合第 3 张工作牌结算后获得 1 编译，每回合限 1 次",
    "relic.a01.name": "好用的笔",
    "task.n01.name": "课后习题",
    "task.b01.name": "大一上·高数期末",
    "encounter.n01.name": "课后习题",
    "encounter.b01.name": "大一上·高数期末",
    "unit.f01.name": "热心室友",
    "unit.f02.name": "忙碌学霸",
    "unit.f03.name": "耐心助教",
    "unit.f04.name": "可靠组长",
    "unit.f05.name": "实验搭档",
    "unit.f06.name": "写作伙伴",
    "unit.f07.name": "编程学长",
    "unit.f08.name": "社团朋友",
    "scene.l01.name": "自家书桌",
    "scene.l02.name": "宿舍",
    "scene.l03.name": "自习室",
    "scene.l04.name": "实验室",
    "scene.l05.name": "图书馆",
    "scene.l06.name": "通宵教室",
}


const STATUS_NAMES: Dictionary = {
    "inspiration": "灵感",
    "compile": "编译",
    "experiment_data": "实验数据",
    "citation": "引用",
    "review": "复习",
    "flow": "心流",
    "anxiety": "焦虑",
    "procrastination": "拖延",
    "drowsiness": "困倦",
    "guard": "护卫",
    "extra_requirements": "额外要求",
    "plagiarism_shield": "查重护盾",
}


const CARD_TYPE_NAMES: Dictionary = {
    "work": "工作",
    "strategy": "策略",
    "ability": "能力",
    "cooperation": "合作",
    "scene": "场景",
}


const PHASE_NAMES: Dictionary = {
    "initializing": "初始化",
    "player_prepare": "玩家准备",
    "draw": "抽牌",
    "player_action": "玩家行动",
    "ally_action": "合作行动",
    "discard": "弃牌",
    "enemy_prepare": "敌方准备",
    "enemy_skill": "敌方技能",
    "enemy_pressure": "敌方压力",
    "round_end": "回合结束",
    "awaiting_choice": "等待选择",
    "finished": "已结束",
}


const RARITY_NAMES: Dictionary = {
    "white": "白",
    "blue": "蓝",
    "purple": "紫",
    "gold": "金",
}


const EXAM_LIMIT_NAMES: Dictionary = {
    "independent_answer": "独立作答",
    "fixed_exam_room": "固定考场",
}


const OUTCOME_NAMES: Dictionary = {
    "won": "胜利",
    "lost": "失败",
    "abandoned": "放弃",
}


const REASON_NAMES: Dictionary = {
    "tasks_completed": "任务全部完成",
    "vitality_depleted": "精力归零",
    "deadline_expired": "DDL 超时",
}


static func name_of(name_key: String, fallback: String = "") -> String:
    var text: Variant = NAMES.get(name_key, null)
    if text != null and not String(text).is_empty():
        return String(text)
    if not fallback.is_empty():
        return fallback
    return name_key


static func status_name(status_id: String) -> String:
    var known: String = String(STATUS_NAMES.get(status_id, ""))
    if known.is_empty():
        return status_id
    return known


static func card_type_name(card_type: String) -> String:
    return String(CARD_TYPE_NAMES.get(card_type, card_type))


static func phase_name(phase: String) -> String:
    return String(PHASE_NAMES.get(phase, phase))


static func rarity_name(rarity: String) -> String:
    return String(RARITY_NAMES.get(rarity, rarity))


static func exam_limit_name(limit_id: String) -> String:
    return String(EXAM_LIMIT_NAMES.get(limit_id, limit_id))


static func outcome_name(result: String) -> String:
    return String(OUTCOME_NAMES.get(result, result))


static func reason_name(reason: String) -> String:
    return String(REASON_NAMES.get(reason, reason))


static func definition_name(catalog, kind: String, definition_id: String) -> String:
    if catalog == null:
        return definition_id
    var definition: Dictionary = catalog.definition(kind, definition_id)
    if definition.is_empty():
        return definition_id
    return name_of(String(definition.get("name_key", "")), definition_id)


## 单条效果文案。catalog 用于把 summon_unit.scene 之类的引用翻成中文名。
static func effect_text(effect: Dictionary, catalog = null) -> String:
    if effect.is_empty():
        return ""
    var op := String(effect.get("op", ""))
    var amount := 0
    if effect.has("amount"):
        amount = int(effect.get("amount"))
    match op:
        GameConstants.OP_COMPLETE:
            return _complete_text(effect, amount)
        GameConstants.OP_RELAX:
            return "放松 %d" % amount
        GameConstants.OP_DRAW:
            return "抽 %d 张" % amount
        GameConstants.OP_DISCARD:
            return "弃 %d 张" % amount
        GameConstants.OP_GAIN_STATUS:
            return "获得 %d 层%s" % [int(effect.get("stacks", 1)), status_name(String(effect.get("status", "")))]
        GameConstants.OP_REMOVE_STATUS:
            return "移除 %d 层%s" % [amount, status_name(String(effect.get("status", "")))]
        GameConstants.OP_WORK_FLAT_BONUS:
            return "本回合首张工作牌完成量 +%d" % amount
        GameConstants.OP_SUMMON_UNIT:
            return "召入%s" % definition_name(catalog, GameConstants.KIND_UNIT, String(effect.get("unit", "")))
        GameConstants.OP_ESTABLISH_SCENE:
            return "建立场景 %s" % definition_name(catalog, GameConstants.KIND_SCENE, String(effect.get("scene", "")))
        GameConstants.OP_RESTORE_WORK:
            return "恢复完成量 %d" % amount
        GameConstants.OP_PRESSURE:
            return "压力 %d" % amount
        GameConstants.OP_GAIN_FOCUS:
            return "获得 %d 专注" % amount
        GameConstants.OP_HEAL:
            return "恢复 %d 精力" % amount
        GameConstants.OP_LOSE_VITALITY:
            return "失去 %d 精力" % amount
    if amount == 0:
        return op
    return "%s %d" % [op, amount]


static func _complete_text(effect: Dictionary, amount: int) -> String:
    var text := "完成 %d" % amount
    var bonus: Variant = effect.get("bonus_if")
    if typeof(bonus) == TYPE_DICTIONARY:
        var bonus_dict: Dictionary = bonus
        text += "（有 %s 至少 %d 层时同段 +%d）" % [
            status_name(String(bonus_dict.get("status", ""))),
            int(bonus_dict.get("min_stacks", 1)),
            int(bonus_dict.get("amount", 0)),
        ]
    return text


static func effect_list_text(effects: Array, catalog = null) -> String:
    var parts := PackedStringArray()
    for raw in effects:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        parts.append(effect_text(raw, catalog))
    return "；".join(parts)


## 实例限次文案。limit 是定义里的 limit，可能为 null。
static func limit_text(limit: Variant) -> String:
    if typeof(limit) != TYPE_DICTIONARY:
        return ""
    var limit_dict: Dictionary = limit
    var per := String(limit_dict.get("per", ""))
    var per_name := "回合"
    if per == "instance_round":
        per_name = "每实例每回合"
    elif per == "battle":
        per_name = "本战"
    return "%s限 %d 次" % [per_name, int(limit_dict.get("times", 1))]