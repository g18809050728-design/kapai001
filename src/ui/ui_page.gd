class_name UiPage
extends Control
##
## 页面基类（《界面层契约》§2）：页面只会做两件事——`render(view)` 把视图画出来、
## `build_action()` 把最近一次点击翻译成一条操作草稿。
##
## 硬约束（t2 验收项）：
##   · 页面不持有 RunState / RunService / SaveStore，也不自己判断规则；
##     节点可达性来自视图，按钮可用性来自 shell 用 RunService.preview 做的门控。
##   · 每个可点控件都有稳定 uid；测试与自动化只用 `press(uid)`，走真实 Button 的 pressed 信号。
##   · 被门控（preview.can_submit=false）或页面自己禁用的按钮，press() 直接返回 false——
##     与鼠标点 disabled 按钮一致，所以「界面不得自行放行非法操作」是可测的。
##

## 一次操作已就绪（shell 读 build_action() 后执行）。
signal action_requested()
## 页面内部选择变化（只改变草稿内容、不改视图），需要 shell 重新做一次门控。
signal view_changed()

## 本次渲染使用的视图（只读；RunView 或 shell 组装的页面视图）。
var view: Dictionary = {}
## shell 写入的全局提示（错误码 / 存档信息）；页面只负责显示。
var status_text: String = ""

var _pending_action: Dictionary = {}
var _buttons: Dictionary = {}   # uid -> Button
var _drafts: Dictionary = {}    # uid -> 操作草稿（只对规则操作登记）
var _reasons: Dictionary = {}   # uid -> 不可用原因
var _gating: Dictionary = {}
var _column: VBoxContainer = null
var _body: VBoxContainer = null
var _status_label: Label = null


# ── 生命周期 ──────────────────────────────────────────────

## shell 唯一的渲染入口；重复调用会清空并重建页面内容。
func render(p_view: Dictionary) -> void:
	view = p_view
	_pending_action = {}
	# 每次 render 都要重建按钮表：否则上一屏的按钮会留在表里，press() 可能点到已经不显示的旧按钮。
	_buttons = {}
	_reasons = {}
	_gating = {}
	if _column == null:
		_build_frame()
	_clear(_body)
	_render(_body)
	_status_label.text = status_text
	_status_label.visible = not status_text.is_empty()


## 最近一次点击产生的操作草稿；没有可提交操作时返回空字典。
func build_action() -> Dictionary:
	return _pending_action.duplicate(true)


## 查看当前草稿但不消费（测试与调试用）。
func peek_action() -> Dictionary:
	return _pending_action.duplicate(true)


# ── 门控接口（shell 调用）──────────────────────────────────

## 登记为规则操作的按钮 uid（升序，便于测试断言）。
func action_uids() -> Array:
	var uids := _drafts.keys()
	uids.sort()
	return uids


func action_draft(uid: String) -> Dictionary:
	var draft: Variant = _drafts.get(uid)
	# 草稿可以是字典，也可以是 Callable：依赖页面本地选择的按钮必须用 Callable，
	# 否则门控拿到的是渲染那一刻的旧选择。
	if draft is Callable:
		draft = (draft as Callable).call()
	if typeof(draft) != TYPE_DICTIONARY:
		return {}
	return (draft as Dictionary).duplicate(true)


## results: uid -> {"ok": bool, "reason": String}；只包含规则操作（ui.* 不在内）。
func apply_gating(results: Dictionary) -> void:
	_gating = results.duplicate(true)
	_apply_gating_now()


# ── 鼠标 / 自动化唯一入口 ─────────────────────────────────

## 模拟点击：按钮必须存在且未禁用（与鼠标行为一致），返回是否真的点了。
func press(uid: String) -> bool:
	var button: Button = _buttons.get(uid)
	if button == null or button.disabled:
		return false
	button.emit_signal("pressed")
	return true


func has_button(uid: String) -> bool:
	return _buttons.has(uid)


func button_disabled(uid: String) -> bool:
	var button: Button = _buttons.get(uid)
	return button == null or button.disabled


func button_reason(uid: String) -> String:
	return String(_reasons.get(uid, ""))


func button_text(uid: String) -> String:
	var button: Button = _buttons.get(uid)
	return "" if button == null else button.text


