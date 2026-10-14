extends RefCounted
##
## E01～E04 事件节点端到端探针（verifier，为 t11 落地 event 组准备）。
## 独立入口：res://tests/suites/audits/audit_events.gd（不登记进主套件）。
##
## 模式（队长 approved）：「阻塞前提仍成立」写法——前置没落地时只跑一条阻塞断言；
## 前置一落地，那条断言自动翻红提醒我，同时后面的实探针立刻开始跑，不会假绿。
##
const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const RandomSource := preload("res://src/common/random_source.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const RunService := preload("res://src/run/run_service.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const EventState := preload("res://src/run/run_event_state.gd")
const SnapshotCodec := preload("res://src/storage/snapshot_codec.gd")
const SaveStore := preload("res://src/storage/save_store.gd")
const SessionStateScript := preload("res://src/app/session_state.gd")

const SEED := "20261013"

var _db = null
var _svc = null


func run(h) -> void:
    var db := ContentDB.new()
    var loaded := db.load("mvp")
    if not Result.is_ok(loaded):
        h.begin("E01～E04 · 前置")
        h.check("mvp 清单可加载", false, str(loaded))
        return
    _db = db
    _svc = RunService.new(db)
    h.begin("E01 选项成本不足被拒且状态不变")
    _e01(h)
    h.begin("E02 候选在进入时冻结（重开界面不重抽）")
    _e02(h)
    h.begin("E03「离开，无变化」必须有且零副作用")
    _e03(h)
    h.begin("E04 事件闭环：选收益选项 → 收益落地 → 离开")
    _e04(h)


# ── 工具 ──────────────────────────────────────────────────

func _state(step: Dictionary):
    return step["data"]["state"]


func _rng(step: Dictionary) -> Dictionary:
    var data: Dictionary = step.get("data", {})
    if data.has("rng_state"):
        return data["rng_state"]
    if data.has("rng_states"):
        return data["rng_states"]
    return {}


func _ok(h, label: String, result: Dictionary) -> bool:
    if Result.is_ok(result):
        h.check(label, true)
        return true
    h.check(label, false, str(result.get("error")))
    return false


func _create_run() -> Dictionary:
    return _svc.create({
        "character_id": "P01",
        "difficulty": GameConstants.DIFFICULTY_NORMAL,
        "manifest_id": _db.manifest_id,
        "seed": SEED,
    }, {})


func _session_of(run, rng: Dictionary, revision: int, battle = null) -> Object:
    var session = SessionStateScript.new()
    session.run_id = run.run_id
    session.revision = revision
    session.run = run
    session.battle = battle
    session.random_snapshot = rng
    return session


## 事件部分：状态摘要（用来断言「状态不变」/「零副作用」）。
func _digest(run, rng: Dictionary) -> String:
    var cards := []
    for card in run.cards:
        cards.append("%s:%s:%d" % [card.card_id, card.definition_id, int(card.upgrade_level)])
    var relics := []
    for relic in run.relics:
        relics.append("%s:%s" % [relic.relic_id, relic.definition_id])
    var seen := []
    for key in run.seen_event_ids:
        seen.append(String(key))
    seen.sort()
    var resolved := ""
    var frozen := ""
    var node = run.current_node()
    if node != null and node.context.get("event") != null:
        resolved = String(node.context["event"].resolved_option_id)
        frozen = SnapshotCodec.canonical_json(node.context["event"].frozen_candidates)
    return SnapshotCodec.canonical_json({
        "money": int(run.money),
        "vitality": int(run.vitality),
        "max_vitality": int(run.max_vitality),
        "cards": cards,
        "relics": relics,
        "career": run.career_progress.duplicate(true),
        "seen": seen,
        "resolved": resolved,
        "frozen": frozen,
        "rng": rng,
    })


func _next_battle_action(state, data: Dictionary) -> Dictionary:
    var choice: Variant = data.get("pending_choice")
    if choice != null:
        var candidates: Array = (choice as Dictionary).get("candidates", [])
        if not candidates.is_empty():
            return {"type": GameConstants.ACTION_CONFIRM_CHOICE, "payload": {
                "choice_id": String((choice as Dictionary)["choice_id"]),
                "selected_ids": [String(((candidates[0]) as Dictionary)["id"])],
            }}
    for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
        var card = state.get_card(String(raw_id))
        if card == null:
            continue
        var definition: Dictionary = _db.definition(GameConstants.KIND_CARD, card.definition_id)
        if String(definition.get("type", "")) != GameConstants.CARD_WORK:
            continue
        if int(definition.get("cost", 0)) > int(state.player.focus):
            continue
        var payload := {"card_id": card.card_id}
        if not (state.tasks as Array).is_empty():
            payload["target_ids"] = [state.tasks[0].task_id]
        return {"type": GameConstants.ACTION_PLAY_CARD, "payload": payload}
    return {"type": GameConstants.ACTION_END_TURN, "payload": {}}


func _fight(battle_input: Dictionary) -> Dictionary:
    var engine = BattleEngine.new(_db)
    var step: Dictionary = engine.begin(battle_input)
    if not Result.is_ok(step):
        return {}
    var guard := 0
    while guard < 240:
        guard += 1
        var data: Dictionary = step["data"]
        if data.get("outcome") != null:
            return data["outcome"]
        var next: Dictionary = engine.apply(data["state"], _next_battle_action(data["state"], data), data.get("rng_state"))
        if not Result.is_ok(next):
            return {}
        step = next
    return {}


func _pick_reachable_kind(run, kind: String) -> String:
    for raw in run.reachable_node_ids():
        if String(run.find_node(String(raw)).kind) == kind:
            return String(raw)
    return ""


## 清掉挡路的战斗节点，直到目标类型的节点可达；返回 {run, rng} 或 {}。
func _clear_until_kind(run, rng: Dictionary, kind: String) -> Dictionary:
    for _index in range(8):
        if not _pick_reachable_kind(run, kind).is_empty():
            return {"run": run, "rng": rng}
        var battle_id := _pick_reachable_kind(run, RunNodeState.KIND_NORMAL)
        if battle_id.is_empty():
            print("[audit] E no path to ", kind)
            return {}
        var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": battle_id}}, rng)
        if not Result.is_ok(entered):
            print("[audit] E enter failed: ", entered)
            return {}
        var current = _state(entered)
        var current_rng: Dictionary = _rng(entered)
        var outcome := _fight(entered["data"]["battle_input"])
        if outcome.is_empty():
            print("[audit] E fight failed at ", battle_id)
            return {}
        var settled: Dictionary = _svc.settle_battle(current, outcome, current_rng)
        if not Result.is_ok(settled):
            print("[audit] E settle failed: ", settled)
            return {}
        current = _state(settled)
        current_rng = _rng(settled)
        var guard := 0
        while current.pending_reward != null and not current.pending_reward.is_complete() and guard < 16:
            guard += 1
            var offer = current.pending_reward
            var items: Array = offer.pending_items()
            if items.is_empty():
                break
            var item = items[0]
            var claim := {"offer_id": String(offer.offer_id), "item_id": String(item.item_id)}
            if not (item.candidates as Array).is_empty():
                claim["candidate_id"] = String((item.candidates as Array)[0])
            var claimed: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": claim}, current_rng)
            if not Result.is_ok(claimed):
                print("[audit] E claim failed: ", claimed)
                return {}
            current = _state(claimed)
            current_rng = _rng(claimed)
        var left: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": battle_id}}, current_rng)
        if not Result.is_ok(left):
            print("[audit] E leave failed: ", left)
            return {}
        run = _state(left)
        rng = _rng(left)
    return {}


func _enter_event(run, rng: Dictionary) -> Dictionary:
    var node_id := _pick_reachable_kind(run, RunNodeState.KIND_EVENT)
    if node_id.is_empty():
        return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.e.no_event_node", {})
    return _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node_id}}, rng)


