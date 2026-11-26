class_name CardDisplayModel
extends RefCounted

## Presentation only: the face and price have already been resolved by the session.
const CATEGORY_NAMES := {"attack": "攻击", "defense": "防御", "utility": "功能", "field": "场地", "ability": "能力", "burden": "负担"}
# Lines the card frame already states elsewhere (header strip, requirement
# prefix, timing strip, bottom tag row) are skipped in the face body so the
# editable description text fits the small paper area.
const FACE_META_PREFIXES := [
	"使用条件：", "打出前提：", "持续能力：", "触发条件：", "触发时机：",
	"不可主动打出", "正常合作：", "支援：", "章节常驻：", "打出后按顺序结算：",
]
const FACE_TAG_LINES := ["消耗", "保留", "固有", "消耗：使用后本场战斗不再回到牌堆"]
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
	var summary := face_summary(face, id)
	return {"id": id, "name": UiStyle.label(id).split("：")[0], "cost": data.get("effective_cost", face.get("cost", "—")), "vitality_cost": data.get("effective_vitality_cost", face.get("vitality_cost", 0)), "kind": str(face.get("type", "work")), "category": category, "category_name": CATEGORY_NAMES[category], "rarity": str(face.get("rarity", "common")), "target": target, "timing": timing, "summary": summary, "requirements": UiStyle.describe_conditions(face.get("requirements", [])), "tags": " · ".join(tags), "detail": face.duplicate(true)}


## The face body reads the editable "说明" text (user edit, bundled default,
## source text) so a card reads the same on its face and in the inspector.
## Falls back to the generated short summary when nothing usable remains.
static func face_summary(face: Dictionary, definition_id: String = "") -> String:
	var detail := face
	if not definition_id.is_empty() and str(face.get("id", "")).is_empty():
		detail = face.duplicate(true)
		detail["id"] = definition_id
	var lines := _description_lines(detail)
	var kept: Array[String] = []
	for line in lines:
		var text := str(line).strip_edges()
		# Resident abilities keep their activation timing on the face; the rest
		# of the sentence (name stacking) is already in the detail text. Checked
		# before the meta filter, which would otherwise drop the whole line.
		if text.begins_with("持续能力："):
			kept.append(text.trim_prefix("持续能力：").split("；")[0])
			continue
		if text.is_empty() or FACE_TAG_LINES.has(text) or _is_meta_line(text):
			continue
		kept.append(str(line))
	if kept.is_empty():
		return UiContentText.card_summary(face)
	return "\n".join(kept)


static func _description_lines(face: Dictionary) -> PackedStringArray:
	var lines := UiContentText.describe_card(face).split("\n")
	if lines.is_empty():
		return lines
	var header := str(UiContentText.describe_card_default(face).split("\n")[0]).strip_edges()
	if str(lines[0]).strip_edges() == header:
		lines.remove_at(0)
	return lines


static func _is_meta_line(text: String) -> bool:
	for prefix in FACE_META_PREFIXES:
		if text.begins_with(prefix):
			return true
	return false


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