func button_uids() -> Array:
	var uids := _buttons.keys()
	uids.sort()
	return uids


# ── 子类钩子 ──────────────────────────────────────────────

## 子类实现：把视图画进 parent。父类已保证 parent 每次都是干净的。
func _render(parent: Node) -> void:
	pass


# ── 页面骨架与控件工厂 ────────────────────────────────────

func _build_frame() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 12)
	margin.add_child(_column)
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_status_label)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 8)
	_column.add_child(_body)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## 标题 + 副标题。
func _header(parent: Node, title: String, subtitle: String = "") -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 30)
	parent.add_child(label)
	if not subtitle.is_empty():
		var sub := Label.new()
		sub.text = subtitle
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(sub)


## 小节标题。
func _section(parent: Node, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)


func _text(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _hint(parent: Node, text: String) -> Label:
	var label := _text(parent, text)
	label.modulate = Color(0.75, 0.78, 0.85)
	return label


func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


func _spacer(parent: Node) -> void:
	parent.add_child(Control.new())


## 规则操作按钮：登记草稿，participate in shell 门控。
func _action_button(parent: Node, uid: String, text: String, draft: Variant) -> Button:
	var button := _new_button(parent, uid, text)
	if typeof(draft) == TYPE_DICTIONARY:
		_drafts[uid] = (draft as Dictionary).duplicate(true)
	elif draft is Callable:
		_drafts[uid] = draft
	else:
		_drafts[uid] = {}
	return button


## 本地按钮（选择 / 导航）：不登记草稿，shell 不会门控它。
func _local_button(parent: Node, uid: String, text: String) -> Button:
	return _new_button(parent, uid, text)


func _new_button(parent: Node, uid: String, text: String) -> Button:
	var button := Button.new()
	button.name = "Btn_" + uid.replace(":", "_").replace("|", "_").replace("<", "_").replace(">", "_")
	button.text = text
	button.set_meta("uid", uid)
	button.pressed.connect(_on_pressed.bind(uid))
	parent.add_child(button)
	_buttons[uid] = button
	return button


func _on_pressed(uid: String) -> void:
	_handle(uid)


## 子类实现：uid -> 行为（提交或本地选择）。
func _handle(uid: String) -> void:
	pass


# ── 内部 ──────────────────────────────────────────────────

func _submit(action: Dictionary) -> void:
	_pending_action = action.duplicate(true)
	action_requested.emit()


func _apply_gating_now() -> void:
	for raw_uid in _gating:
		var uid := String(raw_uid)
		var button: Button = _buttons.get(uid)
		if button == null:
			continue
		var info: Dictionary = _gating[raw_uid]
		var ok := bool(info.get("ok", true))
		var reason := String(info.get("reason", ""))
		_reasons[uid] = reason
		button.disabled = not ok
		button.tooltip_text = "" if ok else reason


## 页面内部选择变化后重建界面并请求 shell 重新门控。
func _selection_changed() -> void:
	render(view)
	view_changed.emit()


# ── 展示工具 ──────────────────────────────────────────────

## 节点类型 / 页面用的人类可读名字（纯展示，不参与规则）。
func kind_label(kind: String) -> String:
	match kind:
		"normal":
			return "普通作业"
		"elite":
			return "精英作业"
		"boss":
			return "期末大作业"
		"shop":
			return "商店"
		"event":
			return "突发事件"
		"rest":
			return "休息"
	return kind


## 字典 -> "k=v  k=v"（只用于把视图里的原始数据展示出来）。
func flatten(data: Dictionary) -> String:
	var keys := data.keys()
	keys.sort()
	var parts := []
	for raw_key in keys:
		var value: Variant = data[raw_key]
		if typeof(value) == TYPE_DICTIONARY:
			parts.append("%s={%s}" % [String(raw_key), flatten(value)])
		elif typeof(value) == TYPE_ARRAY:
			parts.append("%s=[%s]" % [String(raw_key), ",".join(_stringify_array(value))])
		else:
			parts.append("%s=%s" % [String(raw_key), str(value)])
	return "  ".join(parts)


func _stringify_array(raw: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for item in raw:
		out.append(str(item))
	return out