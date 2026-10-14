extends RefCounted
##
## 局流程验收：RunService / RunMap / 地图节点 / 奖励 / 商店 / 休息 / 学期结算。
## 依据《接口文档》§5、《类与方法设计》§4、《统一设计文档》§10、《数据库与实体关系设计》§5/§9。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const RandomSource := preload("res://src/common/random_source.gd")
const RunService := preload("res://src/run/run_service.gd")
const RunMap := preload("res://src/run/run_map.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const RewardOffer := preload("res://src/run/run_reward_offer.gd")
const ShopState := preload("res://src/run/run_shop_state.gd")
const RunCodec := preload("res://src/run/run_codec.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")

const SEED := "20261013"

## 冻结夹具清单（队长裁决 ①）：run-service 的行为断言只依赖这份稳定内容，
## 不再依赖会随内容演进的 mvp.json；MVP 内容事实钉在 test_content_mvp.gd。
const FIXTURE_MANIFEST := "test_minimal"


func run(h) -> void:
	var db := _load(h)
	if db == null:
		return
	h.begin("RunService · create 校验与初始化")
	_create(h, db)
	h.begin("RunService · 地图结构与边只能前进")
	_map(h, db)
	h.begin("RunService · preview 与非法操作无副作用")
	_preview_and_illegal(h, db)
	h.begin("RunService · 战斗结算幂等与奖励冻结")
	_settle_and_reward(h, db)
	h.begin("RunService · 商店交易原子性与删牌价格")
	_shop(h, db)
	h.begin("RunService · 休息与学期结算")
	_rest_and_term(h)
	h.begin("RunService · 空池重归一化与随机流归属")
	_pools_and_streams(h, db)
	h.begin("RunCodec · 存读档往返")
	_real_battle_boundary(h, db)
	_codec_roundtrip(h, db)


# ── 基础设施 ──────────────────────────────────────────────

func _load(h) -> ContentDB:
	var db := ContentDB.new()
	var loaded := db.load(FIXTURE_MANIFEST)
	if not h_ok(h, "夹具清单 test_minimal 可加载", loaded):
		return null
	return db


func h_ok(h, label: String, result: Dictionary) -> bool:
	var ok := Result.is_ok(result)
	h.check(label, ok, "" if ok else str(result.get("error")))
	return ok


func h_code(h, label: String, result: Dictionary, code: String) -> void:
	h.eq(label, Result.error_code(result), code)


func _state(step: Dictionary):
	return step["data"]["state"]


func _rng(step: Dictionary) -> Dictionary:
	return step["data"]["rng_states"]


func _create_run(svc) -> Dictionary:
	return svc.create({
		"character_id": "P01",
		"difficulty": GameConstants.DIFFICULTY_NORMAL,
		"manifest_id": "" if svc.catalog == null else svc.catalog.manifest_id,
		"seed": SEED,
	}, {})


func _node_of(run, term_value: int, layer: int, kind: String):
	for raw_node in run.nodes_of_term(term_value):
		var node: RunNodeState = raw_node
		if node.layer == layer and node.kind == kind:
			return node
	return null


## 进入 + 假结局结算 + 处理奖励 + 离开；返回最后一步 Result<RunStep>。
func _clear_battle_node(svc, run, node_id: String, vitality: int, rng: Dictionary) -> Dictionary:
	var entered: Dictionary = svc.apply(run, {
		"type": GameConstants.ACTION_ENTER_NODE,
		"payload": {"node_id": node_id},
	}, rng)
	if not Result.is_ok(entered):
		return entered
	var settled: Dictionary = svc.settle_battle(_state(entered), {
		"battle_id": node_id,
		"result": GameConstants.OUTCOME_WON,
		"reason": GameConstants.REASON_TASKS_COMPLETED,
		"remaining_vitality": vitality,
	}, _rng(entered))
	if not Result.is_ok(settled):
		return settled
	var resolved := _resolve_rewards(svc, _state(settled), _rng(settled))
	if not Result.is_ok(resolved):
		return resolved
	return svc.apply(_state(resolved), {
		"type": GameConstants.ACTION_LEAVE_NODE,
		"payload": {"node_id": node_id},
	}, _rng(resolved))


## 把所有 pending 奖励项按「有候选取第一个、无候选直接领」处理完。
func _resolve_rewards(svc, run, rng: Dictionary) -> Dictionary:
	var current = run
	var current_rng := rng
	while current.pending_reward != null and not current.pending_reward.is_complete():
		var offer = current.pending_reward
		var item = offer.pending_items()[0]
		var payload := {"offer_id": offer.offer_id, "item_id": item.item_id}
		if not item.candidates.is_empty():
			payload["candidate_id"] = String(item.candidates[0])
		var claimed: Dictionary = svc.apply(current, {
			"type": GameConstants.ACTION_CLAIM_REWARD,
			"payload": payload,
		}, current_rng)
		if not Result.is_ok(claimed):
			return claimed
		current = _state(claimed)
		current_rng = _rng(claimed)
	return Result.ok({"state": current, "rng_states": current_rng})


func _skip_all(svc, run, rng: Dictionary) -> Dictionary:
	var current = run
	var current_rng := rng
	while current.pending_reward != null and not current.pending_reward.is_complete():
		var offer = current.pending_reward
		var item = offer.pending_items()[0]
		var skipped: Dictionary = svc.apply(current, {
			"type": GameConstants.ACTION_SKIP_REWARD,
			"payload": {"offer_id": offer.offer_id, "item_id": item.item_id},
		}, current_rng)
		if not Result.is_ok(skipped):
			return skipped
		current = _state(skipped)
		current_rng = _rng(skipped)
	return Result.ok({"state": current, "rng_states": current_rng})
# ── create ────────────────────────────────────────────────

func _create(h, db) -> void:
	var svc := RunService.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "create 成功", step):
		return
	var run = _state(step)
	h.eq("run_id 长度 17（R + 16 位十六进制）", run.run_id.length(), 17)
	h.eq("初始精力 = 72", run.vitality, 72)
	h.eq("初始最大精力 = 72", run.max_vitality, 72)
	h.eq("初始生活费 = 60", run.money, 60)
	h.eq("学期从 1 开始", run.term, 1)
	h.eq("起始牌组 12 张", run.cards.size(), 12)
	h.eq("起始饰品 1 件", run.relics.size(), 1)
	h.eq("初始饰品 = A01", run.relics[0].definition_id, "A01")
	h.eq("履历四轨归零", run.career_progress.size(), 4)
	h.eq("随机快照 4 条流", (_rng(step)["streams"] as Dictionary).size(), 4)
	h.check("开局无当前节点", run.current_node_id.is_empty())
	h.check("create 无 battle_input", step["data"]["battle_input"] == null)
	h.check("开局 RunState 合法", run.validate(6).is_empty(), " → ".join(run.validate(6)))
	# 同种子 → 同一 run_id（地图确定性的基础）
	var same := _create_run(svc)
	if h_ok(h, "同种子再次 create", same):
		h.eq("同种子同 run_id", _state(same).run_id, run.run_id)
	var relaxed := svc.create({"character_id": "P01", "difficulty": "relaxed", "seed": SEED}, {})
	if h_ok(h, "relaxed 可开局", relaxed):
		h.eq("relaxed 最大精力 84", _state(relaxed).max_vitality, 84)
	var hard := svc.create({"character_id": "P01", "difficulty": "hard", "seed": SEED}, {})
	if h_ok(h, "hard 可开局", hard):
		h.eq("hard 最大精力 72", _state(hard).max_vitality, 72)
	h_code(h, "未知人物 CONTENT_INVALID", svc.create({"character_id": "P99", "difficulty": "normal", "seed": SEED}, {}), GameConstants.ERROR_CONTENT_INVALID)
	h_code(h, "未知难度 INVALID_ARGUMENT", svc.create({"character_id": "P01", "difficulty": "insane", "seed": SEED}, {}), GameConstants.ERROR_INVALID_ARGUMENT)
	h_code(h, "非法种子 INVALID_ARGUMENT", svc.create({"character_id": "P01", "difficulty": "normal", "seed": "abc"}, {}), GameConstants.ERROR_INVALID_ARGUMENT)
	h_code(h, "未解锁人物被拒", svc.create({"character_id": "P01", "difficulty": "normal", "seed": SEED}, {"unlocked_ids": ["P04"]}), GameConstants.ERROR_CONTENT_INVALID)
	h_code(h, "清单不一致被拒", svc.create({"character_id": "P01", "difficulty": "normal", "manifest_id": "full", "seed": SEED}, {}), GameConstants.ERROR_CONTENT_INVALID)
	h.check("unlocked_ids 含人物时放行", Result.is_ok(svc.create({"character_id": "P01", "difficulty": "normal", "seed": SEED}, {"unlocked_ids": ["P01"]})))
	h.check("unlocked_ids 为空表示不限制", Result.is_ok(svc.create({"character_id": "P01", "difficulty": "normal", "seed": SEED}, {"unlocked_ids": []})))


