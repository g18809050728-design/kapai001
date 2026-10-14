extends RefCounted
##
## SnapshotCodec 验收：规范化、checksum、会话往返、64 位随机、拒绝与迁移。
## 依据《数据库与实体关系设计》§7/§9。
##

const Ids := preload("res://src/common/ids.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const BattleStateScript := preload("res://src/battle/battle_state.gd")
const SessionStateScript := preload("res://src/app/session_state.gd")
const RandomSource := preload("res://src/common/random_source.gd")
const SnapshotCodec := preload("res://src/storage/snapshot_codec.gd")
const RunSummaryScript := preload("res://src/run/run_summary.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")

const CONTENT_INFO := {"content_version": "test-1", "content_hash": "hash-1", "manifest_id": "mvp"}


func run(h) -> void:
        h.begin("SnapshotCodec · 规范化与校验和")
        _canonical(h)
        h.begin("SnapshotCodec · 会话往返")
        _round_trip(h)
        h.begin("SnapshotCodec · 64 位随机状态")
        _rng(h)
        h.begin("SnapshotCodec · 拒绝与损坏")
        _reject(h)
        h.begin("SnapshotCodec · 迁移")
        _migrate(h)


func _canonical(h) -> void:
        var a = {"b": 1, "a": [3, 2, 1]}
        var b = {"a": [3, 2, 1], "b": 1}
        h.eq("对象键排序后一致", SnapshotCodec.canonical_json(a), SnapshotCodec.canonical_json(b))
        h.eq("数组顺序原样保留", SnapshotCodec.canonical_json([3, 2, 1]), "[3,2,1]")
        var s1 = SnapshotCodec.wrap_snapshot({"x": 1}, {"run_id": "r", "revision": 2, "content_hash": "h"})
        var s2 = SnapshotCodec.wrap_snapshot({"x": 1}, {"revision": 2, "content_hash": "h", "run_id": "r"})
        h.eq("checksum 与键插入顺序无关", s1["checksum"], s2["checksum"])
        h.eq("checksum 是 64 位十六进制", String(s1["checksum"]).length(), 64)

        # JSON 往返：JSON.parse 把数字变 float，规范化后 checksum 必须仍然匹配
        var text = SnapshotCodec.canonical_json(s1)
        var parsed = JSON.parse_string(text)
        h.check("解析得到的快照 checksum 仍匹配", SnapshotCodec.checksum_matches(parsed))
        var tampered = s1.duplicate(true)
        tampered["payload"]["x"] = 2
        h.check("篡改 payload 后 checksum 不匹配", not SnapshotCodec.checksum_matches(tampered))
        tampered = s1.duplicate(true)
        tampered["checksum"] = "0".repeat(64)
        h.check("篡改 checksum 字段本身不匹配", not SnapshotCodec.checksum_matches(tampered))

        var doc = SnapshotCodec.encode_document({"unlocked_ids": []}, {})
        h.check("非当前局文档 run_id 为 null", doc["data"]["run_id"] == null)
        h.check("非当前局文档 checksum 有效", SnapshotCodec.checksum_matches(doc["data"]))


func _round_trip(h) -> void:
        var session = _sample_session()
        var encoded = SnapshotCodec.encode_session(session, null, CONTENT_INFO)
        if not _ok(h, "encode_session 成功", encoded):
                return
        var snapshot: Dictionary = encoded["data"]
        h.eq("外层 content_hash", snapshot["content_hash"], "hash-1")
        h.eq("外层 run_id", snapshot["run_id"], session.run_id)
        h.eq("外层 revision", int(snapshot["revision"]), 3)

        var parsed = JSON.parse_string(SnapshotCodec.canonical_json(snapshot))
        h.check("JSON 往返后 checksum 仍匹配", SnapshotCodec.checksum_matches(parsed))
        var decoded = SnapshotCodec.decode_session(parsed)
        if not _ok(h, "decode_session 成功", decoded):
                return
        var out = decoded["data"]["session"]
        h.eq("run_id 还原", out.run_id, session.run_id)
        h.eq("revision 还原", int(out.revision), 3)
        h.eq("永久牌 ID 顺序还原", _card_ids(out.run), _card_ids(session.run))
        h.eq("升级只影响一张", _upgraded(out.run, session.run), true)
        h.eq("next_instance_seq 还原（读档不复用已删 ID）", out.run.next_instance_seq, session.run.next_instance_seq)
        h.eq("饰品槽位还原", out.run.relics[0].slot, 0)
        h.eq("settled_battle_ids 还原", SnapshotCodec.canonical_json(out.run.settled_battle_ids), SnapshotCodec.canonical_json(session.run.settled_battle_ids))
        h.eq("career_progress 还原", SnapshotCodec.canonical_json(out.run.career_progress), SnapshotCodec.canonical_json(session.run.career_progress))

        h.eq("牌区顺序还原", _zone_dump(out.battle), _zone_dump(session.battle))
        h.eq("battle 标量还原", _battle_scalars(out.battle), _battle_scalars(session.battle))
        h.eq("玩家还原", _player_dump(out.battle), _player_dump(session.battle))
        h.eq("单位还原", _unit_dump(out.battle), _unit_dump(session.battle))
        h.eq("任务与意图还原", _task_dump(out.battle), _task_dump(session.battle))
        h.eq("状态还原", _status_dump(out.battle), _status_dump(session.battle))
        h.eq("场景与预抽结果还原", _scene_dump(out.battle), _scene_dump(session.battle))
        h.eq("计数器还原（回合/战斗周期）", _counter_dump(out.battle), _counter_dump(session.battle))
        h.eq("随机快照原样还原", SnapshotCodec.canonical_json(out.random_snapshot), SnapshotCodec.canonical_json(session.random_snapshot))
        h.check("待合并摘要为空", decoded["data"]["pending_profile_summary"] == null)

        # 带待合并摘要
        var summary = {"run_id": session.run_id, "result": "won", "unlocked_ids": ["K14"]}
        var encoded2 = SnapshotCodec.encode_session(session, summary, CONTENT_INFO)
        var decoded2 = SnapshotCodec.decode_session(encoded2["data"])
        h.eq("待合并摘要随快照保存", SnapshotCodec.canonical_json(decoded2["data"]["pending_profile_summary"]), SnapshotCodec.canonical_json(summary))

        # G3：pending 必须是 RunCodec.encode_summary 的扁平字典；传 RunSummary 对象要返回 Result，
        # 不能抛 Invalid cast 再返回空 {}（《接口文档》§1.2 统一返回结构）。
        var object_pending: Variant = RunSummaryScript.new()
        var refused_pending: Variant = SnapshotCodec.encode_session(session, object_pending, CONTENT_INFO)
        h.check("传 RunSummary 对象返回带 ok 的 Result", typeof(refused_pending) == TYPE_DICTIONARY and refused_pending.has("ok"), str(refused_pending))
        h.eq("错误码为 INVALID_ARGUMENT", Result.error_code(refused_pending), GameConstants.ERROR_INVALID_ARGUMENT)
        h.check("同一会话的扁平字典仍照常接受", Result.is_ok(SnapshotCodec.encode_session(session, summary, CONTENT_INFO)))


func _rng(h) -> void:
        var big_seed := "9223372036854775000"
        var source = RandomSource.new(0)
        var snapshot = source.export_state()
        snapshot["streams"]["battle"]["seed"] = big_seed
        snapshot["streams"]["battle"]["state"] = big_seed
        var restored_seed = source.restore_state(snapshot)
        h.check("大 seed 可直接恢复", Result.is_ok(restored_seed))

        var session = _sample_session()
        session.random_snapshot = source.export_state()
        var encoded = SnapshotCodec.encode_session(session, null, CONTENT_INFO)
        var text = SnapshotCodec.canonical_json(encoded["data"])
        h.check("seed 以十进制字符串入档", text.find(big_seed) >= 0)

        var parsed = JSON.parse_string(text)
        var decoded = SnapshotCodec.decode_session(parsed)
        var reloaded = RandomSource.new(0)
        h.check("读档随机快照可恢复", Result.is_ok(reloaded.restore_state(decoded["data"]["session"].random_snapshot)))

        var after_save = []
        for _i in range(5):
                after_save.append(reloaded.draw_int(GameConstants.RNG_BATTLE, 0, 1000000)["data"])
        var expected = []
        for _i in range(5):
                expected.append(source.draw_int(GameConstants.RNG_BATTLE, 0, 1000000)["data"])
        h.eq("存读档后随机序列与连续运行一致", after_save, expected)


func _reject(h) -> void:
        var unstable = _sample_session()
        unstable.battle.resolution = BattleStateScript.create_resolution({"card_id": "bc1"})
        var refused = SnapshotCodec.encode_session(unstable)
        h.eq("非稳定边界拒绝保存", Result.error_code(refused), GameConstants.ERROR_CHOICE_PENDING)

        var encoded = SnapshotCodec.encode_session(_sample_session(), null, CONTENT_INFO)
        var snapshot: Dictionary = encoded["data"]
        var tampered = snapshot.duplicate(true)
        tampered["payload"]["run"]["money"] = 9999
        h.eq("篡改 payload 后 decode 报损坏", Result.error_code(SnapshotCodec.decode(tampered)), GameConstants.ERROR_SAVE_CORRUPT)

        var missing = snapshot.duplicate(true)
        missing.erase("payload")
        h.eq("缺 payload 报损坏", Result.error_code(SnapshotCodec.decode(missing)), GameConstants.ERROR_SAVE_CORRUPT)

        var empty_random = snapshot.duplicate(true)
        empty_random["random_state"] = {"algorithm_version": 1}
        empty_random["checksum"] = SnapshotCodec.compute_checksum(empty_random)
        h.eq("随机流缺失报损坏", Result.error_code(SnapshotCodec.decode(empty_random)), GameConstants.ERROR_SAVE_CORRUPT)


func _migrate(h) -> void:
        var current = SnapshotCodec.wrap_snapshot({"x": 1}, {"run_id": "r"})
        var same = SnapshotCodec.migrate(current)
        if _ok(h, "同版本迁移成功", same):
                h.eq("同版本 checksum 不变", same["data"]["checksum"], current["checksum"])

        var older = current.duplicate(true)
        older["schema_version"] = 0
        older["checksum"] = SnapshotCodec.compute_checksum(older)
        h.eq("无迁移路径返回 VERSION_MISMATCH", Result.error_code(SnapshotCodec.migrate(older)), GameConstants.ERROR_VERSION_MISMATCH)

        var migration = func(snapshot):
                var working = snapshot.duplicate(true)
                working["payload"]["x"] = 42
                return working
        var migrations = {0: migration}
        var migrated = SnapshotCodec.migrate(older, migrations)
        if _ok(h, "注册迁移后成功", migrated):
                var data: Dictionary = migrated["data"]
                h.eq("迁移在新的副本上生效", int(data["payload"]["x"]), 42)
                h.eq("迁移后版本升级", int(data["schema_version"]), 1)
                h.check("迁移后 checksum 重新计算", SnapshotCodec.checksum_matches(data))
                h.eq("原快照未被修改", int(older["payload"]["x"]), 1)

        var future = current.duplicate(true)
        future["schema_version"] = 99
        future["checksum"] = SnapshotCodec.compute_checksum(future)
        h.eq("未来版本返回 VERSION_MISMATCH", Result.error_code(SnapshotCodec.migrate(future)), GameConstants.ERROR_VERSION_MISMATCH)


# ── 样例与工具 ────────────────────────────────────────────

func _sample_session():
        var run = RunStateScript.new()
        run.run_id = Ids.run_id_from_seed(4242)
        run.character_id = "P01"
        run.ruleset_id = "campus_v1"
        run.difficulty = "normal"
        run.manifest_id = "mvp"
        run.term = 1
        run.money = 60
        run.vitality = 55
        run.max_vitality = 72
        var c1 = run.add_card("K01", 0, "starter")
        var c2 = run.add_card("K01", 0, "starter")
        run.add_card("K01", 0, "starter")
        run.add_card("K01", 0, "starter")
        c2.upgrade_level = 1
        run.equip_relic("A01", 6, 1)
        run.settled_battle_ids["R_old#9"] = true
        run.career_progress = {"code": 1}

        var battle = BattleStateScript.new()
        battle.battle_id = run.run_id + "#1"
        battle.node_id = "n1"
        battle.encounter_id = "N01"
        battle.phase = GameConstants.PHASE_PLAYER_ACTION
        battle.round_index = 2
        battle.ddl = 7
        battle.character_id = "P01"
        battle.difficulty = "normal"
        battle.relics = ["A01"]
        battle.exam_limits = []
        battle.next_entity_seq = 50
        battle.next_order_seq = 5

        var player = BattleStateScript.create_player("e1", 55, 72)
        player.relax = 3
        player.focus = 2
        battle.player = player
        battle.add_card("bc1", "K01", GameConstants.ZONE_HAND, c1.card_id, 1)
        battle.add_card("bc2", "K02", GameConstants.ZONE_DRAW, c2.card_id, 0)
        battle.add_card("bc3", "K03", GameConstants.ZONE_DISCARD, null, 0)

        var unit = BattleStateScript.create_unit("u1", "F01", 8, 10)
        unit.relax = 1
        unit.cooperation = 2
        unit.entered_order = 1
        unit.actions_taken = 1
        unit.last_acted_round = 1
        battle.units.append(unit)

        var task = BattleStateScript.create_task("t1", "N01", "A", 24)
        task.work_remaining = 18
        task.shield = 3
        task.intent_cursor = 1
        task.intent_snapshot = {"index": 2, "pressure": 7}
        task.entered_order = 1
        task.eligible_round = 1
        battle.tasks.append(task)

        var status = BattleStateScript.create_status("st1", GameConstants.STATUS_COMPILE, "e1", 2)
        status.source = {"source": "K13"}
        status.expiry = ""
        battle.statuses["st1"] = status

        var scene = BattleStateScript.create_scene("sc1", "L03", 1)
        scene.pending_random_result = 7
        battle.scene = scene

        var counter_key = BattleStateScript.counter_key("round", "p01_third_work_compile", "work_resolved")
        var counter = BattleStateScript.create_counter("round", "p01_third_work_compile", "work_resolved")
        counter.count = 2
        counter.round = 2
        battle.counters[counter_key] = counter

        var session = SessionStateScript.new()
        session.run_id = run.run_id
        session.revision = 3
        session.run = run
        session.battle = battle
        session.random_snapshot = RandomSource.new(20261013).export_state()
        return session


func _card_ids(run) -> Array:
        var ids := []
        for card in run.cards:
                ids.append(card.card_id)
        return ids


func _upgraded(out_run, in_run) -> bool:
        var matched := 0
        for index in range(in_run.cards.size()):
                if int(out_run.cards[index].upgrade_level) == int(in_run.cards[index].upgrade_level):
                        matched += 1
        return matched == in_run.cards.size() and int(out_run.cards[1].upgrade_level) == 1


func _zone_dump(battle) -> String:
        var dump := {}
        for zone in battle.zones.zone_ids():
                dump[zone] = (battle.zones.list_for(zone) as Array).duplicate()
        return SnapshotCodec.canonical_json(dump)


func _battle_scalars(battle) -> String:
        return SnapshotCodec.canonical_json({
                "battle_id": battle.battle_id,
                "node_id": battle.node_id,
                "encounter_id": battle.encounter_id,
                "phase": battle.phase,
                "round_index": battle.round_index,
                "ddl": battle.ddl,
                "character_id": battle.character_id,
                "difficulty": battle.difficulty,
                "relics": battle.relics,
                "exam_limits": battle.exam_limits,
                "next_entity_seq": battle.next_entity_seq,
                "next_order_seq": battle.next_order_seq,
                "outcome": battle.outcome,
        })


func _player_dump(battle) -> String:
        return SnapshotCodec.canonical_json({
                "entity_id": battle.player.entity_id,
                "vitality": battle.player.vitality,
                "max_vitality": battle.player.max_vitality,
                "relax": battle.player.relax,
                "focus": battle.player.focus,
        })


func _unit_dump(battle) -> String:
        var units := []
        for unit in battle.units:
                units.append({
                        "unit_id": unit.unit_id,
                        "definition_id": unit.definition_id,
                        "vitality": unit.vitality,
                        "max_vitality": unit.max_vitality,
                        "relax": unit.relax,
                        "cooperation": unit.cooperation,
                        "entered_order": unit.entered_order,
                        "last_acted_round": unit.last_acted_round,
                        "actions_taken": unit.actions_taken,
                        "target_id": unit.target_id,
                })
        return SnapshotCodec.canonical_json(units)


func _task_dump(battle) -> String:
        var tasks := []
        for task in battle.tasks:
                tasks.append({
                        "task_id": task.task_id,
                        "definition_id": task.definition_id,
                        "phase_key": task.phase_key,
                        "work_remaining": task.work_remaining,
                        "work_max": task.work_max,
                        "shield": task.shield,
                        "intent_cursor": task.intent_cursor,
                        "intent_snapshot": task.intent_snapshot,
                        "entered_order": task.entered_order,
                        "eligible_round": task.eligible_round,
                })
        return SnapshotCodec.canonical_json(tasks)


func _status_dump(battle) -> String:
        var statuses := {}
        for status_id in battle.statuses:
                var status = battle.statuses[status_id]
                statuses[status_id] = {
                        "definition_id": status.definition_id,
                        "holder_id": status.holder_id,
                        "stacks": status.stacks,
                        "expiry": status.expiry,
                        "source": status.source,
                }
        return SnapshotCodec.canonical_json(statuses)


func _scene_dump(battle) -> String:
        if battle.scene == null:
                return "null"
        return SnapshotCodec.canonical_json({
                "scene_id": battle.scene.scene_id,
                "definition_id": battle.scene.definition_id,
                "established_round": battle.scene.established_round,
                "pending_random_result": battle.scene.pending_random_result,
        })


func _counter_dump(battle) -> String:
        var counters := {}
        for key in battle.counters:
                var counter = battle.counters[key]
                counters[key] = {
                        "scope": counter.scope,
                        "owner_key": counter.owner_key,
                        "trigger_key": counter.trigger_key,
                        "count": counter.count,
                        "round": counter.round,
                }
        return SnapshotCodec.canonical_json(counters)


func _ok(h, label: String, result: Dictionary) -> bool:
        if Result.is_ok(result):
                h.check(label, true)
                return true
        h.check(label, false, str(result.get("error")))
        return false