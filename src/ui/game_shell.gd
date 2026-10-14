class_name GameShell
extends Control
##
## 局流程壳（《界面层契约》§1）：界面层唯一知道 RunService / SaveStore 的对象。
##
## 职责（也是它存在的理由）：
##   · 页面只 render(view) + build_action()；壳负责「把草稿交给 RunService」与「把视图发给页面」。
##   · 统一门控：每个规则操作按钮都先用 RunService.preview 试算一次，不能提交就 disabled
##     —— 所以「界面不得自行放行非法节点」不是靠页面自觉，而是结构上做不到。
##   · 存档：继续/新局/每步自动存档/结局三步提交全部走 SaveStore，壳自己不写文件。
##   · 战斗交接：battle_requested / battle_resumed 两个信号；没有战斗界面时启用开发回退（引擎代打）。
##

## 新战斗：把 RunService 的 battle_input 交给战斗界面（BattleEngine.begin 可直接吃）。
signal battle_requested(battle_input: Dictionary)
## 读档恢复的进行中战斗：直接把 BattleState 交给战斗界面接管。
signal battle_resumed(battle_state)

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const RunServiceScript := preload("res://src/run/run_service.gd")
const SnapshotCodec := preload("res://src/storage/snapshot_codec.gd")
const SaveStoreScript := preload("res://src/storage/save_store.gd")
const SessionStateScript := preload("res://src/app/session_state.gd")
const ProfileMerge := preload("res://src/storage/profile_merge.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const DevAutoBattle := preload("res://src/ui/dev_auto_battle.gd")
const RunCodecScript := preload("res://src/run/run_codec.gd")
## 页面脚本一律 preload（不依赖编辑器生成的 global class cache，无头运行才稳）。
const PageMenu := preload("res://src/ui/page_menu.gd")
const PageSetup := preload("res://src/ui/page_setup.gd")
const PageMap := preload("res://src/ui/page_map.gd")
const PageBattleEntry := preload("res://src/ui/page_battle_entry.gd")
const PageReward := preload("res://src/ui/page_reward.gd")
const PageShop := preload("res://src/ui/page_shop.gd")
const PageEvent := preload("res://src/ui/page_event.gd")
const PageRest := preload("res://src/ui/page_rest.gd")
const PageTerm := preload("res://src/ui/page_term.gd")
const PageEnding := preload("res://src/ui/page_ending.gd")
const PageSummary := preload("res://src/ui/page_summary.gd")
const PageSettings := preload("res://src/ui/page_settings.gd")
const PageTutorial := preload("res://src/ui/page_tutorial.gd")
const PageRules := preload("res://src/ui/page_rules.gd")
const PageBattleLog := preload("res://src/ui/page_battle_log.gd")
const TutorialText := preload("res://src/ui/tutorial_text.gd")

## 非局内页面（没有 RunView 的页面）。
const UI_SCREEN_SETUP := "setup"
const UI_SCREEN_SETTINGS := "settings"
## 教学 / 规则说明 / 战斗日志：局外的三张「帮助」页（可从主菜单或局内进入）。
const UI_SCREEN_TUTORIAL := "tutorial"
const UI_SCREEN_RULES := "rules"
const UI_SCREEN_LOG := "battle_log"

var catalog = null
var service = null
var store = null
var session = null
## Profile（只读给界面展示；由 SaveStore 的三步提交维护）。
var profile: Dictionary = {}
## 设置文档（difficulty / seed / autosave）。
var settings: Dictionary = {}

## 当前屏幕：局内来自 RunView.screen，局外由 _ui_screen 覆盖。
var screen: String = GameConstants.SCREEN_MENU
var view: Dictionary = {}
var status_text: String = ""
## 进入战斗节点时 RunService 给出的 battle_input（交给战斗界面）。
var pending_battle_input: Dictionary = {}
## 进行中的战斗状态（战斗界面用 attach_battle_state 回填；存档要用）。
var battle_state = null
## 战斗界面回填的战斗随机快照（与 SessionState.random_snapshot 同一形状）。
var _battle_rng: Dictionary = {}
## 最近一次被接受的 BattleOutcome（开发回退与测试用来核对结算结果）。
var last_battle_outcome: Dictionary = {}
## 接上的战斗界面（main.gd 或测试调 attach_battle_host）。
var _battle_host = null
## 战斗界面最近一次结算的日志（战斗日志页展示用；界面只缓存，不重算）。
var last_battle_log: PackedStringArray = PackedStringArray()
var last_battle_log_node: String = ""
## 进入帮助页前的屏幕：教学页据此高亮「你现在该看哪一节」。
var _help_from: String = ""

var _ui_screen: String = ""
var _page = null
var _pages: Dictionary = {}
var _last_request: Dictionary = {}
var _pending_committed: bool = false
var _render_count: int = 0


## 接上一个战斗界面：shell 只认三个约定——start_battle(battle_input) / battle_finished(outcome) /
## action_applied(step)。接线放在 shell 里，是为了让 main.gd 与测试走同一条路径。
## 引擎用「局的 catalog」新建：战斗界面自己的默认清单是冻结的 battle_mvp，遇到出厂 mvp 独有的牌
## （K05/K10/…）会在 engine.begin 直接 unknown_card，战斗根本开不起来。
func attach_battle_host(screen) -> bool:
	if screen == null or not (screen is Control):
		return false
	_battle_host = screen
	if (_battle_host as Object).has_method("set_engine"):
		(_battle_host as Object).call("set_engine", BattleEngineScript.new(catalog))
	if (_battle_host as Object).has_signal("battle_finished"):
		(_battle_host as Object).connect("battle_finished", _on_host_battle_finished)
	if (_battle_host as Object).has_signal("action_applied"):
		(_battle_host as Object).connect("action_applied", _on_host_action_applied)
	if not battle_requested.is_connected(_on_host_battle_requested):
		battle_requested.connect(_on_host_battle_requested)
	if not battle_resumed.is_connected(_on_host_battle_resumed):
		battle_resumed.connect(_on_host_battle_resumed)
	(_battle_host as Control).visible = false
	return true


func battle_host():
	return _battle_host


func _on_host_battle_requested(battle_input: Dictionary) -> void:
	if _battle_host == null or not (_battle_host as Object).has_method("start_battle"):
		return
	(_battle_host as Control).visible = true
	(_battle_host as Object).call("start_battle", battle_input)


func _on_host_battle_resumed(battle_state) -> void:
	if _battle_host == null or not (_battle_host as Object).has_method("resume_battle"):
		return
	(_battle_host as Control).visible = true
	# 战斗随机流必须一起交出去：缺了它后续抽牌会退化成零种子，读档续战与原局不一致。
	(_battle_host as Object).call("resume_battle", battle_state, battle_rng_snapshot())


func _on_host_action_applied(_step: Dictionary) -> void:
	if _battle_host == null:
		return
	var state = null
	var rng = null
	if (_battle_host as Object).has_method("current_state"):
		state = (_battle_host as Object).call("current_state")
	if (_battle_host as Object).has_method("current_rng_state"):
		rng = (_battle_host as Object).call("current_rng_state")
	attach_battle_state(state, rng)


func _on_host_battle_finished(outcome: Dictionary) -> void:
	if _battle_host != null:
		## 先留一份日志再隐藏：局内「战斗日志」页回看的就是这一份。
		if (_battle_host as Object).has_method("log_lines"):
			last_battle_log = (_battle_host as Object).call("log_lines")
			last_battle_log_node = String(outcome.get("battle_id", ""))
		(_battle_host as Control).visible = false
	apply_battle_outcome(outcome)


func _init(catalog_ref = null, store_ref = null) -> void:
	catalog = catalog_ref
	service = RunServiceScript.new(catalog)
	store = store_ref if store_ref != null else SaveStoreScript.new(SaveStoreScript.DEFAULT_BASE_DIR, catalog)
	settings = _load_settings()
	profile = _load_profile()
	_ui_screen = GameConstants.SCREEN_MENU


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 真正的入口：由 main.gd 在挂进场景树后调用。
func start() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()


# ── 对外只读接口（测试与调试）──────────────────────────────

func current_view() -> Dictionary:
	return view


func current_page():
	return _page


## 走真实 Button 的 pressed 信号（与鼠标同一条路径）。
func press(uid: String) -> bool:
	if _page == null:
		return false
	return _page.press(uid)


func has_button(uid: String) -> bool:
	return _page != null and _page.has_button(uid)


func button_disabled(uid: String) -> bool:
	return _page == null or _page.button_disabled(uid)


func button_reason(uid: String) -> String:
	return "" if _page == null else _page.button_reason(uid)


## 可用 uids（含本地按钮 + 规则操作按钮），测试用来断言「页面到底画了什么」。
func button_uids() -> Array:
	return [] if _page == null else _page.button_uids()


## 按钮文案（测试断言用）。
func button_text(uid: String) -> String:
	return "" if _page == null else _page.button_text(uid)


func take_battle_input() -> Dictionary:
	return pending_battle_input.duplicate(true)


## 战斗界面回填进行中的战斗状态 + 该战斗当前的随机快照。
## 随机快照必须一起给：战斗后续抽牌走的是战斗随机流，缺了就退化成零种子，
## 读档续战会与原局不一致（架构 §8「退出继续结果一致」）。
func attach_battle_state(state, rng_snapshot = null) -> void:
	battle_state = state
	_battle_rng = {}
	if typeof(rng_snapshot) == TYPE_DICTIONARY and not (rng_snapshot as Dictionary).is_empty():
		_battle_rng = (rng_snapshot as Dictionary).duplicate(true)
		_merge_battle_rng(_battle_rng)
	if session != null:
		session.battle = state


func detach_battle_state() -> void:
	battle_state = null
	_battle_rng = {}
	if session != null:
		session.battle = null


## 该战斗当前的随机快照：有回填用回填的，否则用局的随机快照（新战斗开打时就是同一份值）。
func battle_rng_snapshot() -> Dictionary:
	if not _battle_rng.is_empty():
		return _battle_rng.duplicate(true)
	if session != null and typeof(session.random_snapshot) == TYPE_DICTIONARY:
		return (session.random_snapshot as Dictionary).duplicate(true)
	return {}


## 没有战斗界面（battle_requested 无监听者）时，界面会说明这一点并启用引擎代打。
func dev_fallback_active() -> bool:
	return battle_requested.get_connections().is_empty()


# ── 渲染 ──────────────────────────────────────────────────

func refresh() -> void:
	_render_count += 1
	_resolve_screen()
	view = _build_view()
	_page = _ensure_page(screen)
	_page.status_text = status_text
	_page.render(view)
	_regate()


func _resolve_screen() -> void:
	if not _ui_screen.is_empty():
		screen = _ui_screen
		return
	if session != null and session.run != null:
		screen = String(service.make_view(session.run).get("screen", GameConstants.SCREEN_MAP))
		return
	screen = GameConstants.SCREEN_MENU


func _build_view() -> Dictionary:
	if screen == GameConstants.SCREEN_MENU:
		return _menu_view()
	if screen == UI_SCREEN_SETUP:
		return _setup_view()
	if screen == UI_SCREEN_SETTINGS:
		return _settings_view()
	if screen == UI_SCREEN_TUTORIAL:
		return _tutorial_view()
	if screen == UI_SCREEN_RULES:
		return _rules_view()
	if screen == UI_SCREEN_LOG:
		return _log_view()
	var run_view: Dictionary = service.make_view(session.run)
	run_view["status"] = status_text
	run_view["battle_input"] = pending_battle_input.duplicate(true)
	run_view["resume_available"] = session.battle != null
	run_view["dev_fallback"] = dev_fallback_active()
	run_view["settings"] = settings.duplicate(true)
	## 局内提示：教学文案由界面文案层提供，不参与任何规则判断。
	run_view["tutorial_hint"] = TutorialText.hint_for_screen(screen, _focus_node_kind())
	run_view["tutorial_highlight"] = _tutorial_highlight(_help_from if not _help_from.is_empty() else screen)
	run_view["has_battle_log"] = not last_battle_log.is_empty()
	return run_view


func _menu_view() -> Dictionary:
	var inspected: Dictionary = store.inspect(SaveStoreScript.SLOT_CURRENT_RUN)
	var meta: Variant = {}
	var has_save := false
	if Result.is_ok(inspected):
		meta = inspected["data"]
		has_save = true
	return {
		"has_save": has_save,
		"save_meta": meta,
		"save_error": "" if has_save else Result.error_code(inspected),
		"profile": profile.duplicate(true),
		"status": status_text,
	}


func _setup_view() -> Dictionary:
	var characters := []
	for raw_id in catalog.enabled_ids(GameConstants.KIND_CHARACTER):
		var character_id := String(raw_id)
		var definition: Dictionary = catalog.definition(GameConstants.KIND_CHARACTER, character_id)
		var entry := {
			"id": character_id,
			"name_key": String(definition.get("name_key", "")),
			"starter_cards": (definition.get("starter_cards", []) as Array).duplicate(),
			"starter_relic_id": String(definition.get("starter_relic_id", "")),
			"locked": false,
			"reason": "",
		}
		# 可用性用 RunService.create 试跑判定：幂等、无副作用，界面不重算解锁规则。
		var probe: Dictionary = service.create({
			"character_id": character_id,
			"difficulty": String(settings.get("difficulty", GameConstants.DIFFICULTY_NORMAL)),
			"seed": "0",
		}, profile)
		if not Result.is_ok(probe):
			entry["locked"] = true
			entry["reason"] = _error_summary(probe)
		characters.append(entry)
	return {
		"characters": characters,
		"difficulties": RunServiceScript.DIFFICULTIES.duplicate(),
		"defaults": {
			"character_id": String(characters[0].get("id", "")) if not characters.is_empty() else "",
			"difficulty": String(settings.get("difficulty", GameConstants.DIFFICULTY_NORMAL)),
			"seed": String(settings.get("seed", "")),
		},
		"profile": profile.duplicate(true),
		"status": status_text,
	}


## 教学页视图：章节来自界面文案层；highlight 由「从哪一屏进来的」决定。
func _tutorial_view() -> Dictionary:
	var from := _help_from if not _help_from.is_empty() else GameConstants.SCREEN_MAP
	return {
		"sections": TutorialText.sections(),
		"highlight": _tutorial_highlight(from),
		"in_run": session != null and session.run != null,
		"status": status_text,
	}


func _rules_view() -> Dictionary:
	return {
		"sections": TutorialText.rule_sections(),
		"in_run": session != null and session.run != null,
		"status": status_text,
	}


func _log_view() -> Dictionary:
	return {
		"lines": last_battle_log,
		"source_node": last_battle_log_node,
		"in_run": session != null and session.run != null,
		"status": status_text,
	}


## 屏幕 → 教学章节（一屏可能对应多节：地图上的商店节点同时值得看「地图」与「商店」）。
func _tutorial_highlight(from_screen: String) -> Array:
	var highlight := []
	match from_screen:
		GameConstants.SCREEN_MAP:
			highlight.append("map")
			var kind := _focus_node_kind()
			if kind == RunNodeState.KIND_SHOP:
				highlight.append("shop")
			elif kind == RunNodeState.KIND_REST:
				highlight.append("rest")
			elif kind == RunNodeState.KIND_EVENT:
				highlight.append("event")
			elif not kind.is_empty():
				highlight.append("battle")
		GameConstants.SCREEN_BATTLE:
			highlight.append("battle")
		GameConstants.SCREEN_REWARD:
			highlight.append("reward")
		GameConstants.SCREEN_SHOP:
			highlight.append("shop")
		GameConstants.SCREEN_EVENT:
			highlight.append("event")
		GameConstants.SCREEN_REST:
			highlight.append("rest")
		GameConstants.SCREEN_TERM:
			highlight.append("term")
		GameConstants.SCREEN_SUMMARY, GameConstants.SCREEN_ENDING:
			highlight.append("save")
	if highlight.is_empty():
		highlight.append("map")
	return highlight


## 地图屏上「玩家现在该注意哪个节点」：当前节点；没有就取第一个可达节点。
func _focus_node_kind() -> String:
	if session == null or session.run == null:
		return ""
	var node = session.run.current_node()
	if node != null:
		return String(node.kind)
	var reachable: Array = session.run.reachable_node_ids()
	for raw_id in reachable:
		var candidate = session.run.find_node(String(raw_id))
		if candidate != null:
			return String(candidate.kind)
	return ""


func _settings_view() -> Dictionary:
	var inspected: Dictionary = store.inspect(SaveStoreScript.SLOT_CURRENT_RUN)
	var backup: Dictionary = store.load_backup(SaveStoreScript.SLOT_CURRENT_RUN)
	return {
		"settings": settings.duplicate(true),
		"difficulties": RunServiceScript.DIFFICULTIES.duplicate(),
		"save_meta": inspected["data"] if Result.is_ok(inspected) else Result.error_code(inspected),
		"backup_meta": backup["data"].get("run_id") if Result.is_ok(backup) else Result.error_code(backup),
		"status": status_text,
	}
# ── 页面路由 ──────────────────────────────────────────────

func _ensure_page(p_screen: String):
	var page: Variant = _pages.get(p_screen)
	if page == null:
		page = _make_page(p_screen)
		(page as Control).name = "Page_" + p_screen
		page.action_requested.connect(_on_page_action)
		page.view_changed.connect(_regate)
		add_child(page)
		_pages[p_screen] = page
	for key in _pages:
		(_pages[key] as Control).visible = String(key) == p_screen
	return page


func _make_page(p_screen: String):
	match p_screen:
		GameConstants.SCREEN_MAP:
			return PageMap.new()
		GameConstants.SCREEN_BATTLE:
			return PageBattleEntry.new()
		GameConstants.SCREEN_REWARD:
			return PageReward.new()
		GameConstants.SCREEN_SHOP:
			return PageShop.new()
		GameConstants.SCREEN_EVENT:
			return PageEvent.new()
		GameConstants.SCREEN_REST:
			return PageRest.new()
		GameConstants.SCREEN_TERM:
			return PageTerm.new()
		GameConstants.SCREEN_ENDING:
			return PageEnding.new()
		GameConstants.SCREEN_SUMMARY:
			return PageSummary.new()
		UI_SCREEN_SETUP:
			return PageSetup.new()
		UI_SCREEN_SETTINGS:
			return PageSettings.new()
		UI_SCREEN_TUTORIAL:
			return PageTutorial.new()
		UI_SCREEN_RULES:
			return PageRules.new()
		UI_SCREEN_LOG:
			return PageBattleLog.new()
	return PageMenu.new()


func _on_page_action() -> void:
	if _page == null:
		return
	dispatch(_page.build_action())


# ── 命令分发 ──────────────────────────────────────────────

## 界面唯一出口：ui.* 与 create_run 由壳自己处理，其余一律交给 RunService。
func dispatch(action: Dictionary) -> Dictionary:
	var action_type := String(action.get("type", ""))
	var raw_payload: Variant = action.get("payload")
	var payload: Dictionary = raw_payload if typeof(raw_payload) == TYPE_DICTIONARY else {}
	if action_type.is_empty():
		_note("页面没有给出操作。")
		refresh()
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.empty_action", {})
	if action_type == "create_run":
		return create_run(payload)
	if action_type.begins_with("ui."):
		return _ui_action(action_type, payload)
	if session == null or session.run == null:
		_note("还没有进行中的局。")
		refresh()
		return Result.fail(GameConstants.ERROR_RUN_NOT_FOUND, "error.run.no_state", {})
	if not (RunServiceScript.RUN_ACTIONS as Array).has(action_type):
		_note("界面不认识的操作：%s" % action_type)
		refresh()
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_action", {
			"type": action_type,
		})
	var gate: Dictionary = service.preview(session.run, action)
	if Result.is_ok(gate) and not bool((gate["data"] as Dictionary).get("can_submit", true)):
		_note("这一步现在不能提交：%s" % _preview_reason(gate["data"]))
		refresh()
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.ui.blocked_by_preview", {
			"type": action_type,
		})
	var applied: Dictionary = service.apply(session.run, action, session.random_snapshot)
	if not Result.is_ok(applied):
		_note("操作被规则层拒绝：%s" % _error_summary(applied))
		refresh()
		return applied
	_commit_step(applied["data"])
	return applied


