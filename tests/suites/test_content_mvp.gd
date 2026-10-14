extends RefCounted
##
## MVP 内容验收（《项目计划书》§3.1 + 《统一设计文档》§4/§5/§8/§9/§10.2）。
##
## 只钉「内容事实」与「出厂清单可见性」：数值逐条与设计文档对齐、引用完整、清单启用集、
## 引擎接线（op / 被动 trigger / 饰品 hook 时点）、缺口账本自洽。
##
## 反面教训（本套件专门防它）：**文件里有 / 夹具里有 ≠ 出厂清单里可见**。
## 所以 §3.1 每个类别的断言都走 ContentDB（get_candidates / definition），
## 而不是直读 JSON；只有「本段故意未启用」的 events.json 才直读文件，且同时断言它在账本里挂着。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const RunService := preload("res://src/run/run_service.gd")

const CARDS_PATH := "res://data/definitions/cards.json"
const RELICS_PATH := "res://data/definitions/relics.json"
const CHARACTERS_PATH := "res://data/definitions/characters.json"
const TASKS_PATH := "res://data/definitions/tasks.json"
const ENCOUNTERS_PATH := "res://data/definitions/encounters.json"
const EVENTS_PATH := "res://data/definitions/events.json"
const DEFERRED_PATH := "res://data/manifests/content_deferred.json"

## 《项目计划书》§3.1 的精确内容清单（文档原文）。每个类别都要有归属：已启用 或 已记账。
const DOC_CARDS: Array[String] = ["K01", "K02", "K03", "K04", "K05", "K06", "K07", "K08", "K10", "K12", "K13", "K14", "K15", "K16", "K19", "K43", "K44", "K45", "K46", "K51", "K52", "K53", "K59", "K60"]
const DOC_SPECIAL_CARDS: Array[String] = ["X01"]
const DOC_RELICS: Array[String] = ["A01", "A04", "A05", "A07", "A08", "A11", "A15", "A18"]
const DOC_CHARACTERS: Array[String] = ["P01", "P04"]
const DOC_TASKS: Array[String] = ["N01", "N02", "N03", "N04", "Q01"]
const DOC_EVENTS: Array[String] = ["V01", "V03", "V04", "V10"]
const BOSS_TASK: String = "B01"

## 出厂清单当前状态（mvp-0.5）。第②段（t19 落地后）只需把 ENABLED_EVENTS 改成 DOC_EVENTS。
const ENABLED_CARDS: Array[String] = ["K01", "K02", "K03", "K04", "K05", "K06", "K07", "K08", "K10", "K12", "K13", "K14", "K15", "K16", "K19", "K43", "K44", "K45", "K46", "K51", "K52", "K53", "K59", "K60", "X01"]
const ENABLED_EVENTS: Array[String] = ["V01", "V03", "V04", "V10"]
const CONTENT_VERSION: String = "mvp-0.6"


func run(h) -> void:
    h.begin("MVP 内容 · 出厂清单与 ContentDB 可见性")
    var db := ContentDB.new()
    var loaded: Dictionary = db.load(GameConstants.MANIFEST_MVP)
    h.check("mvp 清单加载成功（结构 + 引用校验全过）", Result.is_ok(loaded))
    if not Result.is_ok(loaded):
        h.check("失败时给出错误码", not db.last_error_code.is_empty(), db.last_error_code)
        return
    h.eq("manifest_id", db.manifest_id, "mvp")
    h.eq("content_version", db.content_version, CONTENT_VERSION)
    h.eq("content_hash 为 64 位十六进制", db.content_hash.length(), 64)
    _manifest(h, db)
    h.begin("MVP 内容 · 24 张正式牌 + X01 逐字核对（《统一设计文档》§5）")
    _cards(h, db)
    h.begin("MVP 内容 · 任务与遭遇逐字核对（§9）")
    _tasks(h, db)
    h.begin("MVP 内容 · 人物与 8 件饰品（§4/§8）")
    _relics_and_characters(h, db)
    h.begin("MVP 内容 · 4 个事件（§10.2，本段未启用、直读文件）")
    _events(h, db)
    h.begin("MVP 内容 · 引擎接线核对（op / trigger / hook 时点）")
    _wiring(h, db)
    h.begin("MVP 内容 · 缺口账本自洽（content_deferred.json）")
    _ledger(h)

# ── 基础设施 ──────────────────────────────────────────────

func _read_json(path: String) -> Dictionary:
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed


func _def(file: Dictionary, id: String) -> Dictionary:
    for raw in (file.get("definitions", []) as Array):
        var definition: Dictionary = raw
        if String(definition.get("id", "")) == id:
            return definition
    return {}


func _ids(file: Dictionary) -> Array:
    var out := []
    for raw in (file.get("definitions", []) as Array):
        out.append(String((raw as Dictionary).get("id", "")))
    out.sort()
    return out


func _sorted(raw: Array) -> Array:
    var out := raw.duplicate()
    out.sort()
    return out


func _op(effect: Dictionary) -> String:
    return String(effect.get("op", ""))


func _union(left: Array, right: Array) -> Array:
    var out := left.duplicate()
    for item in right:
        if not out.has(item):
            out.append(item)
    out.sort()
    return out


func _overlap(left: Array, right: Array) -> Array:
    var out := []
    for item in left:
        if right.has(item):
            out.append(item)
    return out


## 出厂清单里读不到的 id（空数组 = 全部可见）。
func _missing_defs(db, kind: String, ids: Array) -> Array:
    var missing := []
    for raw_id in ids:
        if db.definition(kind, String(raw_id)).is_empty():
            missing.append(String(raw_id))
    return missing


## 递归收集定义里所有 "op" 值（effects / upgrade.effects / pre_effects / hooks[].effects / passive.effects）。
func _collect_ops(value: Variant) -> Array:
    var ops := []
    if typeof(value) == TYPE_DICTIONARY:
        var dict: Dictionary = value
        if dict.has("op"):
            ops.append(String(dict["op"]))
        for key in dict.keys():
            ops.append_array(_collect_ops(dict[key]))
    elif typeof(value) == TYPE_ARRAY:
        for item in (value as Array):
            ops.append_array(_collect_ops(item))
    return ops


