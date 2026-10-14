class_name DevAutoBattle
extends RefCounted
##
## 开发回退（《界面层契约》§9）：没有安装战斗界面时，用 BattleEngine 的三个公开入口
## （begin / preview / apply）把一场战斗打到结局，让局流程界面能整局试玩。
##
## 它不重算任何规则、也不碰 BattleState 内部字段：每个动作都先 preview 问「现在能不能提交」，
## 能提交才 apply。战斗界面（t1）上线后 shell 会优先把 battle_input 交给它，本回退自然失效。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")

## 单场战斗的动作上限，防止策略与规则不一致时死循环。
const MAX_STEPS := 800


## Result<BattleOutcome>；打不完返回 {}。
## on_step(state, rng_snapshot) 每步回调：交给调用方回填 session（settle_battle 要 battle_id，
## 存档/续战要同一份 battle 流随机快照）。
static func play(engine, first_step: Dictionary, on_step = null) -> Dictionary:
	var current: Dictionary = first_step
	var last_signature := ""
	var stalled := 0
	for _index in range(MAX_STEPS):
		if not Result.is_ok(current):
			return {}
		var data: Dictionary = current["data"]
		if data.get("outcome") != null:
			return data["outcome"]
		var signature := _signature(data)
		if signature == last_signature:
			stalled += 1
			if stalled > 40:
				return {}
		else:
			stalled = 0
			last_signature = signature
		var action := _next_action(engine, data)
		if action.is_empty():
			return {}
		current = engine.apply(data["state"], action, data.get("rng_state"))
		if Result.is_ok(current) and on_step != null and (on_step as Callable).is_valid():
			var stepped: Dictionary = current["data"]
			(on_step as Callable).call(stepped.get("state"), stepped.get("rng_state"))
	return {}


## 待选优先 confirm；否则挑一张现在能打的手牌（需要目标就补第一个任务）；都不能打就结束回合。
static func _next_action(engine, data: Dictionary) -> Dictionary:
	var state = data["state"]
	var choice: Variant = data.get("pending_choice")
	if choice != null:
		var candidates: Array = (choice as Dictionary).get("candidates", [])
		if candidates.is_empty():
			return {}
		var option: Dictionary = candidates[0]
		return {
			"type": GameConstants.ACTION_CONFIRM_CHOICE,
			"payload": {
				"choice_id": String((choice as Dictionary).get("choice_id", "")),
				"selected_ids": [String(option.get("id", ""))],
			},
		}
	for raw_card_id in state.card_ids_in(GameConstants.ZONE_HAND):
		var card_id := String(raw_card_id)
		var draft := {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": card_id}}
		var preview: Dictionary = engine.preview(state, draft)
		if not Result.is_ok(preview):
			continue
		var data_preview: Dictionary = preview["data"]
		if bool(data_preview.get("can_submit", false)):
			return draft
		if (data_preview.get("required_selections", []) as Array).has("target_ids"):
			var tasks: Array = state.tasks
			if tasks.is_empty():
				continue
			var task = tasks[0]
			var with_target := {
				"type": GameConstants.ACTION_PLAY_CARD,
				"payload": {"card_id": card_id, "target_ids": [String(task.task_id)]},
			}
			var second: Dictionary = engine.preview(state, with_target)
			if Result.is_ok(second) and bool((second["data"] as Dictionary).get("can_submit", false)):
				return with_target
	return {"type": GameConstants.ACTION_END_TURN, "payload": {}}


static func _signature(data: Dictionary) -> String:
	var state = data["state"]
	return "%s|%s|%s|%s" % [
		str(state.phase),
		str(state.round_index),
		str(state.card_ids_in(GameConstants.ZONE_HAND).size()),
		str(state.ddl),
	]