## 打开帮助页（教学 / 规则 / 日志）：记下「从哪一屏进来」，返回时用 ui.back。
func _open_help(target: String) -> Dictionary:
	_help_from = screen
	_ui_screen = target
	status_text = ""
	refresh()
	return Result.ok(null)


func _ui_action(action_type: String, payload: Dictionary) -> Dictionary:
	match action_type:
		"ui.menu":
			_ui_screen = GameConstants.SCREEN_MENU
			refresh()
			return Result.ok(null)
		"ui.new_run":
			_ui_screen = UI_SCREEN_SETUP
			status_text = ""
			refresh()
			return Result.ok(null)
		"ui.settings":
			_ui_screen = UI_SCREEN_SETTINGS
			status_text = ""
			refresh()
			return Result.ok(null)
		"ui.tutorial":
			return _open_help(UI_SCREEN_TUTORIAL)
		"ui.rules":
			return _open_help(UI_SCREEN_RULES)
		"ui.battle_log":
			return _open_help(UI_SCREEN_LOG)
		"ui.back":
			if session == null or session.run == null:
				_ui_screen = GameConstants.SCREEN_MENU
			else:
				_ui_screen = ""
			refresh()
			return Result.ok(null)
		"ui.retry":
			return _retry()
		"ui.continue":
			return continue_run()
		"ui.save":
			var saved: Dictionary = save_now()
			if Result.is_ok(saved):
				status_text = "已保存（revision=%s）" % str(session.revision)
				refresh()
			return saved
		"ui.save_settings":
			return _save_settings(payload)
		"ui.restore_backup":
			return _restore_backup()
		"ui.start_battle":
			return _start_battle()
		"ui.resume_battle":
			return _resume_battle()
		"ui.quit":
			return _quit()
	_note("未知界面动作：%s" % action_type)
	refresh()
	return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.unknown_action", {"type": action_type})


