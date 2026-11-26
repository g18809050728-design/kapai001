class_name BattleStatusSlot
extends Button

const GLYPHS := {
	"inspiration": "focus",
	"work_boost": "work",
	"anxiety": "focus",
	"procrastination": "clock",
	"drowsiness": "clock",
	"erosion": "erosion",
	"induced": "induced",
	"brittle": "break",
	"feebleness": "relax",
	"weakness": "relax",
	"vulnerability": "work",
	"guard": "relax",
	"attack_immunity": "relax",
	"extra_requirements": "next",
	"brainstorm": "focus",
	"confusion": "status"
}
const NEGATIVES := [
	"anxiety",
	"procrastination",
	"drowsiness",
	"erosion",
	"induced",
	"brittle",
	"feebleness",
	"weakness",
	"vulnerability"
]
const SHORT_NAMES := {
	"work_boost": "增益",
	"pending_work_bonus": "准备",
	"discount": "减费",
	"extra_requirements": "要求",
	"attack_immunity": "免疫",
	"brainstorm": "脑汁",
	"publication_discount": "发表",
	"erosion_draws": "检索"
}
var entry: Dictionary


func configure(value: Dictionary, edge: float) -> void:
	entry = value
	text = str(entry.title)
	custom_minimum_size = Vector2(edge, edge)
	size = custom_minimum_size
	clip_text = true
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	add_theme_constant_override("outline_size", 0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := UiStyle.surface(
			Color("27333e") if entry.get("negative", false) else Color("233f3e"),
			Color("e9a092") if entry.get("negative", false) else Color("a5c9b1"),
			5
		)
		if state in ["hover", "focus"]:
			style.border_color = UiStyle.BRASS
			style.set_border_width_all(2)
		style.set_content_margin_all(0)
		add_theme_stylebox_override(state, style)


func _draw() -> void:
	# Draw the short identity and count ourselves; text remains the accessible full name.
	var font := get_theme_font("font")
	var ink := Color("ffe2d9") if entry.get("negative", false) else Color("e2f3df")
	EffectGlyph.paint(
		self,
		str(entry.get("glyph", "status")),
		Vector2(size.x * .5, size.y * .29),
		size.y * .19,
		ink
	)
	var caption := str(SHORT_NAMES.get(str(entry.key), str(entry.title).left(2)))
	var count := str(entry.get("count", ""))
	var font_size := roundi(size.y * .28 * UiStyle.text_scale)
	draw_string(
		font,
		Vector2(3, size.y * .84),
		caption,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x - 6,
		font_size,
		ink
	)
	if not count.is_empty():
		draw_string_outline(
			font,
			Vector2(1, size.y * .45),
			count,
			HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 4,
			font_size,
			4,
			Color("14212a")
		)
		draw_string(
			font,
			Vector2(1, size.y * .45),
			count,
			HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 4,
			font_size,
			Color.WHITE
		)


static func entries(view: Dictionary, target: String, player: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rules: Dictionary = view.get("status_rules", {})
	for status: Dictionary in view.get("statuses", []):
		if str(status.get("target_id", "")) != target or int(status.get("stacks", 0)) <= 0:
			continue
		var key := str(status.get("status_id", ""))
		var stacks := int(status.stacks)
		var body := UiGlossary.describe(key)
		match key:
			"inspiration":
				body = (
					"下一张工作牌第一段每层增加 %s 完成量；使用后消耗，轮末清除。"
					% rules.get(key, {}).get("completion_per_stack", 2)
				)
			"work_boost":
				body = "工作牌第一段每层增加 %s 完成量，本战持续。" % rules.get(key, {}).get("completion_per_stack", 1)
			"feebleness":
				body = (
					"每段压力先减去 层数×%s，最低0，再计算虚弱；任务实例内保持。" % rules.get(key, {}).get("pressure_flat", 1)
				)
			"brainstorm":
				body = "任务每层增加 %s 压力，任务实例内持续。" % rules.get(key, {}).get("pressure_per_stack", 1)
			"confusion":
				body = "每层使任务每次获得的屏障增加 %s，任务实例内持续。" % rules.get(key, {}).get("shield_per_stack", 1)
			"attack_immunity":
				body = "抵消下一张工作牌对本任务的直接完成量，同张牌多段只消耗一次；不免疫状态或自动输出。"
			"compile":
				body = "历史兼容资源，当前角色不以编译作为核心机制。"
		result.append(
			{
				"key": key,
				"title": UiStyle.label(key),
				"count": stacks,
				"glyph": GLYPHS.get(key, "status"),
				"negative": key in NEGATIVES,
				"body": body + "\n当前层数：%s" % stacks
			}
		)
	if not player:
		return result
	var v3: Dictionary = view.get("v3", {})
	var seen := {}
	for ability: Dictionary in v3.get("abilities", []):
		var id := str(ability.get("definition_id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		var active := int(view.get("round_index", 0)) >= int(ability.get("activate_round", 0))
		var lines: PackedStringArray = []
		for item: Dictionary in v3.get("abilities", []):
			if item.get("definition_id", "") == id:
				var condition := UiStyle.describe_condition(item.get("condition", {}))
				lines.append(
					(
						UiContentText.trigger_name(str(item.get("trigger", "")))
						+ "："
						+ UiStyle.describe_effects(item.get("effects", []))
						+ ("\n条件：" + condition if not condition.is_empty() else "")
					)
				)
				if not str(item.get("limit", "")).is_empty():
					lines.append("触发限制：" + str(item.limit))
				if not item.get("extra_effects", []).is_empty():
					lines.append("追加效果：" + UiStyle.describe_effects(item.extra_effects))
		result.append(
			{
				"key": "ability:" + id,
				"title": UiStyle.label(id),
				"count": "" if active else "待",
				"glyph": "focus",
				"body":
				("持续能力 · 已生效" if active else "持续能力 · 下回合生效") + "\n" + "\n".join(lines) + "\n同名不叠加。"
			}
		)
	var paper: Dictionary = v3.get("paper", {})
	for row in [
		[
			"pending_work_bonus",
			"工作准备",
			"下一张工作牌第一段主目标完成量增加；使用或回合结束清除。",
			int(v3.get("pending_work_bonus", 0)),
			"work"
		],
		[
			"paper_amplify",
			"增幅",
			UiGlossary.describe("paper_amplify"),
			int(paper.get("amplify", 0)),
			"book"
		],
		[
			"discount",
			"工作减费",
			(
				"下一张基础费用至少 %s 的工作牌减费；成功打出或回合结束清除。"
				% v3.get("pending_cost_discount", {}).get("min_base_cost", 0)
			),
			int(v3.get("pending_cost_discount", {}).get("amount", 0)),
			"focus"
		],
		[
			"publication_discount",
			"发表减费",
			"本回合解题发表费用减少，最低0。",
			int(v3.get("publication_discount", 0)),
			"book"
		],
		[
			"erosion_draws",
			"检索连锁",
			"本回合接下来实际抽到手的牌，各向所有任务施加1侵蚀；数字为剩余可触发抽牌数。",
			int(v3.get("turn", {}).get("erosion_draws", 0)),
			"search"
		]
	]:
		if row[3] > 0:
			result.append(
				{"key": row[0], "title": row[1], "count": row[3], "glyph": row[4], "body": row[2]}
			)
	return result
