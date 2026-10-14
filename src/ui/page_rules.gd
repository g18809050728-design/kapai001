class_name UiRulesPage
extends "res://src/ui/ui_page.gd"
##
## 规则说明页（t4）：助教陈澄负责解释规则。这里放**局流程**的规则（地图/节点/战斗回合/待选/存档），
## 战斗界面的「规则」弹窗（t1 的 battle_rules_dialog.gd）负责战斗细节，两处入口都能到。
##
## 视图（shell 组装）：{sections: [{title, lines}], in_run: bool}
##

const TutorialText := preload("res://src/ui/tutorial_text.gd")


func _render(parent: Node) -> void:
	_header(parent, "规则说明 · %s" % TutorialText.GUIDE_RULES, "只看一类规则：局流程（战斗细节看战斗界面里的「规则」）")
	for raw_section in (view.get("sections", TutorialText.rule_sections()) as Array):
		var section: Dictionary = raw_section
		_section(parent, String(section.get("title", "")))
		for raw_line in (section.get("lines", []) as Array):
			_text(parent, "　· " + String(raw_line))
	_spacer(parent)
	var row := _row(parent)
	_action_button(row, "rules:tutorial", "看教学（%s）" % TutorialText.GUIDE_NODE, {"type": "ui.tutorial", "payload": {}})
	if bool(view.get("in_run", false)):
		_action_button(row, "rules:back", "回到局内", {"type": "ui.back", "payload": {}})
	else:
		_action_button(row, "rules:menu", "回主菜单", {"type": "ui.menu", "payload": {}})


func _handle(uid: String) -> void:
	match uid:
		"rules:tutorial":
			_submit({"type": "ui.tutorial", "payload": {}})
		"rules:back":
			_submit({"type": "ui.back", "payload": {}})
		"rules:menu":
			_submit({"type": "ui.menu", "payload": {}})