# ── 局生命周期 ────────────────────────────────────────────

## 新局：只调用 RunService.create（校验全部在规则层），成功后立刻自动存档。
func create_run(request: Dictionary) -> Dictionary:
	if catalog == null or not catalog.is_loaded():
		_note("内容库未载入，无法开局。")
		refresh()
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.catalog_missing", {})
	var created: Dictionary = service.create(request, profile)
	if not Result.is_ok(created):
		_note("开局失败：%s" % _error_summary(created))
		refresh()
		return created
	var step: Dictionary = created["data"]
	session = SessionStateScript.new()
	session.run_id = step["state"].run_id
	session.revision = 1
	session.run = step["state"]
	session.battle = null
	session.random_snapshot = step["rng_states"]
	_last_request = request.duplicate(true)
	pending_battle_input = {}
	battle_state = null
	_pending_committed = false
	_ui_screen = ""
	status_text = "新局开始：人物 %s，难度 %s" % [String(request.get("character_id", "")), String(request.get("difficulty", ""))]
	_autosave()
	refresh()
	return created


## 继续：SaveStore.load -> SnapshotCodec.decode_session；正式档不可用时尝试备份。
func continue_run() -> Dictionary:
	if session != null and session.run != null:
		_ui_screen = ""
		refresh()
		return Result.ok({"resumed": true, "source": "memory"})
	var loaded: Dictionary = store.load(SaveStoreScript.SLOT_CURRENT_RUN)
	var from_backup := false
	if not Result.is_ok(loaded):
		var backup: Dictionary = store.load_backup(SaveStoreScript.SLOT_CURRENT_RUN)
		if Result.is_ok(backup):
			loaded = backup
			from_backup = true
	if not Result.is_ok(loaded):
		_note("读档失败：%s" % _error_summary(loaded))
		refresh()
		return loaded
	var decoded: Dictionary = SnapshotCodec.decode_session(loaded["data"])
	if not Result.is_ok(decoded):
		_note("存档解码失败：%s" % _error_summary(decoded))
		refresh()
		return decoded
	session = decoded["data"]["session"]
	pending_battle_input = {}
	battle_state = session.battle
	_pending_committed = false
	_ui_screen = ""
	status_text = "已从备份档恢复。" if from_backup else "已读档：revision=%s" % str(session.revision)
	if session.run != null and session.run.pending_profile_summary != null:
		var committed: Dictionary = store.commit_pending_profile(SaveStoreScript.SLOT_CURRENT_RUN, SaveStoreScript.SLOT_PROFILE)
		if Result.is_ok(committed):
			_pending_committed = true
			profile = _load_profile()
		else:
			_note("结局合并 Profile 失败：%s" % _error_summary(committed))
	refresh()
	return Result.ok({"resumed": true, "from_backup": from_backup})


