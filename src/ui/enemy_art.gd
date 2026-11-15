class_name EnemyArt
extends RefCounted

## Presentation IDs stay separate from encounter aliases and persisted state.
const INDEX = preload("res://assets/art/enemies/roster.json")


static func entries() -> Dictionary:
	return INDEX.data.get("enemies", {})


static func ids() -> PackedStringArray:
	return PackedStringArray(entries().keys())


static func rig_path(id: String) -> String:
	return str(entries().get(id, {}).get("rig", ""))


static func texture_path(id: String) -> String:
	return str(entries().get(id, {}).get("texture", ""))


static func version(id: String) -> int:
	return int(entries().get(id, {}).get("version", 0))
