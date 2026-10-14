class_name SaveStore
extends RefCounted
##
## 存档文件存储（《数据库与实体关系设计》§7/§8/§9；《接口文档》§7）。
##
## 契约：
##   · 槽位：current_run / profile / settings（GameConstants.SAVE_*）。
##   · 正式档 <slot>.json，备份 <slot>.json.bak，临时 <slot>.json.tmp，全部同目录。
##   · 保存顺序：同目录写临时 → 读回校验 → 旧有效档转备份 → 替换正式档。
##     磁盘满 / 权限不足 / 中断时不得删除唯一有效副本；失败只返回 SAVE_IO_ERROR。
##   · 校验分三层：结构+checksum（SAVE_CORRUPT）→ 内容引用（CONTENT_INVALID /
##     VERSION_MISMATCH）→ 领域不变量（SAVE_CORRUPT）。
##   · debug_hooks 仅测试用，可注入 fail_write / truncate_temp / fail_after_backup / fail_rename。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const SnapshotCodec := preload("res://src/storage/snapshot_codec.gd")
const ProfileMerge := preload("res://src/storage/profile_merge.gd")

const SLOT_CURRENT_RUN := GameConstants.SAVE_CURRENT_RUN
const SLOT_PROFILE := GameConstants.SAVE_PROFILE
const SLOT_SETTINGS := GameConstants.SAVE_SETTINGS
const KNOWN_SLOTS: Array[String] = [SLOT_CURRENT_RUN, SLOT_PROFILE, SLOT_SETTINGS]

const MAIN_SUFFIX := ".json"
const BACKUP_SUFFIX := ".json.bak"
const TEMP_SUFFIX := ".json.tmp"
const DEFAULT_BASE_DIR := "user://saves"

## 存档根目录；测试可指向 user:// 下的独立目录。
var base_dir: String = DEFAULT_BASE_DIR
## 可选 ContentDB；注入后执行第 2 层引用校验并补齐 content_version/content_hash/manifest_id。
var catalog = null
## 仅测试用故障注入：{"*" 或 slot: {"fail_write": true, "truncate_temp": true, ...}}。
var debug_hooks: Dictionary = {}


func _init(dir := DEFAULT_BASE_DIR, content_db = null) -> void:
        base_dir = String(dir) if not String(dir).is_empty() else DEFAULT_BASE_DIR
        catalog = content_db


func is_known_slot(slot: String) -> bool:
        return KNOWN_SLOTS.has(slot)


func path_for(slot: String) -> String:
        return _join(base_dir, slot + MAIN_SUFFIX)


func backup_path_for(slot: String) -> String:
        return _join(base_dir, slot + BACKUP_SUFFIX)


func temp_path_for(slot: String) -> String:
        return _join(base_dir, slot + TEMP_SUFFIX)


# ── inspect / load ────────────────────────────────────────

## Result<SaveMetadata>：不存在返回 SAVE_NOT_FOUND；存在但损坏时返回 valid=false 的元数据。
func inspect(slot: String) -> Dictionary:
        if not is_known_slot(slot):
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.unknown_slot", {"slot": slot})
        var path := path_for(slot)
        if not FileAccess.file_exists(path):
                return Result.fail(GameConstants.ERROR_SAVE_NOT_FOUND, "error.save.not_found", {"slot": slot})
        var metadata := {
                "slot": slot,
                "path": path,
                "saved_at": FileAccess.get_modified_time(path),
                "schema_version": -1,
                "content_version": "",
                "revision": null,
                "checksum": "",
                "valid": false,
                "problems": [],
        }
        var read := _read_snapshot(path)
        if not Result.is_ok(read):
                metadata["problems"] = Result.error_detail(read, "problems", [Result.error_code(read)])
                return Result.ok(metadata)
        var snapshot: Dictionary = read["data"]
        metadata["schema_version"] = int(snapshot.get("schema_version", -1))
        metadata["content_version"] = String(snapshot.get("content_version", ""))
        metadata["revision"] = snapshot.get("revision")
        metadata["checksum"] = String(snapshot.get("checksum", ""))
        var check := validate_snapshot(snapshot, slot)
        metadata["valid"] = Result.is_ok(check)
        if not Result.is_ok(check):
                metadata["problems"] = Result.error_detail(check, "problems", [Result.error_code(check)])
        return Result.ok(metadata)


