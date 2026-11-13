class_name CardDisplayModel
extends RefCounted

## Presentation only: the face and price have already been resolved by the session.
const CATEGORY_NAMES := {"attack": "攻击", "defense": "防御", "utility": "功能", "field": "场地", "ability": "能力", "burden": "负担"}
const ATTACK_OPS := ["complete", "status_complete", "remove_shield", "trigger_erosion", "trigger_induced", "paper_publish"]
const DEFENSE_OPS := ["relax", "heal", "partner_heal"]

static func from_card(data: Dictionary, definition_id: String = "") -> Dictionary:
	var face: Dictionary = data.get("face", data.get("effective_card", data))
	if face == null:
		face = {}
	var id := str(data.get("definition_id", face.get("id", definition_id)))
	if id.is_empty():
		id = definition_id
	var ability: Dictionary = face.get("ability", {})
	var category := _category(face)
	var flags: Dictionary = face.get("flags", {})
	var tags: PackedStringArray = []
	# The engine's effective face reads top-level exhaust; flags do not override it.
	if face.get("exhaust", false):
		tags.append("消耗")
	if flags.get("retain", face.get("retain", false)):
		tags.append("保留")
	if flags.get("innate", false):
		tags.append("固有")
	if int(face.get("upgrade_level", data.get("upgrade_level", 0))) > 0:
		tags.append("升级")
	var target := str({"self": "自身", "task": "单个任务", "all_tasks": "全部任务", "unit": "伙伴"}.get(str(face.get("target", "self")), "选择目标"))
	var timing := "即时"
	if not ability.is_empty():
		timing = "下回合起" if ability.get("activate","next_round") == "next_round" else "立即持续"
	elif not face.get("chapter", {}).is_empty():
		timing = "即时 / 章节"
	if face.get("exam_substituted", false) or face.get("exam_substitution_applied", false):
		timing += " · 考试"
	var summary := UiContentText.card_summary(face)
	if not face.get("pre_effects",[]).is_empty():
		summary = "先："+UiStyle.describe_effects(face.pre_effects)+"\n"+summary
	return {"id": id, "name": UiStyle.label(id).split("：")[0], "cost": data.get("effective_cost", face.get("cost", "—")), "vitality_cost": data.get("effective_vitality_cost", face.get("vitality_cost", 0)), "kind": str(face.get("type", "work")), "category": category, "category_name": CATEGORY_NAMES[category], "rarity": str(face.get("rarity", "common")), "target": target, "timing": timing, "summary": summary, "requirements": UiStyle.describe_conditions(face.get("requirements", [])), "tags": " · ".join(tags), "detail": face.duplicate(true)}


static func _category(face: Dictionary) -> String:
	# Classify the supplied face, never the card's name or the unreplaced exam definition.
	if face.get("type", "") == "burden":
		return "burden"
	var ops: Array[String] = []
	_collect_immediate_ops(face.get("pre_effects", []), ops)
	_collect_immediate_ops(face.get("effects", []), ops)
	if ops.has("establish_scene"):
		return "field"
	if not face.get("ability", {}).is_empty() or face.get("type", "") == "ability":
		return "ability"
	for op in ATTACK_OPS:
		if ops.has(op):
			return "attack"
	for op in DEFENSE_OPS:
		if ops.has(op):
			return "defense"
	return "attack" if face.get("type", "") == "work" else "utility"


static func _collect_immediate_ops(effects: Array, ops: Array[String]) -> void:
	for effect in effects:
		if effect is Dictionary:
			ops.append(str(effect.get("op", "")))
			# A conditional payment's continuation is still part of this play.
			# Resident chapter and ability trigger trees are intentionally excluded.
			_collect_immediate_ops(effect.get("then", []), ops)