func _option(event: Dictionary, option_id: String) -> Dictionary:
    for raw in (event.get("options", []) as Array):
        var option: Dictionary = raw
        if String(option.get("option_id", "")) == option_id:
            return option
    return {}


func _all_have_doc_line(group: Array) -> bool:
    for raw in group:
        if String((raw as Dictionary).get("doc_line", "")).is_empty():
            return false
    return true


# ── 出厂清单与可见性 ──────────────────────────────────────

func _manifest(h, db) -> void:
    var counts: Dictionary = db.content_info()["counts"]
    h.eq("出厂卡牌 25 张（24 正式牌 + X01）", int(counts.get(GameConstants.KIND_CARD, -1)), 25)
    h.eq("出厂人物 2 个（P01/P04）", int(counts.get(GameConstants.KIND_CHARACTER, -1)), 2)
    h.eq("出厂饰品 8 件", int(counts.get(GameConstants.KIND_RELIC, -1)), 8)
    h.eq("出厂任务 6 个（N01～N04 + Q01 + B01）", int(counts.get(GameConstants.KIND_TASK, -1)), 6)
    h.eq("出厂遭遇 6 条", int(counts.get(GameConstants.KIND_ENCOUNTER, -1)), 6)
    h.eq("出厂单位 4 个（F01～F04，§3.1）", int(counts.get(GameConstants.KIND_UNIT, -1)), 4)
    h.eq("出厂场景 3 个（L01～L03，§3.1）", int(counts.get(GameConstants.KIND_SCENE, -1)), 3)
    h.eq("出厂事件数量 = 本段登记的 ENABLED_EVENTS", int(counts.get(GameConstants.KIND_EVENT, 0)), ENABLED_EVENTS.size())

    # §3.1 每个类别都必须真的能从 ContentDB 读到（不是「文件里有」）
    h.eq("出厂卡牌 = 文档清单（经 ContentDB）", db.get_candidates({"kind": GameConstants.KIND_CARD}), _sorted(ENABLED_CARDS))
    h.eq("出厂人物 = 文档清单", db.get_candidates({"kind": GameConstants.KIND_CHARACTER}), _sorted(DOC_CHARACTERS))
    h.eq("出厂饰品 = 文档清单", db.get_candidates({"kind": GameConstants.KIND_RELIC}), _sorted(DOC_RELICS))
    h.eq("出厂任务 = 文档清单 + 首领", db.get_candidates({"kind": GameConstants.KIND_TASK}), _sorted(DOC_TASKS + [BOSS_TASK]))
    h.eq("出厂遭遇 = 同名 6 条", db.get_candidates({"kind": GameConstants.KIND_ENCOUNTER}), _sorted(DOC_TASKS + [BOSS_TASK]))
    h.eq("出厂单位 = F01～F04", db.get_candidates({"kind": GameConstants.KIND_UNIT}), ["F01", "F02", "F03", "F04"])
    h.eq("出厂场景 = L01～L03", db.get_candidates({"kind": GameConstants.KIND_SCENE}), ["L01", "L02", "L03"])
    h.eq("出厂事件 = ENABLED_EVENTS（本段为空）", db.get_candidates({"kind": GameConstants.KIND_EVENT}), _sorted(ENABLED_EVENTS))
    h.eq("每张出厂卡都能被读到", _missing_defs(db, GameConstants.KIND_CARD, ENABLED_CARDS), [])
    h.eq("每个出厂任务都能被读到", _missing_defs(db, GameConstants.KIND_TASK, DOC_TASKS + [BOSS_TASK]), [])
    h.eq("每个出厂遭遇都能被读到", _missing_defs(db, GameConstants.KIND_ENCOUNTER, DOC_TASKS + [BOSS_TASK]), [])
    h.eq("每件出厂饰品都能被读到", _missing_defs(db, GameConstants.KIND_RELIC, DOC_RELICS), [])
    h.eq("每个人物都能被读到", _missing_defs(db, GameConstants.KIND_CHARACTER, DOC_CHARACTERS), [])

    # 学期 1（MVP 唯一学期）的合法任务池：地图真的抽得到
    h.eq("学期 1 合法任务池（terms 过滤后）", db.get_candidates({"kind": GameConstants.KIND_TASK, "term": 1}), ["B01", "N01", "N02", "N03", "Q01"])
    # 奖励/商店池：基础牌不进随机池，X01 用 rarity=null 不进品质池
    h.eq("非 basic 奖励池不含 4 张基础牌", db.get_candidates({"kind": GameConstants.KIND_CARD, "exclude_tag": "basic"}).has("K01"), false)
    h.eq("X01 不进任何品质池（rarity=null）", db.get_candidates({"kind": GameConstants.KIND_CARD, "rarity": "null"}), [])
    h.eq("白卡品质池不含 X01 与特殊牌", db.get_candidates({"kind": GameConstants.KIND_CARD, "rarity": "white"}).has("X01"), false)
    h.eq("A04 不进掉落池（rarity=null，starter）", db.get_candidates({"kind": GameConstants.KIND_RELIC, "rarity": "white"}).has("A04"), false)
    h.eq("6 件掉落饰品都在白/蓝品质池里", _missing_from_pool(db, ["A05", "A07", "A08", "A11", "A15", "A18"]), [])


func _missing_from_pool(db, ids: Array) -> Array:
    var missing := []
    for raw_id in ids:
        var relic_id := String(raw_id)
        var rarity := String(db.definition(GameConstants.KIND_RELIC, relic_id).get("rarity", ""))
        if not db.get_candidates({"kind": GameConstants.KIND_RELIC, "rarity": rarity}).has(relic_id):
            missing.append(relic_id)
    return missing

# ── 卡牌逐字核对（《统一设计文档》§5.1/5.2/5.5/5.6/5.7/5.8）──

