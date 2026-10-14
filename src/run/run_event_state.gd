class_name EventState
extends RefCounted
##
## 随机事件（《数据库与实体关系设计》§5 EventState；《统一设计文档》§10.2）。
##
## 事件定义 ID 在进入节点时抽取并写进 RunState.seen_event_ids —— 离开也记，同局同 ID 至多出现一次。
## 需要随机候选的选项（如「蓝卡三选一」）在进入时预抽并冻结在 frozen_candidates，
## 重新打开界面不重抽、不换候选。
##
## 事件定义 schema（内容侧按此写 data/definitions/events.json）：
##   {id, name_key, terms:[lo,hi] 或 allowed_terms:[...], once_per_run:true,
##    options:[{option_id, label_key, cost:{money,vitality}, effects:[...]}]}
## effects 支持的 op：gain_money / heal / lose_vitality / gain_card / gain_relic /
##                    upgrade_card / remove_card / career。未知 op 一律 CONTENT_INVALID。
## 每个事件都必须有一个「离开，无变化」的选项（effects 为空数组）。
##

const RunCopy := preload("res://src/run/run_copy.gd")

var event_instance_id: String = ""
var node_id: String = ""
var definition_id: String = ""
## 已结算选项 ID；空串表示尚未选择（「离开，无变化」也是一个显式选项）。
var resolved_option_id: String = ""
## option_id -> Array[String]：进入时冻结的候选（卡/饰品定义 ID）。
var frozen_candidates: Dictionary = {}


static func create(p_event_instance_id: String, p_node_id: String, p_definition_id: String) -> EventState:
	var instance: EventState = load("res://src/run/run_event_state.gd").new()
	instance.event_instance_id = p_event_instance_id
	instance.node_id = p_node_id
	instance.definition_id = p_definition_id
	return instance


func is_resolved() -> bool:
	return not resolved_option_id.is_empty()


func candidates_for(option_id: String) -> Array:
	var raw: Variant = frozen_candidates.get(option_id)
	if typeof(raw) != TYPE_ARRAY:
		return []
	return raw


func copy_for_write() -> EventState:
	var copied: EventState = create(event_instance_id, node_id, definition_id)
	copied.resolved_option_id = resolved_option_id
	copied.frozen_candidates = RunCopy.dictionary(frozen_candidates)
	return copied