func _option_with_op(definition: Dictionary, op: String) -> Dictionary:
    for raw in (definition.get("options", []) as Array):
        var option: Dictionary = raw
        for raw_effect in (option.get("effects", []) as Array):
            if String((raw_effect as Dictionary).get("op", "")) == op:
                return option
    return {}


func _option_with_cost(definition: Dictionary, key: String) -> Dictionary:
    for raw in (definition.get("options", []) as Array):
        var option: Dictionary = raw
        var cost: Dictionary = option.get("cost", {})
        if int(cost.get(key, 0)) > 0:
            return option
    return {}


func _leave_option(definition: Dictionary) -> Dictionary:
    for raw in (definition.get("options", []) as Array):
        var option: Dictionary = raw
        var effects: Array = option.get("effects", [])
        var cost: Dictionary = option.get("cost", {})
        if effects.is_empty() and int(cost.get("money", 0)) == 0 and int(cost.get("vitality", 0)) == 0:
            return option
    return {}


func _has_tag(definition_id: String, tag: String) -> bool:
    var definition: Dictionary = _db.definition(GameConstants.KIND_CARD, definition_id)
    return (definition.get("tags", []) as Array).has(tag)


func _card_type(definition_id: String) -> String:
    return String(_db.definition(GameConstants.KIND_CARD, definition_id).get("type", ""))