## Result<SaveSnapshot>：读取正式档，自动迁移 + 三层校验；失败保留原文件不动。
func load(slot: String) -> Dictionary:
        return _load_from(path_for(slot), slot)


## Result<SaveSnapshot>：显式读取有效备份（<slot>.json.bak）。
func load_backup(slot: String) -> Dictionary:
        return _load_from(backup_path_for(slot), slot)


func _load_from(path: String, slot: String) -> Dictionary:
        if not is_known_slot(slot):
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.unknown_slot", {"slot": slot})
        if not FileAccess.file_exists(path):
                return Result.fail(GameConstants.ERROR_SAVE_NOT_FOUND, "error.save.not_found", {"slot": slot, "path": path})
        var read := _read_snapshot(path)
        if not Result.is_ok(read):
                return read
        var snapshot: Dictionary = read["data"]
        var version := int(snapshot.get("schema_version", -1))
        if version != SnapshotCodec.SNAPSHOT_SCHEMA_VERSION:
                var migrated := SnapshotCodec.migrate(snapshot, {})
                if not Result.is_ok(migrated):
                        return migrated
                snapshot = migrated["data"]
        var check := validate_snapshot(snapshot, slot)
        if not Result.is_ok(check):
                return check
        return Result.ok(snapshot)


# ── 底层读写 ──────────────────────────────────────────────

func _read_snapshot(path: String) -> Dictionary:
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.read_failed", {
                        "path": path,
                        "error": FileAccess.get_open_error(),
                })
        var text := file.get_as_text()
        file.close()
        if text.strip_edges().is_empty():
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.empty", {"path": path})
        var json := JSON.new()
        var parse_error := json.parse(text)
        if parse_error != OK:
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.json_parse", {
                        "path": path,
                        "error": parse_error,
                        "message": json.get_error_message(),
                        "line": json.get_error_line(),
                })
        if typeof(json.data) != TYPE_DICTIONARY:
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.not_object", {"path": path})
        return Result.ok(json.data)


func _write_text(path: String, text: String) -> Dictionary:
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.open_failed", {
                        "path": path,
                        "error": FileAccess.get_open_error(),
                })
        file.store_string(text)
        file.flush()
        file.close()
        if not FileAccess.file_exists(path):
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.write_verify", {"path": path})
        if FileAccess.get_file_as_string(path) != text:
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.write_verify", {"path": path})
        return Result.ok(null)


func _join(dir: String, name: String) -> String:
        var trimmed := String(dir)
        while trimmed.ends_with("/"):
                trimmed = trimmed.substr(0, trimmed.length() - 1)
        return trimmed + "/" + name

# ── save ──────────────────────────────────────────────────

