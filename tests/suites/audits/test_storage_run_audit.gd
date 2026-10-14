extends RefCounted
##
## 独立审查套件（verifier，t6）：把《数据库与实体关系设计》§7～§10、《接口文档》§5/§7、
## 《局流程契约》§5/§6/§11 的条文映射成可复现断言，对象是已提交的 src/storage + src/run。
## 独立入口：res://tests/suites/audits/audit_storage_run.gd（刻意不登记进 run_tests.gd）。
##
## 标 [偏差探针] 的断言断言的是「条文本应成立」：变红 = 实现缺该落点，是审查结论而不是回归。
## 其余分节核对已实现行为；[记录] 前缀只记录当前事实。
##
## 白盒说明：为了造出可复现的真实场景，本套件会直接读/摆弄自己持有的 RunState / BattleState
## （例如把 K04 挪进手牌），只改测试态，不触碰实现。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const RandomSource := preload("res://src/common/random_source.gd")
const SnapshotCodec := preload("res://src/storage/snapshot_codec.gd")
const SaveStore := preload("res://src/storage/save_store.gd")
const ProfileMerge := preload("res://src/storage/profile_merge.gd")
const RunService := preload("res://src/run/run_service.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const RewardOffer := preload("res://src/run/run_reward_offer.gd")
const RunCodec := preload("res://src/run/run_codec.gd")
const SessionStateScript := preload("res://src/app/session_state.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")

const MANIFEST := "test_minimal"
const SEED := "20261013"

var _db = null
var _svc = null


func run(h) -> void:
    var db := ContentDB.new()
    var loaded := db.load(MANIFEST)
    if not Result.is_ok(loaded):
        h.begin("审查 · 前置")
        h.check("夹具清单 test_minimal 可加载", false, str(loaded))
        return
    _db = db
    _svc = RunService.new(db)
    h.begin("审查 §7/§9 · 规范化编码与 checksum 范围")
    _canonical(h)
    h.begin("审查 §9/§11.4 · 校验三层与迁移")
    _validation(h)
    h.begin("审查 §8 · 损坏档不删唯一有效副本")
    _backup(h)
    h.begin("审查 §11/§5 · 真实会话存读档后继续同一学期")
    _roundtrip(h)
    h.begin("审查 §5/§6 · 结算幂等与精力一次性写回")
    _settle(h)
    h.begin("审查 §5 · 随机流归属（RunService 不碰 battle 流）")
    _streams(h)
    h.begin("审查 §5/§8 · 交易工作副本与取消语义")
    _transactions(h)
    h.begin("审查 §8 · 结局三步提交（真实摘要）")
    _ending(h)


# ── 工具 ──────────────────────────────────────────────────

func _state(step: Dictionary):
    return step["data"]["state"]


func _rng(step: Dictionary) -> Dictionary:
    return step["data"]["rng_states"]


func _ok(h, label: String, result: Dictionary) -> bool:
    if Result.is_ok(result):
        h.check(label, true)
        return true
    h.check(label, false, str(result.get("error")))
    return false


func _meta(db) -> Dictionary:
    return {"content_version": db.content_version, "content_hash": db.content_hash, "manifest_id": db.manifest_id}


func _session_of(run, rng: Dictionary, revision: int, battle = null) -> Object:
    var session = SessionStateScript.new()
    session.run_id = run.run_id
    session.revision = revision
    session.run = run
    session.battle = battle
    session.random_snapshot = rng
    return session


## 真实一局的可复现摘要：显式列字段，避免依赖被测编码器自身。
func _digest(run, rng: Dictionary) -> String:
    var cards := []
    for card in run.cards:
        cards.append("%s:%s:%d" % [card.card_id, card.definition_id, int(card.upgrade_level)])
    var relics := []
    for relic in run.relics:
        relics.append("%s:%s:%d" % [relic.relic_id, relic.definition_id, int(relic.slot)])
    var nodes := []
    for raw in run.nodes:
        var node: RunNodeState = raw
        nodes.append("%s:%s:%d:%s" % [node.node_id, String(node.kind), int(node.layer), String(node.status)])
    var settled := []
    for key in run.settled_battle_ids:
        settled.append(String(key))
    settled.sort()
    return SnapshotCodec.canonical_json({
        "run_id": run.run_id,
        "term": int(run.term),
        "money": int(run.money),
        "vitality": int(run.vitality),
        "max_vitality": int(run.max_vitality),
        "next_instance_seq": int(run.next_instance_seq),
        "cards": cards,
        "relics": relics,
        "nodes": nodes,
        "current_node_id": String(run.current_node_id),
        "node_path": run.node_path.duplicate(),
        "seen_event_ids": run.seen_event_ids.duplicate(),
        "removals_used": int(run.removals_used),
        "career_direction": String(run.career_direction),
        "settled": settled,
        "reachable": run.reachable_node_ids(),
        "outcome": String(run.outcome),
        "rng": rng,
    })


func _stream(rng: Dictionary, stream_id: String) -> Dictionary:
    var streams: Dictionary = rng.get("streams", {})
    var entry: Variant = streams.get(stream_id)
    return {} if typeof(entry) != TYPE_DICTIONARY else entry


func _wipe(dir: String) -> void:
    var da := DirAccess.open(dir)
    if da == null:
        return
    for name in da.get_files():
        da.remove(name)


func _fresh_store(db, name: String) -> Object:
    var dir := "user://audit_t6_" + name
    _wipe(dir)
    return SaveStore.new(dir, db)


func _create_run(svc) -> Dictionary:
    return svc.create({
        "character_id": "P01",
        "difficulty": GameConstants.DIFFICULTY_NORMAL,
        "manifest_id": svc.catalog.manifest_id,
        "seed": SEED,
    }, {})


func _first_node(run, layer: int, kind: String):
    for raw in run.nodes_of_term(run.term):
        var node: RunNodeState = raw
        if int(node.layer) == layer and String(node.kind) == kind:
            return node
    return null


func _reachable(run) -> Array:
    return run.reachable_node_ids()


## 简单战斗策略：有待选先确认，有工作牌就打主任务，否则结束回合。
func _next_battle_action(state, data: Dictionary) -> Dictionary:
    var choice: Variant = data.get("pending_choice")
    if choice != null:
        var candidates: Array = (choice as Dictionary).get("candidates", [])
        if not candidates.is_empty():
            var option: Dictionary = candidates[0]
            return {"type": GameConstants.ACTION_CONFIRM_CHOICE, "payload": {
                "choice_id": String((choice as Dictionary)["choice_id"]),
                "selected_ids": [String(option["id"])],
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


## 用真实 BattleEngine 把一场战斗打到底，返回 BattleOutcome（失败返回 {}）。
func _fight(db, battle_input: Dictionary) -> Dictionary:
    var engine = BattleEngine.new(db)
    var step: Dictionary = engine.begin(battle_input)
    if not Result.is_ok(step):
        print("[audit] fight begin failed: ", step)
        return {}
    var guard := 0
    while guard < 240:
        guard += 1
        var data: Dictionary = step["data"]
        if data.get("outcome") != null:
            return data["outcome"]
        var next: Dictionary = engine.apply(data["state"], _next_battle_action(data["state"], data), data.get("rng_state"))
        if not Result.is_ok(next):
            print("[audit] fight apply failed: ", next, " at iteration ", guard)
            return {}
        step = next
    print("[audit] fight guard exhausted")
    return {}


## 处理完 pending_reward 的全部项（有候选取第一张）。
func _claim_all(svc, run, rng: Dictionary) -> Dictionary:
    var pending := 0
    while run.pending_reward != null and pending < 16:
        pending += 1
        var offer = run.pending_reward
        var items: Array = offer.pending_items()
        if items.is_empty():
            break
        var item = items[0]
        var payload := {"offer_id": String(offer.offer_id), "item_id": String(item.item_id)}
        if not (item.candidates as Array).is_empty():
            payload["candidate_id"] = String((item.candidates as Array)[0])
        var step: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": payload}, rng)
        if not Result.is_ok(step):
            return step
        run = _state(step)
        rng = _rng(step)
    return Result.ok({"run": run, "rng": rng})


## 进入当前可达的第一个节点；若是战斗则真打一场并结算 + 领奖 + 离开。
## 返回 Result<{run, rng, entered, outcome, node_kind}>。
func _advance_one_node(svc, run, rng: Dictionary) -> Dictionary:
    var reachable: Array = run.reachable_node_ids()
    if reachable.is_empty():
        return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.audit.no_reachable", {})
    var node_id := String(reachable[0])
    var node = run.find_node(node_id)
    var kind := String(node.kind)
    var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node_id}}, rng)
    if not Result.is_ok(entered):
        return entered
    var current = _state(entered)
    var current_rng: Dictionary = _rng(entered)
    var outcome := {}
    if String(current.find_node(node_id).kind) in RunNodeState.BATTLE_KINDS:
        var input: Variant = entered["data"]["battle_input"]
        if typeof(input) != TYPE_DICTIONARY:
            return Result.fail(GameConstants.ERROR_RESOLUTION_ERROR, "error.audit.no_battle_input", {})
        outcome = _fight(_db, input)
        if outcome.is_empty():
            return Result.fail(GameConstants.ERROR_RESOLUTION_ERROR, "error.audit.fight_failed", {"node_id": node_id, "kind": kind})
        var settled: Dictionary = svc.settle_battle(current, outcome, current_rng)
        if not Result.is_ok(settled):
            return settled
        current = _state(settled)
        current_rng = _rng(settled)
        var claimed: Dictionary = _claim_all(svc, current, current_rng)
        if not Result.is_ok(claimed):
            return claimed
        current = claimed["data"]["run"]
        current_rng = claimed["data"]["rng"]
    var left: Dictionary = svc.apply(current, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": node_id}}, current_rng)
    if not Result.is_ok(left):
        return left
    return Result.ok({
        "run": _state(left),
        "rng": _rng(left),
        "node_id": node_id,
        "node_kind": kind,
        "outcome": outcome,
    })


## 反复推进，直到当前可达节点里出现 kind 指定的类型（返回进入前状态）。
func _advance_until_reachable_kind(svc, run, rng: Dictionary, kind: String) -> Dictionary:
    var current = run
    var current_rng: Dictionary = rng
    for _index in range(8):
        var reachable: Array = current.reachable_node_ids()
        if reachable.is_empty():
            break
        var target = current.find_node(String(reachable[0]))
        if String(target.kind) == kind:
            return Result.ok({"run": current, "rng": current_rng})
        var advanced: Dictionary = _advance_one_node(svc, current, current_rng)
        if not Result.is_ok(advanced):
            return advanced
        current = advanced["data"]["run"]
        current_rng = advanced["data"]["rng"]
    return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.audit.kind_not_reachable", {"kind": kind})


# ── §7/§9 规范化编码与 checksum 范围 ─────────────────────

func _canonical(h) -> void:
    var a := {"b": 1, "a": {"y": 2, "x": [3, {"n": 4}]}}
    var b := {"a": {"x": [3, {"n": 4}], "y": 2}, "b": 1}
    h.eq("对象键排序：插入顺序不同得到同一编码", SnapshotCodec.canonical_json(a), SnapshotCodec.canonical_json(b))
    var text := SnapshotCodec.canonical_json(a)
    h.check("编码里 a 在 b 之前", text.find("\"a\"") < text.find("\"b\""), text)
    h.check("嵌套里 x 在 y 之前", text.find("\"x\"") < text.find("\"y\""), text)
    h.eq("数组保持游戏顺序", SnapshotCodec.canonical_json([3, 1, 2]), "[3,1,2]")

    var snapshot := SnapshotCodec.wrap_snapshot({
        "run": {"money": 60, "vitality": 72.0, "cards": ["a", "b"]},
    }, {"content_version": "c1", "content_hash": "h1", "manifest_id": "m1"})
    h.check("外层字段齐全", snapshot.has("schema_version") and snapshot.has("checksum") and snapshot.has("payload"))
    h.eq("checksum 是 64 位十六进制", String(snapshot["checksum"]).length(), 64)
    h.check("写入时 checksum 自洽", SnapshotCodec.checksum_matches(snapshot))
    var reparsed: Variant = JSON.parse_string(SnapshotCodec.canonical_json(snapshot))
    h.check("canonical_json 可被 JSON 解析回对象", typeof(reparsed) == TYPE_DICTIONARY)
    h.check("JSON 往返后 checksum 仍匹配（整数值浮点已规范化）", SnapshotCodec.checksum_matches(reparsed))

    # checksum 范围：只排除 checksum 字段本身。
    var tampered: Dictionary = snapshot.duplicate(true)
    tampered["checksum"] = "x".repeat(64)
    h.eq("checksum 字段自身不参与计算", SnapshotCodec.compute_checksum(tampered), SnapshotCodec.compute_checksum(snapshot))
    var changed: Dictionary = snapshot.duplicate(true)
    changed["payload"]["run"]["money"] = 61
    h.check("payload 变化会改变 checksum", SnapshotCodec.compute_checksum(changed) != SnapshotCodec.compute_checksum(snapshot))
    var outer_changed: Dictionary = snapshot.duplicate(true)
    outer_changed["revision"] = 7
    h.check("外层 revision 变化也会改变 checksum", SnapshotCodec.compute_checksum(outer_changed) != SnapshotCodec.compute_checksum(snapshot))
    h.check("空 checksum 视为不匹配", not SnapshotCodec.checksum_matches({"payload": {}}))

    # 64 位整数字符串化：大于 2^53 的 seed 必须原样往返。
    var big_seed := 1234567890123456789
    var source = RandomSource.new(big_seed)
    var state: Dictionary = source.export_state()
    h.check("随机快照 seed 是十进制字符串", typeof(_stream(state, "map")["seed"]) == TYPE_STRING)
    h.check("随机快照 state 是十进制字符串", typeof(_stream(state, "battle")["state"]) == TYPE_STRING)
    var wrapped := SnapshotCodec.wrap_snapshot({"random_state": state}, {})
    var back: Variant = JSON.parse_string(SnapshotCodec.canonical_json(wrapped))
    h.eq("大种子经 JSON 往返后数值不变", String(_stream(back["payload"]["random_state"], "map")["seed"]), String(_stream(state, "map")["seed"]))
    var probe = RandomSource.new(0)
    h.check("大种子快照可恢复", Result.is_ok(probe.restore_state(back["payload"]["random_state"])))
    h.eq("恢复后的四条流状态完全一致", SnapshotCodec.canonical_json(probe.export_state()), SnapshotCodec.canonical_json(state))
    h.check("对照：同一数字走 float 会失真", str(int(float(big_seed))) != str(big_seed), str(int(float(big_seed))))
    var advanced: Dictionary = state.duplicate(true)
    var move: Dictionary = probe.draw_int(GameConstants.RNG_REWARD, 0, 100)
    h.check("draw_int 推进 reward 流", Result.is_ok(move) and SnapshotCodec.canonical_json(probe.export_state()) != SnapshotCodec.canonical_json(state))


## 用同一份外层元信息换掉 payload 并重算 checksum（用来只让某一层校验失败）。
func _rewrap(snapshot: Dictionary, payload: Dictionary) -> Dictionary:
    return SnapshotCodec.wrap_snapshot(payload, {
        "schema_version": int(snapshot.get("schema_version", 1)),
        "content_version": String(snapshot.get("content_version", "")),
        "content_hash": String(snapshot.get("content_hash", "")),
        "manifest_id": String(snapshot.get("manifest_id", "")),
        "run_id": snapshot.get("run_id"),
        "revision": snapshot.get("revision"),
        "random_state": snapshot.get("random_state"),
    })


## 真实会话：create → 进第 1 层战斗 → 给主角挂 2 层灵感 → 返回 {run, rng, battle, snapshot}。
func _session_with_player_status() -> Dictionary:
    var created: Dictionary = _create_run(_svc)
    if not Result.is_ok(created):
        return {}
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var node = _first_node(run, 1, "normal")
    var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not Result.is_ok(entered):
        return {}
    var input: Dictionary = entered["data"]["battle_input"]
    var engine = BattleEngine.new(_db)
    var step: Dictionary = engine.begin(input)
    if not Result.is_ok(step):
        return {}
    var state = _state(step)
    var k04 := ""
    for raw_id in state.card_by_id:
        var card = state.card_by_id[raw_id]
        if card.definition_id == "K04":
            k04 = String(raw_id)
            break
    if k04.is_empty():
        return {}
    state.move_card(k04, GameConstants.ZONE_HAND)
    var played: Dictionary = engine.apply(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": k04}}, step["data"]["rng_state"])
    if not Result.is_ok(played):
        return {}
    var battle = _state(played)
    var focused = _state(entered)
    var session = _session_of(focused, rng, 1, battle)
    var encoded: Dictionary = SnapshotCodec.encode_session(session, null, _meta(_db))
    if not Result.is_ok(encoded):
        return {}
    return {"run": focused, "rng": rng, "battle": battle, "snapshot": encoded["data"], "outcome": played["data"]["outcome"]}


func _validation(h) -> void:
    var good := SnapshotCodec.wrap_snapshot({"run": {"money": 60}}, {"content_version": "c", "content_hash": "h", "manifest_id": "m"})
    h.check("正常快照第 1 层通过", SnapshotCodec.validate_structure(good).is_empty())
    var no_payload: Dictionary = good.duplicate(true)
    no_payload.erase("payload")
    h.check("缺 payload 被第 1 层拒绝", not SnapshotCodec.validate_structure(no_payload).is_empty())
    var bad_checksum: Dictionary = good.duplicate(true)
    bad_checksum["checksum"] = "short"
    h.check("checksum 长度非法被第 1 层拒绝", not SnapshotCodec.validate_structure(bad_checksum).is_empty())
    var bad_random: Dictionary = good.duplicate(true)
    bad_random["random_state"] = {"streams": {}}
    h.check("random_state 缺 algorithm_version 被拒", not SnapshotCodec.validate_structure(bad_random).is_empty())
    var bad_payload: Dictionary = good.duplicate(true)
    bad_payload["payload"] = []
    h.check("payload 非对象被拒", not SnapshotCodec.validate_structure(bad_payload).is_empty())

    var future: Dictionary = good.duplicate(true)
    future["schema_version"] = 2
    future["checksum"] = SnapshotCodec.compute_checksum(future)
    h.eq("未来 schema_version 返回 VERSION_MISMATCH", Result.error_code(SnapshotCodec.decode(future)), GameConstants.ERROR_VERSION_MISMATCH)
    var tampered: Dictionary = good.duplicate(true)
    tampered["payload"]["run"]["money"] = 999
    h.eq("payload 被改动返回 SAVE_CORRUPT（checksum 不匹配）", Result.error_code(SnapshotCodec.decode(tampered)), GameConstants.ERROR_SAVE_CORRUPT)

    var created: Dictionary = _create_run(_svc)
    if not _ok(h, "create 成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var clean: Dictionary = SnapshotCodec.encode_session(_session_of(run, rng, 1, null), null, _meta(_db))["data"]
    var store := _fresh_store(_db, "validate")
    h.check("控制组：无战斗的当前局快照三层通过", Result.is_ok(store.validate_snapshot(clean, SaveStore.SLOT_CURRENT_RUN)))

    # ── 第 2 层：内容引用与兼容 ──
    var ref_payload := {"run": SnapshotCodec.encode_run(run), "battle": null, "pending_profile_summary": null}
    ref_payload["run"]["cards"][0]["definition_id"] = "K06"
    h.eq("引用未启用定义返回 CONTENT_INVALID", Result.error_code(store.validate_snapshot(_rewrap(clean, ref_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_CONTENT_INVALID)
    var ruleset_payload := {"run": SnapshotCodec.encode_run(run), "battle": null, "pending_profile_summary": null}
    ruleset_payload["run"]["ruleset_id"] = "other_ruleset"
    h.eq("ruleset_id 不一致返回 VERSION_MISMATCH", Result.error_code(store.validate_snapshot(_rewrap(clean, ruleset_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_VERSION_MISMATCH)
    var hash_base: Dictionary = clean.duplicate(true)
    hash_base["content_hash"] = "deadbeef"
    h.eq("content_hash 不一致返回 VERSION_MISMATCH", Result.error_code(store.validate_snapshot(_rewrap(hash_base, ref_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_VERSION_MISMATCH)
    var manifest_base: Dictionary = clean.duplicate(true)
    manifest_base["manifest_id"] = "other_manifest"
    h.eq("manifest_id 不一致返回 VERSION_MISMATCH", Result.error_code(store.validate_snapshot(_rewrap(manifest_base, ref_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_VERSION_MISMATCH)

    # ── 第 3 层：领域不变量 ──
    var money_payload := {"run": SnapshotCodec.encode_run(run), "battle": null, "pending_profile_summary": null}
    money_payload["run"]["money"] = -5
    h.eq("负钱返回 SAVE_CORRUPT", Result.error_code(store.validate_snapshot(_rewrap(clean, money_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)
    var pending_payload := {"run": SnapshotCodec.encode_run(run), "battle": null, "pending_profile_summary": {"run_id": "other#9"}}
    h.eq("待合并摘要 run_id 不匹配返回 SAVE_CORRUPT", Result.error_code(store.validate_snapshot(_rewrap(clean, pending_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)

    # ── 带战斗的稳定边界 ──
    var real := _session_with_player_status()
    if real.is_empty():
        h.check("构造真实战斗会话夹具", false)
        return
    h.check("构造真实战斗会话夹具", true)
    var battle_data: Dictionary = SnapshotCodec.encode_battle(real["battle"])
    battle_data["statuses"] = {}
    var battle_payload := {
        "run": SnapshotCodec.encode_run(real["run"]),
        "battle": battle_data,
        "pending_profile_summary": null,
    }
    var battle_snapshot := _rewrap(real["snapshot"], battle_payload)
    var control: Dictionary = store.validate_snapshot(battle_snapshot, SaveStore.SLOT_CURRENT_RUN)
    h.check("控制组：战斗稳定边界（无主角状态）三层通过", Result.is_ok(control), str(Result.error_detail(control, "problems", [])))
    var res_payload: Dictionary = battle_payload.duplicate(true)
    res_payload["battle"]["resolution"] = {"queue": []}
    var res_check: Dictionary = store.validate_snapshot(_rewrap(battle_snapshot, res_payload), SaveStore.SLOT_CURRENT_RUN)
    h.eq("稳定边界出现 resolution 返回 SAVE_CORRUPT", Result.error_code(res_check), GameConstants.ERROR_SAVE_CORRUPT)
    h.check("问题清单指出 resolution", str(Result.error_detail(res_check, "problems", [])).find("resolution") >= 0, str(Result.error_detail(res_check, "problems", [])))
    var st_payload: Dictionary = battle_payload.duplicate(true)
    st_payload["battle"]["statuses"] = {"s_x": {"definition_id": "not_a_status", "holder_id": "h"}}
    h.eq("battle.statuses 引用未定义状态返回 CONTENT_INVALID", Result.error_code(store.validate_snapshot(_rewrap(battle_snapshot, st_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_CONTENT_INVALID)
    var settled_payload: Dictionary = battle_payload.duplicate(true)
    settled_payload["run"]["settled_battle_ids"] = {String(real["battle"].battle_id): true}
    h.eq("已结算战斗仍挂在场返回 SAVE_CORRUPT", Result.error_code(store.validate_snapshot(_rewrap(battle_snapshot, settled_payload), SaveStore.SLOT_CURRENT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)

    # ── §11.6 已知缺陷在存储层的后果：主角持有状态 → 合法存档被拒 ──
    var player_check: Dictionary = store.validate_snapshot(real["snapshot"], SaveStore.SLOT_CURRENT_RUN)
    h.eq("[偏差探针] 主角持有灵感时合法会话仍应通过三层校验", Result.error_code(player_check), "")
    if not Result.is_ok(player_check):
        h.eq("[记录] 实际返回码", Result.error_code(player_check), GameConstants.ERROR_SAVE_CORRUPT)
        var problems: Array = Result.error_detail(player_check, "problems", [])
        h.check("[记录] 问题清单指向主角状态持有者", str(problems).find("状态持有者不属于本战") >= 0, str(problems))

    # ── 迁移 ──
    var legacy: Dictionary = clean.duplicate(true)
    legacy["schema_version"] = 0
    legacy["checksum"] = SnapshotCodec.compute_checksum(legacy)
    h.eq("无迁移路径返回 VERSION_MISMATCH", Result.error_code(SnapshotCodec.migrate(legacy, {})), GameConstants.ERROR_VERSION_MISMATCH)
    var before := SnapshotCodec.canonical_json(legacy)
    var upgrader := func(snap): return snap
    var migrated: Dictionary = SnapshotCodec.migrate(legacy, {0: upgrader})
    if _ok(h, "提供迁移路径后迁移成功", migrated):
        h.eq("schema_version 提升到 1", int(migrated["data"]["schema_version"]), 1)
        h.check("迁移后 checksum 重算并自洽", SnapshotCodec.checksum_matches(migrated["data"]))
        h.eq("恒等迁移不改动 payload", SnapshotCodec.canonical_json(migrated["data"]["payload"]), SnapshotCodec.canonical_json(legacy["payload"]))
    h.eq("迁移在副本上执行，入参快照不被修改", SnapshotCodec.canonical_json(legacy), before)
    var future_again: Dictionary = clean.duplicate(true)
    future_again["schema_version"] = 99
    future_again["checksum"] = SnapshotCodec.compute_checksum(future_again)
    h.eq("未来版本迁移返回 VERSION_MISMATCH", Result.error_code(SnapshotCodec.migrate(future_again, {})), GameConstants.ERROR_VERSION_MISMATCH)


## main 或 backup 至少有一份能通过加载（= 至少一份有效档）。
func _any_valid(store, slot: String) -> bool:
    if Result.is_ok(store.load(slot)):
        return true
    return Result.is_ok(store.load_backup(slot))


func _backup(h) -> void:
    var store := _fresh_store(_db, "backup")
    var slot := SaveStore.SLOT_CURRENT_RUN
    var created: Dictionary = _create_run(_svc)
    if not _ok(h, "create 成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var rev1: Dictionary = SnapshotCodec.encode_session(_session_of(run, rng, 1, null), null, _meta(_db))["data"]
    var rev2: Dictionary = SnapshotCodec.encode_session(_session_of(run, rng, 2, null), null, _meta(_db))["data"]
    if not _ok(h, "首次保存", store.save(slot, rev1)):
        return
    h.eq("首存没有备份", Result.error_code(store.load_backup(slot)), GameConstants.ERROR_SAVE_NOT_FOUND)
    if not _ok(h, "第二次保存", store.save(slot, rev2)):
        return
    var backup: Dictionary = store.load_backup(slot)
    if _ok(h, "备份可读（轮转到上一版）", backup):
        h.eq("备份是 revision 1", int(backup["data"]["revision"]), 1)

    # 正式档损坏：不删证据、备份仍可用。
    var file := FileAccess.open(store.path_for(slot), FileAccess.WRITE)
    file.store_string("broken")
    file.close()
    h.eq("正式档损坏返回 SAVE_CORRUPT", Result.error_code(store.load(slot)), GameConstants.ERROR_SAVE_CORRUPT)
    h.check("损坏的正式档文件仍在（保留证据）", FileAccess.file_exists(store.path_for(slot)))
    h.check("备份仍可加载", Result.is_ok(store.load_backup(slot)))
    var inspected: Dictionary = store.inspect(slot)
    if Result.is_ok(inspected):
        h.eq("inspect 标出 valid=false", bool(inspected["data"]["valid"]), false)

    # 两份都损坏：都报错，且都不被删除。
    var backup_file := FileAccess.open(store.backup_path_for(slot), FileAccess.WRITE)
    backup_file.store_string("broken too")
    backup_file.close()
    h.eq("备份损坏返回 SAVE_CORRUPT", Result.error_code(store.load_backup(slot)), GameConstants.ERROR_SAVE_CORRUPT)
    h.check("两份损坏时文件都还在（不自动覆盖证据）", FileAccess.file_exists(store.path_for(slot)) and FileAccess.file_exists(store.backup_path_for(slot)))
    h.check("两份损坏时没有任何有效档", not _any_valid(store, slot))

    # ── 故障注入：写失败 / 写一半 / 备份后失败 / 替换失败 ──
    var hooks := _fresh_store(_db, "hooks")
    var hslot := SaveStore.SLOT_CURRENT_RUN
    hooks.save(hslot, rev1)
    hooks.save(hslot, rev2)
    hooks.debug_hooks = {"current_run": {"fail_write": true}}
    h.eq("fail_write 返回 SAVE_IO_ERROR", Result.error_code(hooks.save(hslot, rev1)), GameConstants.ERROR_SAVE_IO_ERROR)
    h.eq("fail_write 后正式档仍是旧值", int(hooks.load(hslot)["data"]["revision"]), 2)
    hooks.debug_hooks = {"current_run": {"truncate_temp": true}}
    h.eq("写一半中断返回 SAVE_IO_ERROR", Result.error_code(hooks.save(hslot, rev1)), GameConstants.ERROR_SAVE_IO_ERROR)
    h.check("中断后临时文件已清理", not FileAccess.file_exists(hooks.temp_path_for(hslot)))
    h.eq("中断后正式档仍是旧值", int(hooks.load(hslot)["data"]["revision"]), 2)
    hooks.debug_hooks = {"current_run": {"fail_after_backup": true}}
    h.eq("备份后失败返回 SAVE_IO_ERROR", Result.error_code(hooks.save(hslot, rev1)), GameConstants.ERROR_SAVE_IO_ERROR)
    h.check("备份后失败仍保留有效正式档", Result.is_ok(hooks.load(hslot)))
    hooks.debug_hooks = {"current_run": {"fail_rename": true}}
    h.eq("替换失败返回 SAVE_IO_ERROR", Result.error_code(hooks.save(hslot, rev1)), GameConstants.ERROR_SAVE_IO_ERROR)
    h.check("替换失败后仍有有效档可加载", _any_valid(hooks, hslot))
    hooks.debug_hooks = {}

    # ── [偏差探针] 备份拷贝失败未被检查 ──
    # 注入方式：把备份路径占成目录，等价于「拷贝旧有效档到备份」这一步失败（磁盘满/权限不足）。
    # 代码不检查 copy_absolute 的返回值，随后无条件删除正式档；若替换阶段再失败，唯一有效副本就没了。
    var probe_store := _fresh_store(_db, "backup_copy_probe")
    var pslot := SaveStore.SLOT_CURRENT_RUN
    if not _ok(h, "探针：首存成功", probe_store.save(pslot, rev1)):
        return
    var abs_backup := ProjectSettings.globalize_path(probe_store.backup_path_for(pslot))
    if DirAccess.dir_exists_absolute(abs_backup):
        DirAccess.remove_absolute(abs_backup)
    h.eq("故障注入：备份路径被占成目录（模拟拷贝失败）", DirAccess.make_dir_absolute(abs_backup), OK)
    probe_store.debug_hooks = {"current_run": {"fail_rename": true}}
    h.eq("探针：失败发生在替换阶段", Result.error_code(probe_store.save(pslot, rev2)), GameConstants.ERROR_SAVE_IO_ERROR)
    var probe_reloaded = probe_store.load(pslot)
    h.check("[正向] 修复后：正式档仍在且可加载（不再被删）", Result.is_ok(probe_reloaded))
    if Result.is_ok(probe_reloaded):
        h.eq("[正向] 正式档仍是修复前那一版（revision 1）", int(probe_reloaded["data"]["revision"]), 1)
    h.check("[记录] 备份路径不是一个有效档", not Result.is_ok(probe_store.load_backup(pslot)))
    h.check("[偏差探针] 保存失败后仍应保留至少一份有效档", _any_valid(probe_store, pslot))
    probe_store.debug_hooks = {}


# ── §11/§5 真实会话：存读档后继续同一学期 ─────────────────

func _roundtrip(h) -> void:
    var control: Dictionary = _create_run(_svc)
    if not _ok(h, "create 成功（控制组）", control):
        return
    var c_run = _state(control)
    var c_rng: Dictionary = _rng(control)
    var c1: Dictionary = _advance_one_node(_svc, c_run, c_rng)
    if not _ok(h, "控制组：清掉第 1 层战斗节点", c1):
        return
    c_run = c1["data"]["run"]
    c_rng = c1["data"]["rng"]

    var created: Dictionary = _create_run(_svc)
    if not _ok(h, "create 成功（存读档组）", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var step1: Dictionary = _advance_one_node(_svc, run, rng)
    if not _ok(h, "存读档组：清掉第 1 层战斗节点", step1):
        return
    run = step1["data"]["run"]
    rng = step1["data"]["rng"]
    h.eq("两组第 1 步结果一致（同种子确定性）", _digest(run, rng), _digest(c_run, c_rng))

    var store := _fresh_store(_db, "roundtrip")
    var slot := SaveStore.SLOT_CURRENT_RUN
    var encoded: Dictionary = SnapshotCodec.encode_session(_session_of(run, rng, 3, null), null, _meta(_db))
    if not _ok(h, "encode_session 成功", encoded):
        return
    h.check("快照里随机流是十进制字符串", typeof(_stream(encoded["data"]["random_state"], "map")["seed"]) == TYPE_STRING)
    if not _ok(h, "save 成功", store.save(slot, encoded["data"])):
        return
    var loaded: Dictionary = store.load(slot)
    if not _ok(h, "load 成功", loaded):
        return
    var decoded: Dictionary = SnapshotCodec.decode_session(loaded["data"])
    if not _ok(h, "decode_session 成功", decoded):
        return
    var session = decoded["data"]["session"]
    h.eq("读档后 revision 保留", int(session.revision), 3)
    h.eq("读档后 run_id 保留", String(session.run_id), String(run.run_id))
    h.eq("读档后随机快照原样", SnapshotCodec.canonical_json(session.random_snapshot), SnapshotCodec.canonical_json(rng))
    h.eq("§11 跨模块：存读档前后局状态摘要一致（地图/奖励进度不丢）", _digest(session.run, session.random_snapshot), _digest(run, rng))
    h.eq("读档后可达节点集合一致", str(session.run.reachable_node_ids()), str(run.reachable_node_ids()))
    h.check("读档后 RunState 自洽", session.run.validate(6).is_empty(), str(session.run.validate(6)))

    var c2: Dictionary = _advance_one_node(_svc, c_run, c_rng)
    var resume: Dictionary = _advance_one_node(_svc, session.run, session.random_snapshot)
    if _ok(h, "控制组第二步", c2) and _ok(h, "读档后可继续进入下一个节点", resume):
        h.eq("读档后继续两步都与控制组一致（含全部随机流）", _digest(resume["data"]["run"], resume["data"]["rng"]), _digest(c2["data"]["run"], c2["data"]["rng"]))


# ── §5/§6 结算幂等与精力一次性写回 ───────────────────────

func _settle(h) -> void:
    var created: Dictionary = _create_run(_svc)
    if not _ok(h, "create 成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var node = _first_node(run, 1, "normal")
    var outcome_win := {
        "battle_id": String(node.node_id),
        "result": GameConstants.OUTCOME_WON,
        "reason": GameConstants.REASON_TASKS_COMPLETED,
        "remaining_vitality": 40,
    }
    var early: Dictionary = _svc.settle_battle(run, outcome_win, rng)
    h.eq("无活动战斗时结算返回 WRONG_PHASE", Result.error_code(early), GameConstants.ERROR_WRONG_PHASE)
    var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, "进入战斗节点", entered):
        return
    var in_battle = _state(entered)
    var battle_rng: Dictionary = _rng(entered)
    h.eq("battle_id == 节点 ID", String(in_battle.active_battle_id), String(node.node_id))
    var wrong := outcome_win.duplicate(true)
    wrong["battle_id"] = "other|node"
    h.eq("battle_id 不匹配返回 INVALID_TARGET", Result.error_code(_svc.settle_battle(in_battle, wrong, battle_rng)), GameConstants.ERROR_INVALID_TARGET)
    var bad_result := outcome_win.duplicate(true)
    bad_result["result"] = "draw"
    h.eq("非法结果值返回 INVALID_ARGUMENT", Result.error_code(_svc.settle_battle(in_battle, bad_result, battle_rng)), GameConstants.ERROR_INVALID_ARGUMENT)
    h.check("失败调用不改变调用方状态", String(in_battle.active_battle_id) == String(node.node_id) and not in_battle.settled_battle_ids.has(String(node.node_id)))

    var settled: Dictionary = _svc.settle_battle(in_battle, outcome_win, battle_rng)
    if not _ok(h, "结算成功", settled):
        return
    var after = _state(settled)
    h.eq("精力一次性写回为 40（赋值而不是叠加）", int(after.vitality), 40)
    h.eq("生活费一次性发放：60+15=75", int(after.money), 75)
    h.check("battle_id 进入已结算集合", after.settled_battle_ids.has(String(node.node_id)))
    h.eq("活动战斗已清空", String(after.active_battle_id), "")
    h.check("胜利后生成待处理奖励", after.pending_reward != null)
    var again := outcome_win.duplicate(true)
    again["remaining_vitality"] = 5
    h.eq("重复结算返回 ALREADY_RESOLVED", Result.error_code(_svc.settle_battle(after, again, battle_rng)), GameConstants.ERROR_ALREADY_RESOLVED)
    h.eq("精力没有被第二次写回（仍 40）", int(after.vitality), 40)
    h.eq("金钱没有被第二次发放（仍 75）", int(after.money), 75)
    h.eq("节点状态已进入 active", String(after.find_node(node.node_id).status), RunNodeState.STATUS_ACTIVE)

    # 幂等键跨读档仍然有效
    var store := _fresh_store(_db, "settle")
    var slot := SaveStore.SLOT_CURRENT_RUN
    var encoded: Dictionary = SnapshotCodec.encode_session(_session_of(after, battle_rng, 4, null), null, _meta(_db))
    if not _ok(h, "结算后 encode_session 成功", encoded):
        return
    if not _ok(h, "保存结算后的局势", store.save(slot, encoded["data"])):
        return
    var reloaded: Dictionary = store.load(slot)
    if not _ok(h, "读回结算后的局势", reloaded):
        return
    var session = SnapshotCodec.decode_session(reloaded["data"])["data"]["session"]
    h.eq("读档后精力仍是 40", int(session.run.vitality), 40)
    h.eq("读档后金钱仍是 75", int(session.run.money), 75)
    h.check("读档后已结算集合仍在", session.run.settled_battle_ids.has(String(node.node_id)))
    var replay := outcome_win.duplicate(true)
    replay["remaining_vitality"] = 1
    h.eq("读档后重复结算仍被拒", Result.error_code(_svc.settle_battle(session.run, replay, session.random_snapshot)), GameConstants.ERROR_ALREADY_RESOLVED)
    h.check("拒绝后读档状态未被改动", int(session.run.vitality) == 40 and int(session.run.money) == 75)


# ── §5 随机流归属 ─────────────────────────────────────────

func _same_stream(a: Dictionary, b: Dictionary, stream_id: String) -> bool:
    return SnapshotCodec.canonical_json(_stream(a, stream_id)) == SnapshotCodec.canonical_json(_stream(b, stream_id))


func _streams(h) -> void:
    var created: Dictionary = _create_run(_svc)
    if not _ok(h, "create 成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var node = _first_node(run, 1, "normal")
    var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, "进入战斗节点", entered):
        return
    var after_enter: Dictionary = _rng(entered)
    h.check("[记录] test_minimal 的 normal 池只有 1 个候选：进入战斗节点不推进 map 流（randi_range(0,0) 不推进）", _same_stream(after_enter, rng, GameConstants.RNG_MAP))
    h.check("进入战斗节点不动 battle 流", _same_stream(after_enter, rng, GameConstants.RNG_BATTLE))
    h.check("进入战斗节点不动 reward 流", _same_stream(after_enter, rng, GameConstants.RNG_REWARD))
    h.check("进入战斗节点不动 event 流", _same_stream(after_enter, rng, GameConstants.RNG_EVENT))

    var outcome := {
        "battle_id": String(node.node_id),
        "result": GameConstants.OUTCOME_WON,
        "reason": GameConstants.REASON_TASKS_COMPLETED,
        "remaining_vitality": 40,
    }
    var settled: Dictionary = _svc.settle_battle(_state(entered), outcome, after_enter)
    if not _ok(h, "结算成功", settled):
        return
    var after_settle: Dictionary = _rng(settled)
    h.check("结算推进 reward 流（冻结奖励候选）", not _same_stream(after_settle, after_enter, GameConstants.RNG_REWARD))
    h.check("结算不动 map 流", _same_stream(after_settle, after_enter, GameConstants.RNG_MAP))
    h.check("结算不动 battle 流", _same_stream(after_settle, after_enter, GameConstants.RNG_BATTLE))
    h.check("结算不动 event 流", _same_stream(after_settle, after_enter, GameConstants.RNG_EVENT))

    var claimed: Dictionary = _claim_all(_svc, _state(settled), after_settle)
    if not _ok(h, "领完奖励", claimed):
        return
    var after_claim: Dictionary = claimed["data"]["rng"]
    h.check("领取奖励不动任何随机流", SnapshotCodec.canonical_json(after_claim) == SnapshotCodec.canonical_json(after_settle))
    var left: Dictionary = _svc.apply(claimed["data"]["run"], {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": node.node_id}}, after_claim)
    if not _ok(h, "离开节点", left):
        return
    h.check("离开节点不动 battle 流", _same_stream(_rng(left), after_claim, GameConstants.RNG_BATTLE))
    h.check("离开节点不动 map 流（未进入新节点）", _same_stream(_rng(left), after_claim, GameConstants.RNG_MAP))

    # 被拒的操作不消费随机：先失败一次再正常进入，结果应与直接进入一致。
    var with_failure: Dictionary = _svc.apply(_state(created), {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": _first_node(run, 6, "boss").node_id}}, rng)
    h.eq("跳过 5 层进入首领被拒", Result.error_code(with_failure), GameConstants.ERROR_INVALID_TARGET)
    var then_enter: Dictionary = _svc.apply(_state(created), {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if _ok(h, "失败后再进入第 1 层节点", then_enter):
        h.eq("被拒操作没有消费随机", _digest(_state(then_enter), _rng(then_enter)), _digest(_state(entered), after_enter))

    # ── [偏差探针] 契约 §5：候选池只有 1 个时不推进 map 流 ──
    h.eq("[偏差探针] 契约 §5：候选池只有 1 个（test_minimal 的 normal 池只有 N01）时不推进 map 流", SnapshotCodec.canonical_json(_stream(after_enter, GameConstants.RNG_MAP)), SnapshotCodec.canonical_json(_stream(rng, GameConstants.RNG_MAP)))
    _pool_advance(h)


# ── §5/§8 交易工作副本与取消语义 ─────────────────────────

func _enter_shop(h, label: String) -> Dictionary:
    var created: Dictionary = _create_run(_svc)
    if not _ok(h, label + " create 成功", created):
        return {}
    var reached: Dictionary = _advance_until_reachable_kind(_svc, _state(created), _rng(created), "shop")
    if not _ok(h, label + " 推进到商店可达", reached):
        return {}
    var run = reached["data"]["run"]
    var rng: Dictionary = reached["data"]["rng"]
    var node = run.find_node(String(run.reachable_node_ids()[0]))
    var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, label + " 进入商店节点", entered):
        return {}
    var shop_run = _state(entered)
    var shop = shop_run.current_node().context.get("shop")
    h.check(label + " 商店库存已生成", shop != null and not (shop.stocks as Array).is_empty())
    if shop == null or (shop.stocks as Array).is_empty():
        return {}
    return {"run": shop_run, "rng": _rng(entered), "shop": shop}


func _transactions(h) -> void:
    var a := _enter_shop(h, "买")
    if a.is_empty():
        return
    var run = a["run"]
    var rng: Dictionary = a["rng"]
    var shop = a["shop"]
    var cheapest = null
    for raw in shop.stocks:
        if cheapest == null or int((raw as Object).price) < int((cheapest as Object).price):
            cheapest = raw
    h.eq("清两个战斗节点后钱 = 60+15+15 = 90", int(run.money), 90)
    var deck_before: int = run.cards.size()
    h.check("清两个战斗节点后牌组已含 2 张奖励牌", deck_before >= 13, str(deck_before))
    var preview = _svc.preview(run, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": String((cheapest as Object).stock_id)}})
    if Result.is_ok(preview):
        h.check("preview 允许购买", bool(preview["data"]["can_submit"]))
        h.eq("preview 报的价钱与库存一致", int((preview["data"]["costs"] as Dictionary).get("money", -1)), int((cheapest as Object).price))
    h.check("cancel 语义：preview 不改金钱/库存/牌组", int(run.money) == 90 and not bool((cheapest as Object).sold) and run.cards.size() == deck_before)

    var before_digest := _digest(run, rng)
    var unknown: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": "no-such-stock"}}, rng)
    h.eq("未知库存返回 INVALID_TARGET", Result.error_code(unknown), GameConstants.ERROR_INVALID_TARGET)
    h.eq("失败交易不改动调用方状态（工作副本）", _digest(run, rng), before_digest)

    var card = null
    for raw in shop.stocks:
        if String((raw as Object).kind) == "card" and card == null:
            card = raw
    if card == null:
        h.check("商店里有卡牌库存", false)
        return
    var price := int((card as Object).price)
    var bought: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": String((card as Object).stock_id)}}, rng)
    if not _ok(h, "购买卡牌成功", bought):
        return
    var current = _state(bought)
    var current_rng: Dictionary = _rng(bought)
    h.eq("金钱按现算价格扣除", int(current.money), 90 - price)
    h.check("库存标记已售出", bool(current.current_node().context["shop"].find_stock(String((card as Object).stock_id)).sold))
    h.eq("牌组 +1", current.cards.size(), deck_before + 1)
    var again: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": String((card as Object).stock_id)}}, current_rng)
    h.eq("重复购买返回 ALREADY_RESOLVED", Result.error_code(again), GameConstants.ERROR_ALREADY_RESOLVED)
    h.eq("重复购买不重复扣钱", int(current.money), 90 - price)

    # 买光所有买得起的库存，剩下的必须都是「钱不够」。
    var guard := 0
    while guard < 10:
        guard += 1
        var affordable = null
        for raw in current.current_node().context["shop"].stocks:
            if not bool((raw as Object).sold) and int((raw as Object).price) <= int(current.money):
                affordable = raw
                break
        if affordable == null:
            break
        var step_buy: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": String((affordable as Object).stock_id)}}, current_rng)
        if not Result.is_ok(step_buy):
            break
        current = _state(step_buy)
        current_rng = _rng(step_buy)
    var money_before_denied := int(current.money)
    var unsold := 0
    for raw in current.current_node().context["shop"].stocks:
        if bool((raw as Object).sold):
            continue
        unsold += 1
        var denied: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": String((raw as Object).stock_id)}}, current_rng)
        h.eq("钱不够返回 INSUFFICIENT_RESOURCE：%s" % String((raw as Object).stock_id), Result.error_code(denied), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
    h.check("用例有效：确实存在买不起的库存", unsold > 0)
    h.eq("买不起的失败不扣钱", int(current.money), money_before_denied)

    # ── 删牌：价格现算 + 每店 1 次 ──
    var b := _enter_shop(h, "删")
    if b.is_empty():
        return
    var run_b = b["run"]
    var rng_b: Dictionary = b["rng"]
    h.eq("首删价格 = 60 + 20×0", int(_svc.transactions().removal_price(run_b)), 60)
    var before_size: int = run_b.cards.size()
    var target = run_b.cards[0]
    var removed: Dictionary = _svc.apply(run_b, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"card_instance_id": String(target.card_id)}}, rng_b)
    if _ok(h, "删牌成功", removed):
        var after_b = _state(removed)
        h.eq("金钱扣除删牌价：90-60=30", int(after_b.money), 30)
        h.eq("牌组 -1", after_b.cards.size(), before_size - 1)
        h.eq("全局删牌次数 +1", int(after_b.removals_used), 1)
        h.check("目标卡已不在牌组", after_b.find_card(String(target.card_id)) == null)
        h.eq("下次删牌价格递增到 80", int(_svc.transactions().removal_price(after_b)), 80)
        var twice: Dictionary = _svc.apply(after_b, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"card_instance_id": String(after_b.cards[0].card_id)}}, _rng(removed))
        h.eq("每店上限触发 LIMIT_REACHED", Result.error_code(twice), GameConstants.ERROR_LIMIT_REACHED)
        h.eq("被拒后金钱不变", int(after_b.money), 30)
        h.eq("被拒后牌组不变", after_b.cards.size(), before_size - 1)
    var bad: Dictionary = _svc.apply(run_b, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"card_instance_id": "no-such-card"}}, rng_b)
    h.eq("未知实例返回 INVALID_TARGET", Result.error_code(bad), GameConstants.ERROR_INVALID_TARGET)
    h.eq("失败删牌不扣钱/不计数", int(run_b.money) == 90 and int(run_b.removals_used) == 0)


func _sorted(raw: Variant) -> Array:
    var items: Array = []
    if typeof(raw) == TYPE_ARRAY:
        for item in (raw as Array):
            items.append(String(item))
    items.sort()
    return items


# ── §8 结局三步提交（真实摘要） ───────────────────────────

func _ending(h) -> void:
    var created: Dictionary = _create_run(_svc)
    if not _ok(h, "create 成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var node = _first_node(run, 1, "normal")
    var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, "进入战斗节点", entered):
        return
    var lost := {
        "battle_id": String(node.node_id),
        "result": GameConstants.OUTCOME_LOST,
        "reason": GameConstants.REASON_VITALITY_DEPLETED,
        "remaining_vitality": 0,
    }
    var settled: Dictionary = _svc.settle_battle(_state(entered), lost, _rng(entered))
    if not _ok(h, "结算为失败", settled):
        return
    var after = _state(settled)
    h.eq("失败局 outcome=lost", String(after.outcome), GameConstants.OUTCOME_LOST)
    h.check("失败局生成摘要", after.run_summary != null)
    h.check("pending_profile_summary 与 run_id 一致", after.pending_profile_summary != null and String(after.pending_profile_summary.run_id) == String(after.run_id))
    h.check("pending 与 run_summary 是同一对象（§3）", after.pending_profile_summary == after.run_summary)
    h.check("摘要带 unlock/seen 数组", typeof(after.run_summary.unlocked_ids) == TYPE_ARRAY)
    var pending: Variant = after.pending_profile_summary
    var store := _fresh_store(_db, "ending")
    var slot := SaveStore.SLOT_CURRENT_RUN
    var profile_slot := SaveStore.SLOT_PROFILE
    var raw_pending = SnapshotCodec.encode_session(_session_of(after, _rng(settled), 5, null), pending, _meta(_db))
    print("[audit] encode_session(RunSummary 对象) -> ", str(raw_pending))
    h.check("[偏差探针] 传 RunState 的 RunSummary 对象时仍应返回带 ok/error 的 Result（《接口文档》§1.2 统一返回结构）",
        typeof(raw_pending) == TYPE_DICTIONARY and raw_pending.has("ok"),
        "实际返回：" + str(raw_pending))
    h.check("[记录] 该路径抛 Invalid cast 运行时错误，正确用法是传 RunCodec.encode_summary() 的扁平字典",
        typeof(raw_pending) == TYPE_DICTIONARY and not Result.is_ok(raw_pending))
    var encoded_pending: Dictionary = RunCodec.encode_summary(pending)
    var encoded: Dictionary = SnapshotCodec.encode_session(_session_of(after, _rng(settled), 5, null), encoded_pending, _meta(_db))
    if not _ok(h, "带 pending 的 encode_session 成功", encoded):
        return
    if not _ok(h, "保存带 pending 的 current_run", store.save(slot, encoded["data"])):
        return
    var committed: Dictionary = store.commit_pending_profile(slot, profile_slot)
    if _ok(h, "commit_pending_profile 成功", committed):
        h.eq("merged=true", bool(committed["data"]["merged"]), true)
        h.eq("completed_runs=1", int(committed["data"]["completed_runs"]), 1)
    var profile = store.load(profile_slot)
    if _ok(h, "Profile 已写出", profile):
        var payload: Dictionary = profile["data"]["payload"]
        var summaries: Dictionary = payload["summaries_by_run_id"]
        h.eq("按 run_id 只记一份摘要", summaries.size(), 1)
        h.eq("completed_runs = 去重摘要数", int(payload["completed_runs"]), summaries.size())
        h.eq("unlocked_ids 已排序", str(payload["unlocked_ids"]), str(_sorted(payload["unlocked_ids"])))
        h.eq("seen_content_ids 已排序", str(payload["seen_content_ids"]), str(_sorted(payload["seen_content_ids"])))
    var cleared: Dictionary = store.load(slot)
    if Result.is_ok(cleared):
        h.check("第 3 步已清空 pending", cleared["data"]["payload"]["pending_profile_summary"] == null)
    var second: Dictionary = store.commit_pending_profile(slot, profile_slot)
    if _ok(h, "无 pending 时再次提交成功", second):
        h.eq("第二次 merged=false", bool(second["data"]["merged"]), false)
    var again = store.load(profile_slot)
    if Result.is_ok(again):
        h.eq("摘要仍是 1 份（幂等）", (again["data"]["payload"]["summaries_by_run_id"] as Dictionary).size(), 1)
        h.eq("completed_runs 仍是 1", int(again["data"]["payload"]["completed_runs"]), 1)

    # 第 2 步失败：pending 保留、Profile 未写出。
    var store2 := _fresh_store(_db, "ending_step2")
    if _ok(h, "保存带 pending 的 current_run（第 2 步失败组）", store2.save(slot, encoded["data"])):
        store2.debug_hooks = {"profile": {"fail_write": true}}
        h.eq("Profile 写失败返回 SAVE_IO_ERROR", Result.error_code(store2.commit_pending_profile(slot, profile_slot)), GameConstants.ERROR_SAVE_IO_ERROR)
        store2.debug_hooks = {}
        h.eq("失败后 Profile 仍不存在", Result.error_code(store2.load(profile_slot)), GameConstants.ERROR_SAVE_NOT_FOUND)
        var still = store2.load(slot)
        if Result.is_ok(still):
            h.check("失败后 pending 仍保留", still["data"]["payload"]["pending_profile_summary"] != null)

    # 第 3 步失败：重试不重复记录。
    var store3 := _fresh_store(_db, "ending_step3")
    if _ok(h, "保存带 pending 的 current_run（第 3 步失败组）", store3.save(slot, encoded["data"])):
        store3.debug_hooks = {"current_run": {"fail_write": true}}
        h.eq("清 pending 步骤失败返回 SAVE_IO_ERROR", Result.error_code(store3.commit_pending_profile(slot, profile_slot)), GameConstants.ERROR_SAVE_IO_ERROR)
        store3.debug_hooks = {}
        var profile3 = store3.load(profile_slot)
        if Result.is_ok(profile3):
            h.eq("第 2 步已生效：摘要 1 份", (profile3["data"]["payload"]["summaries_by_run_id"] as Dictionary).size(), 1)
        var retried: Dictionary = store3.commit_pending_profile(slot, profile_slot)
        if _ok(h, "重试提交成功", retried):
            h.eq("重试 merged=true", bool(retried["data"]["merged"]), true)
            h.eq("重试不重复记（completed_runs 仍 1）", int(retried["data"]["completed_runs"]), 1)
        var profile3b = store3.load(profile_slot)
        if Result.is_ok(profile3b):
            h.eq("重试后摘要仍只 1 份", (profile3b["data"]["payload"]["summaries_by_run_id"] as Dictionary).size(), 1)
        var cleared3 = store3.load(slot)
        if Result.is_ok(cleared3):
            h.check("重试后 pending 已清空", cleared3["data"]["payload"]["pending_profile_summary"] == null)


## 契约 §5 另一半：候选池有多个时，map 流必须推进（test_minimal 只有单候选，这里换 mvp 清单核对）。
func _pool_advance(h) -> void:
    var db := ContentDB.new()
    var loaded := db.load("mvp")
    if not _ok(h, "mvp 清单可加载", loaded):
        return
    var svc := RunService.new(db)
    var created: Dictionary = svc.create({
        "character_id": "P01",
        "difficulty": GameConstants.DIFFICULTY_NORMAL,
        "manifest_id": db.manifest_id,
        "seed": SEED,
    }, {})
    if not _ok(h, "mvp 局创建成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var node = _first_node(run, 1, "normal")
    if node == null:
        h.check("mvp 第 1 层有普通节点", false)
        return
    var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, "mvp 进入战斗节点", entered):
        return
    h.check("[记录] mvp 的 normal 池有多个候选 → map 流推进", not _same_stream(_rng(entered), rng, GameConstants.RNG_MAP))
    h.check("[记录] 多候选时也不动 battle 流", _same_stream(_rng(entered), rng, GameConstants.RNG_BATTLE))
