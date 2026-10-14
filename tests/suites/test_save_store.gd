extends RefCounted
##
## SaveStore 验收：槽位、原子保存、备份、三层校验、故障注入、结局三步提交、存读档一致性。
## 依据《数据库与实体关系设计》§7/§8/§9/§10；《接口文档》§7。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Ids := preload("res://src/common/ids.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const BattleStateScript := preload("res://src/battle/battle_state.gd")
const SessionStateScript := preload("res://src/app/session_state.gd")
const RandomSource := preload("res://src/common/random_source.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const SnapshotCodec := preload("res://src/storage/snapshot_codec.gd")
const SaveStoreScript := preload("res://src/storage/save_store.gd")
const ProfileMerge := preload("res://src/storage/profile_merge.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")

const SLOT_RUN := GameConstants.SAVE_CURRENT_RUN
const SLOT_PROFILE := GameConstants.SAVE_PROFILE


func run(h) -> void:
        var db := ContentDB.new()
        var loaded = db.load("battle_mvp")
        if not Result.is_ok(loaded):
                h.begin("SaveStore · 前置")
                h.check("battle_mvp 清单加载成功", false, str(loaded))
                return
        h.begin("SaveStore · 槽位与元数据")
        _slots(h, db)
        h.begin("SaveStore · 保存 / 读取 / 备份")
        _save_load_backup(h, db)
        h.begin("SaveStore · 损坏档")
        _corruption(h, db)
        h.begin("SaveStore · 故障注入")
        _faults(h, db)
        h.begin("SaveStore · 三层校验")
        _validation(h, db)
        h.begin("SaveStore · 验收案例 §10.1/§10.2/§10.4")
        _acceptance(h, db)
        h.begin("SaveStore · 结局三步提交 §10.6")
        _profile_commit(h, db)
        h.begin("SaveStore · 连续运行 vs 存读档后再运行")
        _determinism(h, db)


# ── 槽位与元数据 ──────────────────────────────────────────

func _slots(h, db) -> void:
        var store = _new_store(db, "slots")
        var missing = store.inspect(SLOT_RUN)
        h.eq("无档返回 SAVE_NOT_FOUND", Result.error_code(missing), GameConstants.ERROR_SAVE_NOT_FOUND)
        var unknown = store.inspect("no_such_slot")
        h.eq("未知槽位返回 INVALID_ARGUMENT", Result.error_code(unknown), GameConstants.ERROR_INVALID_ARGUMENT)
        h.check("正式档路径带 .json", store.path_for(SLOT_RUN).ends_with("current_run.json"))
        h.check("备份路径带 .json.bak", store.backup_path_for(SLOT_RUN).ends_with("current_run.json.bak"))
        h.check("临时路径带 .json.tmp", store.temp_path_for(SLOT_RUN).ends_with("current_run.json.tmp"))
        _cleanup(store.base_dir)


# ── 保存 / 读取 / 备份 ────────────────────────────────────

func _save_load_backup(h, db) -> void:
        var store = _new_store(db, "backup")
        var session = _sample_session()
        session.revision = 3

        var saved := _save_session(store, session)
        if not _ok(h, "首存成功", saved):
                return
        h.eq("SaveReceipt.slot", saved["data"]["slot"], SLOT_RUN)
        h.eq("SaveReceipt.revision", int(saved["data"]["revision"]), 3)
        h.eq("SaveReceipt.checksum 64 位", String(saved["data"]["checksum"]).length(), 64)

        var meta = store.inspect(SLOT_RUN)
        if _ok(h, "inspect 成功", meta):
                h.eq("inspect.valid", meta["data"]["valid"], true)
                h.eq("inspect.schema_version", int(meta["data"]["schema_version"]), 1)
                h.eq("inspect.content_version 已补齐", meta["data"]["content_version"], "battle-mvp-0.1")
                h.eq("inspect.revision", int(meta["data"]["revision"]), 3)
        h.check("首存没有备份", Result.error_code(store.load_backup(SLOT_RUN)) == GameConstants.ERROR_SAVE_NOT_FOUND)

        session.revision = 4
        session.run.money = 61
        if not _ok(h, "二次保存成功", _save_session(store, session)):
                return
        var current = store.load(SLOT_RUN)
        if _ok(h, "读取最新档", current):
                h.eq("当前档 revision=4", int(current["data"]["revision"]), 4)
                h.eq("当前档 money=61", int(current["data"]["payload"]["run"]["money"]), 61)
        var backup = store.load_backup(SLOT_RUN)
        if _ok(h, "读取备份", backup):
                h.eq("备份是上一版 revision=3", int(backup["data"]["revision"]), 3)
                h.eq("备份 money=60", int(backup["data"]["payload"]["run"]["money"]), 60)
        _cleanup(store.base_dir)


# ── 损坏档 ────────────────────────────────────────────────

func _corruption(h, db) -> void:
        var store = _new_store(db, "corrupt")
        var session = _sample_session()
        session.revision = 1
        _save_session(store, session)
        session.revision = 2
        session.run.money = 70
        _save_session(store, session)

        # 只改 checksum：仍能解析，但校验和不匹配
        var snapshot = store.load(SLOT_RUN)
        if not _ok(h, "读取用于篡改的档", snapshot):
                return
        var tampered: Dictionary = snapshot["data"].duplicate(true)
        tampered["checksum"] = "0".repeat(64)
        _write_json(store.path_for(SLOT_RUN), tampered)
        h.eq("checksum 不匹配返回 SAVE_CORRUPT", Result.error_code(store.load(SLOT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)
        var inspected = store.inspect(SLOT_RUN)
        if Result.is_ok(inspected):
                h.eq("inspect 标出 valid=false", inspected["data"]["valid"], false)
        h.check("正式档损坏时备份仍可读", Result.is_ok(store.load_backup(SLOT_RUN)))

        # 结构缺字段
        var missing = snapshot["data"].duplicate(true)
        missing.erase("payload")
        missing["checksum"] = SnapshotCodec.compute_checksum(missing)
        _write_json(store.path_for(SLOT_RUN), missing)
        h.eq("缺 payload 结构层报损坏", Result.error_code(store.load(SLOT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)

        # 非 JSON
        _write_text(store.path_for(SLOT_RUN), "{ not json")
        h.eq("非法 JSON 报损坏", Result.error_code(store.load(SLOT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)

        # §10.7 原始档与备份均损坏：都报错，且不自动删档
        _write_text(store.path_for(SLOT_RUN), "garbage-main")
        _write_text(store.backup_path_for(SLOT_RUN), "garbage-backup")
        h.eq("原始档损坏报错", Result.error_code(store.load(SLOT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)
        h.eq("备份损坏报错", Result.error_code(store.load_backup(SLOT_RUN)), GameConstants.ERROR_SAVE_CORRUPT)
        h.check("损坏的证据仍在（未静默覆盖）", FileAccess.file_exists(store.path_for(SLOT_RUN)) and FileAccess.file_exists(store.backup_path_for(SLOT_RUN)))
        _cleanup(store.base_dir)


# ── 故障注入 ──────────────────────────────────────────────

func _faults(h, db) -> void:
        var store = _new_store(db, "faults")
        var session = _sample_session()
        session.revision = 1
        if not _ok(h, "写入基准档", _save_session(store, session)):
                return

        # 写一半中断：临时文件被截断，读回校验失败，正式档保持旧值
        store.debug_hooks = {SLOT_RUN: {"truncate_temp": true}}
        session.revision = 2
        h.eq("写一半中断返回 SAVE_IO_ERROR", Result.error_code(_save_session(store, session)), GameConstants.ERROR_SAVE_IO_ERROR)
        store.debug_hooks = {}
        h.check("中断后临时文件已清理", not FileAccess.file_exists(store.temp_path_for(SLOT_RUN)))
        var after_interrupt = store.load(SLOT_RUN)
        if Result.is_ok(after_interrupt):
                h.eq("中断后正式档仍是旧值", int(after_interrupt["data"]["revision"]), 1)

        # 磁盘不可写（注入）
        store.debug_hooks = {SLOT_RUN: {"fail_write": true}}
        h.eq("写失败返回 SAVE_IO_ERROR", Result.error_code(_save_session(store, session)), GameConstants.ERROR_SAVE_IO_ERROR)
        store.debug_hooks = {}

        # 替换阶段失败：备份还原正式档
        store.debug_hooks = {SLOT_RUN: {"fail_rename": true}}
        session.revision = 5
        h.eq("替换失败返回 SAVE_IO_ERROR", Result.error_code(_save_session(store, session)), GameConstants.ERROR_SAVE_IO_ERROR)
        store.debug_hooks = {}
        var restored = store.load(SLOT_RUN)
        if Result.is_ok(restored):
                h.eq("替换失败后从备份还原", int(restored["data"]["revision"]), 1)

        # G2：备份拷贝失败（备份路径被占成目录）时，绝不能删掉唯一有效档。
        var probe = _new_store(db, "faults_backup_copy")
        session.revision = 1
        if not _ok(h, "探针：写入基准档", _save_session(probe, session)):
                return
        var abs_backup := ProjectSettings.globalize_path(probe.backup_path_for(SLOT_RUN))
        if DirAccess.dir_exists_absolute(abs_backup):
                DirAccess.remove_absolute(abs_backup)
        h.eq("故障注入：备份路径被占成目录", DirAccess.make_dir_absolute(abs_backup), OK)
        probe.debug_hooks = {SLOT_RUN: {"fail_rename": true}}
        session.revision = 2
        h.eq("备份失败返回 SAVE_IO_ERROR", Result.error_code(_save_session(probe, session)), GameConstants.ERROR_SAVE_IO_ERROR)
        probe.debug_hooks = {}
        h.check("备份失败后正式档仍在（没删唯一有效副本）", Result.is_ok(probe.load(SLOT_RUN)))
        if Result.is_ok(probe.load(SLOT_RUN)):
                h.eq("正式档仍是旧有效值", int(probe.load(SLOT_RUN)["data"]["revision"]), 1)
        h.check("备份路径仍不是有效档", not Result.is_ok(probe.load_backup(SLOT_RUN)))
        h.check("至少一份有效档可读", Result.is_ok(probe.load(SLOT_RUN)) or Result.is_ok(probe.load_backup(SLOT_RUN)))
        _cleanup(probe.base_dir)

        # 磁盘不可写（真实：路径中间是文件，目录建不出来）
        var blocked_dir = "user://test_saves_blocked_" + str(Time.get_ticks_usec())
        DirAccess.make_dir_recursive_absolute(blocked_dir)
        _write_text(blocked_dir + "/not_a_dir", "x")
        var blocked_store = SaveStoreScript.new(blocked_dir + "/not_a_dir/saves", db)
        h.eq("目录不可创建返回 SAVE_IO_ERROR", Result.error_code(_save_session(blocked_store, session)), GameConstants.ERROR_SAVE_IO_ERROR)
        _cleanup(store.base_dir)
        _cleanup(blocked_dir)

# ── 三层校验 ──────────────────────────────────────────────

func _validation(h, db) -> void:
        var store = _new_store(db, "validation")
        var session = _sample_session()

        var broken = _sample_session()
        broken.run.add_card("K99", 0, "test")
        h.eq("引用未启用定义返回 CONTENT_INVALID", Result.error_code(_save_session(store, broken)), GameConstants.ERROR_CONTENT_INVALID)

        var encoded = SnapshotCodec.encode_session(session, null, _meta(session))
        if not _ok(h, "基准快照可编码", encoded):
                return
        var base: Dictionary = encoded["data"]

        var bad_hash = base.duplicate(true)
        bad_hash["content_hash"] = "0123456789abcdef".repeat(4)
        bad_hash["checksum"] = SnapshotCodec.compute_checksum(bad_hash)
        h.eq("content_hash 不一致返回 VERSION_MISMATCH", Result.error_code(store.save(SLOT_RUN, bad_hash)), GameConstants.ERROR_VERSION_MISMATCH)

        var bad_manifest = base.duplicate(true)
        bad_manifest["manifest_id"] = "mvp"
        bad_manifest["checksum"] = SnapshotCodec.compute_checksum(bad_manifest)
        h.eq("manifest 不一致返回 VERSION_MISMATCH", Result.error_code(store.save(SLOT_RUN, bad_manifest)), GameConstants.ERROR_VERSION_MISMATCH)

        var future = base.duplicate(true)
        future["schema_version"] = 99
        future["checksum"] = SnapshotCodec.compute_checksum(future)
        h.eq("未来 schema 返回 VERSION_MISMATCH", Result.error_code(store.save(SLOT_RUN, future)), GameConstants.ERROR_VERSION_MISMATCH)

        var unstable = base.duplicate(true)
        unstable["payload"]["battle"]["resolution"] = {"card_id": "bc1"}
        unstable["checksum"] = SnapshotCodec.compute_checksum(unstable)
        h.eq("稳定边界出现 resolution 返回 SAVE_CORRUPT", Result.error_code(store.save(SLOT_RUN, unstable)), GameConstants.ERROR_SAVE_CORRUPT)

        var bad_pending = base.duplicate(true)
        bad_pending["payload"]["pending_profile_summary"] = {"run_id": "Rother"}
        bad_pending["checksum"] = SnapshotCodec.compute_checksum(bad_pending)
        h.eq("待合并摘要 run_id 不匹配返回 SAVE_CORRUPT", Result.error_code(store.save(SLOT_RUN, bad_pending)), GameConstants.ERROR_SAVE_CORRUPT)

        var settled = _sample_session()
        settled.run.settled_battle_ids[settled.battle.battle_id] = true
        h.eq("已结算战斗仍在场返回 SAVE_CORRUPT", Result.error_code(_save_session(store, settled)), GameConstants.ERROR_SAVE_CORRUPT)
        _cleanup(store.base_dir)


# ── 验收案例 ──────────────────────────────────────────────

func _acceptance(h, db) -> void:
        var store = _new_store(db, "acceptance")
        var session = _sample_session()
        if not _ok(h, "基准档可保存", _save_session(store, session)):
                return
        var loaded = store.load(SLOT_RUN)
        if not _ok(h, "基准档可读取", loaded):
                return
        var decoded = SnapshotCodec.decode_session(loaded["data"])
        if not _ok(h, "基准档可重建会话", decoded):
                return
        var out = decoded["data"]["session"]

        # §10.1 四个 K01 实例 ID 互不相同，升级只影响一张
        var ids := {}
        for card in out.run.cards:
                ids[card.card_id] = true
        h.eq("§10.1 四个永久实例 ID 互不相同", ids.size(), 4)
        h.eq("§10.1 升级只影响一张", int(out.run.cards[1].upgrade_level), 1)
        h.eq("§10.1 其余三张未升级", [int(out.run.cards[0].upgrade_level), int(out.run.cards[2].upgrade_level), int(out.run.cards[3].upgrade_level)], [0, 0, 0])
        h.eq("§10.1 next_instance_seq 继续递增", int(out.run.next_instance_seq), int(session.run.next_instance_seq))

        # §10.2 临时牌不进永久牌组；删除的永久牌读档后仍是删除状态
        var temporary_ids := ["bc3"]
        var permanent_ids := {}
        for card in out.run.cards:
                permanent_ids[card.card_id] = true
        h.check("§10.2 临时战斗牌不在永久牌组", not permanent_ids.has(temporary_ids[0]))
        out.run.remove_card(out.run.cards[0].card_id)
        if _ok(h, "§10.2 删除一张永久牌后保存", _save_session(store, out)):
                var after = store.load(SLOT_RUN)
                var after_session = SnapshotCodec.decode_session(after["data"])["data"]["session"]
                h.eq("§10.2 删除在读档后保持", after_session.run.cards.size(), 3)

        # §10.3 首领新阶段 task_id 改变，旧目标不再存在
        var b01 = _begin_battle(db, {"encounter_id": "B01", "deck": _deck("K01", 12), "seed": 5})
        if Result.is_ok(b01):
                var state = _state(b01)
                var old_task_id = state.tasks[0].task_id
                state.tasks[0].work_remaining = 2
                state.tasks[0].shield = 4
                var played = _play_first(engine_for(db), b01, "K01")
                if Result.is_ok(played):
                        var next_state = _state(played)
                        var new_task_id = next_state.tasks[0].task_id
                        var phased = _sample_session()
                        phased.battle = next_state
                        phased.random_snapshot = played["data"]["rng_state"]
                        if _ok(h, "§10.3 转阶段后可保存", _save_session(store, phased)):
                                var phased_loaded = store.load(SLOT_RUN)
                                var phased_session = SnapshotCodec.decode_session(phased_loaded["data"])["data"]["session"]
                                h.eq("§10.3 新 task_id 保留", phased_session.battle.tasks[0].task_id, new_task_id)
                                h.eq("§10.3 新阶段 phase_key 保留", phased_session.battle.tasks[0].phase_key, "integral")
                                h.check("§10.3 旧 task_id 不存在", phased_session.battle.find_task(old_task_id) == null)

        # §10.4 计数器与 L02 预抽结果不因读档刷新
        var counted = _sample_session()
        counted.battle.scene.definition_id = "L02"
        counted.battle.scene.pending_random_result = 3
        var round_key = BattleStateScript.counter_key("round", "p01_third_work_compile", "work_resolved")
        var battle_key = BattleStateScript.counter_key("battle", "L01", "prepare")
        counted.battle.counters[round_key].count = 2
        counted.battle.counters[round_key].round = 2
        var battle_counter = BattleStateScript.create_counter("battle", "L01", "prepare")
        battle_counter.count = 3
        counted.battle.counters[battle_key] = battle_counter
        if _ok(h, "§10.4 带计数器保存", _save_session(store, counted)):
                var counted_loaded = store.load(SLOT_RUN)
                var counted_session = SnapshotCodec.decode_session(counted_loaded["data"])["data"]["session"]
                h.eq("§10.4 回合计数保留", int(counted_session.battle.counters[round_key].count), 2)
                h.eq("§10.4 回合计数周期保留", int(counted_session.battle.counters[round_key].round), 2)
                h.eq("§10.4 战斗计数保留", int(counted_session.battle.counters[battle_key].count), 3)
                h.eq("§10.4 L02 预抽结果不重抽", int(counted_session.battle.scene.pending_random_result), 3)
                h.eq("§10.4 随机状态原样", SnapshotCodec.canonical_json(counted_session.random_snapshot), SnapshotCodec.canonical_json(counted.random_snapshot))
        _cleanup(store.base_dir)

# ── 结局三步提交 ──────────────────────────────────────────

func _profile_commit(h, db) -> void:
        var store = _new_store(db, "profile")
        var session = _sample_session()
        var run_id = session.run_id
        var summary = {
                "run_id": run_id,
                "result": "won",
                "unlocked_ids": ["K14", "K01"],
                "seen_content_ids": ["N01"],
                "tutorial_flags": {"tut_1": true},
                "career_progress": {"code": 1},
        }
        if not _ok(h, "pending 随终局落盘", _save_session(store, session, summary)):
                return

        # 第 2 步失败：Profile 未写入，pending 保留
        store.debug_hooks = {SLOT_PROFILE: {"fail_write": true}}
        h.eq("Profile 写失败返回 SAVE_IO_ERROR", Result.error_code(store.commit_pending_profile(SLOT_RUN, SLOT_PROFILE)), GameConstants.ERROR_SAVE_IO_ERROR)
        store.debug_hooks = {}
        var still = store.load(SLOT_RUN)
        if Result.is_ok(still):
                h.check("失败后 pending 保留", still["data"]["payload"]["pending_profile_summary"] != null)
        h.eq("Profile 仍不存在", Result.error_code(store.load(SLOT_PROFILE)), GameConstants.ERROR_SAVE_NOT_FOUND)

        # 重试成功
        var committed = store.commit_pending_profile(SLOT_RUN, SLOT_PROFILE)
        if _ok(h, "重试提交成功", committed):
                h.eq("merged=true", committed["data"]["merged"], true)
                h.eq("completed_runs=1", int(committed["data"]["completed_runs"]), 1)
        var profile = store.load(SLOT_PROFILE)
        if _ok(h, "Profile 可读取", profile):
                var payload: Dictionary = profile["data"]["payload"]
                h.eq("摘要只记 1 份", (payload["summaries_by_run_id"] as Dictionary).size(), 1)
                h.eq("completed_runs 由去重摘要导出", int(payload["completed_runs"]), 1)
                h.eq("解锁并集排序", payload["unlocked_ids"], ["K01", "K14"])
                h.eq("教程标记合并", payload["tutorial_flags"]["tut_1"], true)
        var cleared = store.load(SLOT_RUN)
        if Result.is_ok(cleared):
                h.check("第 3 步清掉 pending", cleared["data"]["payload"]["pending_profile_summary"] == null)

        # 第 3 步失败：Profile 已合并，pending 尚未清除；重试不重复记录
        _attach_pending(store, summary)
        store.debug_hooks = {SLOT_RUN: {"fail_write": true}}
        h.eq("清 pending 失败返回 SAVE_IO_ERROR", Result.error_code(store.commit_pending_profile(SLOT_RUN, SLOT_PROFILE)), GameConstants.ERROR_SAVE_IO_ERROR)
        store.debug_hooks = {}
        var mid_profile = store.load(SLOT_PROFILE)
        if Result.is_ok(mid_profile):
                h.eq("重试前摘要已存在且不重复", (mid_profile["data"]["payload"]["summaries_by_run_id"] as Dictionary).size(), 1)
        var retried = store.commit_pending_profile(SLOT_RUN, SLOT_PROFILE)
        if _ok(h, "第 3 步重试成功", retried):
                h.eq("重试后 completed_runs 仍为 1", int(retried["data"]["completed_runs"]), 1)
        var final_profile = store.load(SLOT_PROFILE)
        if Result.is_ok(final_profile):
                h.eq("重试后摘要仍 1 份", (final_profile["data"]["payload"]["summaries_by_run_id"] as Dictionary).size(), 1)

        # 第二局：不同 run_id 才允许承接新的 pending
        var session2 = _sample_session()
        session2.run_id = session2.run_id + "B"
        session2.run.run_id = session2.run_id
        session2.battle = null
        session2.revision = 1
        var summary2 = {"run_id": session2.run_id, "result": "lost", "unlocked_ids": ["K13"]}
        _save_session(store, session2, summary2)
        var committed2 = store.commit_pending_profile(SLOT_RUN, SLOT_PROFILE)
        if _ok(h, "第二局提交成功", committed2):
                h.eq("completed_runs=2", int(committed2["data"]["completed_runs"]), 2)
        _cleanup(store.base_dir)


# ── 连续运行 vs 存读档后再运行 ────────────────────────────

func _determinism(h, db) -> void:
        var store = _new_store(db, "determinism")
        var engine = BattleEngine.new(db)
        var plan = ["play", "play", "end", "play", "play"]
        var source = RandomSource.new(99)
        var start = engine.begin({
                "battle_id": "Rtest#1",
                "node_id": "n1",
                "encounter_id": "N01",
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": 72,
                "max_vitality": 72,
                "cards": _deck("K01", 12),
                "relics": ["A01"],
                "rng_state": source.export_state(),
        })
        if not _ok(h, "对局开始", start):
                return

        var step_a = start
        for item in plan:
                step_a = _apply_plan(engine, step_a, String(item))
                if not Result.is_ok(step_a):
                        h.check("连续运行失败", false, str(step_a))
                        return

        var step_b = start
        for index in range(3):
                step_b = _apply_plan(engine, step_b, String(plan[index]))
                if not Result.is_ok(step_b):
                        h.check("存读档前运行失败", false, str(step_b))
                        return
        var mid_session = _sample_session()
        mid_session.battle = _state(step_b)
        mid_session.random_snapshot = step_b["data"]["rng_state"]
        mid_session.revision = 1
        if not _ok(h, "中途保存", _save_session(store, mid_session)):
                return
        var loaded = store.load(SLOT_RUN)
        if not _ok(h, "中途读取", loaded):
                return
        var decoded = SnapshotCodec.decode_session(loaded["data"])
        if not _ok(h, "中途重建会话", decoded):
                return
        var resumed = decoded["data"]["session"]
        var step_b2 = {"data": {"state": resumed.battle, "rng_state": resumed.random_snapshot}}
        for index in range(3, plan.size()):
                step_b2 = _apply_plan(engine, step_b2, String(plan[index]))
                if not Result.is_ok(step_b2):
                        h.check("存读档后运行失败", false, str(step_b2))
                        return

        h.eq("状态签名一致", _signature(_state(step_b2)), _signature(_state(step_a)))
        h.check("随机快照一致", SnapshotCodec.canonical_json(step_b2["data"]["rng_state"]) == SnapshotCodec.canonical_json(step_a["data"]["rng_state"]))
        _cleanup(store.base_dir)


# ── 工具 ──────────────────────────────────────────────────

func _new_store(db, name: String):
        return SaveStoreScript.new("user://test_saves_" + name + "_" + str(Time.get_ticks_usec()), db)


func _meta(session) -> Dictionary:
        return {"content_version": "", "content_hash": "", "manifest_id": session.run.manifest_id}


func _save_session(store, session, pending: Variant = null) -> Dictionary:
        var encoded = SnapshotCodec.encode_session(session, pending, _meta(session))
        if not Result.is_ok(encoded):
                return encoded
        return store.save(SLOT_RUN, encoded["data"])


func _attach_pending(store, summary: Dictionary) -> void:
        var loaded = store.load(SLOT_RUN)
        if not Result.is_ok(loaded):
                return
        var snapshot: Dictionary = loaded["data"].duplicate(true)
        var payload: Dictionary = snapshot["payload"].duplicate(true)
        payload["pending_profile_summary"] = summary
        snapshot["payload"] = payload
        snapshot["checksum"] = SnapshotCodec.compute_checksum(snapshot)
        store.save(SLOT_RUN, snapshot)


func _sample_session():
        var run = RunStateScript.new()
        run.run_id = Ids.run_id_from_seed(4242)
        run.character_id = "P01"
        run.ruleset_id = "campus_v1"
        run.difficulty = "normal"
        run.manifest_id = "battle_mvp"
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
        unit.cooperation = 2
        unit.entered_order = 1
        battle.units.append(unit)
        var task = BattleStateScript.create_task("t1", "N01", "A", 24)
        task.work_remaining = 18
        task.shield = 3
        task.intent_cursor = 1
        task.intent_snapshot = {"index": 2, "pressure": 7}
        task.entered_order = 1
        battle.tasks.append(task)
        # 状态交给主角持有（K04 灵感是最常见路径）——以前这里用任务持有者绕开了
        # 「主角状态」这个真实场景，等于把 G1 藏起来。
        var status = BattleStateScript.create_status("st1", GameConstants.STATUS_INSPIRATION, "e1", 2)
        status.source = {"source": "K04"}
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


func _begin_battle(db, options: Dictionary) -> Dictionary:
        var engine = BattleEngine.new(db)
        var source = RandomSource.new(int(options.get("seed", 7)))
        return engine.begin({
                "battle_id": "Rtest#1",
                "node_id": "n1",
                "encounter_id": String(options.get("encounter_id", "N01")),
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": 72,
                "max_vitality": 72,
                "cards": options.get("deck", []),
                "relics": ["A01"],
                "rng_state": source.export_state(),
        })


func engine_for(db):
        return BattleEngine.new(db)


func _play_first(engine, step: Dictionary, definition_id: String) -> Dictionary:
        var state = _state(step)
        var card_id = _first_hand(state, definition_id)
        if card_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.test.no_card", {})
        var payload = {"card_id": card_id}
        if not state.tasks.is_empty():
                payload["target_ids"] = [state.tasks[0].task_id]
        return engine.apply(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": payload}, step["data"]["rng_state"])


func _apply_plan(engine, step: Dictionary, item: String) -> Dictionary:
        var state = _state(step)
        var card_id = _first_hand(state, "K01")
        if item == "end" or card_id.is_empty() or state.tasks.is_empty():
                return engine.apply(state, {"type": GameConstants.ACTION_END_TURN, "payload": {}}, step["data"]["rng_state"])
        return engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card_id, "target_ids": [state.tasks[0].task_id]},
        }, step["data"]["rng_state"])


func _signature(state) -> String:
        var work := -1
        if not state.tasks.is_empty():
                work = int(state.tasks[0].work_remaining)
        return SnapshotCodec.canonical_json({
                "phase": state.phase,
                "round_index": state.round_index,
                "ddl": state.ddl,
                "focus": state.player.focus,
                "vitality": state.player.vitality,
                "work": work,
                "hand": state.card_ids_in(GameConstants.ZONE_HAND),
                "zones": state.zones.counts(),
                "units": state.units.size(),
        })


func _first_hand(state, definition_id: String) -> String:
        for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
                var card = state.get_card(String(raw_id))
                if card != null and card.definition_id == definition_id:
                        return card.card_id
        return ""


func _deck(definition_id: String, count: int) -> Array:
        var deck = []
        for index in range(count):
                deck.append({
                        "card_id": "Rtest#B_%s_%d" % [definition_id, index],
                        "definition_id": definition_id,
                        "origin_card_id": "Rtest#R_%s_%d" % [definition_id, index],
                        "upgrade_level": 0,
                })
        return deck


func _write_text(path: String, text: String) -> void:
        var file = FileAccess.open(path, FileAccess.WRITE)
        if file == null:
                return
        file.store_string(text)
        file.flush()
        file.close()


func _write_json(path: String, data: Dictionary) -> void:
        _write_text(path, SnapshotCodec.canonical_json(data))


func _cleanup(dir: String) -> void:
        var access = DirAccess.open(dir)
        if access == null:
                return
        access.list_dir_begin()
        var name = access.get_next()
        while name != "":
                if not access.current_is_dir():
                        access.remove(name)
                name = access.get_next()
        access.list_dir_end()
        DirAccess.remove_absolute(dir)


func _state(step: Dictionary):
        return step["data"]["state"]


func _ok(h, label: String, result: Dictionary) -> bool:
        if Result.is_ok(result):
                h.check(label, true)
                return true
        h.check(label, false, str(result.get("error")))
        return false