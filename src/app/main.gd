extends Node

var _session: GameSession
var _shell: GameShell


func _ready() -> void:
	if OS.has_feature("web"):
		UiStyle.web_touch = bool(JavaScriptBridge.eval("window.kapaiMobile === true"))
		get_window().content_scale_factor = float(JavaScriptBridge.eval("window.kapaiRenderScale || 1"))
		if UiStyle.web_touch:
			get_tree().node_added.connect(MobileScroll.prepare_node)
	else:
		get_window().min_size = Vector2i(960, 640)
	var relic_pilot := "--relic-pilot" in OS.get_cmdline_user_args()
	_session = GameSession.new(null, Callable(), relic_pilot)
	if relic_pilot:
		TextOverrides.use_path("user://relic_pilot/text_overrides.json")
		get_window().title = "DDL 战争 · 饰品试玩（独立存档）"
	_session.name = "GameSession"
	add_child(_session)
	_shell = GameShell.new()
	_shell.session = _session
	_shell.name = "GameShell"
	if OS.has_feature("web") and not relic_pilot:
		_shell.web_account_state = "checking"
		_shell.web_team_tools_available = false
	add_child(_shell)
	if OS.has_feature("web") and not relic_pilot:
		var accounts := preload("res://src/app/web_accounts.gd").new()
		accounts.session = _session
		accounts.shell = _shell
		add_child(accounts)
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(
		func(): _shell.submit_action({"type": "ui.quit", "payload": {}})
	)
	print("Project bootstrap ready; Godot %s" % GameConstants.GODOT_VERSION)