## Result<SaveReceipt>。先写临时并读回校验，再保留旧有效档到备份，最后替换正式档。
func save(slot: String, snapshot: Dictionary) -> Dictionary:
        if not is_known_slot(slot):
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.unknown_slot", {"slot": slot})
        if typeof(snapshot) != TYPE_DICTIONARY:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.not_a_snapshot", {})
        var working: Dictionary = snapshot.duplicate(true)
        if String(working.get("checksum", "")).is_empty():
                working["checksum"] = SnapshotCodec.compute_checksum(working)
        elif not SnapshotCodec.checksum_matches(working):
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.save.bad_checksum", {})
        var enriched := _enrich_content_info(working)
        if not Result.is_ok(enriched):
                return enriched
        working = enriched["data"]
        # 补齐 content_* / manifest 后旧 checksum 失效，按新内容重算。
        working["checksum"] = SnapshotCodec.compute_checksum(working)
        var check := validate_snapshot(working, slot)
        if not Result.is_ok(check):
                return check

        var dir_error := DirAccess.make_dir_recursive_absolute(base_dir)
        if dir_error != OK:
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.mkdir_failed", {
                        "dir": base_dir,
                        "error": dir_error,
                })
        if _hook_enabled(slot, "fail_write"):
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.write_failed", {
                        "slot": slot,
                        "injected": true,
                })

        var main_path := path_for(slot)
        var backup_path := backup_path_for(slot)
        var temp_path := temp_path_for(slot)
        var text := SnapshotCodec.canonical_json(working)
        var written := _write_text(temp_path, text)
        if not Result.is_ok(written):
                _remove_if_exists(temp_path)
                return written
        if _hook_enabled(slot, "truncate_temp"):
                # 模拟「写一半中断」：截断临时文件，读回校验必然失败。
                _write_text(temp_path, text.substr(0, maxi(1, text.length() / 3)))
        var verified := _read_snapshot(temp_path)
        if not Result.is_ok(verified) or not SnapshotCodec.checksum_matches(verified["data"]):
                _remove_if_exists(temp_path)
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.verify_failed", {"slot": slot})

        # 旧有效档转备份；旧档已损坏时保留既有备份，不覆盖唯一有效副本。
        if FileAccess.file_exists(main_path) and _is_valid_file(main_path, slot):
                if FileAccess.file_exists(backup_path):
                        var removed_backup := DirAccess.remove_absolute(backup_path)
                        if removed_backup != OK:
                                _remove_if_exists(temp_path)
                                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.backup_failed", {
                                        "slot": slot,
                                        "stage": "remove_old_backup",
                                        "error": removed_backup,
                                })
                var copied_backup := DirAccess.copy_absolute(main_path, backup_path)
                # 拷贝失败绝不能继续删正式档（《数据库与实体关系设计》§8「不删除唯一有效副本」）。
                if copied_backup != OK or not FileAccess.file_exists(backup_path):
                        _remove_if_exists(temp_path)
                        return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.backup_failed", {
                                "slot": slot,
                                "stage": "copy_backup",
                                "error": copied_backup,
                        })
        if _hook_enabled(slot, "fail_after_backup"):
                _remove_if_exists(temp_path)
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.write_failed", {
                        "slot": slot,
                        "stage": "after_backup",
                })
        if FileAccess.file_exists(main_path):
                var removed_main := DirAccess.remove_absolute(main_path)
                if removed_main != OK:
                        _remove_if_exists(temp_path)
                        return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.replace_failed", {
                                "slot": slot,
                                "stage": "remove_main",
                                "error": removed_main,
                        })
        var rename_error := OK
        if _hook_enabled(slot, "fail_rename"):
                rename_error = FAILED
        else:
                rename_error = DirAccess.rename_absolute(temp_path, main_path)
        if rename_error != OK:
                # 新档没就位：从备份回滚，至少要留一份有效档（§11.2「保留至少一份有效旧档」）。
                var rolled_back := false
                if not FileAccess.file_exists(main_path) and FileAccess.file_exists(backup_path):
                        rolled_back = DirAccess.copy_absolute(backup_path, main_path) == OK
                _remove_if_exists(temp_path)
                return Result.fail(GameConstants.ERROR_SAVE_IO_ERROR, "error.save.rename_failed", {
                        "slot": slot,
                        "error": rename_error,
                        "rolled_back": rolled_back,
                        "backup_available": FileAccess.file_exists(backup_path),
                })
        return Result.ok({
                "slot": slot,
                "saved_at": FileAccess.get_modified_time(main_path),
                "revision": working.get("revision"),
                "checksum": String(working.get("checksum", "")),
        })


# ── 三层校验 ──────────────────────────────────────────────

