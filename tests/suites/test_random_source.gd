extends RefCounted
##
## RandomSource 验收：《接口文档》§6 + 《初步架构设计》§5.3（随机源按流分开、可保存、
## 预览与取消不消费随机）。
##

const RandomSource := preload("res://src/common/random_source.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")


func run(h) -> void:
	h.begin("RandomSource · 四条流与快照")
	_streams_are_isolated(h)
	_validation_does_not_advance(h)
	_same_seed_same_sequence(h)
	_shuffle_contract(h)
	_snapshot_round_trip(h)
	_snapshot_rejects_bad_input(h)


# ── 流隔离 ────────────────────────────────────────────────

func _streams_are_isolated(h) -> void:
	var rng := RandomSource.new(2026)
	for stream_id in RandomSource.STREAM_IDS:
		h.check("流可抽：%s" % stream_id, Result.is_ok(rng.draw_int(stream_id, 0, 9)))

	var before := rng.export_state()
	for _i in range(10):
		rng.draw_int(GameConstants.RNG_MAP, 0, 1000)
	var after := rng.export_state()

	h.check("map 流已推进",
		_text(after, GameConstants.RNG_MAP, "state") != _text(before, GameConstants.RNG_MAP, "state"))
	for other in [GameConstants.RNG_REWARD, GameConstants.RNG_EVENT, GameConstants.RNG_BATTLE]:
		h.eq("推进 map 不影响 %s" % other,
			_text(after, other, "state"), _text(before, other, "state"))
	h.eq("未知流名不被接受", rng.is_known_stream("global"), false)


# ── 非法调用不推进 ────────────────────────────────────────

func _validation_does_not_advance(h) -> void:
	var rng := RandomSource.new(7)
	var before := str(rng.export_state())

	var unknown: Dictionary = rng.draw_int("no_such_stream", 0, 9)
	h.check("未知流被拒绝", not Result.is_ok(unknown))
	h.eq("未知流错误码", Result.error_code(unknown), GameConstants.ERROR_INVALID_ARGUMENT)

	var bad_range: Dictionary = rng.draw_int(GameConstants.RNG_BATTLE, 5, 4)
	h.check("min>max 被拒绝", not Result.is_ok(bad_range))
	h.eq("min>max 错误码", Result.error_code(bad_range), GameConstants.ERROR_INVALID_ARGUMENT)

	h.eq("非法调用不推进任何流", str(rng.export_state()), before)

	var in_range := true
	var single_ok := true
	for _i in range(300):
		var drawn: Dictionary = rng.draw_int(GameConstants.RNG_EVENT, 3, 6)
		var value := int(drawn["data"])
		if value < 3 or value > 6:
			in_range = false
	h.check("draw_int 落在闭区间 [3,6] 内", in_range)
	h.eq("min==max 返回该值", int(rng.draw_int(GameConstants.RNG_EVENT, 4, 4)["data"]), 4)
	h.check("端点合法但空区间不代表不推进", single_ok)


# ── 可复现 ────────────────────────────────────────────────

func _same_seed_same_sequence(h) -> void:
	var a := RandomSource.new(20261013)
	var b := RandomSource.new(20261013)
	var same := true
	for _i in range(50):
		if int(a.draw_int(GameConstants.RNG_BATTLE, 0, 999999)["data"]) != int(b.draw_int(GameConstants.RNG_BATTLE, 0, 999999)["data"]):
			same = false
	h.check("同种子同序列（50 次抽值全等）", same)

	var c := RandomSource.new(20261014)
	var d := RandomSource.new(20261013)
	var differs := false
	for _i in range(50):
		if int(c.draw_int(GameConstants.RNG_BATTLE, 0, 999999)["data"]) != int(d.draw_int(GameConstants.RNG_BATTLE, 0, 999999)["data"]):
			differs = true
	h.check("不同种子序列不同", differs)


# ── 洗牌 ──────────────────────────────────────────────────

func _shuffle_contract(h) -> void:
	var ids := []
	for i in range(20):
		ids.append("K%02d" % (i + 1))
	var original: Array = ids.duplicate()

	var a := RandomSource.new(99)
	var b := RandomSource.new(99)
	var shuffled_a: Array = a.shuffle(GameConstants.RNG_REWARD, ids)["data"]
	var shuffled_b: Array = b.shuffle(GameConstants.RNG_REWARD, ids)["data"]

	h.eq("shuffle 不丢不重", _sorted(shuffled_a), _sorted(original))
	h.check("shuffle 不修改入参", ids == original)
	h.eq("同种子 shuffle 一致", shuffled_a, shuffled_b)

	var before := str(a.export_state())
	var again: Array = a.shuffle(GameConstants.RNG_REWARD, ids)["data"]
	h.check("shuffle 推进该流", str(a.export_state()) != before)
	h.check("连续两次 shuffle 结果不同", again != shuffled_a)

	var empty_ok: Dictionary = a.shuffle(GameConstants.RNG_REWARD, [])
	h.check("空数组可洗", Result.is_ok(empty_ok))
	h.eq("空数组洗出空数组", (empty_ok["data"] as Array).size(), 0)

	var other := RandomSource.new(5)
	var untouched := str(other.export_state())
	h.check("shuffle 未知流被拒绝", not Result.is_ok(other.shuffle("nope", ids)))
	h.eq("shuffle 未知流不推进", str(other.export_state()), untouched)


