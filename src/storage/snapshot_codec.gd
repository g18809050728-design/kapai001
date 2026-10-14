class_name SnapshotCodec
extends RefCounted
##
## 稳定边界快照编解码（《数据库与实体关系设计》§7、§9；《接口文档》§7）。
##
## 契约：
##   · 规范化编码：对象键按字符串排序、数组保持游戏顺序、只用 JSON 基础类型。
##   · 64 位 seed/state 仍是十进制字符串（由 RandomSource.export_state 保证），本类不改写。
##   · checksum = 对排除 checksum 字段后的规范化 UTF-8 内容算 SHA-256（损坏检测，非防作弊）。
##   · 快照外层：schema_version / content_version / content_hash / manifest_id /
##     run_id / revision / random_state / payload / checksum。
##   · 只有稳定边界可编码：battle.resolution 非空时 encode_session 返回 CHOICE_PENDING。
##   · 本类只做字典 <-> 对象转换与校验和，不碰磁盘；文件 IO 归 SaveStore。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const BattleStateScript := preload("res://src/battle/battle_state.gd")
const SessionStateScript := preload("res://src/app/session_state.gd")
const RandomSource := preload("res://src/common/random_source.gd")

## 当前快照结构版本。只表示结构；内容兼容看 content_version/content_hash。
const SNAPSHOT_SCHEMA_VERSION: int = 1
## 解码重建 RunState 时的假饰品槽数上限；解码后会按存档里的 slot 覆盖。
const DECODE_RELIC_SLOT_HINT: int = 64

## RunState 显式序列化的字段；之外的脚本变量走通用对象编码（前向兼容新字段）。
const RUN_EXPLICIT_FIELDS: Array[String] = [
        "run_id", "character_id", "ruleset_id", "difficulty", "manifest_id", "term", "money",
        "vitality", "max_vitality", "next_instance_seq",
        "cards", "relics", "career_progress", "settled_battle_ids",
]

const OUTER_REQUIRED: Array[String] = [
        "schema_version", "content_version", "content_hash", "manifest_id",
        "payload", "checksum",
]


# ── 规范化与校验和 ────────────────────────────────────────

## 对象键排序的紧凑 JSON；数组顺序原样保留。
static func canonical_json(value: Variant) -> String:
        return JSON.stringify(normalize_numbers(value), "", true, true)


## 对排除 checksum 后的快照算 SHA-256（十六进制 64 位）。
static func compute_checksum(snapshot: Dictionary) -> String:
        var body := snapshot.duplicate(true)
        body.erase("checksum")
        return canonical_json(body).sha256_text()


static func checksum_matches(snapshot: Dictionary) -> bool:
        var stored := String(snapshot.get("checksum", ""))
        if stored.is_empty():
                return false
        return stored == compute_checksum(snapshot)


# ── 外层组装 ──────────────────────────────────────────────

## 通用外层包装：payload + meta -> SaveSnapshot（含 checksum）。命名避开内置 wrap(value,min,max)。
## meta 可带 schema_version / content_version / content_hash / manifest_id /
## run_id（可空）/ revision（可空）/ random_state（可空）。
static func wrap_snapshot(payload: Dictionary, meta: Dictionary = {}) -> Dictionary:
        var snapshot := {
                "schema_version": int(meta.get("schema_version", SNAPSHOT_SCHEMA_VERSION)),
                "content_version": String(meta.get("content_version", "")),
                "content_hash": String(meta.get("content_hash", "")),
                "manifest_id": String(meta.get("manifest_id", "")),
                "run_id": meta.get("run_id"),
                "revision": meta.get("revision"),
                "random_state": meta.get("random_state"),
                "payload": payload.duplicate(true),
        }
        snapshot["checksum"] = compute_checksum(snapshot)
        return snapshot