func _cards(h, db) -> void:
    var k01: Dictionary = db.definition(GameConstants.KIND_CARD, "K01")
    h.eq("K01 写：1·工作·白/基础｜完成6｜升级8",
        [int(k01["cost"]), String(k01["type"]), String(k01["rarity"]), (k01["tags"] as Array).has("basic"), int(k01["effects"][0]["amount"]), int(k01["upgrade"]["effects"][0]["amount"])],
        [1, "work", "white", true, 6, 8])
    var k02: Dictionary = db.definition(GameConstants.KIND_CARD, "K02")
    h.eq("K02 暂时休息：获得5放松｜升级8", [int(k02["effects"][0]["amount"]), int(k02["upgrade"]["effects"][0]["amount"])], [5, 8])
    var k03: Dictionary = db.definition(GameConstants.KIND_CARD, "K03")
    h.eq("K03 寻找思路：抽2弃1｜升级抽3弃1", [int(k03["effects"][0]["amount"]), int(k03["effects"][1]["amount"]), int(k03["upgrade"]["effects"][0]["amount"])], [2, 1, 3])
    var k04: Dictionary = db.definition(GameConstants.KIND_CARD, "K04")
    h.eq("K04 查资料：2灵感+抽1｜升级灵感3",
        [String(k04["effects"][0]["status"]), int(k04["effects"][0]["stacks"]), int(k04["effects"][1]["amount"]), int(k04["upgrade"]["effects"][0]["stacks"])],
        ["inspiration", 2, 1, 3])

    var k05: Dictionary = db.definition(GameConstants.KIND_CARD, "K05")
    h.eq("K05 细心写：2·工作·白｜完成14｜升级基础18（条件保留）",
        [int(k05["cost"]), String(k05["type"]), String(k05["rarity"]), int(k05["effects"][0]["amount"]), int(k05["upgrade"]["effects"][0]["amount"])],
        [2, "work", "white", 14, 18])
    var k05_bonus: Dictionary = k05["effects"][0]["bonus_if"]
    h.eq("K05 条件：本回合打过 K04 则同段+4",
        [String(k05_bonus["played_definition"]), String(k05_bonus["scope"]), int(k05_bonus["amount"])], ["K04", "round", 4])
    h.eq("K05 升级保留同一条件", [String(k05["upgrade"]["effects"][0]["bonus_if"]["played_definition"]), int(k05["upgrade"]["effects"][0]["bonus_if"]["amount"])], ["K04", 4])

    var k06: Dictionary = db.definition(GameConstants.KIND_CARD, "K06")
    h.eq("K06 潦草急就：0·工作·蓝｜完成3+1专注｜耗尽｜升级完成5",
        [int(k06["cost"]), String(k06["type"]), String(k06["rarity"]), int(k06["effects"][0]["amount"]), _op(k06["effects"][1]), int(k06["effects"][1]["amount"]), bool(k06["exhaust"]), int(k06["upgrade"]["effects"][0]["amount"])],
        [0, "work", "blue", 3, "gain_focus", 1, true, 5])

    var k07: Dictionary = db.definition(GameConstants.KIND_CARD, "K07")
    h.eq("K07 复盘：1·策略·蓝｜弃牌堆回收1｜耗尽｜升级费用0",
        [int(k07["cost"]), String(k07["type"]), String(k07["rarity"]), _op(k07["effects"][0]), int(k07["effects"][0]["amount"]), bool(k07["exhaust"]), int(k07["upgrade"]["cost"])],
        [1, "strategy", "blue", "recall_from_discard", 1, true, 0])

    var k08: Dictionary = db.definition(GameConstants.KIND_CARD, "K08")
    h.eq("K08 运动：恢复3精力+3放松+移除1焦虑｜耗尽",
        [String(k08["type"]), String(k08["rarity"]), _op(k08["effects"][0]), int(k08["effects"][0]["amount"]), _op(k08["effects"][1]), int(k08["effects"][2]["amount"]), String(k08["effects"][2]["status"]), bool(k08["exhaust"])],
        ["strategy", "blue", "heal", 3, "relax", 1, "anxiety", true])
    h.eq("K08 升级只改恢复量（5）", int(k08["upgrade"]["effects"][0]["amount"]), 5)

    var k10: Dictionary = db.definition(GameConstants.KIND_CARD, "K10")
    h.eq("K10 熬夜：支付4精力（vitality_cost）+2专注｜耗尽｜升级支付3",
        [int(k10["cost"]), int(k10["vitality_cost"]), _op(k10["effects"][0]), int(k10["effects"][0]["amount"]), bool(k10["exhaust"]), int(k10["upgrade"]["vitality_cost"])],
        [0, 4, "gain_focus", 2, true, 3])

    var k12: Dictionary = db.definition(GameConstants.KIND_CARD, "K12")
    h.eq("K12 转换思路：弃至多2张（up_to）+抽1（每弃置+1）｜升级建立前+2放松",
        [String(k12["type"]), int(k12["effects"][0]["amount"]), bool(k12["effects"][0]["up_to"]), int(k12["effects"][1]["amount"]), int(k12["effects"][1]["per_discarded"]), _op(k12["upgrade"]["pre_effects"][0]), int(k12["upgrade"]["pre_effects"][0]["amount"])],
        ["strategy", 2, true, 1, 1, "relax", 2])

    var k13: Dictionary = db.definition(GameConstants.KIND_CARD, "K13")
    h.eq("K13 编译：0·策略·白｜1编译｜每实例每回合限1次｜升级2",
        [int(k13["cost"]), String(k13["rarity"]), int(k13["effects"][0]["stacks"]), String(k13["limit"]["per"]), int(k13["limit"]["times"]), int(k13["upgrade"]["effects"][0]["stacks"])],
        [0, "white", 1, "instance_round", 1, 2])
    var k14: Dictionary = db.definition(GameConstants.KIND_CARD, "K14")
    h.eq("K14 打印Hello：完成5｜编译≥1同段+3｜升级基础7",
        [int(k14["effects"][0]["amount"]), String(k14["effects"][0]["bonus_if"]["status"]), int(k14["effects"][0]["bonus_if"]["min_stacks"]), int(k14["effects"][0]["bonus_if"]["amount"]), int(k14["upgrade"]["effects"][0]["amount"])],
        [5, "compile", 1, 3, 7])
    var k15: Dictionary = db.definition(GameConstants.KIND_CARD, "K15")
    h.eq("K15 循环练习：完成4抽1｜升级完成6", [int(k15["effects"][0]["amount"]), int(k15["effects"][1]["amount"]), int(k15["upgrade"]["effects"][0]["amount"])], [4, 1, 6])
    var k16: Dictionary = db.definition(GameConstants.KIND_CARD, "K16")
    h.eq("K16 调试：净化2层负面（选焦虑/拖延/困倦之一，§3.6）+1编译｜升级编译2",
        [_op(k16["effects"][0]), String(k16["effects"][0]["category"]), int(k16["effects"][0]["amount"]), int(k16["effects"][1]["stacks"]), int(k16["upgrade"]["effects"][1]["stacks"])],
        ["remove_status", "negative", 2, 1, 2])
    var k19: Dictionary = db.definition(GameConstants.KIND_CARD, "K19")
    h.eq("K19 版本控制：5放松+保留另一张手牌｜升级放松8",
        [int(k19["effects"][0]["amount"]), _op(k19["effects"][1]), int(k19["effects"][1]["amount"]), int(k19["upgrade"]["effects"][0]["amount"]), _op(k19["upgrade"]["effects"][1])],
        [5, "retain_hand_card", 1, 8, "retain_hand_card"])
    var k43: Dictionary = db.definition(GameConstants.KIND_CARD, "K43")
    h.eq("K43 室友搭把手：1·合作·白｜召入F01｜耗尽｜升级单位上限精力+3",
        [int(k43["cost"]), String(k43["type"]), String(k43["rarity"]), String(k43["effects"][0]["unit"]), bool(k43["exhaust"]), int(k43["upgrade"]["unit_bonus"]["max_vitality"])],
        [1, "cooperation", "white", "F01", true, 3])
    var k44: Dictionary = db.definition(GameConstants.KIND_CARD, "K44")
    h.eq("K44 请教学霸：2·合作·白｜召入F02｜升级单位协作+2",
        [int(k44["cost"]), String(k44["effects"][0]["unit"]), int(k44["upgrade"]["unit_bonus"]["cooperation"])], [2, "F02", 2])
    var k45: Dictionary = db.definition(GameConstants.KIND_CARD, "K45")
    h.eq("K45 请教助教：1·合作·蓝｜召入F03｜升级单位上限精力+3",
        [int(k45["cost"]), String(k45["rarity"]), String(k45["effects"][0]["unit"]), int(k45["upgrade"]["unit_bonus"]["max_vitality"])], [1, "blue", "F03", 3])
    var k46: Dictionary = db.definition(GameConstants.KIND_CARD, "K46")
    h.eq("K46 组队分工：2·合作·蓝｜召入F04｜升级单位上限精力+4",
        [int(k46["cost"]), String(k46["rarity"]), String(k46["effects"][0]["unit"]), int(k46["upgrade"]["unit_bonus"]["max_vitality"])], [2, "blue", "F04", 4])

    var k51: Dictionary = db.definition(GameConstants.KIND_CARD, "K51")
    h.eq("K51 回到自家：1·场景·蓝｜建立L01｜升级费用0",
        [int(k51["cost"]), String(k51["rarity"]), String(k51["effects"][0]["scene"]), int(k51["upgrade"]["cost"])], [1, "blue", "L01", 0])
    var k52: Dictionary = db.definition(GameConstants.KIND_CARD, "K52")
    h.eq("K52 宿舍自习：1·场景·白｜建立L02｜升级建立前3放松",
        [int(k52["cost"]), String(k52["rarity"]), String(k52["effects"][0]["scene"]), _op(k52["upgrade"]["pre_effects"][0]), int(k52["upgrade"]["pre_effects"][0]["amount"])],
        [1, "white", "L02", "relax", 3])
    var k53: Dictionary = db.definition(GameConstants.KIND_CARD, "K53")
    h.eq("K53 找到自习室：2·场景·紫｜建立L03｜升级建立前4放松",
        [int(k53["cost"]), String(k53["rarity"]), String(k53["effects"][0]["scene"]), int(k53["upgrade"]["pre_effects"][0]["amount"])], [2, "purple", "L03", 4])

    var k59: Dictionary = db.definition(GameConstants.KIND_CARD, "K59")
    h.eq("K59 临时抱佛脚：2·工作·紫｜完成12｜DDL≤3同段+10｜升级基础16（条件保留）",
        [int(k59["cost"]), String(k59["type"]), String(k59["rarity"]), int(k59["effects"][0]["amount"]), int(k59["effects"][0]["bonus_if"]["ddl_lte"]), int(k59["effects"][0]["bonus_if"]["amount"]), int(k59["upgrade"]["effects"][0]["amount"]), int(k59["upgrade"]["effects"][0]["bonus_if"]["ddl_lte"])],
        [2, "work", "purple", 12, 3, 10, 16, 3])

    var k60: Dictionary = db.definition(GameConstants.KIND_CARD, "K60")
    h.eq("K60 检查卷面：1·策略·白｜4放松+抽1+移除目标任务1层额外要求｜升级放松7",
        [int(k60["cost"]), String(k60["rarity"]), int(k60["effects"][0]["amount"]), int(k60["effects"][1]["amount"]), _op(k60["effects"][2]), String(k60["effects"][2]["status"]), int(k60["effects"][2]["amount"]), String(k60["target"]), int(k60["upgrade"]["effects"][0]["amount"])],
        [1, "white", 4, 1, "remove_status", "extra_requirements", 1, "task", 7])

    var x01: Dictionary = db.definition(GameConstants.KIND_CARD, "X01")
    h.eq("X01 分心消息：临时/不可打出/回合末正常弃置（§5.8）",
        [String(x01["type"]), int(x01["cost"]), String(x01["target"]), bool(x01["unplayable"]), (x01["effects"] as Array).size(),
         (x01["tags"] as Array).has("temporary"), (x01["tags"] as Array).has("special")],
        ["strategy", 0, "self", true, 0, true, true])
    h.eq("X01 rarity=null（不进随机品质池）", x01["rarity"], null)