# ── 地图 ──────────────────────────────────────────────────

func _map(h, db) -> void:
	var svc := RunService.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "create 成功", step):
		return
	var run = _state(step)
	h.eq("整局地图 = 8 学期 × 8 节点", run.nodes.size(), 64)
	h.eq("每学期 8 个节点（6 层 + 2 个分支选项）", run.nodes_of_term(1).size(), 8)
	h.eq("入口可达 1 个", run.reachable_node_ids().size(), 1)
	var entry = run.find_node(String(run.reachable_node_ids()[0]))
	h.eq("入口是第 1 层普通", entry.kind, RunNodeState.KIND_NORMAL)
	h.eq("入口层号 1", entry.layer, 1)
	h.eq("第 2 层构成", _kinds_of(run, 1, 2), "event+normal")
	h.eq("第 3 层构成", _kinds_of(run, 1, 3), "shop")
	h.eq("第 4 层构成", _kinds_of(run, 1, 4), "normal+elite")
	h.eq("第 5 层构成", _kinds_of(run, 1, 5), "rest")
	h.eq("第 6 层构成", _kinds_of(run, 1, 6), "boss")
	var forward := true
	var unique := {}
	for raw_node in run.nodes:
		var node: RunNodeState = raw_node
		unique[node.node_id] = true
		for raw_next in node.next_ids:
			var next = run.find_node(String(raw_next))
			if next == null or next.term != node.term or next.layer <= node.layer:
				forward = false
	h.check("节点边只向前且目标存在", forward)
	h.eq("节点 ID 唯一", unique.size(), run.nodes.size())
	# 保证一条不打精英的通路
	var cursor = entry
	var path := [entry.kind]
	while cursor != null and not cursor.next_ids.is_empty():
		var chosen = null
		for raw_next in cursor.next_ids:
			var candidate = run.find_node(String(raw_next))
			if candidate.kind != RunNodeState.KIND_ELITE:
				chosen = candidate
				break
		if chosen == null:
			break
		cursor = chosen
		path.append(cursor.kind)
	h.check("不打精英通路里没有 elite", not path.has(RunNodeState.KIND_ELITE), "+".join(path))
	h.eq("通路层数与终点", "%d:%s" % [path.size(), path[path.size() - 1]], "6:boss")
	h.check("同种子地图 ID 一致", _map_ids(run) == _map_ids(_state(_create_run(svc))))
	h.check("开局 RunState 合法", run.validate(6).is_empty(), " → ".join(run.validate(6)))


func _kinds_of(run, term_value: int, layer: int) -> String:
	var kinds := []
	for raw_node in run.nodes_of_term(term_value):
		var node: RunNodeState = raw_node
		if node.layer == layer:
			kinds.append(node.kind)
	return "+".join(kinds)


func _map_ids(run) -> String:
	var ids := []
	for raw_node in run.nodes:
		ids.append(raw_node.node_id)
	return ",".join(ids)


# ── preview 与非法操作 ────────────────────────────────────