## Result<SaveSnapshot>：当前局快照（payload = run / battle / pending_profile_summary）。
static func encode_session(session, pending_profile_summary: Variant = null, content_info: Dictionary = {}) -> Dictionary:
        if session == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.no_session", {})
        if session.run == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.no_run", {})
        if session.battle != null and session.battle.resolution != null:
                return Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.save.choice_pending", {
                        "battle_id": session.battle.battle_id,
                })
        var payload := {
                "run": encode_run(session.run),
                "battle": null,
                "pending_profile_summary": null,
        }
        if session.battle != null:
                payload["battle"] = encode_battle(session.battle)
        if pending_profile_summary != null:
                # 统一返回结构（《接口文档》§1.2）：这里以前用 (pending as Dictionary) 硬转，
                # 传 RunState 上的 RunSummary 对象时只会抛 Invalid cast 并返回空 {}（G3）。
                if typeof(pending_profile_summary) != TYPE_DICTIONARY:
                        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.pending_not_encoded", {
                                "type": typeof(pending_profile_summary),
                                "hint": "RunSummary 对象请先用 RunCodec.encode_summary() 转成扁平字典",
                        })
                payload["pending_profile_summary"] = (pending_profile_summary as Dictionary).duplicate(true)
        var meta := {
                "content_version": String(content_info.get("content_version", "")),
                "content_hash": String(content_info.get("content_hash", "")),
                "manifest_id": String(content_info.get("manifest_id", session.run.manifest_id)),
                "run_id": session.run_id,
                "revision": session.revision,
                "random_state": (session.random_snapshot as Dictionary).duplicate(true),
        }
        return Result.ok(wrap_snapshot(payload, meta))


## Result<SaveSnapshot>：Profile / Settings 这类非当前局文档（run_id/revision/random_state 可空）。
static func encode_document(payload: Dictionary, meta: Dictionary = {}) -> Dictionary:
        var filled := meta.duplicate(true)
        if not filled.has("run_id"):
                filled["run_id"] = null
        if not filled.has("revision"):
                filled["revision"] = null
        if not filled.has("random_state"):
                filled["random_state"] = null
        return Result.ok(wrap_snapshot(payload, filled))


# ── 结构校验 / 解码 ───────────────────────────────────────

## 第 1 层（结构与基本类型）。问题清单为空表示通过。
static func validate_structure(snapshot: Variant) -> PackedStringArray:
        var problems := PackedStringArray()
        if typeof(snapshot) != TYPE_DICTIONARY:
                problems.append("快照不是对象")
                return problems
        var data: Dictionary = snapshot
        for key in OUTER_REQUIRED:
                if not data.has(key):
                        problems.append("缺少外层字段：%s" % key)
        if data.has("schema_version") and not is_integral(data["schema_version"]):
                problems.append("schema_version 必须是整数")
        for key in ["content_version", "content_hash", "manifest_id"]:
                if data.has(key) and typeof(data[key]) != TYPE_STRING:
                        problems.append("%s 必须是字符串" % key)
        if data.has("checksum"):
                if typeof(data["checksum"]) != TYPE_STRING or String(data["checksum"]).length() != 64:
                        problems.append("checksum 必须是 64 位十六进制字符串")
        if data.has("run_id") and data["run_id"] != null and typeof(data["run_id"]) != TYPE_STRING:
                problems.append("run_id 必须是字符串或 null")
        if data.has("revision") and data["revision"] != null and not is_integral(data["revision"]):
                problems.append("revision 必须是整数或 null")
        var raw_random: Variant = data.get("random_state")
        if raw_random != null:
                if typeof(raw_random) != TYPE_DICTIONARY:
                        problems.append("random_state 必须是对象或 null")
                else:
                        var random_state: Dictionary = raw_random
                        if not is_integral(random_state.get("algorithm_version")):
                                problems.append("random_state 缺少 algorithm_version")
                        if typeof(random_state.get("streams")) != TYPE_DICTIONARY:
                                problems.append("random_state 缺少 streams")
        var raw_payload: Variant = data.get("payload")
        if typeof(raw_payload) != TYPE_DICTIONARY:
                problems.append("payload 必须是对象")
        else:
                var payload: Dictionary = raw_payload
                if payload.has("run") and typeof(payload["run"]) != TYPE_DICTIONARY:
                        problems.append("payload.run 必须是对象")
                if payload.has("battle") and payload["battle"] != null and typeof(payload["battle"]) != TYPE_DICTIONARY:
                        problems.append("payload.battle 必须是对象或 null")
                if payload.has("pending_profile_summary") and payload["pending_profile_summary"] != null and typeof(payload["pending_profile_summary"]) != TYPE_DICTIONARY:
                        problems.append("payload.pending_profile_summary 必须是对象或 null")
        return problems