# ── 任务与遭遇逐字核对（§9.1/9.2/9.3）──────────────────────

func _tasks(h, db) -> void:
    var n01: Dictionary = db.definition(GameConstants.KIND_TASK, "N01")
    h.eq("N01 课后习题：学期1～2｜24/8｜压力5→7",
        [int(n01["terms"][0]), int(n01["terms"][1]), int(n01["phases"][0]["work"]), int(n01["ddl"]), int(n01["phases"][0]["intents"][0]["pressure"]), int(n01["phases"][0]["intents"][1]["pressure"])],
        [1, 2, 24, 8, 5, 7])
    var n02: Dictionary = db.definition(GameConstants.KIND_TASK, "N02")
    h.eq("N02 英语小作文：学期1～2｜28/8｜屏障5→压力8",
        [int(n02["terms"][0]), int(n02["terms"][1]), int(n02["phases"][0]["work"]), int(n02["ddl"]), int(n02["phases"][0]["intents"][0]["shield"]), int(n02["phases"][0]["intents"][1]["pressure"])],
        [1, 2, 28, 8, 5, 8])
    var n03: Dictionary = db.definition(GameConstants.KIND_TASK, "N03")
    var n03_b: Dictionary = n03["phases"][0]["intents"][1]
    h.eq("N03 C语言练习：学期1～3｜30/8｜压力6→（加X01至弃牌堆+压力4）",
        [int(n03["terms"][0]), int(n03["terms"][1]), int(n03["phases"][0]["work"]), int(n03["ddl"]), int(n03["phases"][0]["intents"][0]["pressure"]),
         String(n03_b["add_card"]["card"]), int(n03_b["add_card"]["count"]), String(n03_b["add_card"]["zone"]), int(n03_b["pressure"])],
        [1, 3, 30, 8, 6, "X01", 1, "discard", 4])
    h.eq("N03 意图加的 X01 已启用（引用与引用者同清单）", db.is_enabled(GameConstants.KIND_CARD, "X01"), true)
    var n04: Dictionary = db.definition(GameConstants.KIND_TASK, "N04")
    h.eq("N04 实验预习：学期2～3｜32/8｜主角焦虑1→压力9",
        [int(n04["terms"][0]), int(n04["terms"][1]), int(n04["phases"][0]["work"]), int(n04["ddl"]),
         String(n04["phases"][0]["intents"][0]["gain_status"]["status"]), int(n04["phases"][0]["intents"][0]["gain_status"]["stacks"]),
         String(n04["phases"][0]["intents"][0]["gain_status"]["target"]), int(n04["phases"][0]["intents"][1]["pressure"])],
        [2, 3, 32, 8, "anxiety", 1, "player", 9])
    var q01: Dictionary = db.definition(GameConstants.KIND_TASK, "Q01")
    var q01_intents: Array = q01["phases"][0]["intents"]
    h.eq("Q01 随堂小测：精英｜学期1～2｜38/6｜压力7→屏障6→压力10",
        [int(q01["terms"][0]), int(q01["terms"][1]), int(q01["phases"][0]["work"]), int(q01["ddl"]),
         int(q01_intents[0]["pressure"]), int(q01_intents[1]["shield"]), int(q01_intents[2]["pressure"])],
        [1, 2, 38, 6, 7, 6, 10])
    var b01: Dictionary = db.definition(GameConstants.KIND_TASK, "B01")
    h.eq("B01 高数期末：总DDL10｜三阶段20/25/25｜各段压力7→屏障5→压力9",
        [int(b01["ddl"]), int(b01["phases"][0]["work"]), int(b01["phases"][1]["work"]), int(b01["phases"][2]["work"]),
         int(b01["phases"][0]["intents"][0]["pressure"]), int(b01["phases"][0]["intents"][1]["shield"]), int(b01["phases"][0]["intents"][2]["pressure"]),
         int(b01["phases"][2]["intents"][0]["pressure"]), int(b01["phases"][2]["intents"][1]["shield"]), int(b01["phases"][2]["intents"][2]["pressure"])],
        [10, 20, 25, 25, 7, 5, 9, 7, 5, 9])

    var n02_enc: Dictionary = db.definition(GameConstants.KIND_ENCOUNTER, "N02")
    h.eq("遭遇 N02：普通 + 任务 N02", [String(n02_enc["kind"]), String(n02_enc["tasks"][0])], ["normal", "N02"])
    var n03_enc: Dictionary = db.definition(GameConstants.KIND_ENCOUNTER, "N03")
    h.eq("遭遇 N03：普通 + 任务 N03（X01 前置解除后启用）", [String(n03_enc["kind"]), String(n03_enc["tasks"][0])], ["normal", "N03"])
    var q01_enc: Dictionary = db.definition(GameConstants.KIND_ENCOUNTER, "Q01")
    h.eq("遭遇 Q01：精英 + 独立作答", [String(q01_enc["kind"]), String(q01_enc["exam_limits"][0])], ["elite", "independent_answer"])
    var b01_enc: Dictionary = db.definition(GameConstants.KIND_ENCOUNTER, "B01")
    h.eq("遭遇 B01：首领 + 两项考试限制", [String(b01_enc["kind"]), String(b01_enc["exam_limits"][0]), String(b01_enc["exam_limits"][1])], ["boss", "independent_answer", "fixed_exam_room"])

