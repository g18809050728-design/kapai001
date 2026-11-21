extends Node

var session: GameSession
var shell: GameShell
var _bridge: JavaScriptObject
var _callback: JavaScriptObject
var _account_id := ""


func _ready() -> void:
	_bridge = JavaScriptBridge.get_interface("kapaiAccounts")
	if _bridge == null:
		shell.set_web_account_state("bundle_unavailable", false, "", "账号界面加载失败，请刷新页面。")
		return
	_callback = JavaScriptBridge.create_callback(_browser_request)
	session.checkpoint_saved.connect(_checkpoint_saved)
	session.run_recorded.connect(_run_recorded)
	session.checkpoint_priority.connect(func(): _bridge.priority())
	shell.web_menu_visible.connect(_menu_visible)
	shell.web_privacy_requested.connect(func(): _bridge.openPrivacy())
	shell.web_account_requested.connect(func(registering): _bridge.openAccount(registering))
	shell.web_guest_requested.connect(func(): _bridge.enterGuest())
	shell.web_guest_logout_requested.connect(func(): _bridge.exitGuest())
	shell.web_play_requested.connect(func(developer_tools: bool): _bridge.confirmPlay(developer_tools))
	shell.web_section_requested.connect(func(section: String): _bridge.openSection(section))
	_bridge.connectGame(_callback)
	_menu_visible(true)


func _menu_visible(visible: bool) -> void:
	_bridge.showMenu(visible, session.get_view().run_id == null and not session.has_test_room())


func _checkpoint_saved(slot: String, snapshot: Dictionary) -> void:
	if not _account_id.is_empty():
		_bridge.saved(slot, SnapshotCodec.canonical_json(snapshot))


func _run_recorded(kind: String, run: Dictionary, detail: Dictionary) -> void:
	if not _account_id.is_empty():
		_bridge.record(kind, JSON.stringify(run), JSON.stringify(detail))


func _browser_request(args: Array) -> void:
	_bridge.reply(_dispatch(args))


func _dispatch(args: Array) -> Variant:
	if args.size() < 2:
		return ""
	var operation := str(args[0])
	var argument := str(args[1])
	match operation:
		"account_features":
			shell.web_privacy_available = argument == "true"
			shell.refresh()
		"account_menu":
			shell.set_web_account_state(argument, str(args[2]) == "true", str(args[3]), str(args[4]), str(args[5]) if args.size() > 5 else "")
		"play_confirmed":
			shell.resolve_web_play(argument == "true")
		"erase":
			if not _valid_account_id(argument) or argument != _account_id or session.get_view().run_id != null:
				return false
			var path := "user://accounts/%s" % argument
			return _erase_directory(path)
		"switch":
			if not argument.is_empty() and not _valid_account_id(argument):
				return false
			if not session.use_account_storage(argument):
				return false
			_account_id = argument
			shell.refresh()
			return true
		"read", "read_guest":
			if argument not in ["current_run", "profile"]:
				return ""
			var result := session.cloud_snapshot(argument, operation == "read_guest")
			if result.ok:
				return SnapshotCodec.canonical_json(result.data)
			return "" if result.error.code == GameConstants.ERROR_SAVE_NOT_FOUND else "invalid"
		"restore":
			if args.size() != 3:
				return "invalid"
			var snapshot: Variant = SnapshotCodec.normalize_numbers(JSON.parse_string(str(args[2])))
			if not snapshot is Dictionary or not SnapshotCodec.validate_structure(snapshot).is_empty() or not SnapshotCodec.checksum_matches(snapshot):
				return "invalid"
			var restored := session.restore_cloud_snapshot(argument, snapshot)
			if restored.ok:
				shell.refresh()
			return "ok" if restored.ok else str(restored.error.message_key)
		"merge_profile":
			if args.size() != 3:
				return ""
			return _merge_profile(argument, str(args[2]))
		"close_run":
			shell.submit_action({"type": "ui.close_account_run", "payload": {"return_to": argument}})
			return session.get_view().run_id == null
		"refresh":
			shell.refresh()
	return ""


func _valid_account_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$")
	return pattern.search(value) != null


func _merge_profile(left: String, right: String) -> String:
	var local := SnapshotCodec.decode_document(JSON.parse_string(left), "profile")
	var remote := SnapshotCodec.decode_document(JSON.parse_string(right), "profile")
	if not local.ok or not remote.ok:
		return ""
	var merged := ProfileMerge.combine(local.data.payload, remote.data.payload)
	if not merged.ok:
		return ""
	var snapshot := SnapshotCodec.encode_document("profile", merged.data)
	return SnapshotCodec.canonical_json(snapshot.data) if snapshot.ok else ""

func _erase_directory(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	for filename in DirAccess.get_files_at(path):
		if DirAccess.remove_absolute(path.path_join(filename)) != OK:
			return false
	for directory in DirAccess.get_directories_at(path):
		if not _erase_directory(path.path_join(directory)):
			return false
	return DirAccess.remove_absolute(path) == OK
