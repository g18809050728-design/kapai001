class_name MobileScroll
extends RefCounted

class TapScroll:
	extends ScrollContainer

	const TAP_SLOP := 8.0
	var _press_origin := Vector2.ZERO
	var _tracking := false
	var _dragged := false

	func _ready() -> void:
		scroll_started.connect(func(): _dragged = true)

	func _input(event: InputEvent) -> void:
		if not UiStyle.web_touch or not is_visible_in_tree():
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_tracking = get_global_rect().has_point(event.position)
				_press_origin = event.position
				_dragged = false
			elif _tracking:
				_track(event.position)
				_dragged = _dragged or event.canceled
				_tracking = false
		elif _tracking and (event is InputEventScreenDrag or event is InputEventMouseMotion):
			_track(event.position)
		elif event.is_action_pressed("ui_accept"):
			_dragged = false

	func _track(point: Vector2) -> void:
		_dragged = _dragged or point.distance_squared_to(_press_origin) >= TAP_SLOP * TAP_SLOP

	func allows_activation() -> bool:
		return not UiStyle.web_touch or not _dragged


## Let Godot's native single-finger scroll reach its container from content and
## release-mode buttons. The engine supplies inertia and cancels button presses
## when a drag begins. Scrollbars and text caret/selection keep their own input.
static func prepare_node(node: Node) -> void:
	if node is ScrollContainer:
		node.scroll_deadzone = 9
		return
	if not node is Control or node is ScrollBar or node is LineEdit or node is TextEdit:
		return
	if node.mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	var parent := node.get_parent()
	while parent is Control:
		if parent is ScrollContainer:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
			return
		parent = parent.get_parent()