# ── 人物与饰品（§4/§8）────────────────────────────────────

func _relics_and_characters(h, db) -> void:
    var a01: Dictionary = db.definition(GameConstants.KIND_RELIC, "A01")
    h.eq("A01 好用的笔：每回合首张工作牌第一段+1｜初始",
        [String(a01["availability"]), a01["rarity"], _op(a01["effects"][0]), int(a01["effects"][0]["amount"]), String(a01["effects"][0]["segment"]), String(a01["limit"]["per"]), int(a01["limit"]["times"])],
        ["starter", null, "work_flat_bonus", 1, "first", "round", 1])

    var a04: Dictionary = db.definition(GameConstants.KIND_RELIC, "A04")
    var a04_hook: Dictionary = a04["hooks"][0]
    h.eq("A04 小组通讯录：数据驱动（不再有 amount 0 占位 effects）", a04.has("effects"), false)
    h.eq("A04 hook：每战首张合作牌费用-1（备考面同样适用）",
        [String(a04["availability"]), a04["rarity"], String(a04_hook["at"]), String(a04_hook["card_type"]), int(a04_hook["discount"]), String(a04_hook["limit"]["per"]), int(a04_hook["limit"]["times"])],
        ["starter", null, "cost_quote", "cooperation", 1, "battle", 1])

    var a05: Dictionary = db.definition(GameConstants.KIND_RELIC, "A05")
    var a05_hook: Dictionary = a05["hooks"][0]
    h.eq("A05 老妈的饭：第3、6回合开始恢复3精力",
        [String(a05["rarity"]), String(a05_hook["at"]), int(a05_hook["rounds"][0]), int(a05_hook["rounds"][1]), _op(a05_hook["effects"][0]), int(a05_hook["effects"][0]["amount"])],
        ["white", "round_start", 3, 6, "heal", 3])
    var a07: Dictionary = db.definition(GameConstants.KIND_RELIC, "A07")
    var a07_hook: Dictionary = a07["hooks"][0]
    h.eq("A07 课堂笔记：第1回合额外抽2（受手牌上限）",
        [String(a07["rarity"]), String(a07_hook["at"]), int(a07_hook["rounds"][0]), _op(a07_hook["effects"][0]), int(a07_hook["effects"][0]["amount"])],
        ["blue", "draw", 1, "draw", 2])
    var a08: Dictionary = db.definition(GameConstants.KIND_RELIC, "A08")
    var a08_hook: Dictionary = a08["hooks"][0]
    h.eq("A08 咖啡杯：每战首张K10免除精力支付",
        [String(a08["rarity"]), String(a08_hook["at"]), String(a08_hook["definition_id"]), bool(a08_hook["skip_vitality_cost"]), String(a08_hook["limit"]["per"]), int(a08_hook["limit"]["times"])],
        ["white", "cost_quote", "K10", true, "battle", 1])
    var a11: Dictionary = db.definition(GameConstants.KIND_RELIC, "A11")
    var a11_hook: Dictionary = a11["hooks"][0]
    h.eq("A11 计划本：每回合首张策略牌结算后+2放松",
        [String(a11["rarity"]), String(a11_hook["at"]), String(a11_hook["card_type"]), String(a11_hook["limit"]["per"]), int(a11_hook["limit"]["times"]), _op(a11_hook["effects"][0]), int(a11_hook["effects"][0]["amount"])],
        ["white", "card_resolved", "strategy", "round", 1, "relax", 2])
    var a15: Dictionary = db.definition(GameConstants.KIND_RELIC, "A15")
    var a15_hook: Dictionary = a15["hooks"][0]
    h.eq("A15 校园卡：商店卡牌与饰品价格×0.8向上取整（不动删牌与餐食）",
        [String(a15["rarity"]), String(a15_hook["at"]), String(a15_hook["kinds"][0]), String(a15_hook["kinds"][1]), int(a15_hook["multiplier_percent"]), String(a15_hook["rounding"])],
        ["white", "shop_price", "card", "relic", 80, "ceil"])
    var a18: Dictionary = db.definition(GameConstants.KIND_RELIC, "A18")
    var a18_hook: Dictionary = a18["hooks"][0]
    h.eq("A18 室友零食：前3回合开始各恢复1精力",
        [String(a18["rarity"]), String(a18_hook["at"]), int(a18_hook["rounds"][0]), int(a18_hook["rounds"][1]), int(a18_hook["rounds"][2]), int(a18_hook["effects"][0]["amount"])],
        ["white", "round_start", 1, 2, 3, 1])
    h.eq("8 件饰品的 hook 时点都被引擎登记", _unknown_hook_points(db, DOC_RELICS), [])

    var p01: Dictionary = db.definition(GameConstants.KIND_CHARACTER, "P01")
    h.eq("P01 林序：起始牌 K13/K14｜初始饰品 A01｜第3张工作牌得1编译",
        [String(p01["starter_cards"][0]), String(p01["starter_cards"][1]), String(p01["starter_relic_id"]), String(p01["passive"]["trigger"]), int(p01["passive"]["count"]), String(p01["passive"]["limit"]["per"]), int(p01["passive"]["limit"]["times"]), String(p01["passive"]["effects"][0]["status"]), int(p01["passive"]["effects"][0]["stacks"])],
        ["K13", "K14", "A01", "work_card_resolved", 3, "round", 1, "compile", 1])
    var p04: Dictionary = db.definition(GameConstants.KIND_CHARACTER, "P04")
    h.eq("P04 唐以宁：起始牌 K43/K44｜初始饰品 A04｜每回合首张合作牌结算后+2放松",
        [String(p04["starter_cards"][0]), String(p04["starter_cards"][1]), String(p04["starter_relic_id"]), String(p04["passive"]["trigger"]), int(p04["passive"]["count"]), String(p04["passive"]["limit"]["per"]), int(p04["passive"]["limit"]["times"]), _op(p04["passive"]["effects"][0]), int(p04["passive"]["effects"][0]["amount"])],
        ["K43", "K44", "A04", "cooperation_card_resolved", 1, "round", 1, "relax", 2])
    h.eq("P04 被动 trigger 已被引擎登记（启用即会派发）", GameConstants.PASSIVE_TRIGGERS.has(GameConstants.PASSIVE_TRIGGER_COOPERATION_RESOLVED), true)
    h.eq("P01/P04 起始牌与初始饰品都在清单里",
        _missing_defs(db, GameConstants.KIND_CARD, p01["starter_cards"] + p04["starter_cards"]) + _missing_defs(db, GameConstants.KIND_RELIC, [String(p01["starter_relic_id"]), String(p04["starter_relic_id"])]), [])