## Result：结构+checksum -> 内容兼容/引用 -> 领域不变量。slot 为空时只做不需要槽位语义的检查。
func validate_snapshot(snapshot: Dictionary, slot: String = "") -> Dictionary:
        var structural := SnapshotCodec.validate_structure(snapshot)
        if not structural.is_empty():
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.structure", {"problems": structural})
        if not SnapshotCodec.checksum_matches(snapshot):
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.checksum_mismatch", {"slot": slot})
        var version := int(snapshot.get("schema_version", -1))
        if version != SnapshotCodec.SNAPSHOT_SCHEMA_VERSION:
                return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.schema_version", {
                        "expected": SnapshotCodec.SNAPSHOT_SCHEMA_VERSION,
                        "got": version,
                })
        var compat := _content_compat_problem(snapshot)
        if not compat.is_empty():
                return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.content_mismatch", {"problem": compat})
        var references := _reference_problems(snapshot)
        if not references.is_empty():
                return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.save.broken_reference", {"problems": references})
        var domain := _domain_problems(snapshot, slot)
        if not domain.is_empty():
                return Result.fail(GameConstants.ERROR_SAVE_CORRUPT, "error.save.invariant", {"problems": domain})
        return Result.ok({"slot": slot})


func _enrich_content_info(snapshot: Dictionary) -> Dictionary:
        var working := snapshot.duplicate(true)
        if catalog == null:
                return Result.ok(working)
        var stored_hash := String(working.get("content_hash", ""))
        if not stored_hash.is_empty() and stored_hash != String(catalog.content_hash):
                return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.content_mismatch", {"field": "content_hash"})
        working["content_hash"] = String(catalog.content_hash)
        working["content_version"] = String(catalog.content_version)
        var stored_manifest := String(working.get("manifest_id", ""))
        if not stored_manifest.is_empty() and stored_manifest != String(catalog.manifest_id):
                return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.save.content_mismatch", {"field": "manifest_id"})
        working["manifest_id"] = String(catalog.manifest_id)
        return Result.ok(working)


func _content_compat_problem(snapshot: Dictionary) -> String:
        if catalog == null:
                return ""
        var stored_hash := String(snapshot.get("content_hash", ""))
        if not stored_hash.is_empty() and stored_hash != String(catalog.content_hash):
                return "content_hash 不一致"
        var stored_manifest := String(snapshot.get("manifest_id", ""))
        if not stored_manifest.is_empty() and stored_manifest != String(catalog.manifest_id):
                return "manifest_id 不一致"
        var payload := _as_dict(snapshot.get("payload"))
        var run := _as_dict(payload.get("run"))
        var stored_ruleset := String(run.get("ruleset_id", ""))
        if not stored_ruleset.is_empty() and stored_ruleset != String(catalog.ruleset_id):
                return "ruleset_id 不一致"
        return ""


func _reference_problems(snapshot: Dictionary) -> PackedStringArray:
        var problems := PackedStringArray()
        if catalog == null:
                return problems
        var payload := _as_dict(snapshot.get("payload"))
        var run := _as_dict(payload.get("run"))
        if not run.is_empty():
                _require_definition(problems, GameConstants.KIND_CHARACTER, String(run.get("character_id", "")), "run.character_id")
                for raw_card in _as_array(run.get("cards")):
                        var card := _as_dict(raw_card)
                        _require_definition(problems, GameConstants.KIND_CARD, String(card.get("definition_id", "")), "run.cards")
                for raw_relic in _as_array(run.get("relics")):
                        var relic := _as_dict(raw_relic)
                        _require_definition(problems, GameConstants.KIND_RELIC, String(relic.get("definition_id", "")), "run.relics")
        var battle := _as_dict(payload.get("battle"))
        if not battle.is_empty():
                _require_definition(problems, GameConstants.KIND_ENCOUNTER, String(battle.get("encounter_id", "")), "battle.encounter_id")
                _require_definition(problems, GameConstants.KIND_CHARACTER, String(battle.get("character_id", "")), "battle.character_id")
                for relic_id in _as_array(battle.get("relics")):
                        _require_definition(problems, GameConstants.KIND_RELIC, String(relic_id), "battle.relics")
                for raw_card_id in _as_dict(battle.get("card_by_id")):
                        var card_entry := _as_dict(_as_dict(battle.get("card_by_id"))[raw_card_id])
                        _require_definition(problems, GameConstants.KIND_CARD, String(card_entry.get("definition_id", "")), "battle.card_by_id")
                for raw_task in _as_array(battle.get("tasks")):
                        var task := _as_dict(raw_task)
                        _require_definition(problems, GameConstants.KIND_TASK, String(task.get("definition_id", "")), "battle.tasks")
                for raw_unit in _as_array(battle.get("units")):
                        var unit := _as_dict(raw_unit)
                        _require_definition(problems, GameConstants.KIND_UNIT, String(unit.get("definition_id", "")), "battle.units")
                var scene := _as_dict(battle.get("scene"))
                if not scene.is_empty():
                        _require_definition(problems, GameConstants.KIND_SCENE, String(scene.get("definition_id", "")), "battle.scene")
                for raw_status_id in _as_dict(battle.get("statuses")):
                        var status := _as_dict(_as_dict(battle.get("statuses"))[raw_status_id])
                        var status_id := String(status.get("definition_id", ""))
                        if status_id.is_empty() or not catalog.has_status_definition(status_id):
                                problems.append("battle.statuses 引用未定义状态：%s" % status_id)
        return problems