## Result<Dictionary>：校验结构 + checksum + schema 后返回 {"payload": {...}}（不重建对象）。
static func decode(snapshot: Dictionary) -> Dictionary:
        var structural := validate_structure(snapshot)
        if not structural.is_empty():
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.structure", {"problems": structural})
        if not checksum_matches(snapshot):
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.checksum_mismatch", {})
        var version := int(snapshot.get("schema_version", -1))
        if version != SNAPSHOT_SCHEMA_VERSION:
                return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.schema_version", {
                        "expected": SNAPSHOT_SCHEMA_VERSION,
                        "got": version,
                })
        return Result.ok({"payload": (snapshot["payload"] as Dictionary).duplicate(true)})


## Result<{session, pending_profile_summary}>：由快照重建 SessionState（§7「decode 时重建」）。
static func decode_session(snapshot: Dictionary) -> Dictionary:
        var decoded := decode(snapshot)
        if not Result.is_ok(decoded):
                return decoded
        var payload: Dictionary = decoded["data"]["payload"]
        var run_data: Variant = payload.get("run")
        if typeof(run_data) != TYPE_DICTIONARY:
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.missing_run", {})
        var session = SessionStateScript.new()
        session.run_id = String(snapshot.get("run_id", ""))
        var raw_revision: Variant = snapshot.get("revision")
        session.revision = int(raw_revision) if raw_revision != null else 0
        session.run = decode_run(run_data)
        session.battle = null
        var battle_data: Variant = payload.get("battle")
        if typeof(battle_data) == TYPE_DICTIONARY:
                session.battle = decode_battle(battle_data)
        var raw_random: Variant = snapshot.get("random_state")
        session.random_snapshot = (raw_random as Dictionary).duplicate(true) if typeof(raw_random) == TYPE_DICTIONARY else {}
        return Result.ok({
                "session": session,
                "pending_profile_summary": payload.get("pending_profile_summary"),
        })


# ── RunState ──────────────────────────────────────────────

static func encode_run(run) -> Dictionary:
        var cards := []
        for card in run.cards:
                cards.append({
                        "card_id": card.card_id,
                        "definition_id": card.definition_id,
                        "upgrade_level": card.upgrade_level,
                        "acquired_from": card.acquired_from,
                })
        var relics := []
        for relic in run.relics:
                relics.append({
                        "relic_id": relic.relic_id,
                        "definition_id": relic.definition_id,
                        "slot": relic.slot,
                        "acquired_order": relic.acquired_order,
                })
        var data := {
                "run_id": run.run_id,
                "character_id": run.character_id,
                "ruleset_id": run.ruleset_id,
                "difficulty": run.difficulty,
                "manifest_id": run.manifest_id,
                "term": run.term,
                "money": run.money,
                "vitality": run.vitality,
                "max_vitality": run.max_vitality,
                "next_instance_seq": run.next_instance_seq,
                "cards": cards,
                "relics": relics,
                "career_progress": run.career_progress.duplicate(true),
                "settled_battle_ids": run.settled_battle_ids.duplicate(true),
        }
        for property in run.get_property_list():
                if not is_script_variable(property):
                        continue
                var name := String(property.get("name", ""))
                if name.is_empty() or RUN_EXPLICIT_FIELDS.has(name):
                        continue
                data[name] = encode_value(run.get(name))
        return data


