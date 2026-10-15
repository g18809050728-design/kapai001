class_name RandomSnapshot
extends RefCounted

var algorithm_version: int
var streams: Dictionary


func _init(
	p_algorithm_version: int = GameConstants.RANDOM_ALGORITHM_VERSION, p_streams: Dictionary = {}
) -> void:
	algorithm_version = p_algorithm_version
	streams = p_streams.duplicate(true)


func copy() -> RandomSnapshot:
	return RandomSnapshot.new(algorithm_version, streams)


func to_dictionary() -> Dictionary:
	return {"algorithm_version": algorithm_version, "streams": streams.duplicate(true)}