func _require_definition(problems: PackedStringArray, kind: String, id: String, what: String) -> void:
        if id.is_empty() or not catalog.is_enabled(kind, id):
                problems.append("%s 指向未启用的 %s：%s" % [what, kind, id])


func _domain_problems(snapshot: Dictionary, slot: String) -> PackedStringArray:
        var problems := PackedStringArray()
        var payload := _as_dict(snapshot.get("payload"))
        if slot == SLOT_CURRENT_RUN:
                problems.append_array(_session_problems(snapshot, payload))
        elif slot == SLOT_PROFILE:
                problems.append_array(_profile_problems(payload))
        return problems


# ── 小工具 ────────────────────────────────────────────────

func _is_valid_file(path: String, slot: String) -> bool:
        var read := _read_snapshot(path)
        if not Result.is_ok(read):
                return false
        return Result.is_ok(validate_snapshot(read["data"], slot))


func _hook(slot: String, name: String) -> Variant:
        var per_slot: Variant = debug_hooks.get(slot)
        if typeof(per_slot) == TYPE_DICTIONARY and (per_slot as Dictionary).has(name):
                return (per_slot as Dictionary)[name]
        var all_slots: Variant = debug_hooks.get("*")
        if typeof(all_slots) == TYPE_DICTIONARY and (all_slots as Dictionary).has(name):
                return (all_slots as Dictionary)[name]
        return null


## bool(null) 在 GDScript 会报错，这里显式把「未注入」当作 false。
func _hook_enabled(slot: String, name: String) -> bool:
        var value = _hook(slot, name)
        if value == null:
                return false
        return bool(value)


func _remove_if_exists(path: String) -> void:
        if FileAccess.file_exists(path):
                DirAccess.remove_absolute(path)


func _as_array(raw: Variant) -> Array:
        if typeof(raw) == TYPE_ARRAY:
                return raw
        return []


func _as_dict(raw: Variant) -> Dictionary:
        if typeof(raw) == TYPE_DICTIONARY:
                return raw
        return {}

# ── 结局三步提交（§8「结局写入Profile」）──────────────────

