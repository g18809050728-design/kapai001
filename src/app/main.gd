extends Node

var _session: GameSession
var _shell: GameShell


func _ready() -> void:
	get_window().min_size = Vector2i(960, 640)
	_session = GameSession.new()
	_session.name = "GameSession"
	add_child(_session)
	_shell = GameShell.new()
	_shell.session = _session
	_shell.name = "GameShell"
	add_child(_shell)
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(
		func(): _shell.submit_action({"type": "ui.quit", "payload": {}})
	)
	print("Project bootstrap ready; Godot %s" % GameConstants.GODOT_VERSION)