## 失败/通关后重开：同人物同难度，种子 +1（避免一模一样的一局）。
func _retry() -> Dictionary:
	var request: Dictionary = _last_request.duplicate(true)
	if request.is_empty():
		request = {
			"character_id": "",
			"difficulty": String(settings.get("difficulty", GameConstants.DIFFICULTY_NORMAL)),
			"seed": String(settings.get("seed", "")),
		}
	request["seed"] = str(_seed_int(request.get("seed", "")) + 1)
	return create_run(request)


## 战斗界面打完把 BattleOutcome 交回来；壳只做 settle_battle + 存档 + 重绘。
func apply_battle_outcome(outcome: Dictionary) -> Dictionary:
	if session == null or session.run == null:
		return Result.fail(GameConstants.ERROR_RUN_NOT_FOUND, "error.run.no_state", {})
	var settled: Dictionary = service.settle_battle(session.run, outcome, session.random_snapshot)
	if Result.is_ok(settled):
		last_battle_outcome = outcome.duplicate(true)
	if not Result.is_ok(settled):
		_note("战斗结算被拒绝：%s" % _error_summary(settled))
		refresh()
		return settled
	session.battle = null
	battle_state = null
	pending_battle_input = {}
	_commit_step(settled["data"])
	return settled


func _start_battle() -> Dictionary:
	if pending_battle_input.is_empty():
		_note("没有待开始的战斗。")
		refresh()
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_active_battle", {})
	if not dev_fallback_active():
		battle_requested.emit(pending_battle_input.duplicate(true))
		return Result.ok({"dispatched": true})
	return _dev_play_battle()


