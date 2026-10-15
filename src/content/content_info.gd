class_name ContentInfo
extends RefCounted

var id: String
var content_version: String
var content_hash: String
var ruleset_id: String
var enabled: Dictionary


func _init(
	p_id: String = "",
	p_content_version: String = "",
	p_content_hash: String = "",
	p_ruleset_id: String = "",
	p_enabled: Dictionary = {}
) -> void:
	id = p_id
	content_version = p_content_version
	content_hash = p_content_hash
	ruleset_id = p_ruleset_id
	enabled = p_enabled.duplicate(true)


func copy() -> ContentInfo:
	return ContentInfo.new(id, content_version, content_hash, ruleset_id, enabled)