## 用 add_card / equip_relic 重建后覆盖实例 ID 与槽位，最后恢复 next_instance_seq；
## 不改动 src/run（RunState 未暴露子实体工厂）。
static func decode_run(data: Dictionary):
        var run = RunStateScript.new()
        run.run_id = _str(data, "run_id")
        run.character_id = _str(data, "character_id")
        run.ruleset_id = _str(data, "ruleset_id")
        run.difficulty = _str(data, "difficulty")
        run.manifest_id = _str(data, "manifest_id")
        run.term = _int(data, "term", 1)
        run.money = _int(data, "money", 0)
        run.vitality = _int(data, "vitality", 0)
        run.max_vitality = _int(data, "max_vitality", 0)
        for raw in _array(data, "cards"):
                if typeof(raw) != TYPE_DICTIONARY:
                        continue
                var entry: Dictionary = raw
                var card = run.add_card(_str(entry, "definition_id"), _int(entry, "upgrade_level", 0), _str(entry, "acquired_from"))
                if card != null:
                        card.card_id = _str(entry, "card_id")
        for raw_relic in _array(data, "relics"):
                if typeof(raw_relic) != TYPE_DICTIONARY:
                        continue
                var relic_entry: Dictionary = raw_relic
                var relic = run.equip_relic(_str(relic_entry, "definition_id"), DECODE_RELIC_SLOT_HINT, _int(relic_entry, "acquired_order", 0))
                if relic != null:
                        relic.relic_id = _str(relic_entry, "relic_id")
                        relic.slot = _int(relic_entry, "slot", -1)
        run.career_progress = _dict(data, "career_progress").duplicate(true)
        run.settled_battle_ids = _dict(data, "settled_battle_ids").duplicate(true)
        run.next_instance_seq = _int(data, "next_instance_seq", 1)
        for key in data:
                if RUN_EXPLICIT_FIELDS.has(String(key)):
                        continue
                run.set(String(key), decode_value(data[key]))
        return run


# ── BattleState ───────────────────────────────────────────

static func encode_battle(battle) -> Dictionary:
        var card_by_id := {}
        for card_id in battle.card_by_id:
                var card = battle.card_by_id[card_id]
                card_by_id[card_id] = {
                        "definition_id": card.definition_id,
                        "origin_card_id": card.origin_card_id,
                        "upgrade_level": card.upgrade_level,
                        "modifiers": (card.modifiers as Dictionary).duplicate(true),
                }
        var zones := {}
        for zone in battle.zones.zone_ids():
                zones[zone] = (battle.zones.list_for(zone) as Array).duplicate()
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
        var statuses := {}
        for status_id in battle.statuses:
                var status = battle.statuses[status_id]
                statuses[status_id] = {
                        "status_id": status.status_id,
                        "definition_id": status.definition_id,
                        "holder_id": status.holder_id,
                        "source": (status.source as Dictionary).duplicate(true),
                        "stacks": status.stacks,
                        "expiry": status.expiry,
                }
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
        var player_data: Variant = null
        if battle.player != null:
                player_data = {
                        "entity_id": battle.player.entity_id,
                        "vitality": battle.player.vitality,
                        "max_vitality": battle.player.max_vitality,
                        "relax": battle.player.relax,
                        "focus": battle.player.focus,
                }
        var scene_data: Variant = null
        if battle.scene != null:
                scene_data = {
                        "scene_id": battle.scene.scene_id,
                        "definition_id": battle.scene.definition_id,
                        "established_round": battle.scene.established_round,
                        "pending_random_result": battle.scene.pending_random_result,
                }
        return {
                "battle_id": battle.battle_id,
                "node_id": battle.node_id,
                "encounter_id": battle.encounter_id,
                "phase": battle.phase,
                "round_index": battle.round_index,
                "ddl": battle.ddl,
                "character_id": battle.character_id,
                "difficulty": battle.difficulty,
                "relics": (battle.relics as Array).duplicate(),
                "exam_limits": (battle.exam_limits as Array).duplicate(),
                "outcome": battle.outcome,
                "next_entity_seq": battle.next_entity_seq,
                "next_order_seq": battle.next_order_seq,
                "player": player_data,
                "card_by_id": card_by_id,
                "zones": zones,
                "units": units,
                "tasks": tasks,
                "statuses": statuses,
                "scene": scene_data,
                "counters": counters,
                "resolution": null,
        }