func _resume_battle() -> Dictionary:
	if session == null or session.battle == null:
		_note("没有未打完的战斗。")
		refresh()
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_active_battle", {})
	if not battle_resumed.get_connections().is_empty():
		battle_resumed.emit(session.battle)
		return Result.ok({"dispatched": true})
	_note("没有安装战斗界面，无法继续这一场；可以回主菜单或从备份恢复。")
	refresh()
	return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.ui.no_battle_screen", {})


## 开发回退：没有战斗界面时用 BattleEngine 的公开入口把这一场打完并结算。
## 战斗交接的三个入口（新开战 / resume / dev 代打）都必须把 state + 随机快照回填 session：
## settle_battle 靠 BattleOutcome.battle_id 定位节点，存档/续战靠 battle 流。
func _dev_play_battle() -> Dictionary:
	var engine := BattleEngineScript.new(catalog)
	var begin: Dictionary = engine.begin(pending_battle_input.duplicate(true))
	if not Result.is_ok(begin):
		_note("战斗无法开始：%s" % _error_summary(begin))
		refresh()
		return begin
	var outcome: Dictionary = DevAutoBattle.play(engine, begin, Callable(self, "_on_dev_battle_step"))
	if outcome.is_empty():
		_note("开发回退没能打完这一场（战斗卡住了）。")
		refresh()
		return Result.fail(GameConstants.ERROR_RESOLUTION_ERROR, "error.ui.dev_battle_stuck", {})
	return apply_battle_outcome(outcome)