## Result<Dictionary>：① pending 已随 current_run 落盘 → ② 幂等合并并保存 Profile →
## ③ 清 pending 并保存 current_run。第 2 步失败保留 pending；第 3 步失败后重试不重复记录。
func commit_pending_profile(slot_current: String = SLOT_CURRENT_RUN, slot_profile: String = SLOT_PROFILE) -> Dictionary:
        var current_result := self.load(slot_current)
        if not Result.is_ok(current_result):
                return current_result
        var snapshot: Dictionary = current_result["data"]
        var payload := _as_dict(snapshot.get("payload"))
        var pending: Variant = payload.get("pending_profile_summary")
        if pending == null:
                return Result.ok({"merged": false, "run_id": String(snapshot.get("run_id", ""))})
        var summary: Dictionary = pending

        var profile := ProfileMerge.empty_profile()
        var profile_result := self.load(slot_profile)
        if Result.is_ok(profile_result):
                var profile_payload := _as_dict(profile_result["data"].get("payload"))
                if not profile_payload.is_empty():
                        profile = profile_payload
        elif Result.error_code(profile_result) != GameConstants.ERROR_SAVE_NOT_FOUND:
                # 损坏的 Profile 不静默覆盖，交给调用方提示恢复备份。
                return profile_result

        var merged_result := ProfileMerge.merge(profile, summary)
        if not Result.is_ok(merged_result):
                return merged_result
        var merged: Dictionary = merged_result["data"]
        var profile_meta := {
                "content_version": String(catalog.content_version) if catalog != null else "",
                "content_hash": String(catalog.content_hash) if catalog != null else "",
                "manifest_id": String(catalog.manifest_id) if catalog != null else "",
        }
        var profile_snapshot_result := SnapshotCodec.encode_document(merged, profile_meta)
        if not Result.is_ok(profile_snapshot_result):
                return profile_snapshot_result
        var profile_saved := save(slot_profile, profile_snapshot_result["data"])
        if not Result.is_ok(profile_saved):
                return profile_saved

        payload["pending_profile_summary"] = null
        snapshot["payload"] = payload
        snapshot["checksum"] = SnapshotCodec.compute_checksum(snapshot)
        var current_saved := save(slot_current, snapshot)
        if not Result.is_ok(current_saved):
                return current_saved
        return Result.ok({
                "merged": true,
                "run_id": String(summary.get("run_id", "")),
                "completed_runs": int(merged.get(ProfileMerge.KEY_COMPLETED, 0)),
                "saved_at": current_saved["data"].get("saved_at"),
        })

# ── 领域不变量（第 3 层）─────────────────────────────────

func _session_problems(snapshot: Dictionary, payload: Dictionary) -> PackedStringArray:
        var problems := PackedStringArray()
        var decoded := SnapshotCodec.decode_session(snapshot)
        if not Result.is_ok(decoded):
                problems.append("会话无法重建：%s" % Result.error_code(decoded))
                return problems
        var session = decoded["data"]["session"]
        problems.append_array(session.validate())
        var relic_slots := 6
        var unit_slots := 3
        if catalog != null:
                relic_slots = catalog.run_int("relic_slots", 6)
                unit_slots = catalog.battle_int("unit_slots", 3)
        problems.append_array(session.run.validate(relic_slots))
        if session.battle != null:
                problems.append_array(session.battle.validate(unit_slots))
                if session.run.settled_battle_ids.has(session.battle.battle_id):
                        problems.append("已结算战斗仍挂在会话上：%s" % session.battle.battle_id)
        var raw_battle := _as_dict(payload.get("battle"))
        if not raw_battle.is_empty() and raw_battle.get("resolution") != null:
                problems.append("稳定边界快照的 battle.resolution 必须为 null")
        var pending: Variant = payload.get("pending_profile_summary")
        if typeof(pending) == TYPE_DICTIONARY:
                var pending_run_id := String((pending as Dictionary).get("run_id", ""))
                if pending_run_id != session.run_id:
                        problems.append("待合并摘要 run_id 与当前局不一致：%s != %s" % [pending_run_id, session.run_id])
        return problems


func _profile_problems(payload: Dictionary) -> PackedStringArray:
        var problems := PackedStringArray()
        if typeof(payload.get("summaries_by_run_id", {})) != TYPE_DICTIONARY:
                problems.append("profile.summaries_by_run_id 必须是对象")
        if typeof(payload.get("unlocked_ids", [])) != TYPE_ARRAY:
                problems.append("profile.unlocked_ids 必须是数组")
        if typeof(payload.get("seen_content_ids", [])) != TYPE_ARRAY:
                problems.append("profile.seen_content_ids 必须是数组")
        if typeof(payload.get("tutorial_flags", {})) != TYPE_DICTIONARY:
                problems.append("profile.tutorial_flags 必须是对象")
        var summaries := _as_dict(payload.get("summaries_by_run_id"))
        if payload.has("completed_runs") or not summaries.is_empty():
                var declared := int(payload.get("completed_runs", summaries.size()))
                if declared != summaries.size():
                        problems.append("profile.completed_runs 与去重摘要数不一致：%d != %d" % [declared, summaries.size()])
        return problems