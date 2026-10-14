class_name UiMenuPage
extends "res://src/ui/ui_page.gd"
##
## 主菜单页（《界面层契约》§3）：新局 / 继续 / 设置 / 退出。
##
## 视图（shell 组装，非 RunView）：{has_save, save_meta, profile, status}
## 「继续」的可用性只看存档元数据（SaveStore.inspect 的结果），不读文件内容。
##

const GameConstants := preload("res://src/common/game_constants.gd")


func _render(parent: Node) -> void:
	_header(parent, "交大四年：DDL战争", "主菜单")
	var has_save := bool(view.get("has_save", false))
	var continue_button := _action_button(parent, "menu:continue", "继续上一局", {
		"type": "ui.continue",
		"payload": {},
	})
	continue_button.disabled = not has_save
	if not has_save:
		_hint(parent, "没有存档：先开新局，之后每一步都会自动存到 current_run。")
	else:
		_hint(parent, _save_text(view.get("save_meta")))
	_action_button(parent, "menu:new", "新的一局", {"type": "ui.new_run", "payload": {}})
	_action_button(parent, "menu:settings", "设置", {"type": "ui.settings", "payload": {}})
	_action_button(parent, "menu:tutorial", "教学 · 一学期怎么走", {"type": "ui.tutorial", "payload": {}})
	_action_button(parent, "menu:rules", "规则说明", {"type": "ui.rules", "payload": {}})
	_action_button(parent, "menu:quit", "退出游戏", {"type": "ui.quit", "payload": {}})
	_spacer(parent)
	var profile: Variant = view.get("profile")
	if typeof(profile) == TYPE_DICTIONARY:
		_section(parent, "人物档案")
		_text(parent, "已完成局数：%s" % str((profile as Dictionary).get("completed_runs", 0)))
		_text(parent, "解锁：%s" % _join(profile.get("unlocked_ids")))


func _save_text(raw_meta: Variant) -> String:
	if typeof(raw_meta) != TYPE_DICTIONARY:
		return "存档存在，但读不到元数据。"
	var meta: Dictionary = raw_meta
	var valid := bool(meta.get("valid", false))
	var text := "存档：revision=%s  内容版本=%s" % [
		str(meta.get("revision")),
		str(meta.get("content_version")),
	]
	if not valid:
		text += "  ⚠ 存档损坏，可尝试恢复备份"
	return text


func _join(raw: Variant) -> String:
	if typeof(raw) != TYPE_ARRAY:
		return "（空）"
	var items := []
	for item in (raw as Array):
		items.append(str(item))
	return "（空）" if items.is_empty() else ", ".join(items)


func _handle(uid: String) -> void:
	match uid:
		"menu:continue":
			_submit({"type": "ui.continue", "payload": {}})
		"menu:new":
			_submit({"type": "ui.new_run", "payload": {}})
		"menu:settings":
			_submit({"type": "ui.settings", "payload": {}})
		"menu:tutorial":
			_submit({"type": "ui.tutorial", "payload": {}})
		"menu:rules":
			_submit({"type": "ui.rules", "payload": {}})
		"menu:quit":
			_submit({"type": "ui.quit", "payload": {}})