class_name UiTutorialPage
extends "res://src/ui/ui_page.gd"
##
## 教学页（t4）：辅导员周岚带玩家走一遍一学期闭环的每一步。
##
## 视图（shell 组装）：{sections: [{id,title,guide,line,steps}], highlight: [章节 id], in_run: bool}
## highlight 由 shell 按「当前在哪一屏 / 当前节点 kind」决定；页面只负责呈现，不判断规则。
##

const TutorialText := preload("res://src/ui/tutorial_text.gd")


func _render(parent: Node) -> void:
	_header(parent, "教学 · %s" % TutorialText.GUIDE_NODE, "一学期怎么走：八小节，按顺序看一遍就能上手")
	_hint(parent, "教学只解释界面怎么用；具体数值以局内视图为准。")
	var highlight: Array = view.get("highlight", [])
	var sections: Array = view.get("sections", TutorialText.sections())
	var ordered := []
	for raw_section in sections:
		var section: Dictionary = raw_section
		if highlight.has(String(section.get("id", ""))):
			ordered.append(section)
	for raw_section in sections:
		var section2: Dictionary = raw_section
		if not highlight.has(String(section2.get("id", ""))):
			ordered.append(section2)
	for raw_section in ordered:
		var section: Dictionary = raw_section
		var section_id := String(section.get("id", ""))
		var title := String(section.get("title", section_id))
		if highlight.has(section_id):
			title = "★ " + title + "（当前这一段）"
		_section(parent, title)
		_text(parent, "%s：%s" % [String(section.get("guide", TutorialText.GUIDE_NODE)), String(section.get("line", ""))])
		for raw_step in (section.get("steps", []) as Array):
			_text(parent, "　· " + String(raw_step))
	_spacer(parent)
	var row := _row(parent)
	_action_button(row, "tutorial:rules", "看规则说明（%s）" % TutorialText.GUIDE_RULES, {"type": "ui.rules", "payload": {}})
	if bool(view.get("in_run", false)):
		_action_button(row, "tutorial:back", "回到局内", {"type": "ui.back", "payload": {}})
	else:
		_action_button(row, "tutorial:menu", "回主菜单", {"type": "ui.menu", "payload": {}})


func _handle(uid: String) -> void:
	match uid:
		"tutorial:rules":
			_submit({"type": "ui.rules", "payload": {}})
		"tutorial:back":
			_submit({"type": "ui.back", "payload": {}})
		"tutorial:menu":
			_submit({"type": "ui.menu", "payload": {}})