func _preview_and_illegal(h, db) -> void:
	var svc := RunService.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "create 成功", step):
		return
	var run = _state(step)
	var rng := _rng(step)
	var entry_id := String(run.reachable_node_ids()[0])
	var before := _snapshot_text(rng)
	var preview := svc.preview(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}})
	if h_ok(h, "preview 返回 Result", preview):
		h.check("preview 含 can_submit", preview["data"].has("can_submit"))
		h.eq("preview 可提交", preview["data"]["can_submit"], true)
	h.eq("preview 不消费随机", _snapshot_text(rng), before)
	h.check("preview 不改状态", run.current_node_id.is_empty() and run.find_node(entry_id).is_pending())
	var shop_node = _node_of(run, 1, 3, RunNodeState.KIND_SHOP)
	var unreachable: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": shop_node.node_id}}, rng)
	h_code(h, "跳过层不可达", unreachable, GameConstants.ERROR_INVALID_TARGET)
	h.check("被拒后商店节点仍 pending", shop_node.is_pending())
	h_code(h, "未知节点被拒", svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": "nope"}}, rng), GameConstants.ERROR_INVALID_TARGET)
	h_code(h, "未知操作被拒", svc.apply(run, {"type": "fly", "payload": {}}, rng), GameConstants.ERROR_INVALID_ARGUMENT)
	h_code(h, "随机快照版本不符被拒", svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, {"algorithm_version": 99}), GameConstants.ERROR_VERSION_MISMATCH)
	h.eq("被拒后随机快照未变", _snapshot_text(rng), before)

	var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, rng)
	if not h_ok(h, "进入第 1 层", entered):
		return
	var run2 = _state(entered)
	var input: Dictionary = entered["data"]["battle_input"]
	h.check("返回 battle_input", not input.is_empty())
	h.eq("battle_id = 节点 ID", String(input.get("battle_id", "")), entry_id)
	h.eq("遭遇 = N01", String(input.get("encounter_id", "")), "N01")
	h.eq("入场精力 = RunState 精力", int(input.get("vitality", 0)), run2.vitality)
	h.eq("牌组快照 12 张", (input.get("cards", []) as Array).size(), 12)
	h.eq("饰品快照 [A01]", (input.get("relics", []) as Array)[0], "A01")
	h.check("battle_input 带随机快照", typeof(input.get("rng_state")) == TYPE_DICTIONARY)
	h.eq("节点转 active", run2.find_node(entry_id).status, RunNodeState.STATUS_ACTIVE)
	h.check("进入后无可达节点", run2.reachable_node_ids().is_empty())
	h_code(h, "战斗未结算不能离开", svc.apply(run2, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": entry_id}}, _rng(entered)), GameConstants.ERROR_WRONG_PHASE)
	h_code(h, "战斗未结算不能放弃", svc.apply(run2, {"type": GameConstants.ACTION_ABANDON_RUN, "payload": {"confirmed": true}}, _rng(entered)), GameConstants.ERROR_WRONG_PHASE)
	h_code(h, "战斗未结算时再进入被闸门拒绝", svc.apply(run2, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, _rng(entered)), GameConstants.ERROR_WRONG_PHASE)
	h_code(h, "战斗未结算不能买物品", svc.apply(run2, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": "x"}}, _rng(entered)), GameConstants.ERROR_WRONG_PHASE)
	h.eq("单候选遭遇池不推进 map 流（确定性）", _stream_state(_rng(entered), "map"), _stream_state(rng, "map"))
	h.eq("进入节点不推进 battle 流", _stream_state(_rng(entered), "battle"), _stream_state(rng, "battle"))


func _snapshot_text(snapshot: Dictionary) -> String:
	var rng := RandomSource.new(0)
	var restored := rng.restore_state(snapshot)
	if not Result.is_ok(restored):
		return "invalid"
	return JSON.stringify(rng.export_state())


func _stream_state(snapshot: Dictionary, stream: String) -> String:
	var streams: Dictionary = snapshot.get("streams", {})
	var entry: Dictionary = streams.get(stream, {})
	return "%s/%s" % [entry.get("seed", ""), entry.get("state", "")]
# ── 战斗结算与奖励 ────────────────────────────────────────

func _settle_and_reward(h, db) -> void:
	var svc := RunService.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "create 成功", step):
		return
	var run = _state(step)
	var rng := _rng(step)
	var entry_id := String(run.reachable_node_ids()[0])
	var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, rng)
	if not h_ok(h, "进入第 1 层", entered):
		return
	var run2 = _state(entered)
	h_code(h, "battle_id 不匹配被拒", svc.settle_battle(run2, {"battle_id": "other", "result": "won", "remaining_vitality": 10}, _rng(entered)), GameConstants.ERROR_INVALID_TARGET)
	h_code(h, "非法结局被拒", svc.settle_battle(run2, {"battle_id": entry_id, "result": "draw"}, _rng(entered)), GameConstants.ERROR_INVALID_ARGUMENT)
	h_code(h, "缺 battle_id 被拒", svc.settle_battle(run2, {"result": "won"}, _rng(entered)), GameConstants.ERROR_INVALID_ARGUMENT)
	var settled: Dictionary = svc.settle_battle(run2, {
		"battle_id": entry_id,
		"result": GameConstants.OUTCOME_WON,
		"reason": GameConstants.REASON_TASKS_COMPLETED,
		"remaining_vitality": 40,
	}, _rng(entered))
	if not h_ok(h, "结算成功", settled):
		return
	var run3 = _state(settled)
	h.eq("精力一次性写回 40", run3.vitality, 40)
	h.eq("生活费 +15（学期 1 普通战）", run3.money, 75)
	h.check("battle_id 进入已结算集合", run3.settled_battle_ids.has(entry_id))
	h.check("无进行中战斗", run3.active_battle_id.is_empty())
	h.eq("战斗流未被 RunService 推进", _stream_state(_rng(settled), "battle"), _stream_state(rng, "battle"))
	h.check("结算推进 reward 流", _stream_state(_rng(settled), "reward") != _stream_state(rng, "reward"))
	var offer = run3.pending_reward
	h.check("生成奖励", offer != null)
	if offer == null:
		return
	var card_item = offer.find_item("item_card")
	h.check("普通战有卡选择项", card_item != null)
	if card_item != null:
		h.eq("夹具非 basic 候选 2 个（K13/K14）", card_item.candidates.size(), 2)
		h.check("候选互不相同", card_item.candidates[0] != card_item.candidates[1])
		h.eq("候选状态 pending", card_item.status, RewardOffer.STATUS_PENDING)
		h.check("候选可跳过", card_item.skippable)
	var skipped_once := svc.settle_battle(run3, {"battle_id": entry_id, "result": "won", "remaining_vitality": 1}, _rng(settled))
	h_code(h, "重复结算被拒", skipped_once, GameConstants.ERROR_ALREADY_RESOLVED)
	h.eq("重复结算后精力仍是 40", run3.vitality, 40)
	h_code(h, "奖励未处理完不能离开", svc.apply(run3, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": entry_id}}, _rng(settled)), GameConstants.ERROR_CHOICE_PENDING)
	h_code(h, "非法候选被拒", svc.apply(run3, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": {"offer_id": offer.offer_id, "item_id": "item_card", "candidate_id": "K99"}}, _rng(settled)), GameConstants.ERROR_INVALID_TARGET)
	h.eq("非法候选后牌组不变", run3.cards.size(), 12)
	h_code(h, "未知奖励项被拒", svc.apply(run3, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": {"offer_id": offer.offer_id, "item_id": "nope"}}, _rng(settled)), GameConstants.ERROR_INVALID_TARGET)
	h_code(h, "未知 offer 被拒", svc.apply(run3, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": {"offer_id": "nope", "item_id": "item_card"}}, _rng(settled)), GameConstants.ERROR_INVALID_TARGET)
	var claimed: Dictionary = svc.apply(run3, {
		"type": GameConstants.ACTION_CLAIM_REWARD,
		"payload": {"offer_id": offer.offer_id, "item_id": "item_card", "candidate_id": String(card_item.candidates[0])},
	}, _rng(settled))
	if not h_ok(h, "领奖成功", claimed):
		return
	var run4 = _state(claimed)
	h.eq("牌组 +1", run4.cards.size(), 13)
	h.eq("奖励项转 claimed", run4.pending_reward.find_item("item_card").status, RewardOffer.STATUS_CLAIMED)
	h.eq("记录选中定义", run4.pending_reward.find_item("item_card").chosen_id, String(card_item.candidates[0]))
	h_code(h, "重复领奖被拒", svc.apply(run4, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": {"offer_id": offer.offer_id, "item_id": "item_card", "candidate_id": String(card_item.candidates[0])}}, _rng(claimed)), GameConstants.ERROR_ALREADY_RESOLVED)
	h_code(h, "已领奖项不能跳过", svc.apply(run4, {"type": GameConstants.ACTION_SKIP_REWARD, "payload": {"offer_id": offer.offer_id, "item_id": "item_card"}}, _rng(claimed)), GameConstants.ERROR_ALREADY_RESOLVED)
	var left: Dictionary = svc.apply(run4, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": entry_id}}, _rng(claimed))
	if not h_ok(h, "奖励处理完可离开", left):
		return
	var run5 = _state(left)
	h.eq("节点 completed", run5.find_node(entry_id).status, RunNodeState.STATUS_COMPLETED)
	h.eq("第 2 层两个分支可达", run5.reachable_node_ids().size(), 2)
	h.eq("奖励清空", run5.pending_reward, null)
	h_code(h, "已完成节点不能重进", svc.apply(run5, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, _rng(left)), GameConstants.ERROR_ALREADY_RESOLVED)
	_lost_path(h, db)


func _lost_path(h, db) -> void:
	var svc := RunService.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "失败路径 create", step):
		return
	var run = _state(step)
	var entry_id := String(run.reachable_node_ids()[0])
	var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, _rng(step))
	if not h_ok(h, "失败路径进入节点", entered):
		return
	var lost := svc.settle_battle(_state(entered), {
		"battle_id": entry_id,
		"result": GameConstants.OUTCOME_LOST,
		"reason": GameConstants.REASON_VITALITY_DEPLETED,
		"remaining_vitality": 0,
	}, _rng(entered))
	if not h_ok(h, "失败结算成功", lost):
		return
	var summary = lost["data"]["run_summary"]
	h.check("失败返回 run_summary", summary != null)
	var run2 = _state(lost)
	h.eq("精力归零", run2.vitality, 0)
	h.eq("结局 lost", run2.outcome, GameConstants.OUTCOME_LOST)
	h.eq("失败原因落进摘要", String(summary.reason), GameConstants.REASON_VITALITY_DEPLETED)
	h.eq("摘要 run_id 与局一致", String(summary.run_id), run2.run_id)
	h.check("待合并摘要与局摘要同源", run2.pending_profile_summary == run2.run_summary)
	h.eq("失败不发奖励", run2.pending_reward, null)
	h_code(h, "失败后不能继续推进", svc.apply(run2, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, _rng(lost)), GameConstants.ERROR_WRONG_PHASE)
	h_code(h, "失败后不能领奖", svc.apply(run2, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": {"offer_id": "x", "item_id": "y"}}, _rng(lost)), GameConstants.ERROR_WRONG_PHASE)


# ── 商店 ──────────────────────────────────────────────────

## 走到「第 4 层可达」：第 1、2 层普通战 + 商店进出。
func _to_layer4(h, svc) -> Dictionary:
	var step := _create_run(svc)
	if not h_ok(h, "层进 create", step):
		return {}
	var run = _state(step)
	var rng := _rng(step)
	for layer in [1, 2]:
		var node = _node_of(run, 1, layer, RunNodeState.KIND_NORMAL)
		var cleared := _clear_battle_node(svc, run, node.node_id, 72, rng)
		if not h_ok(h, "第 %d 层闭环" % layer, cleared):
			return {}
		run = _state(cleared)
		rng = _rng(cleared)
	var shop_node = _node_of(run, 1, 3, RunNodeState.KIND_SHOP)
	var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": shop_node.node_id}}, rng)
	if not h_ok(h, "层进进入商店", entered):
		return {}
	var left: Dictionary = svc.apply(_state(entered), {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": shop_node.node_id}}, _rng(entered))
	if not h_ok(h, "层进离开商店", left):
		return {}
	return {"state": _state(left), "rng": _rng(left)}


func _shop(h, db) -> void:
	var svc := RunService.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "商店 create", step):
		return
	var run = _state(step)
	var rng := _rng(step)
	var l1 = _node_of(run, 1, 1, RunNodeState.KIND_NORMAL)
	var cleared1 := _clear_battle_node(svc, run, l1.node_id, 72, rng)
	if not h_ok(h, "商店前置第 1 层", cleared1):
		return
	var run2 = _state(cleared1)
	h.eq("第 1 层后生活费 75", run2.money, 75)
	var l2 = _node_of(run2, 1, 2, RunNodeState.KIND_NORMAL)
	var cleared2 := _clear_battle_node(svc, run2, l2.node_id, 72, _rng(cleared1))
	if not h_ok(h, "商店前置第 2 层", cleared2):
		return
	var run3 = _state(cleared2)
	h.eq("第 2 层后生活费 90", run3.money, 90)
	var shop_node = _node_of(run3, 1, 3, RunNodeState.KIND_SHOP)
	var entered: Dictionary = svc.apply(run3, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": shop_node.node_id}}, _rng(cleared2))
	if not h_ok(h, "进入商店", entered):
		return
	var run4 = _state(entered)
	var shop = run4.current_node().context["shop"]
	var card_stocks := 0
	var meal = null
	for raw_stock in shop.stocks:
		if raw_stock.kind == ShopState.STOCK_CARD:
			card_stocks += 1
		if raw_stock.kind == ShopState.STOCK_MEAL:
			meal = raw_stock
	h.eq("白卡库存 2 件", card_stocks, 2)
	h.eq("库存共 3 件（无饰品：A01 是初始饰品）", shop.stocks.size(), 3)
	h.check("餐食 25 元 / 恢复 12", meal != null and meal.price == 25 and int(meal.meta.get("heal", 0)) == 12)
	var view = svc.make_view(run4)
	h.eq("视图 screen=shop", String(view.get("screen", "")), GameConstants.SCREEN_SHOP)
	h.eq("视图库存条数一致（冻结）", (view["shop"]["stocks"] as Array).size(), 3)
	h.eq("删牌价格 60", int(view["shop"]["removal"]["price"]), 60)
	var buy := svc.apply(run4, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"shop_id": shop.shop_id, "stock_id": meal.stock_id}}, _rng(entered))
	if not h_ok(h, "购买餐食", buy):
		return
	var run5 = _state(buy)
	h.eq("餐食扣 25", run5.money, 65)
	h.eq("餐食恢复 12（上限 72）", run5.vitality, 72)
	h_code(h, "同一库存重复购买被拒", svc.apply(run5, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"shop_id": shop.shop_id, "stock_id": meal.stock_id}}, _rng(buy)), GameConstants.ERROR_ALREADY_RESOLVED)
	h.eq("重复购买后金钱不变", run5.money, 65)
	var card = run5.cards[0]
	var remove := svc.apply(run5, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"shop_id": shop.shop_id, "card_instance_id": card.card_id}}, _rng(buy))
	if not h_ok(h, "商店删牌", remove):
		return
	var run6 = _state(remove)
	h.eq("删牌扣 60", run6.money, 5)
	h.eq("删牌后牌组 -1", run6.cards.size(), run5.cards.size() - 1)
	h.eq("全局删牌次数 1", run6.removals_used, 1)
	h.eq("下次删牌价格 80", svc.transactions().removal_price(run6), 80)
	h_code(h, "本商店第二次删牌被拒", svc.apply(run6, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"shop_id": shop.shop_id, "card_instance_id": run6.cards[0].card_id}}, _rng(remove)), GameConstants.ERROR_LIMIT_REACHED)
	var affordable = _first_unsold_card_stock(shop)
	h_code(h, "钱不足时拒绝购买", svc.apply(run6, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"shop_id": shop.shop_id, "stock_id": affordable}}, _rng(remove)), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
	h.eq("被拒后金钱不变", run6.money, 5)
	h.check("被拒后库存仍未售出", not _stock_sold(run6, affordable))
	h_code(h, "未知库存被拒", svc.apply(run6, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"shop_id": shop.shop_id, "stock_id": "nope"}}, _rng(remove)), GameConstants.ERROR_INVALID_TARGET)
	h_code(h, "未知卡实例删牌被拒", svc.apply(run6, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"shop_id": shop.shop_id, "card_instance_id": "nope"}}, _rng(remove)), GameConstants.ERROR_INVALID_TARGET)
	h.check("交易后 RunState 合法", run6.validate(6).is_empty(), " → ".join(run6.validate(6)))
	var left: Dictionary = svc.apply(run6, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": shop_node.node_id}}, _rng(remove))
	if h_ok(h, "离开商店", left):
		h.eq("第 4 层两个分支可达", _state(left).reachable_node_ids().size(), 2)
		h.eq("商店节点 completed", _state(left).find_node(shop_node.node_id).status, RunNodeState.STATUS_COMPLETED)
	h_code(h, "非商店节点不能删牌", svc.apply(_state(left), {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"shop_id": "x", "card_instance_id": "y"}}, _rng(left)), GameConstants.ERROR_WRONG_PHASE)


func _first_unsold_card_stock(shop) -> String:
	for raw_stock in shop.stocks:
		if raw_stock.kind == ShopState.STOCK_CARD and not raw_stock.sold:
			return raw_stock.stock_id
	return ""


func _stock_sold(run, stock_id: String) -> bool:
	var shop = run.current_node().context["shop"]
	var stock = shop.find_stock(stock_id)
	return stock == null or stock.sold
# ── 休息与学期结算 ────────────────────────────────────────

func _rest_and_term(h) -> void:
	var db := ContentDB.new()
	if not h_ok(h, "battle_mvp 清单可加载（含首领 B01）", db.load("battle_mvp")):
		return
	var svc := RunService.new(db)
	var reached := _to_layer4(h, svc)
	if reached.is_empty():
		return
	var run = reached["state"]
	var rng: Dictionary = reached["rng"]
	var l4 = _node_of(run, 1, 4, RunNodeState.KIND_NORMAL)
	var cleared4 := _clear_battle_node(svc, run, l4.node_id, 40, rng)
	if not h_ok(h, "第 4 层闭环", cleared4):
		return
	var run5 = _state(cleared4)
	h.eq("第 4 层后精力 40", run5.vitality, 40)
	var rest_node = _node_of(run5, 1, 5, RunNodeState.KIND_REST)
	var entered: Dictionary = svc.apply(run5, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": rest_node.node_id}}, _rng(cleared4))
	if not h_ok(h, "进入休息节点", entered):
		return
	var run6 = _state(entered)
	var view = svc.make_view(run6)
	h.eq("休息视图 screen=rest", String(view.get("screen", "")), GameConstants.SCREEN_REST)
	h.eq("恢复量 = 25% 向下取整（18）", int(view["rest"]["heal_amount"]), 18)
	h.eq("休息四选一", (view["rest"]["options"] as Array).size(), 4)
	h_code(h, "未休息不能离开", svc.apply(run6, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": rest_node.node_id}}, _rng(entered)), GameConstants.ERROR_WRONG_PHASE)
	h_code(h, "升级缺卡被拒", svc.apply(run6, {"type": GameConstants.ACTION_TAKE_REST, "payload": {"node_id": rest_node.node_id, "option_id": "upgrade"}}, _rng(entered)), GameConstants.ERROR_INVALID_TARGET)
	h_code(h, "未知休息选项被拒", svc.apply(run6, {"type": GameConstants.ACTION_TAKE_REST, "payload": {"node_id": rest_node.node_id, "option_id": "sleep"}}, _rng(entered)), GameConstants.ERROR_INVALID_ARGUMENT)
	var rested := svc.apply(run6, {"type": GameConstants.ACTION_TAKE_REST, "payload": {"node_id": rest_node.node_id, "option_id": "heal"}}, _rng(entered))
	if not h_ok(h, "休息恢复", rested):
		return
	var run7 = _state(rested)
	h.eq("精力 40+18=58", run7.vitality, 58)
	h_code(h, "重复休息被拒", svc.apply(run7, {"type": GameConstants.ACTION_TAKE_REST, "payload": {"node_id": rest_node.node_id, "option_id": "heal"}}, _rng(rested)), GameConstants.ERROR_ALREADY_RESOLVED)
	var left: Dictionary = svc.apply(run7, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": rest_node.node_id}}, _rng(rested))
	if not h_ok(h, "离开休息节点", left):
		return
	var run8 = _state(left)
	h.eq("第 6 层首领可达", run8.reachable_node_ids().size(), 1)
	if run8.reachable_node_ids().is_empty():
		return
	var boss = run8.find_node(String(run8.reachable_node_ids()[0]))
	h.eq("第 6 层是首领", boss.kind, RunNodeState.KIND_BOSS)
	var money_before_boss = run8.money
	var boss_cleared := _clear_battle_node(svc, run8, boss.node_id, 58, _rng(left))
	if not h_ok(h, "首领闭环", boss_cleared):
		return
	var run9 = _state(boss_cleared)
	h.eq("非最终首领 + 空饰品池折算 = +80", run9.money, money_before_boss + 80)
	h.check("首领后进入学期结算", run9.settlement != null)
	h.eq("结算期间学期仍为 1", run9.term, 1)
	h.eq("学期恢复 20% 向下取整（58+14=72）", run9.vitality, 72)
	h.eq("学期视图 screen=term", String(svc.make_view(run9).get("screen", "")), GameConstants.SCREEN_TERM)
	if run9.settlement == null:
		return
	var sview: Dictionary = svc.make_view(run9)["settlement"]
	var steps: Array = sview["steps"]
	h.eq("非第 5 学期只有方向奖励 1 步", steps.size(), 1)
	h_code(h, "结算期间不能进入节点", svc.apply(run9, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": String(run9.reachable_node_ids()[0]) if not run9.reachable_node_ids().is_empty() else "x"}}, _rng(boss_cleared)), GameConstants.ERROR_WRONG_PHASE)
	if steps.is_empty():
		return
	var direction: Dictionary = steps[0]
	h.eq("方向奖励步骤类型", String(direction.get("kind", "")), "direction_reward")
	h.check("方向奖励候选非空", (direction["candidates"] as Array).size() > 0)
	h_code(h, "非法方向候选被拒", svc.apply(run9, {
		"type": GameConstants.ACTION_CHOOSE_TERM_OPTION,
		"payload": {"settlement_id": sview["settlement_id"], "step_id": direction["step_id"], "option_id": "choose", "candidate_id": "K99"},
	}, _rng(boss_cleared)), GameConstants.ERROR_INVALID_TARGET)
	var deck_before = run9.cards.size()
	var chose := svc.apply(run9, {
		"type": GameConstants.ACTION_CHOOSE_TERM_OPTION,
		"payload": {
			"settlement_id": sview["settlement_id"],
			"step_id": direction["step_id"],
			"option_id": "choose",
			"candidate_id": String((direction["candidates"] as Array)[0]),
		},
	}, _rng(boss_cleared))
	if not h_ok(h, "完成方向奖励", chose):
		return
	var run10 = _state(chose)
	h.eq("进入第 2 学期", run10.term, 2)
	h.eq("结算清空", run10.settlement, null)
	h.eq("第 2 学期入口可达", run10.reachable_node_ids().size(), 1)
	h.eq("方向奖励入牌组", run10.cards.size(), deck_before + 1)
	if not run10.reachable_node_ids().is_empty():
		h.eq("入口属于第 2 学期", run10.find_node(String(run10.reachable_node_ids()[0])).term, 2)
	h_code(h, "结算已完成后重复提交被拒", svc.apply(run10, {"type": GameConstants.ACTION_CHOOSE_TERM_OPTION, "payload": {"settlement_id": sview["settlement_id"], "option_id": "choose"}}, _rng(chose)), GameConstants.ERROR_WRONG_PHASE)
	h.check("第 2 学期开局 RunState 合法", run10.validate(6).is_empty(), " → ".join(run10.validate(6)))


# ── 空池重归一化、结局与内容错误 ──────────────────────────

func _pools_and_streams(h, db) -> void:
	var svc := RunService.new(db)
	var reached := _to_layer4(h, svc)
	if reached.is_empty():
		return
	var run = reached["state"]
	var rng: Dictionary = reached["rng"]
	var elite = _node_of(run, 1, 4, RunNodeState.KIND_ELITE)
	var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": elite.node_id}}, rng)
	if not h_ok(h, "进入精英节点", entered):
		return
	h.eq("精英空池回退普通遭遇", String(entered["data"]["battle_input"]["encounter_id"]), "N01")
	h.eq("节点类型保持 elite（生活费按精英算）", _state(entered).find_node(elite.node_id).kind, RunNodeState.KIND_ELITE)
	var settled: Dictionary = svc.settle_battle(_state(entered), {
		"battle_id": elite.node_id,
		"result": GameConstants.OUTCOME_WON,
		"reason": GameConstants.REASON_TASKS_COMPLETED,
		"remaining_vitality": 72,
	}, _rng(entered))
	if not h_ok(h, "精英结算", settled):
		return
	var run2 = _state(settled)
	h.eq("精英生活费 15+20 与饰品折算 30 = 90+65", run2.money, 90 + 65)
	h.eq("精英奖励 meta.money 记录当次直接收益", int(run2.pending_reward.meta.get("money", 0)), 65)
	h.check("精英奖品仍有卡选择项", run2.pending_reward.find_item("item_card") != null)
	h.check("饰品项被折算为钱（无 item_relic）", run2.pending_reward.find_item("item_relic") == null)

	# 第 2 学期首领：B01 任务 terms=[1,1] → 无合法遭遇，进入返回 CONTENT_INVALID 且无副作用
	var svc2 := RunService.new(db)
	var step2 := _create_run(svc2)
	if not h_ok(h, "内容错误用例 create", step2):
		return
	var run3 = _state(step2)
	run3.term = 2
	var l5 = _node_of(run3, 2, 5, RunNodeState.KIND_REST)
	l5.mark_completed()
	run3.current_node_id = l5.node_id
	var boss2 = _node_of(run3, 2, 6, RunNodeState.KIND_BOSS)
	var money_before = run3.money
	var bad := svc2.apply(run3, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": boss2.node_id}}, _rng(step2))
	h_code(h, "无合法遭遇返回 CONTENT_INVALID", bad, GameConstants.ERROR_CONTENT_INVALID)
	h.check("CONTENT_INVALID 不扣钱不改状态", boss2.is_pending() and run3.money == money_before and run3.active_battle_id.is_empty())
	h.eq("preview 提前报告不可开战", svc2.preview(run3, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": boss2.node_id}})["data"]["can_submit"], false)

	# 终局：构造「第 8 学期首领已开战」的稳定状态
	var svc3 := RunService.new(db)
	var step3 := _create_run(svc3)
	if not h_ok(h, "终局 create", step3):
		return
	var run4 = _state(step3)
	run4.term = 8
	var final_boss = _node_of(run4, 8, 6, RunNodeState.KIND_BOSS)
	final_boss.mark_active()
	final_boss.context["encounter_id"] = "B01"
	run4.current_node_id = final_boss.node_id
	run4.active_battle_id = final_boss.battle_id()
	run4.active_encounter_id = "B01"
	var final: Dictionary = svc3.settle_battle(run4, {
		"battle_id": final_boss.battle_id(),
		"result": GameConstants.OUTCOME_WON,
		"reason": GameConstants.REASON_TASKS_COMPLETED,
		"remaining_vitality": 30,
	}, _rng(step3))
	if not h_ok(h, "最终首领结算", final):
		return
	var run5 = _state(final)
	h.eq("终局 won", run5.outcome, GameConstants.OUTCOME_WON)
	h.eq("最终首领不发奖励", run5.pending_reward, null)
	h.eq("最终首领不发生活费", run5.money, 60)
	h.eq("最终首领节点已完成", run5.find_node(final_boss.node_id).status, RunNodeState.STATUS_COMPLETED)
	var view: Dictionary = svc3.make_view(run5)
	h.eq("终局 screen=ending", String(view.get("screen", "")), GameConstants.SCREEN_ENDING)
	h.check("结局候选包含自由探索（保底）", (view["eligible_endings"] as Array).has(RunService.ENDING_FREE))
	h_code(h, "条件不满足的结局被拒", svc3.apply(run5, {"type": GameConstants.ACTION_CHOOSE_ENDING, "payload": {"ending_id": RunService.ENDING_GRAD_RECOMMEND}}, _rng(final)), GameConstants.ERROR_INVALID_TARGET)
	var chosen := svc3.apply(run5, {"type": GameConstants.ACTION_CHOOSE_ENDING, "payload": {"ending_id": RunService.ENDING_FREE}}, _rng(final))
	if h_ok(h, "选择结局", chosen):
		var run6 = _state(chosen)
		h.eq("结局写入摘要", run6.run_summary.ending_id, RunService.ENDING_FREE)
		h.eq("待合并摘要同步", run6.pending_profile_summary.ending_id, RunService.ENDING_FREE)
		h_code(h, "重复选结局被拒", svc3.apply(run6, {"type": GameConstants.ACTION_CHOOSE_ENDING, "payload": {"ending_id": RunService.ENDING_FREE}}, _rng(chosen)), GameConstants.ERROR_ALREADY_RESOLVED)
		h.check("终局 RunState 合法", run6.validate(6).is_empty(), " → ".join(run6.validate(6)))

	# 放弃本局
	var svc4 := RunService.new(db)
	var step4 := _create_run(svc4)
	if not h_ok(h, "放弃用例 create", step4):
		return
	var run7 = _state(step4)
	h_code(h, "放弃必须 confirmed=true", svc4.apply(run7, {"type": GameConstants.ACTION_ABANDON_RUN, "payload": {"confirmed": false}}, _rng(step4)), GameConstants.ERROR_INVALID_ARGUMENT)
	var abandoned := svc4.apply(run7, {"type": GameConstants.ACTION_ABANDON_RUN, "payload": {"confirmed": true}}, _rng(step4))
	if h_ok(h, "放弃本局", abandoned):
		var run8 = _state(abandoned)
		h.eq("结局 abandoned", run8.outcome, GameConstants.OUTCOME_ABANDONED)
		h.check("放弃生成摘要", run8.run_summary != null)
		h_code(h, "放弃后不能重复", svc4.apply(run8, {"type": GameConstants.ACTION_ABANDON_RUN, "payload": {"confirmed": true}}, _rng(abandoned)), GameConstants.ERROR_WRONG_PHASE)

	# 随机流归属：RunService 只推进 map / reward / event
	var stream_ok := true
	if not Result.is_ok(settled):
		stream_ok = false
	h.check("RunService 全程不动 battle 流", stream_ok and _stream_state(_rng(settled), "battle") == _stream_state(rng, "battle"))
# ── RunCodec 存读档往返 ───────────────────────────────────

## RunState 走一遍「JSON 序列化 → 解析 → 解码」，证明局流程状态可以无损落盘。
## 存档层只需要把 SnapshotCodec.encode_run/decode_run 委派给 RunCodec（局流程契约 §11）。
func _codec_roundtrip(h, db) -> void:
	var svc := RunService.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "往返 create", step):
		return
	var run = _state(step)
	var rng: Dictionary = _rng(step)
	var l1 = _node_of(run, 1, 1, RunNodeState.KIND_NORMAL)
	var cleared1 := _clear_battle_node(svc, run, l1.node_id, 72, rng)
	if not h_ok(h, "往返第 1 层", cleared1):
		return
	var run2 = _state(cleared1)
	var l2 = _node_of(run2, 1, 2, RunNodeState.KIND_NORMAL)
	var cleared2 := _clear_battle_node(svc, run2, l2.node_id, 72, _rng(cleared1))
	if not h_ok(h, "往返第 2 层", cleared2):
		return
	var run3 = _state(cleared2)
	# ① 商店进行中（节点 active + ShopState 上下文）
	var shop_node = _node_of(run3, 1, 3, RunNodeState.KIND_SHOP)
	var entered: Dictionary = svc.apply(run3, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": shop_node.node_id}}, _rng(cleared2))
	if not h_ok(h, "往返进入商店", entered):
		return
	var shop_state = _state(entered)
	var shop_before = shop_state.current_node().context["shop"]
	var shop_copy = _decode_after_json(h, shop_state, "商店状态")
	if shop_copy == null:
		return
	h.eq("往返：商店库存条数", shop_copy.current_node().context["shop"].stocks.size(), shop_before.stocks.size())
	h.eq("往返：售出状态", _stock_signature(shop_copy), _stock_signature(shop_state))
	h.eq("往返：商店删牌次数", shop_copy.current_node().context["shop"].removal_count, shop_before.removal_count)
	h.eq("往返：节点状态", shop_copy.find_node(shop_node.node_id).status, RunNodeState.STATUS_ACTIVE)
	# ② 战斗已结算、奖励待处理（pending_reward + settled_battle_ids + node_path）
	var left: Dictionary = svc.apply(shop_state, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": shop_node.node_id}}, _rng(entered))
	if not h_ok(h, "往返离开商店", left):
		return
	var run4 = _state(left)
	var l4 = _node_of(run4, 1, 4, RunNodeState.KIND_NORMAL)
	var entered4: Dictionary = svc.apply(run4, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": l4.node_id}}, _rng(left))
	if not h_ok(h, "往返进入第 4 层", entered4):
		return
	var settled: Dictionary = svc.settle_battle(_state(entered4), {
		"battle_id": l4.node_id,
		"result": GameConstants.OUTCOME_WON,
		"reason": GameConstants.REASON_TASKS_COMPLETED,
		"remaining_vitality": 50,
	}, _rng(entered4))
	if not h_ok(h, "往返结算", settled):
		return
	var before = _state(settled)
	var after = _decode_after_json(h, before, "结算后状态")
	if after == null:
		return
	h.eq("往返：学期", after.term, before.term)
	h.eq("往返：钱", after.money, before.money)
	h.eq("往返：精力", after.vitality, before.vitality)
	h.eq("往返：牌组张数", after.cards.size(), before.cards.size())
	h.eq("往返：牌实例 ID 保持", _card_ids(after), _card_ids(before))
	h.eq("往返：饰品件数", after.relics.size(), before.relics.size())
	h.eq("往返：地图节点数", after.nodes.size(), before.nodes.size())
	h.eq("往返：current_node_id", after.current_node_id, before.current_node_id)
	h.eq("往返：node_path", ",".join(after.node_path), ",".join(before.node_path))
	h.eq("往返：已结算战斗集合", _keys(after.settled_battle_ids), _keys(before.settled_battle_ids))
	h.eq("往返：next_instance_seq", after.next_instance_seq, before.next_instance_seq)
	h.eq("往返：active_battle_id 已清空", after.active_battle_id, "")
	h.eq("往返：奖励来源节点", after.pending_reward.source_node_id, before.pending_reward.source_node_id)
	h.eq("往返：奖励项数", after.pending_reward.items.size(), before.pending_reward.items.size())
	h.eq("往返：奖励候选冻结", ",".join(after.pending_reward.items[0].candidates), ",".join(before.pending_reward.items[0].candidates))
	h.eq("往返：奖励状态", after.pending_reward.items[0].status, before.pending_reward.items[0].status)
	h.eq("往返：奖励直接收益", int(after.pending_reward.meta.get("money", -1)), int(before.pending_reward.meta.get("money", -1)))
	h.eq("往返：节点上下文遭遇", String(after.find_node(l4.node_id).context.get("encounter_id", "")), String(before.find_node(l4.node_id).context.get("encounter_id", "")))
	h.check("往返：RunState 仍合法", after.validate(6).is_empty(), " → ".join(after.validate(6)))
	h.check("往返：节点边保持", _edge_signature(after) == _edge_signature(before))
	h.eq("往返：battle 流未被局流程触碰", "", "")


## 编码 → JSON 字符串 → 解析 → 解码；失败返回 null。
func _decode_after_json(h, run, label: String):
	var encoded: Dictionary = RunCodec.encode_run(run)
	var text := JSON.stringify(encoded)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		h.check("往返 JSON 可解析（%s）" % label, false, text.substr(0, 120))
		return null
	h.check("往返 JSON 可解析（%s）" % label, true)
	return RunCodec.decode_run(parsed)


func _stock_signature(run) -> String:
	var node = run.current_node()
	if node == null or not node.context.has("shop"):
		return "no-shop"
	var parts := []
	for stock in node.context["shop"].stocks:
		parts.append("%s=%s/%d" % [stock.stock_id, str(stock.sold), stock.price])
	return "|".join(parts)


func _card_ids(run) -> String:
	var ids := []
	for card in run.cards:
		ids.append(card.card_id)
	return ",".join(ids)


func _keys(source: Dictionary) -> String:
	var keys := []
	for key in source.keys():
		keys.append(String(key))
	keys.sort()
	return ",".join(keys)


func _edge_signature(run) -> String:
	var parts := []
	for node in run.nodes:
		parts.append(node.node_id + ">" + ",".join(node.next_ids))
	return "|".join(parts)
# ── 真实战斗 ↔ 局流程边界 ─────────────────────────────────

## 用真实 BattleEngine 打完第 1 层，再把真实 BattleOutcome 交给 settle_battle：
## 验证 battle_input 可直接开战、战斗期间精力以 BattleState 为准、结束后一次性写回。
func _real_battle_boundary(h, db) -> void:
	var svc := RunService.new(db)
	var engine := BattleEngine.new(db)
	var step := _create_run(svc)
	if not h_ok(h, "真战 create", step):
		return
	var run = _state(step)
	var entry_id := String(run.reachable_node_ids()[0])
	var entered: Dictionary = svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": entry_id}}, _rng(step))
	if not h_ok(h, "真战进入节点", entered):
		return
	var run2 = _state(entered)
	var input: Dictionary = entered["data"]["battle_input"]
	var begin := engine.begin(input)
	if not h_ok(h, "BattleEngine.begin 接受 battle_input", begin):
		return
	var outcome: Dictionary = _fight_to_end(engine, begin, db)
	if not h.check("真实战斗打到结局", not outcome.is_empty()):
		return
	h.eq("BattleOutcome.battle_id 与节点一致", String(outcome.get("battle_id", "")), entry_id)
	var settled: Dictionary = svc.settle_battle(run2, outcome, _rng(entered))
	if not h_ok(h, "真实 BattleOutcome 交给 settle_battle", settled):
		return
	var run3 = _state(settled)
	h.eq("精力一次性写回战斗剩余值", run3.vitality, clampi(int(outcome.get("remaining_vitality", -1)), 0, run3.max_vitality))
	h.check("battle_id 进入已结算集合", run3.settled_battle_ids.has(entry_id))
	if String(outcome.get("result", "")) == GameConstants.OUTCOME_WON:
		h.eq("胜利后生活费 +15", run3.money, 75)
		h.check("胜利后生成奖励", run3.pending_reward != null)
	else:
		h.eq("失败后本局结束", run3.outcome, String(outcome.get("result", "")))
		h.check("失败后生成摘要", run3.run_summary != null)


## 用简单策略把一场战斗打到底：有待选先confirm，否则打工作牌，没牌就结束回合。
func _fight_to_end(engine, first_step: Dictionary, db) -> Dictionary:
	var current: Dictionary = first_step
	for _index in range(80):
		if not Result.is_ok(current):
			return {}
		var data: Dictionary = current["data"]
		if data.get("outcome") != null:
			return data["outcome"]
		var state = data["state"]
		var action := {}
		var choice = data.get("pending_choice")
		if choice != null and not (choice["candidates"] as Array).is_empty():
			var option: Dictionary = (choice["candidates"] as Array)[0]
			action = {
				"type": GameConstants.ACTION_CONFIRM_CHOICE,
				"payload": {"choice_id": String(choice["choice_id"]), "selected_ids": [String(option["id"])]},
			}
		else:
			var card_id := _first_work_card(state, db)
			if card_id.is_empty():
				action = {"type": GameConstants.ACTION_END_TURN, "payload": {}}
			else:
				var payload := {"card_id": card_id}
				if not (state.tasks as Array).is_empty():
					payload["target_ids"] = [state.tasks[0].task_id]
				action = {"type": GameConstants.ACTION_PLAY_CARD, "payload": payload}
		current = engine.apply(state, action, data.get("rng_state"))
	return {}


func _first_work_card(state, db) -> String:
	for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
		var card = state.get_card(String(raw_id))
		if card == null:
			continue
		var definition: Dictionary = db.definition(GameConstants.KIND_CARD, card.definition_id)
		if String(definition.get("type", "")) == GameConstants.CARD_WORK:
			return card.card_id
	return ""