static func decode_battle(data: Dictionary):
        var battle = BattleStateScript.new()
        battle.battle_id = _str(data, "battle_id")
        battle.node_id = _str(data, "node_id")
        battle.encounter_id = _str(data, "encounter_id")
        battle.phase = _str(data, "phase", GameConstants.PHASE_INITIALIZING)
        battle.round_index = _int(data, "round_index", 1)
        battle.ddl = _int(data, "ddl", 0)
        battle.character_id = _str(data, "character_id")
        battle.difficulty = _str(data, "difficulty")
        battle.relics = _array(data, "relics").duplicate()
        battle.exam_limits = _array(data, "exam_limits").duplicate()
        battle.outcome = data.get("outcome")
        battle.next_entity_seq = _int(data, "next_entity_seq", 1)
        battle.next_order_seq = _int(data, "next_order_seq", 1)

        var raw_player: Variant = data.get("player")
        if typeof(raw_player) == TYPE_DICTIONARY:
                var player_data: Dictionary = raw_player
                var player = BattleStateScript.create_player(
                        _str(player_data, "entity_id"),
                        _int(player_data, "vitality", 0),
                        _int(player_data, "max_vitality", 0)
                )
                player.relax = _int(player_data, "relax", 0)
                player.focus = _int(player_data, "focus", 0)
                battle.player = player

        var zones: Dictionary = _dict(data, "zones")
        var card_by_id: Dictionary = _dict(data, "card_by_id")
        for zone in battle.zones.zone_ids():
                for raw_id in _array(zones, zone):
                        var card_id := String(raw_id)
                        var raw_card: Variant = card_by_id.get(card_id)
                        if typeof(raw_card) != TYPE_DICTIONARY:
                                continue
                        var card_data: Dictionary = raw_card
                        var card = battle.add_card(
                                card_id,
                                _str(card_data, "definition_id"),
                                zone,
                                card_data.get("origin_card_id"),
                                _int(card_data, "upgrade_level", 0)
                        )
                        if card != null and typeof(card_data.get("modifiers")) == TYPE_DICTIONARY:
                                card.modifiers = (card_data["modifiers"] as Dictionary).duplicate(true)

        for raw_unit in _array(data, "units"):
                if typeof(raw_unit) != TYPE_DICTIONARY:
                        continue
                var unit_data: Dictionary = raw_unit
                var unit = BattleStateScript.create_unit(
                        _str(unit_data, "unit_id"),
                        _str(unit_data, "definition_id"),
                        _int(unit_data, "vitality", 0),
                        _int(unit_data, "max_vitality", 0)
                )
                unit.relax = _int(unit_data, "relax", 0)
                unit.cooperation = _int(unit_data, "cooperation", 0)
                unit.entered_order = _int(unit_data, "entered_order", 0)
                unit.last_acted_round = _int(unit_data, "last_acted_round", 0)
                unit.actions_taken = _int(unit_data, "actions_taken", 0)
                unit.target_id = unit_data.get("target_id")
                battle.units.append(unit)

        for raw_task in _array(data, "tasks"):
                if typeof(raw_task) != TYPE_DICTIONARY:
                        continue
                var task_data: Dictionary = raw_task
                var task = BattleStateScript.create_task(
                        _str(task_data, "task_id"),
                        _str(task_data, "definition_id"),
                        _str(task_data, "phase_key"),
                        _int(task_data, "work_max", 0)
                )
                task.work_remaining = _int(task_data, "work_remaining", task.work_max)
                task.shield = _int(task_data, "shield", 0)
                task.intent_cursor = _int(task_data, "intent_cursor", 0)
                task.intent_snapshot = task_data.get("intent_snapshot")
                task.entered_order = _int(task_data, "entered_order", 0)
                task.eligible_round = _int(task_data, "eligible_round", 1)
                battle.tasks.append(task)

        var statuses: Dictionary = _dict(data, "statuses")
        for raw_status_id in statuses:
                var raw_status: Variant = statuses[raw_status_id]
                if typeof(raw_status) != TYPE_DICTIONARY:
                        continue
                var status_data: Dictionary = raw_status
                var status = BattleStateScript.create_status(
                        _str(status_data, "status_id"),
                        _str(status_data, "definition_id"),
                        _str(status_data, "holder_id"),
                        _int(status_data, "stacks", 0)
                )
                status.source = _dict(status_data, "source").duplicate(true)
                status.expiry = _str(status_data, "expiry")
                battle.statuses[String(raw_status_id)] = status

        var raw_scene: Variant = data.get("scene")
        if typeof(raw_scene) == TYPE_DICTIONARY:
                var scene_data: Dictionary = raw_scene
                var scene = BattleStateScript.create_scene(
                        _str(scene_data, "scene_id"),
                        _str(scene_data, "definition_id"),
                        _int(scene_data, "established_round", 0)
                )
                scene.pending_random_result = scene_data.get("pending_random_result")
                battle.scene = scene

        var counters: Dictionary = _dict(data, "counters")
        for raw_counter_key in counters:
                var raw_counter: Variant = counters[raw_counter_key]
                if typeof(raw_counter) != TYPE_DICTIONARY:
                        continue
                var counter_data: Dictionary = raw_counter
                var counter = BattleStateScript.create_counter(
                        _str(counter_data, "scope"),
                        _str(counter_data, "owner_key"),
                        _str(counter_data, "trigger_key")
                )
                counter.count = _int(counter_data, "count", 0)
                counter.round = counter_data.get("round")
                battle.counters[String(raw_counter_key)] = counter
        return battle


