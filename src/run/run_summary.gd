class_name RunSummary
extends RefCounted
##
## 局摘要（《数据库与实体关系设计》§5 RunSummary；《接口文档》§5/§7）。
##
## 与 run_id 一一对应；结局写入 Profile 时以 run_id 为幂等键（《数据库与实体关系设计》§8 三步提交）。
## 生成后只有 ending_id 允许在 choose_ending 时补一次，其余字段不再改写。
##

var run_id: String = ""
## won / lost / abandoned
var result: String = ""
var reason: String = ""
## 通关后由 choose_ending 写入；失败或放弃时为空串
var ending_id: String = ""
var character_id: String = ""
var difficulty: String = ""
var term: int = 0
## 结束时统计（学期、钱、精力、牌组、饰品、已结算战斗、节点）
var stats: Dictionary = {}
## 传承解锁候选（由 Session/Profile 层按 run_id 幂等合并）
var unlocked_ids: Array = []


static func create(p_run_id: String, p_result: String, p_reason: String, p_character_id: String, p_difficulty: String, p_term: int) -> RunSummary:
	var summary: RunSummary = load("res://src/run/run_summary.gd").new()
	summary.run_id = p_run_id
	summary.result = p_result
	summary.reason = p_reason
	summary.character_id = p_character_id
	summary.difficulty = p_difficulty
	summary.term = p_term
	return summary


func copy_for_write() -> RunSummary:
	var copied: RunSummary = load("res://src/run/run_summary.gd").new()
	copied.run_id = run_id
	copied.result = result
	copied.reason = reason
	copied.ending_id = ending_id
	copied.character_id = character_id
	copied.difficulty = difficulty
	copied.term = term
	copied.stats = stats.duplicate(true)
	copied.unlocked_ids = unlocked_ids.duplicate()
	return copied