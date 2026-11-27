class_name MobileScroll
extends RefCounted

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