func _unknown_hook_points(db, relic_ids: Array) -> Array:
    var unknown := []
    for raw_id in relic_ids:
        var definition: Dictionary = db.definition(GameConstants.KIND_RELIC, String(raw_id))
        for raw_hook in (definition.get("hooks", []) as Array):
            var at := String((raw_hook as Dictionary).get("at", ""))
            if not GameConstants.RELIC_HOOK_POINTS.has(at):
                unknown.append("%s:%s" % [String(raw_id), at])
    return unknown

# ── 事件（§10.2；本段未进出厂清单，直读文件 + 引用核对）──

func _events(h, db) -> void:
    var events := _read_json(EVENTS_PATH)
    h.check("events.json 可读", not events.is_empty())
    if events.is_empty():
        return
    h.eq("events.json 有 4 个 MVP 事件（§3.1）", _ids(events), _sorted(DOC_EVENTS))
    h.eq("每个事件都标了同局至多一次（once_per_run）", _missing_once_per_run(events), [])
    h.eq("每个事件都有「离开，无变化」（effects 为空）", _missing_leave(events), [])
    h.eq("每个事件选项都只用引擎登记的事件 op（RunService.EVENT_OPS）", _unknown_event_ops(events), [])

    var v01 := _def(events, "V01")
    h.eq("V01 节日放假：学期1～8", [int(v01["terms"][0]), int(v01["terms"][1])], [1, 8])
    var home: Dictionary = _option(v01, "home")
    h.eq("V01 回老家：白饰品1件", [String(home["effects"][0]["op"]), String(home["effects"][0]["rarity"]), int(home["effects"][0]["count"])], ["gain_relic", "white", 1])
    var play: Dictionary = _option(v01, "play")
    h.eq("V01 出去玩：蓝卡三选一", [String(play["effects"][0]["op"]), String(play["effects"][0]["rarity"]), int(play["effects"][0]["candidate_count"])], ["gain_card", "blue", 3])
    h.eq("V01 在家打游戏：恢复24精力", [String(_option(v01, "game")["effects"][0]["op"]), int(_option(v01, "game")["effects"][0]["amount"])], ["heal", 24])

    var v03 := _def(events, "V03")
    h.eq("V03 选课咨询：学期1～3", [int(v03["terms"][0]), int(v03["terms"][1])], [1, 3])
    var consult: Dictionary = _option(v03, "consult")
    var pool: Array = consult["effects"][0]["card_pool"]
    h.eq("V03 从 K14/K05/K60 中选 1（MVP 明确标识的测试替代池）",
        [String(pool[0]), String(pool[1]), String(pool[2]), int(consult["effects"][0]["selection_count"]), int(consult["effects"][0]["fallback_money"])],
        ["K14", "K05", "K60", 1, 20])
    h.eq("V03 替代池 3 张牌都在出厂清单里（引用与引用者同清单）", _missing_defs(db, GameConstants.KIND_CARD, pool), [])
    var drop: Dictionary = _option(v03, "drop")
    h.eq("V03 删1张基础牌并支付5精力", [int(drop["cost"]["vitality"]), String(drop["effects"][0]["op"]), String(drop["effects"][0]["tag_filter"])], [5, "remove_card", "basic"])

    var v04 := _def(events, "V04")
    h.eq("V04 宿舍断电：学期1～4", [int(v04["terms"][0]), int(v04["terms"][1])], [1, 4])
    h.eq("V04 提前休息恢复10", [String(_option(v04, "rest")["effects"][0]["op"]), int(_option(v04, "rest")["effects"][0]["amount"])], ["heal", 10])
    var pay: Dictionary = _option(v04, "pay")
    h.eq("V04 支付6精力升级1张工作牌", [int(pay["cost"]["vitality"]), String(pay["effects"][0]["op"]), String(pay["effects"][0]["type_filter"])], [6, "upgrade_card", "work"])

    var v10 := _def(events, "V10")
    h.eq("V10 捡到校园卡：学期1～8", [int(v10["terms"][0]), int(v10["terms"][1])], [1, 8])
    var back: Dictionary = _option(v10, "return")
    h.eq("V10 归还：获得A15，已持有则20生活费",
        [String(back["effects"][0]["op"]), String(back["effects"][0]["relic_id"]), int(back["effects"][0]["fallback_money"])], ["gain_relic", "A15", 20])
    h.eq("V10 引用的 A15 在出厂清单里", db.is_enabled(GameConstants.KIND_RELIC, "A15"), true)
    h.eq("V10 交服务台：恢复6精力", [String(_option(v10, "desk")["effects"][0]["op"]), int(_option(v10, "desk")["effects"][0]["amount"])], ["heal", 6])


