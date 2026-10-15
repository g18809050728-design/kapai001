class_name RandomSource
extends RefCounted

const STREAMS := ["map", "reward", "event", "battle"]
const SNAPSHOT_FIELDS := ["algorithm_version", "streams"]
const STREAM_FIELDS := ["seed", "state"]

var _generators: Dictionary = {}


func _init(seed: String = "0") -> void:
	for stream in STREAMS:
		var generator := RandomNumberGenerator.new()
		generator.seed = _derive_seed(seed, stream)
		_generators[stream] = generator


func draw_int(stream: String, minimum: int, maximum: int) -> GameResult:
	if not _generators.has(stream):
		return _random_error("random.stream.unknown", {"stream": stream})
	if minimum > maximum:
		return _random_error("random.range.invalid", {"minimum": minimum, "maximum": maximum})
	if minimum == maximum:
		return GameResult.success(minimum)
	return GameResult.success(_generators[stream].randi_range(minimum, maximum))


func shuffle(stream: String, ids: Array[String]) -> GameResult:
	if not _generators.has(stream):
		return _random_error("random.stream.unknown", {"stream": stream})
	var result := ids.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var chosen: int = _generators[stream].randi_range(0, index)
		var current: String = result[index]
		result[index] = result[chosen]
		result[chosen] = current
	return GameResult.success(result)


func export_state() -> RandomSnapshot:
	var streams := {}
	for stream in STREAMS:
		var generator: RandomNumberGenerator = _generators[stream]
		streams[stream] = {"seed": str(generator.seed), "state": str(generator.state)}
	return RandomSnapshot.new(GameConstants.RANDOM_ALGORITHM_VERSION, streams)


func restore_state(snapshot: Variant) -> GameResult:
	var data: Variant = snapshot.to_dictionary() if snapshot is RandomSnapshot else snapshot
	var issues: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		return _random_error("random.snapshot.invalid", {"issues": ["snapshot must be an object"]})
	_validate_keys(data, SNAPSHOT_FIELDS, ["algorithm_version", "streams"], "snapshot", issues)
	if typeof(data.get("algorithm_version")) != TYPE_INT:
		issues.append("snapshot.algorithm_version must be an integer")
	elif data.algorithm_version != GameConstants.RANDOM_ALGORITHM_VERSION:
		issues.append("snapshot.algorithm_version is unsupported")
	if typeof(data.get("streams")) != TYPE_DICTIONARY:
		issues.append("snapshot.streams must be an object")
	else:
		for stream in data.streams:
			if not STREAMS.has(stream):
				issues.append("snapshot.streams.%s is unknown" % stream)
		for stream in STREAMS:
			if not data.streams.has(stream):
				issues.append("snapshot.streams.%s is required" % stream)
				continue
			var entry: Variant = data.streams[stream]
			_validate_keys(
				entry, STREAM_FIELDS, STREAM_FIELDS, "snapshot.streams.%s" % stream, issues
			)
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			for field in STREAM_FIELDS:
				if typeof(entry.get(field)) != TYPE_STRING or not _is_int64_decimal(entry[field]):
					issues.append(
						"snapshot.streams.%s.%s must be a decimal 64-bit string" % [stream, field]
					)
	if not issues.is_empty():
		return _random_error("random.snapshot.invalid", {"issues": issues})
	var next_generators := {}
	for stream in STREAMS:
		var entry: Dictionary = data.streams[stream]
		var generator := RandomNumberGenerator.new()
		generator.seed = int(entry.seed)
		generator.state = int(entry.state)
		next_generators[stream] = generator
	_generators = next_generators
	return GameResult.success(true)


func _is_int64_decimal(value: String) -> bool:
	if not value.is_valid_int():
		return false
	return str(value.to_int()) == value


func _derive_seed(seed: String, stream: String) -> int:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(
		(
			("godot-rng-%d:%s:%s" % [GameConstants.RANDOM_ALGORITHM_VERSION, seed, stream])
			. to_utf8_buffer()
		)
	)
	var digest := context.finish()
	var value: int = 0
	for index in range(8):
		value = (value << 8) | digest[index]
	return value


func _validate_keys(
	value: Variant, allowed: Array, required: Array, location: String, issues: Array[String]
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		issues.append("%s must be an object" % location)
		return
	for key in required:
		if not value.has(key):
			issues.append("%s.%s is required" % [location, key])
	for key in value:
		if not allowed.has(key):
			issues.append("%s.%s is unknown" % [location, key])


func _random_error(message_key: String, details: Dictionary) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, message_key, details)
	)