# ── 快照往返 ──────────────────────────────────────────────

func _snapshot_round_trip(h) -> void:
	# 2^53+1：一旦被当 JSON 数字解析就会丢精度，所以快照必须用十进制字符串
	var big_seed := 9007199254740993
	var source := RandomSource.new(big_seed)
	for _i in range(7):
		source.draw_int(GameConstants.RNG_MAP, 0, 1000)
		source.draw_int(GameConstants.RNG_EVENT, 0, 100)

	var snapshot := source.export_state()
	h.check("快照含算法版本", snapshot.has("algorithm_version"))
	h.eq("seed 是十进制字符串", typeof(_stream(snapshot, GameConstants.RNG_MAP, "seed")), TYPE_STRING)
	h.eq("state 是十进制字符串", typeof(_stream(snapshot, GameConstants.RNG_MAP, "state")), TYPE_STRING)
	h.eq("流数与常量一致", (snapshot["streams"] as Dictionary).size(), RandomSource.STREAM_IDS.size())

	var text := JSON.stringify(snapshot)
	var reparsed: Variant = JSON.parse_string(text)
	h.eq("快照可 JSON 文本往返", typeof(reparsed), TYPE_DICTIONARY)

	var restored := RandomSource.new(1)
	h.check("restore 成功", Result.is_ok(restored.restore_state(reparsed)))

	var expected := []
	var actual := []
	for _i in range(12):
		expected.append(int(source.draw_int(GameConstants.RNG_EVENT, 0, 999999)["data"]))
		actual.append(int(restored.draw_int(GameConstants.RNG_EVENT, 0, 999999)["data"]))
	h.eq("恢复后继续抽取结果一致（64 位种子无精度损失）", actual, expected)

	snapshot["streams"][GameConstants.RNG_MAP]["state"] = "1"
	h.check("export_state 返回副本", str(source.export_state()) != str(snapshot))


# ── 快照非法输入 ──────────────────────────────────────────

func _snapshot_rejects_bad_input(h) -> void:
	var source := RandomSource.new(42)
	source.draw_int(GameConstants.RNG_BATTLE, 0, 100)
	var before := str(source.export_state())

	var wrong_version := source.export_state()
	wrong_version["algorithm_version"] = RandomSource.ALGORITHM_VERSION + 1
	var version_result: Dictionary = source.restore_state(wrong_version)
	h.check("算法版本不兼容被拒绝", not Result.is_ok(version_result))
	h.eq("版本错误码", Result.error_code(version_result), GameConstants.ERROR_VERSION_MISMATCH)
	h.eq("版本拒绝后状态不变", str(source.export_state()), before)

	var missing := source.export_state()
	var missing_streams: Dictionary = missing["streams"]
	missing_streams.erase(GameConstants.RNG_BATTLE)
	h.check("缺流被拒绝", not Result.is_ok(source.restore_state(missing)))
	h.eq("缺流后状态不变", str(source.export_state()), before)

	var bad_int := source.export_state()
	bad_int["streams"][GameConstants.RNG_MAP]["seed"] = "abc"
	h.check("非法十进制被拒绝", not Result.is_ok(source.restore_state(bad_int)))
	h.eq("非法值后状态不变", str(source.export_state()), before)

	var no_streams := source.export_state()
	no_streams["streams"] = []
	h.check("streams 非对象被拒绝", not Result.is_ok(source.restore_state(no_streams)))
	h.eq("结构非法后状态不变", str(source.export_state()), before)


# ── 工具 ──────────────────────────────────────────────────

func _stream(snapshot: Dictionary, stream_id: String, key: String) -> Variant:
	var streams: Dictionary = snapshot.get("streams", {})
	var entry: Dictionary = streams.get(stream_id, {})
	return entry.get(key)


func _text(snapshot: Dictionary, stream_id: String, key: String) -> String:
	return str(_stream(snapshot, stream_id, key))


func _sorted(items: Array) -> Array:
	var copy := items.duplicate()
	copy.sort()
	return copy