func _missing_once_per_run(events: Dictionary) -> Array:
    var missing := []
    for raw in (events.get("definitions", []) as Array):
        if not bool((raw as Dictionary).get("once_per_run", false)):
            missing.append(String((raw as Dictionary).get("id", "")))
    return missing


func _missing_leave(events: Dictionary) -> Array:
    var missing := []
    for raw in (events.get("definitions", []) as Array):
        var event: Dictionary = raw
        var leave: Dictionary = _option(event, "leave")
        if leave.is_empty() or not (leave.get("effects", []) as Array).is_empty():
            missing.append(String(event.get("id", "")))
    return missing


func _unknown_event_ops(events: Dictionary) -> Array:
    var unknown := []
    for raw in (events.get("definitions", []) as Array):
        var event: Dictionary = raw
        for raw_option in (event.get("options", []) as Array):
            var option: Dictionary = raw_option
            for raw_effect in (option.get("effects", []) as Array):
                var op := String((raw_effect as Dictionary).get("op", ""))
                if not RunService.EVENT_OPS.has(op):
                    unknown.append("%s/%s:%s" % [String(event.get("id", "")), String(option.get("option_id", "")), op])
    return unknown


# ── 引擎接线核对 ──────────────────────────────────────────

const SELECTION_OPS: Array[String] = ["recall_from_discard", "discard", "remove_status", "retain_hand_card"]


