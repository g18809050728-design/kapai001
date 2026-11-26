class_name BattleStatusSlot
extends Button

const GLYPHS := {
	"inspiration": "focus",
	"work_boost": "work",
	"anxiety": "anxiety",
	"procrastination": "clock",
	"drowsiness": "drowsiness",
	"erosion": "erosion",
	"induced": "induced",
	"brittle": "brittle",
	"feebleness": "feebleness",
	"weakness": "weakness",
	"vulnerability": "vulnerability",
	"guard": "relax",
	"attack_immunity": "relax",
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
var entry: Dictionary
var _accent := Color("a8edd7")
var _counter_style: StyleBoxFlat


func configure(value: Dictionary, edge: float) -> void:
	entry = value
	text = str(entry.title)
	accessibility_description = str(entry.body)
	custom_minimum_size = Vector2(edge, edge)
	size = custom_minimum_size
	clip_text = true
	# The spoken name belongs to the button. The painted emblem carries the visual identity.
	for state in ["font_color", "font_hover_color", "font_hover_pressed_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	add_theme_constant_override("outline_size", 0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if entry.has("mechanic"):
		_accent = Color("ffdc8c")
	elif entry.get("negative", false):
		_accent = Color("ffc1a9")
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "disabled"]:
		add_theme_stylebox_override(state, empty)
	var highlight := UiStyle.surface(Color("263745"), Color("e2d4a5"), 8)
	highlight.shadow_size = 0
	highlight.set_content_margin_all(0)
	add_theme_stylebox_override("hover", highlight)
	var focus := highlight.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.set_border_width_all(2)
	add_theme_stylebox_override("focus", focus)
	_counter_style = UiStyle.surface(Color("10202b"), _accent.darkened(.3), 5)
	_counter_style.shadow_size = 0


func _draw() -> void:
	var center := size * .5
	var radius := size.y * .39
	draw_circle(center + Vector2(0, 2), radius, Color("0a131c"), true, -1, true)
	draw_circle(center, radius, Color("172936"), true, -1, true)
	draw_circle(center, radius, _accent.darkened(.25), false, maxf(1.3, size.y * .035), true)
	EffectGlyph.paint(self, str(entry.get("glyph", "status")), center, radius * .65, _accent)
	var count := str(entry.get("count", ""))
	if count.is_empty():
		return
	var font := get_theme_font("font")
	var font_size := roundi(size.y * .29 * minf(UiStyle.text_scale, 1.22))
	while font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 8 and font_size > 8:
		font_size -= 1
	var width := maxf(size.y * .32, font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 5)
	var height := font.get_height(font_size)
	var badge := Rect2(size.x - width - 1, size.y - height - 1, width, height)
	draw_style_box(_counter_style, badge)
	draw_string(font, badge.position + Vector2(0, font.get_ascent(font_size)), count, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, font_size, Color.WHITE)


static func entries(view: Dictionary, target: String, player: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rules: Dictionary = view.get("status_rules", {})
	if not player:
		for task: Dictionary in view.get("tasks", []):
			if str(task.get("task_id", "")) != target:
				continue
			result.append_array(TaskIntentText.mechanics(task, rules))
			break
	for status: Dictionary in view.get("statuses", []):
		if str(status.get("target_id", "")) != target or int(status.get("stacks", 0)) <= 0:
			continue
		var key := str(status.get("status_id", ""))
		var stacks := int(status.stacks)
		var body := UiGlossary.describe(key)
		var count_label := "当前层数"
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
				body = "每层使本任务的每段压力增加 %s 点。该状态在本任务实例内持续。" % rules.get(key, {}).get("pressure_per_stack", 1)
			"confusion":
				body = "每层使任务每次获得的屏障增加 %s，任务实例内持续。" % rules.get(key, {}).get("shield_per_stack", 1)
			"attack_immunity":
				body = "抵消下一张工作牌对本任务的直接完成量，同张牌多段只消耗一次；不免疫状态或自动输出。"
				count_label = "剩余次数"
			"compile":
				body = "历史兼容资源，当前角色不以编译作为核心机制。"
		result.append(
			{
				"key": key,
				"title": UiStyle.label(key),
				"count": stacks,
				"glyph": GLYPHS.get(key, "status"),
				"negative": key in NEGATIVES,
				"body": body + "\n%s %s" % [count_label, stacks]
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
