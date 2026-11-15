class_name CharacterArt
extends RefCounted

## Selected presentation versions. Saves keep only the existing character ID.
const RIGS := {
	"P01": "res://assets/art/actor-lin-polish/P01/rig.json",
	"P02": "res://assets/art/actor-proportions/P02/rig.json",
	"P03": "res://assets/art/actor-rebuild/P03/rig.json",
	"P04": "res://assets/art/actor-motion/P04/rig.json",
}
const VERSIONS := {"P01": 12, "P02": 8, "P03": 10, "P04": 11}


static func rig_path(id: String) -> String:
	return str(RIGS.get(id, ""))


static func texture_path(id: String, portrait: bool = false) -> String:
	if not RIGS.has(id):
		return ""
	return "res://assets/art/characters/%s/%s.png" % [id, "portrait" if portrait else "neutral"]