func _wiring(h, db) -> void:
    var unknown_ops := []
    for kind in [GameConstants.KIND_CARD, GameConstants.KIND_RELIC, GameConstants.KIND_SCENE, GameConstants.KIND_UNIT, GameConstants.KIND_CHARACTER]:
        for raw_id in db.get_candidates({"kind": kind}):
            var definition: Dictionary = db.definition(kind, String(raw_id))
            for op in _collect_ops(definition):
                if not ContentDB.KNOWN_OPS.has(op):
                    unknown_ops.append("%s/%s:%s" % [kind, String(raw_id), op])
    h.eq("出厂定义不含未实现 op（对照 ContentDB.KNOWN_OPS）", unknown_ops, [])
    h.eq("8 件饰品的 hook 时点都在 GameConstants.RELIC_HOOK_POINTS 里", _unknown_hook_points(db, DOC_RELICS), [])
    h.eq("P04 被动 trigger 在 GameConstants.PASSIVE_TRIGGERS 里", GameConstants.PASSIVE_TRIGGERS.has("cooperation_card_resolved"), true)
    h.eq("选择类 op 只写在卡牌里（场景/饰品/单位/被动写了会被内容校验拒绝）", _selection_ops_outside_cards(db), [])


func _selection_ops_outside_cards(db) -> Array:
    var bad := []
    for kind in [GameConstants.KIND_RELIC, GameConstants.KIND_SCENE, GameConstants.KIND_UNIT, GameConstants.KIND_CHARACTER]:
        for raw_id in db.get_candidates({"kind": kind}):
            for op in _collect_ops(db.definition(kind, String(raw_id))):
                if SELECTION_OPS.has(op):
                    bad.append("%s/%s:%s" % [kind, String(raw_id), op])
    return bad


# ── 缺口账本自洽（content_deferred.json）──────────────────

func _ledger(h) -> void:
    var ledger := _read_json(DEFERRED_PATH)
    h.check("缺口账本可读", not ledger.is_empty())
    if ledger.is_empty():
        return
    var enabled: Dictionary = _read_json("res://data/manifests/mvp.json")["enabled"]
    var hold: Dictionary = ledger["manifest_holdback"]["ids"]
    var reasons: Dictionary = ledger["manifest_holdback"]["reasons"]
    var kinds := ["card", "character", "relic", "task", "encounter", "event"]

    # 判据：文档清单的每一项都必须有归属（已启用 或 已记账），一个都不许漏
    h.eq("卡牌：出厂 ∪ holdback = 文档 24 正式牌 + X01", _union(enabled.get("card", []), hold.get("card", [])), _sorted(DOC_CARDS + DOC_SPECIAL_CARDS))
    h.eq("人物：出厂 ∪ holdback = P01/P04", _union(enabled.get("character", []), hold.get("character", [])), _sorted(DOC_CHARACTERS))
    h.eq("饰品：出厂 ∪ holdback = 8 件", _union(enabled.get("relic", []), hold.get("relic", [])), _sorted(DOC_RELICS))
    h.eq("任务：出厂 ∪ holdback = N01～N04 + Q01（B01 是首领，不在 §3.1 普通任务行）", _minus(_union(enabled.get("task", []), hold.get("task", [])), [BOSS_TASK]), _sorted(DOC_TASKS))
    h.eq("遭遇：出厂 ∪ holdback = 同名 5 条", _minus(_union(enabled.get("encounter", []), hold.get("encounter", [])), [BOSS_TASK]), _sorted(DOC_TASKS))
    h.eq("事件：出厂 ∪ holdback = 4 个事件", _union(enabled.get("event", []), hold.get("event", [])), _sorted(DOC_EVENTS))

    # holdback 与出厂清单不得重叠（同一件东西不能既启用又记账）
    for kind in kinds:
        h.eq("holdback.%s 与出厂清单无交集" % kind, _overlap(hold.get(kind, []), enabled.get(kind, [])), [])
    # 非空 holdback 必须写明原因；空组不写原因
    for kind in kinds:
        if (hold.get(kind, []) as Array).is_empty():
            continue
        h.check("holdback.%s 写明了不启用的原因" % kind, not String(reasons.get(kind, "")).is_empty())
    # holdback 清空后账本不得再挂着过期计划
    if (hold.get("event", []) as Array).is_empty():
        h.check("holdback 已清空时账本写明该段已完成", String(ledger["manifest_next_segment"]["note"]).contains("已完成"))
    else:
        h.check("事件组写明了推迟原因（t19 地图路线解耦后启用）", String(reasons.get("event", "")).contains("t19"))
    # 下一段计划必须与 holdback 一致
    h.eq("下一段要启用的事件 = 当前 holdback 的事件", _sorted(ledger["manifest_next_segment"]["event"]), _sorted(hold.get("event", [])))

    # 考古区：landed 必须保留卡面原文，且非空（e1/e2 确实落地过）
    var landed: Dictionary = ledger["landed"]
    for kind in ["card", "character", "relic", "event"]:
        h.check("landed.%s 保留了卡面原文（doc_line）" % kind, _all_have_doc_line(landed.get(kind, [])))
    h.eq("landed 四组都非空", [not (landed["card"] as Array).is_empty(), not (landed["character"] as Array).is_empty(), not (landed["relic"] as Array).is_empty(), not (landed["event"] as Array).is_empty()], [true, true, true, true])


func _minus(raw: Array, items: Array) -> Array:
    var out := []
    for item in raw:
        if not items.has(item):
            out.append(item)
    out.sort()
    return out