## 代打的每一步都回填：与战斗界面的 action_applied 回填同一条路。
func _on_dev_battle_step(state, rng_snapshot) -> void:
	attach_battle_state(state, rng_snapshot)


func _quit() -> Dictionary:
	if get_tree() == null:
		return Result.ok({"quit": false})
	get_tree().quit()
	return Result.ok({"quit": true})


# ── 存档 ──────────────────────────────────────────────────

## 稳定边界写档：current_run + （有结局时）三步提交 Profile。
## 战斗进行中且没有 battle_state 时不写档——否则会留下「active_battle_id 非空但快照无战斗」的死档。
func save_now() -> Dictionary:
	if session == null or session.run == null:
		return Result.fail(GameConstants.ERROR_RUN_NOT_FOUND, "error.run.no_state", {})
	var pending: Variant = null
	# RunState 里的待合并摘要是 RunSummary 对象，快照层要的是字典（RunCodec 是它的编解码器）。
	if session.run.pending_profile_summary != null and not _pending_committed:
		pending = RunCodecScript.encode_summary(session.run.pending_profile_summary)
	var encoded: Dictionary = SnapshotCodec.encode_session(session, pending, _content_info())
	if not Result.is_ok(encoded):
		_note("存档编码失败：%s" % _error_summary(encoded))
		return encoded
	var saved: Dictionary = store.save(SaveStoreScript.SLOT_CURRENT_RUN, encoded["data"])
	if not Result.is_ok(saved):
		_note("存档写入失败：%s" % _error_summary(saved))
		return saved
	if pending != null:
		var committed: Dictionary = store.commit_pending_profile(SaveStoreScript.SLOT_CURRENT_RUN, SaveStoreScript.SLOT_PROFILE)
		if not Result.is_ok(committed):
			_note("结局合并 Profile 失败：%s" % _error_summary(committed))
			return committed
		_pending_committed = true
		profile = _load_profile()
	return saved