## 需要目标/候选的收益 op：自动给出合法选择（remove_card 用 basic 牌、upgrade_card 用工作牌、gain_card 用冻结候选）。
func _selection_for(run, option: Dictionary, instance) -> Array:
    for raw in (option.get("effects", []) as Array):
        var effect: Dictionary = raw
        var op := String(effect.get("op", ""))
        if op == "remove_card":
            for card in run.cards:
                if _has_tag(String(card.definition_id), "basic"):
                    return [String(card.card_id)]
        if op == "upgrade_card":
            for card in run.cards:
                if _card_type(String(card.definition_id)) == GameConstants.CARD_WORK:
                    return [String(card.card_id)]
    var frozen: Array = instance.candidates_for(String(option.get("option_id", "")))
    if not frozen.is_empty():
        return [String(frozen[0])]
    return []


func _choose(run, rng: Dictionary, instance, option: Dictionary) -> Dictionary:
    return _svc.apply(run, {"type": GameConstants.ACTION_CHOOSE_EVENT, "payload": {
        "event_instance_id": String(instance.event_instance_id),
        "option_id": String(option.get("option_id", "")),
        "selection_ids": _selection_for(run, option, instance),
    }}, rng)


func _event_instance(run):
    var node = run.current_node()
    if node == null:
        return null
    return node.context.get("event")


# ── E01～E04 ─────────────────────────────────────────────

## 阻塞前提：mvp 清单里目前没有启用任何事件（events.json 已存在但未进清单，t11 负责扩容）。
## 前置一落地，这条会翻红提醒我，同时后面的实探针立刻开始跑。
func _premise(h, label: String) -> bool:
    var events: Array = _db.enabled_ids(GameConstants.KIND_EVENT)
    if events.is_empty():
        h.check("[待内容] %s 阻塞前提：清单尚未启用任何事件" % label, true)
        return true
    h.check("[记录] %s 阻塞前提已解除：事件已进 mvp 清单，实探针就位" % label, true)
    return false


