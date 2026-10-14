class_name SessionState
extends RefCounted
##
## 会话聚合（《数据库与实体关系设计》§5 局内实体）。
##
## SessionState 是唯一 revision 与唯一随机快照的持有者；整个 current_run 文件保存的就是它。
## RunState / BattleState 里不再存第二份随机状态（§7「外层 revision、run_id、random_state 各存一次」）。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const BattleStateScript := preload("res://src/battle/battle_state.gd")
const RandomSource := preload("res://src/common/random_source.gd")

var run_id: String = ""
## 本局所有写操作共用一个 revision；接受命令递增 1，拒绝/预览/保存不递增。
var revision: int = 0
var run: RunStateScript = null
## 至多一个活动战斗；无战斗时为 null。
var battle: BattleStateScript = null
## RandomSource.export_state() 的结果。
var random_snapshot: Dictionary = {}


func has_battle() -> bool:
	return battle != null


## 校验（《数据库与实体关系设计》§9 必查项中属于会话层的部分）。
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if run_id.is_empty():
		problems.append("run_id 为空")
	if revision < 0:
		problems.append("revision 不能为负：%d" % revision)

	if run == null:
		problems.append("缺少 RunState")
	elif run.run_id != run_id:
		problems.append("RunState.run_id（%s）与 SessionState.run_id（%s）不一致" % [run.run_id, run_id])

	if battle != null and battle.battle_id.is_empty():
		problems.append("活动战斗缺少 battle_id")

	# §9 必查：随机流缺失
	var raw_streams: Variant = random_snapshot.get("streams")
	if typeof(raw_streams) != TYPE_DICTIONARY:
		problems.append("随机快照缺少 streams")
	else:
		var streams: Dictionary = raw_streams
		for stream_id in RandomSource.STREAM_IDS:
			if not streams.has(stream_id):
				problems.append("随机快照缺少流：%s" % stream_id)

	# 整份快照必须能被 RandomSource 接受，否则读档必然失败
	var probe := RandomSource.new()
	var restored: Dictionary = probe.restore_state(random_snapshot)
	if not bool(restored.get("ok", false)):
		problems.append("随机快照无法恢复：%s" % str(restored.get("error")))
	return problems
