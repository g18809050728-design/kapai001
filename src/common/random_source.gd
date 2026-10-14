class_name RandomSource
extends RefCounted
##
## 可保存的随机源（《初步架构设计》§3、§5.3；《接口文档》§6）。
##
## 契约：
##   · 流限定 map / reward / event / battle，彼此独立。RunService 只推进 map/reward/event，
##     BattleEngine 只推进 battle（《接口文档》§5）。
##   · draw_int 的区间是闭区间；min > max 返回 INVALID_ARGUMENT 且不推进。
##   · 本类不提供任何隐式随机：预览与取消选择不消费随机，靠调用方不调用来实现
##     （《初步架构设计》§5.3）。
##   · 快照里 seed/state 用十进制字符串存（《数据库与实体关系设计》§7 规范化编码）。
##     Godot 的 JSON 把数字一律解析成 float，直接存 64 位整数会丢精度。
##   · 一次执行创建独立实例、restore 输入快照，成功随 SessionState 一起发布，
##     失败就丢弃（《类与方法设计》RandomSource 节）；不要做成全局共享随机源。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")

## 快照算法版本；不兼容时 restore_state 返回 VERSION_MISMATCH。
const ALGORITHM_VERSION: int = 1

const STREAM_IDS: Array[String] = [
	GameConstants.RNG_MAP,
	GameConstants.RNG_REWARD,
	GameConstants.RNG_EVENT,
	GameConstants.RNG_BATTLE,
]

var _streams: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


## 用同一个种子重建四条流。派生方式固定，保证「同种子同序列」。
func reseed(seed_value: int) -> void:
	_streams = {}
	var master := RandomNumberGenerator.new()
	master.seed = seed_value
	for stream_id in STREAM_IDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = master.randi()
		_streams[stream_id] = rng


func is_known_stream(stream: String) -> bool:
	return _streams.has(stream)


func stream_ids() -> Array[String]:
	return STREAM_IDS.duplicate()


# ── 抽取 ──────────────────────────────────────────────────

## Result<int>：闭区间 [min_value, max_value]，成功时推进该流。
func draw_int(stream: String, min_value: int, max_value: int) -> Dictionary:
	if not is_known_stream(stream):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.unknown_stream", {
			"stream": stream,
		})
	if min_value > max_value:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.invalid_range", {
			"min_value": min_value,
			"max_value": max_value,
		})
	var rng: RandomNumberGenerator = _streams[stream]
	return Result.ok(rng.randi_range(min_value, max_value))


## Result<Array>：返回新数组（不修改入参、不原地打乱），成功时推进该流。
func shuffle(stream: String, ids: Array) -> Dictionary:
	if not is_known_stream(stream):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.unknown_stream", {
			"stream": stream,
		})
	var rng: RandomNumberGenerator = _streams[stream]
	var shuffled := ids.duplicate()
	var index := shuffled.size() - 1
	while index > 0:
		var other := rng.randi_range(0, index)
		var carried: Variant = shuffled[index]
		shuffled[index] = shuffled[other]
		shuffled[other] = carried
		index -= 1
	return Result.ok(shuffled)


# ── 快照 ──────────────────────────────────────────────────

## RandomSnapshot 副本：算法版本 + 各流 seed/state（十进制字符串）。
func export_state() -> Dictionary:
	var streams := {}
	for stream_id in STREAM_IDS:
		var rng: RandomNumberGenerator = _streams[stream_id]
		streams[stream_id] = {
			"seed": str(rng.seed),
			"state": str(rng.state),
		}
	return {
		"algorithm_version": ALGORITHM_VERSION,
		"streams": streams,
	}


## Result：校验全部通过后才整体替换；任何一步失败都保持当前状态不变。
func restore_state(snapshot: Dictionary) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.snapshot_type", {})

	var raw_version: Variant = snapshot.get("algorithm_version")
	if not _is_number(raw_version):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.snapshot_version", {})
	if int(raw_version) != ALGORITHM_VERSION:
		return Result.fail(GameConstants.ERROR_VERSION_MISMATCH, "error.rng.algorithm_version", {
			"expected": ALGORITHM_VERSION,
			"got": int(raw_version),
		})

	var raw_streams: Variant = snapshot.get("streams")
	if typeof(raw_streams) != TYPE_DICTIONARY:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.snapshot_streams", {})
	var streams: Dictionary = raw_streams

	var rebuilt := {}
	for stream_id in STREAM_IDS:
		var raw_entry: Variant = streams.get(stream_id)
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.snapshot_missing_stream", {
				"stream": stream_id,
			})
		var entry: Dictionary = raw_entry
		var seed_text := _decimal_text(entry.get("seed"))
		var state_text := _decimal_text(entry.get("state"))
		if seed_text.is_empty() or state_text.is_empty():
			return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.rng.snapshot_bad_int", {
				"stream": stream_id,
			})
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_text.to_int()
		rng.state = state_text.to_int()
		rebuilt[stream_id] = rng

	_streams = rebuilt
	return Result.ok(null)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## 接受十进制字符串或整数；其它一律视为非法，避免把 float 精度损失悄悄带进来。
func _decimal_text(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		var text := String(value)
		if text.is_valid_int():
			return text
		return ""
	if typeof(value) == TYPE_INT:
		return str(value)
	if typeof(value) == TYPE_FLOAT:
		var as_float := float(value)
		if as_float == floor(as_float):
			return str(int(as_float))
	return ""