# ── 迁移 ──────────────────────────────────────────────────

## Result<SaveSnapshot>：在副本上执行迁移并重算 checksum。
## migrations 形如 {from_version: Callable(snapshot) -> snapshot}；未提供路径返回 VERSION_MISMATCH。
static func migrate(snapshot: Dictionary, migrations: Dictionary = {}) -> Dictionary:
        if typeof(snapshot) != TYPE_DICTIONARY:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.not_a_snapshot", {})
        var working := snapshot.duplicate(true)
        var version := int(working.get("schema_version", -1))
        if version < 0:
                return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.schema_version", {
                        "got": version,
                })
        if version > SNAPSHOT_SCHEMA_VERSION:
                return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.schema_future", {
                        "supported": SNAPSHOT_SCHEMA_VERSION,
                        "got": version,
                })
        var guard := 0
        while version < SNAPSHOT_SCHEMA_VERSION and guard < 64:
                guard += 1
                if not migrations.has(version):
                        return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.no_migration", {
                                "from": version,
                                "to": SNAPSHOT_SCHEMA_VERSION,
                        })
                var migration: Variant = migrations[version]
                if not (migration is Callable):
                        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.bad_migration", {"from": version})
                var migrated: Variant = (migration as Callable).call(working.duplicate(true))
                if typeof(migrated) != TYPE_DICTIONARY:
                        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.bad_migration_result", {"from": version})
                working = migrated
                working["schema_version"] = version + 1
                version += 1
        working["checksum"] = compute_checksum(working)
        return Result.ok(working)


# ── 小工具 ────────────────────────────────────────────────

static func is_integral(value: Variant) -> bool:
        if typeof(value) == TYPE_INT:
                return true
        if typeof(value) == TYPE_FLOAT:
                return float(value) == floor(float(value))
        return false


static func _str(data: Dictionary, key: String, fallback: String = "") -> String:
        var value: Variant = data.get(key)
        if value == null:
                return fallback
        return String(value)


