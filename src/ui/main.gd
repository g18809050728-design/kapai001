extends Control
##
## 游戏入口（P0 占位页已被真实页面层取代）。
##
## 只做三件事：载入内容库 -> 造 GameShell -> 把战斗界面接上去（如果工程里已经有）。
## 战斗界面探测顺序见 BATTLE_SCREEN_PATHS；找不到时 GameShell 自己会启用「开发回退（引擎代打）」，
## 所以局流程界面在战斗界面到位之前也能整局试玩。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const SaveStoreScript := preload("res://src/storage/save_store.gd")
const GameShellScript := preload("res://src/ui/game_shell.gd")

## 战斗界面候选路径（t1 交付后自动生效；不需要改本文件）。
const BATTLE_SCREEN_PATHS: Array[String] = [
	"res://src/ui/battle_screen.tscn",
	"res://src/ui/battle.tscn",
	"res://src/ui/page_battle.tscn",
]

var _shell = null
var _battle_screen = null


func _ready() -> void:
	var db := ContentDB.new()
	var info := db.load("")
	if not Result.is_ok(info):
		_show_error("内容库载入失败：%s" % str(info.get("error")))
		return
	var problems := db.validate()
	if not problems.is_empty():
		push_warning("[MAIN] 内容库校验问题 %d 条：%s" % [problems.size(), " → ".join(problems)])

	var store := SaveStoreScript.new(SaveStoreScript.DEFAULT_BASE_DIR, db)
	_shell = GameShellScript.new(db, store)
	_shell.name = "GameShell"
	add_child(_shell)
	_wire_battle_screen()
	_shell.start()
	print("[MAIN] 内容版本=%s 清单=%s 校验问题=%d" % [
		db.content_version,
		db.manifest_id,
		problems.size(),
	])


## 战斗界面（t1）如果已经存在，就直接交给 shell 接线（start_battle / battle_finished / action_applied）。
## 接线逻辑住在 GameShell.attach_battle_host 里：main.gd 与测试因此走同一条路径，
## 且引擎一定用「局的 catalog」新建（界面默认的 battle_mvp 清单没有出厂 mvp 的 K05/K10 等牌）。
func _wire_battle_screen() -> void:
	for raw_path in BATTLE_SCREEN_PATHS:
		var path := String(raw_path)
		if not ResourceLoader.exists(path):
			continue
		var packed: Resource = load(path)
		if packed == null:
			continue
		var instance: Variant = (packed as PackedScene).instantiate()
		if instance == null or not (instance is Control):
			continue
		_battle_screen = instance
		(_battle_screen as Control).visible = false
		(_battle_screen as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_battle_screen)
		if not _shell.attach_battle_host(_battle_screen):
			push_warning("[MAIN] 战斗界面接线失败：%s" % path)
			_battle_screen = null
			continue
		print("[MAIN] 战斗界面已接入：%s" % path)
		return
	push_warning("[MAIN] 未发现战斗界面，局流程将使用开发回退（引擎代打）结算战斗。")


func _show_error(text: String) -> void:
	var label := Label.new()
	label.name = "Error"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(label)
	push_error("[MAIN] " + text)