func _autosave() -> void:
	if not bool(settings.get("autosave", true)):
		return
	if not pending_battle_input.is_empty() and battle_state == null:
		return
	save_now()


func _save_settings(payload: Dictionary) -> Dictionary:
	var raw: Variant = payload.get("settings")
	var incoming: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var merged := {
		"difficulty": String(incoming.get("difficulty", GameConstants.DIFFICULTY_NORMAL)),
		"seed": String(incoming.get("seed", "")),
		"autosave": bool(incoming.get("autosave", true)),
	}
	var document: Dictionary = SnapshotCodec.encode_document(merged, _content_info())
	if not Result.is_ok(document):
		_note("设置编码失败：%s" % _error_summary(document))
		refresh()
		return document
	var saved: Dictionary = store.save(SaveStoreScript.SLOT_SETTINGS, document["data"])
	if not Result.is_ok(saved):
		_note("设置写入失败：%s" % _error_summary(saved))
		refresh()
		return saved
	settings = merged
	status_text = "设置已保存"
	refresh()
	return saved


func _restore_backup() -> Dictionary:
	var backup: Dictionary = store.load_backup(SaveStoreScript.SLOT_CURRENT_RUN)
	if not Result.is_ok(backup):
		_note("没有可用备份：%s" % _error_summary(backup))
		refresh()
		return backup
	var decoded: Dictionary = SnapshotCodec.decode_session(backup["data"])
	if not Result.is_ok(decoded):
		_note("备份解码失败：%s" % _error_summary(decoded))
		refresh()
		return decoded
	session = decoded["data"]["session"]
	battle_state = session.battle
	pending_battle_input = {}
	_pending_committed = false
	_ui_screen = ""
	status_text = "已用备份档恢复（正式档保持不动，下一步操作会覆盖它）"
	refresh()
	return Result.ok({"restored": true})


# ── 门控 ──────────────────────────────────────────────────

## 用 RunService.preview 逐个试算页面上的规则操作：不能提交就禁用按钮并记下原因。
func _regate() -> void:
	if _page == null:
		return
	if session == null or session.run == null:
		_page.apply_gating({})
		return
	var results := {}
	for raw_uid in _page.action_uids():
		var uid := String(raw_uid)
		var draft: Dictionary = _page.action_draft(uid)
		var action_type := String(draft.get("type", ""))
		if not (RunServiceScript.RUN_ACTIONS as Array).has(action_type):
			continue
		var preview: Dictionary = service.preview(session.run, draft)
		var ok := false
		var reason := ""
		if Result.is_ok(preview):
			var data: Dictionary = preview["data"]
			ok = bool(data.get("can_submit", false))
			if not ok:
				reason = _preview_reason(data)
		else:
			reason = _error_summary(preview)
		results[uid] = {"ok": ok, "reason": reason}
	_page.apply_gating(results)