static func _int(data: Dictionary, key: String, fallback: int = 0) -> int:
        var value: Variant = data.get(key)
        if value == null:
                return fallback
        if typeof(value) == TYPE_INT:
                return int(value)
        if typeof(value) == TYPE_FLOAT:
                return int(value)
        if typeof(value) == TYPE_STRING and String(value).is_valid_int():
                return String(value).to_int()
        return fallback


static func _array(data: Dictionary, key: String) -> Array:
        var value: Variant = data.get(key, [])
        if typeof(value) == TYPE_ARRAY:
                return value
        return []


static func _dict(data: Dictionary, key: String) -> Dictionary:
        var value: Variant = data.get(key, {})
        if typeof(value) == TYPE_DICTIONARY:
                return value
        return {}

## JSON.parse 会把所有数字解析成 float；规范化把「整数值浮点」还原为 int，
## 使解析后的快照与写入时算出同一个 checksum（只对 64 位以内整数，超出范围保持 float）。
static func normalize_numbers(value: Variant) -> Variant:
        var value_type := typeof(value)
        if value_type == TYPE_FLOAT:
                var number := float(value)
                if is_finite(number) and number == floor(number) and abs(number) <= 9007199254740992.0:
                        return int(number)
                return number
        if value_type == TYPE_ARRAY:
                var result := []
                for item in (value as Array):
                        result.append(normalize_numbers(item))
                return result
        if value_type == TYPE_DICTIONARY:
                var mapped := {}
                for key in (value as Dictionary):
                        mapped[key] = normalize_numbers((value as Dictionary)[key])
                return mapped
        return value

# ── 通用值编码（前向兼容新增字段）─────────────────────────

## 只认脚本变量，跳过引擎内置属性（如 script、位置等）。
static func is_script_variable(property: Dictionary) -> bool:
        return (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0


## 把 JSON 基础类型原样编码；Array/Dictionary 递归；RefCounted 对象编码成
## {"__object": script_path, "fields": {...}}，让新增的子实体也能落盘（不丢字段）。
static func encode_value(value: Variant) -> Variant:
        if value == null:
                return null
        var value_type := typeof(value)
        if value_type == TYPE_BOOL or value_type == TYPE_INT or value_type == TYPE_FLOAT or value_type == TYPE_STRING:
                return value
        if value_type == TYPE_ARRAY:
                var items := []
                for item in (value as Array):
                        items.append(encode_value(item))
                return items
        if value_type == TYPE_DICTIONARY:
                var mapped := {}
                for key in (value as Dictionary):
                        mapped[String(key)] = encode_value((value as Dictionary)[key])
                return mapped
        if value_type == TYPE_OBJECT:
                var script = value.get_script()
                var path := ""
                if script != null:
                        path = String(script.resource_path)
                var fields := {}
                for property in value.get_property_list():
                        if not is_script_variable(property):
                                continue
                        var name := String(property.get("name", ""))
                        if name.is_empty():
                                continue
                        fields[name] = encode_value(value.get(name))
                return {"__object": path, "fields": fields}
        return null


## encode_value 的逆操作。__object 用脚本路径重建实例；未知路径返回 null（不抛异常）。
static func decode_value(value: Variant) -> Variant:
        if value == null:
                return null
        var value_type := typeof(value)
        if value_type == TYPE_ARRAY:
                var items := []
                for item in (value as Array):
                        items.append(decode_value(item))
                return items
        if value_type == TYPE_DICTIONARY:
                var data: Dictionary = value
                var raw_fields: Variant = data.get("fields")
                if data.has("__object") and typeof(raw_fields) == TYPE_DICTIONARY:
                        var path := String(data["__object"])
                        if path.is_empty():
                                return null
                        var script = load(path)
                        if script == null:
                                return null
                        var instance = script.new()
                        for key in (raw_fields as Dictionary):
                                instance.set(String(key), decode_value((raw_fields as Dictionary)[key]))
                        return instance
                var mapped := {}
                for key in data:
                        mapped[String(key)] = decode_value(data[key])
                return mapped
        return value