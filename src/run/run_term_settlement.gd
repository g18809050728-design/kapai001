class_name TermSettlement
extends RefCounted
##
## 学期结算（《数据库与实体关系设计》§5 TermSettlement；《统一设计文档》§10）。
##
## steps 是有序子步骤，每个步骤有 pending/done 标记；恢复和履历不能重复发（幂等键 = step_id）。
## 步骤 kind：
##   direction_reward -> 方向奖励：白/蓝卡三选一（term 权重组 50/50 先抽品质），可跳过
##   career_track     -> 履历方向：第 5 学期开始前从科研/竞赛/实习选一，立即 +1，不可跳过
## 学期恢复（max_vitality × term_heal_percent 向下取整）在建立结算时直接写回，不是步骤。
##

const RunCopy := preload("res://src/run/run_copy.gd")

const STEP_PENDING := "pending"
const STEP_DONE := "done"
const STEP_IDS: Array[String] = [STEP_PENDING, STEP_DONE]

const STEP_DIRECTION_REWARD := "direction_reward"
const STEP_CAREER_TRACK := "career_track"
const STEP_KINDS: Array[String] = [STEP_DIRECTION_REWARD, STEP_CAREER_TRACK]

## 四条履历轨（《统一设计文档》§10.3）；第 5 学期选方向时只能从除升学外的三条里选。
const TRACK_RESEARCH := "research"
const TRACK_COMPETITION := "competition"
const TRACK_INTERNSHIP := "internship"
const TRACK_GRADUATE := "graduate"
const TRACKS: Array[String] = [TRACK_RESEARCH, TRACK_COMPETITION, TRACK_INTERNSHIP, TRACK_GRADUATE]
const TRACK_CHOICES: Array[String] = [TRACK_RESEARCH, TRACK_COMPETITION, TRACK_INTERNSHIP]


var settlement_id: String = ""
var term: int = 1
## 每项：{step_id, kind, status, candidates, skippable, chosen_id}
var steps: Array = []


static func create(p_settlement_id: String, p_term: int) -> TermSettlement:
	var settlement: TermSettlement = load("res://src/run/run_term_settlement.gd").new()
	settlement.settlement_id = p_settlement_id
	settlement.term = p_term
	return settlement


func add_step(p_step_id: String, p_kind: String, p_candidates: Array, p_skippable: bool) -> Dictionary:
	var step := {
		"step_id": p_step_id,
		"kind": p_kind,
		"status": STEP_PENDING,
		"candidates": p_candidates.duplicate(),
		"skippable": p_skippable,
		"chosen_id": "",
	}
	steps.append(step)
	return step


func find_step(step_id: String) -> Dictionary:
	if step_id.is_empty():
		return {}
	for raw_step in steps:
		var step: Dictionary = raw_step
		if String(step.get("step_id", "")) == step_id:
			return step
	return {}


## 当前待处理步骤；全部完成时返回 {}。
func current_step() -> Dictionary:
	for raw_step in steps:
		var step: Dictionary = raw_step
		if String(step.get("status", "")) == STEP_PENDING:
			return step
	return {}


func is_complete() -> bool:
	return current_step().is_empty()


func copy_for_write() -> TermSettlement:
	var copied: TermSettlement = create(settlement_id, term)
	for raw_step in steps:
		copied.steps.append(RunCopy.dictionary(raw_step))
	return copied