# ── 小工具 ────────────────────────────────────────────────

func _commit_step(step: Dictionary) -> void:
	session.run = step["state"]
	session.random_snapshot = step["rng_states"]
	session.revision += 1
	var raw_input: Variant = step.get("battle_input")
	if typeof(raw_input) == TYPE_DICTIONARY and not (raw_input as Dictionary).is_empty():
		pending_battle_input = (raw_input as Dictionary).duplicate(true)
	if step.get("run_summary") != null:
		_pending_committed = false
	status_text = ""
	_autosave()
	refresh()


func _note(text: String) -> void:
	status_text = text


## 把战斗的 battle 流写回局快照：battle 流只有战斗在用，写回后存档/读档都能续上。
func _merge_battle_rng(rng_snapshot: Dictionary) -> void:
	if session == null or typeof(session.random_snapshot) != TYPE_DICTIONARY:
		return
	var battle_streams: Variant = rng_snapshot.get("streams")
	if typeof(battle_streams) != TYPE_DICTIONARY:
		return
	if not (battle_streams as Dictionary).has(GameConstants.RNG_BATTLE):
		return
	var merged: Dictionary = (session.random_snapshot as Dictionary).duplicate(true)
	var streams: Variant = merged.get("streams")
	if typeof(streams) != TYPE_DICTIONARY:
		return
	(streams as Dictionary)[GameConstants.RNG_BATTLE] = (battle_streams as Dictionary)[GameConstants.RNG_BATTLE]
	session.random_snapshot = merged


func _content_info() -> Dictionary:
	if catalog == null:
		return {}
	return {
		"content_version": String(catalog.content_version),
		"content_hash": String(catalog.content_hash),
		"manifest_id": String(catalog.manifest_id),
	}


func _load_profile() -> Dictionary:
	var loaded: Dictionary = store.load(SaveStoreScript.SLOT_PROFILE)
	if Result.is_ok(loaded):
		var payload: Variant = (loaded["data"] as Dictionary).get("payload")
		if typeof(payload) == TYPE_DICTIONARY and not (payload as Dictionary).is_empty():
			return (payload as Dictionary).duplicate(true)
	return ProfileMerge.empty_profile()


func _load_settings() -> Dictionary:
	var defaults := {
		"difficulty": GameConstants.DIFFICULTY_NORMAL,
		"seed": "",
		"autosave": true,
	}
	var loaded: Dictionary = store.load(SaveStoreScript.SLOT_SETTINGS)
	if not Result.is_ok(loaded):
		return defaults
	var payload: Variant = (loaded["data"] as Dictionary).get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		return defaults
	var data: Dictionary = payload
	return {
		"difficulty": String(data.get("difficulty", defaults["difficulty"])),
		"seed": String(data.get("seed", defaults["seed"])),
		"autosave": bool(data.get("autosave", defaults["autosave"])),
	}


func _seed_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_STRING and String(value).is_valid_int():
		return String(value).to_int()
	return 0


func _error_summary(result: Dictionary) -> String:
	var error: Variant = result.get("error")
	if typeof(error) != TYPE_DICTIONARY:
		return str(result)
	var data: Dictionary = error
	var parts := [String(data.get("code", ""))]
	var message_key := String(data.get("message_key", ""))
	if not message_key.is_empty():
		parts.append(message_key)
	var details: Variant = data.get("details")
	if typeof(details) == TYPE_DICTIONARY and not (details as Dictionary).is_empty():
		parts.append(flatten_for_log(details))
	return " / ".join(parts)


func flatten_for_log(data: Dictionary) -> String:
	var keys := data.keys()
	keys.sort()
	var parts := []
	for raw_key in keys:
		parts.append("%s=%s" % [String(raw_key), str(data[raw_key])])
	return " ".join(parts)


func _preview_reason(preview: Dictionary) -> String:
	var reasons := []
	for raw_error in (preview.get("blocking_errors", []) as Array):
		var error: Dictionary = raw_error
		reasons.append(String(error.get("message_key", String(error.get("code", "")))))
	var required: Array = preview.get("required_selections", [])
	if not required.is_empty():
		reasons.append("还缺选择：%s" % str(required))
	return "；".join(reasons) if not reasons.is_empty() else "现在不能提交"