func _e01(h) -> void:
    if _premise(h, "E01"):
        return
    var created: Dictionary = _create_run()
    if not _ok(h, "E01 局创建成功", created):
        return
    var reached := _clear_until_kind(_state(created), _rng(created), RunNodeState.KIND_EVENT)
    if reached.is_empty():
        h.check("E01 推进到事件节点可达", false)
        return
    h.check("E01 推进到事件节点可达", true)
    var entered := _enter_event(reached["run"], reached["rng"])
    if not _ok(h, "E01 进入事件节点", entered):
        return
    var current = _state(entered)
    var current_rng: Dictionary = _rng(entered)
    var instance = _event_instance(current)
    if instance == null:
        h.check("E01 事件实例已建立（未被空池回退成战斗）", false)
        return
    var definition: Dictionary = _db.definition(GameConstants.KIND_EVENT, String(instance.definition_id))
    if not _ok(h, "E01 事件定义可读", Result.ok(definition) if not definition.is_empty() else Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.e.no_definition", {})):
        return
    var cost_option := _option_with_cost(definition, "vitality")
    if cost_option.is_empty():
        h.check("[记录] E01 本事件没有体力成本选项，跳过体力分支", true)
    else:
        var cost := int((cost_option.get("cost", {}) as Dictionary).get("vitality", 0))
        current.vitality = cost
        var before := _digest(current, current_rng)
        var denied = _choose(current, current_rng, instance, cost_option)
        h.eq("E01 支付后不足 1 精力被拒", Result.error_code(denied), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("E01 被拒后状态逐字段不变", _digest(current, current_rng), before)
        current.vitality = cost + 1
        var allowed = _choose(current, current_rng, instance, cost_option)
        if _ok(h, "E01 精力够（支付后恰好剩 1）则可选", allowed):
            var after = _state(allowed)
            h.eq("E01 体力成本只扣一次（1）", int(after.vitality), 1)
            h.eq("E01 选项已记录", String(_event_instance(after).resolved_option_id), String(cost_option["option_id"]))
            var again = _choose(after, _rng(allowed), instance, cost_option)
            h.eq("E01 同一选项不能重复选", Result.error_code(again), GameConstants.ERROR_ALREADY_RESOLVED)
        return
    var money_option := _option_with_cost(definition, "money")
    if money_option.is_empty():
        h.check("[记录] E01 本事件没有金钱成本选项，跳过金钱分支", true)
        return
    var money_cost := int((money_option.get("cost", {}) as Dictionary).get("money", 0))
    current.money = money_cost - 1
    var before_money := _digest(current, current_rng)
    var denied_money = _choose(current, current_rng, instance, money_option)
    h.eq("E01 钱不足被拒", Result.error_code(denied_money), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
    h.eq("E01 钱不足被拒后状态不变", _digest(current, current_rng), before_money)
    current.money = money_cost
    var allowed_money = _choose(current, current_rng, instance, money_option)
    if _ok(h, "E01 钱刚好够则可选", allowed_money):
        h.eq("E01 金钱成本只扣一次（0）", int(_state(allowed_money).money), 0)


func _e02(h) -> void:
    if _premise(h, "E02"):
        return
    var created: Dictionary = _create_run()
    if not _ok(h, "E02 局创建成功", created):
        return
    var reached := _clear_until_kind(_state(created), _rng(created), RunNodeState.KIND_EVENT)
    if reached.is_empty():
        h.check("E02 推进到事件节点可达", false)
        return
    var entered := _enter_event(reached["run"], reached["rng"])
    if not _ok(h, "E02 进入事件节点", entered):
        return
    var current = _state(entered)
    var current_rng: Dictionary = _rng(entered)
    var instance = _event_instance(current)
    if instance == null:
        h.check("E02 事件实例已建立（未被空池回退成战斗）", false)
        return
    var frozen_before := SnapshotCodec.canonical_json(instance.frozen_candidates)
    var rng_before := SnapshotCodec.canonical_json(current_rng)
    h.check("[记录] E02 本事件进入时冻结的候选：%s" % frozen_before, true)
    _svc.make_view(current)
    _svc.preview(current, {"type": GameConstants.ACTION_CHOOSE_EVENT, "payload": {"option_id": "leave"}})
    _svc.make_view(current)
    h.eq("E02 重开界面不重抽候选", SnapshotCodec.canonical_json(_event_instance(current).frozen_candidates), frozen_before)
    h.eq("E02 重开界面不消耗随机", SnapshotCodec.canonical_json(current_rng), rng_before)
    var view = _svc.make_view(current)
    h.check("E02 视图可直接给出冻结候选（界面不需要自己抽）", typeof(view) == TYPE_DICTIONARY and view.has("event"))
    var store := SaveStore.new("user://audit_e02", _db)
    var encoded = SnapshotCodec.encode_session(_session_of(current, current_rng, 3, null), null, {
        "content_version": _db.content_version,
        "content_hash": _db.content_hash,
        "manifest_id": _db.manifest_id,
    })
    if not _ok(h, "E02 事件节点是稳定边界，可存档", encoded):
        return
    if not _ok(h, "E02 保存", store.save(SaveStore.SLOT_CURRENT_RUN, encoded["data"])):
        return
    var loaded = store.load(SaveStore.SLOT_CURRENT_RUN)
    if not _ok(h, "E02 读回", loaded):
        return
    var decoded = SnapshotCodec.decode_session(loaded["data"])
    if not _ok(h, "E02 重建会话", decoded):
        return
    var session = decoded["data"]["session"]
    h.eq("E02 读档后候选不重抽", SnapshotCodec.canonical_json(_event_instance(session.run).frozen_candidates), frozen_before)
    h.eq("E02 读档后随机快照原样", SnapshotCodec.canonical_json(session.random_snapshot), rng_before)


func _e03(h) -> void:
    if _premise(h, "E03"):
        return
    var events: Array = _db.enabled_ids(GameConstants.KIND_EVENT)
    var missing := []
    for raw_id in events:
        var definition: Dictionary = _db.definition(GameConstants.KIND_EVENT, String(raw_id))
        if _leave_option(definition).is_empty():
            missing.append(String(raw_id))
    h.check("E03 每个启用事件都有「离开，无变化」选项（空效果+零成本）", missing.is_empty(), str(missing))
    var created: Dictionary = _create_run()
    if not _ok(h, "E03 局创建成功", created):
        return
    var reached := _clear_until_kind(_state(created), _rng(created), RunNodeState.KIND_EVENT)
    if reached.is_empty():
        h.check("E03 推进到事件节点可达", false)
        return
    var entered := _enter_event(reached["run"], reached["rng"])
    if not _ok(h, "E03 进入事件节点", entered):
        return
    var current = _state(entered)
    var current_rng: Dictionary = _rng(entered)
    var instance = _event_instance(current)
    if instance == null:
        h.check("E03 事件实例已建立", false)
        return
    var node_id := String(current.current_node_id)
    var definition: Dictionary = _db.definition(GameConstants.KIND_EVENT, String(instance.definition_id))
    var early_leave: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": node_id}}, current_rng)
    h.check("E03 没选选项时不能离开节点", not Result.is_ok(early_leave), Result.error_code(early_leave))
    var leave_option := _leave_option(definition)
    var chosen = _choose(current, current_rng, instance, leave_option)
    if not _ok(h, "E03 选择「离开，无变化」", chosen):
        return
    var after = _state(chosen)
    h.eq("E03 零副作用：金钱不变", int(after.money), int(current.money))
    h.eq("E03 零副作用：精力不变", int(after.vitality), int(current.vitality))
    h.eq("E03 零副作用：牌组不变", after.cards.size(), current.cards.size())
    h.eq("E03 零副作用：饰品不变", after.relics.size(), current.relics.size())
    h.eq("E03 已记录选项（离开也是显式选项）", String(_event_instance(after).resolved_option_id), String(leave_option["option_id"]))
    var left: Dictionary = _svc.apply(after, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": node_id}}, _rng(chosen))
    if _ok(h, "E03 选完可以离开", left):
        h.eq("E03 节点进入 completed", String(_state(left).find_node(node_id).status), RunNodeState.STATUS_COMPLETED)


func _e04(h) -> void:
    if _premise(h, "E04"):
        return
    var created: Dictionary = _create_run()
    if not _ok(h, "E04 局创建成功", created):
        return
    var reached := _clear_until_kind(_state(created), _rng(created), RunNodeState.KIND_EVENT)
    if reached.is_empty():
        h.check("E04 推进到事件节点可达", false)
        return
    var entered := _enter_event(reached["run"], reached["rng"])
    if not _ok(h, "E04 进入事件节点", entered):
        return
    var current = _state(entered)
    var current_rng: Dictionary = _rng(entered)
    var instance = _event_instance(current)
    if instance == null:
        h.check("E04 事件实例已建立", false)
        return
    var definition: Dictionary = _db.definition(GameConstants.KIND_EVENT, String(instance.definition_id))
    var def_id := String(instance.definition_id)
    var node_id := String(current.current_node_id)
    h.check("E04 进入即记 seen_event_ids（同局同 ID 至多一次）", current.seen_event_ids.has(def_id))
    # ① t10 三个 op 的覆盖点必须先在**未结算**的事件上跑：一旦 event.is_resolved，
    #    再选任何选项都只会得到 ALREADY_RESOLVED，那是假绿（这里曾因此漏跑过）。
    var card_pick := _option_with_op(definition, "gain_card")
    var remove_option := _option_with_op(definition, "remove_card")
    var upgrade_option := _option_with_op(definition, "upgrade_card")
    h.check("[记录] E04 本事件 op 覆盖：gain_card=%s remove_card=%s upgrade_card=%s" % [str(not card_pick.is_empty()), str(not remove_option.is_empty()), str(not upgrade_option.is_empty())], true)
    if not remove_option.is_empty():
        var non_basic := ""
        for card in current.cards:
            if not _has_tag(String(card.definition_id), "basic"):
                non_basic = String(card.card_id)
                break
        if not non_basic.is_empty():
            var denied: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_CHOOSE_EVENT, "payload": {
                "event_instance_id": String(instance.event_instance_id),
                "option_id": String(remove_option["option_id"]),
                "selection_ids": [non_basic],
            }}, current_rng)
            h.check("E04 remove_card 只接受 tag=basic 的目标（非 basic 被拒）", not Result.is_ok(denied), Result.error_code(denied))
    if not upgrade_option.is_empty():
        var non_work := ""
        for card in current.cards:
            if _card_type(String(card.definition_id)) != GameConstants.CARD_WORK:
                non_work = String(card.card_id)
                break
        if not non_work.is_empty():
            var denied_work: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_CHOOSE_EVENT, "payload": {
                "event_instance_id": String(instance.event_instance_id),
                "option_id": String(upgrade_option["option_id"]),
                "selection_ids": [non_work],
            }}, current_rng)
            h.check("E04 upgrade_card 只接受 type=work 的目标（非工作牌被拒）", not Result.is_ok(denied_work), Result.error_code(denied_work))
    if not card_pick.is_empty():
        var frozen: Array = instance.candidates_for(String(card_pick["option_id"]))
        h.check("E04 显式三选一的候选在进入时冻结（数量 ≥1）", frozen.size() >= 1, str(frozen.size()))
        h.check("[记录] E04 gain_card 选项要求从冻结候选里选（selection 非空）", true)
    # ② 收益落地：选 heal → 断言恢复量 → 离开 → 节点 completed。
    var heal_option := _option_with_op(definition, "heal")
    if heal_option.is_empty():
        h.check("[记录] E04 本事件没有 heal 选项，跳过收益落地分支", true)
    else:
        current.vitality = 30
        var amount := 0
        for raw in (heal_option.get("effects", []) as Array):
            if String((raw as Dictionary).get("op", "")) == "heal":
                amount = int((raw as Dictionary).get("amount", 0))
        var chosen = _choose(current, current_rng, instance, heal_option)
        if _ok(h, "E04 选择带收益的选项", chosen):
            var after = _state(chosen)
            h.eq("E04 收益落地（heal 按量恢复并受上限裁切）", int(after.vitality), mini(int(after.max_vitality), 30 + amount))
            h.eq("E04 选项已记录", String(_event_instance(after).resolved_option_id), String(heal_option["option_id"]))
            var left: Dictionary = _svc.apply(after, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": node_id}}, _rng(chosen))
            if _ok(h, "E04 事件节点可以正常离开", left):
                h.eq("E04 节点进入 completed", String(_state(left).find_node(node_id).status), RunNodeState.STATUS_COMPLETED)
