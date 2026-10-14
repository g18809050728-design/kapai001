extends RefCounted
##
## 两人物完整试玩（t4）：P01 与 P04 各用**真实局流程 + 真实战斗界面**走完一学期（含 B01 首领），
## 并逐项验证《项目计划书》§3.1 的配套清单在界面上可达：
##   教学、奖励、商店、休息、设置、保存/继续、失败重开、战斗日志。
##
## 口径：
##   · 每一步都走 `press(uid)`——与鼠标点击同一条 Button.pressed 信号路径；
##   · 战斗全部由**真实战斗界面**（battle_screen.tscn）的公开 API 驱动到底，不注入胜利结局；
##   · 试玩过程逐步写进 `user://playthrough/<人物>_t1.log`（无头环境无法截图，日志即证据）；
##   · 断言的期望值一律从视图/规则层派生（节点 kind → 界面、战斗节点数、首领遭遇是否启用），
##     不写死内容清单事实。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const SaveStore := preload("res://src/storage/save_store.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const GameShell := preload("res://src/ui/game_shell.gd")
const BattleScreenScene := preload("res://src/ui/battle_screen.tscn")
const BattleScreenScript := preload("res://src/ui/battle_screen.gd")
const TutorialText := preload("res://src/ui/tutorial_text.gd")

const LOG_DIR := "user://playthrough"
const STEP_GUARD := 900


func run(h) -> void:
	var db := ContentDB.new()
	var loaded := db.load(GameConstants.MANIFEST_MVP)
	if not Result.is_ok(loaded):
		h.begin("试玩 · 前置")
		h.check("出厂 mvp 清单可加载", false, str(loaded))
		return
	h.begin("试玩 · §3.1 配套清单逐项可达（教学 / 设置 / 保存继续 / 失败重开 / 战斗日志）")
	_checklist(h, db)
	h.begin("试玩 · P01 林序：一学期全流程（真实战斗界面 + B01）")
	_playthrough(h, db, "P01")
	h.begin("试玩 · P04 唐以宁：一学期全流程（真实战斗界面 + B01）")
	_playthrough(h, db, "P04")


# ── 完整试玩 ──────────────────────────────────────────────

func _playthrough(h, db, character_id: String) -> void:
	var shell = _new_shell(db, "play_" + character_id)
	var screen = BattleScreenScene.instantiate()
	h.check("%s：battle_screen.tscn 可实例化" % character_id, screen != null)
	if screen == null:
		_cleanup(shell)
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).root.add_child(screen)
	h.check("%s：attach_battle_host 接线成功" % character_id, shell.attach_battle_host(screen))

	var log := PackedStringArray()
	_log(log, "== 试玩开始：人物 %s，清单 %s ==" % [character_id, db.manifest_id])
	# 主菜单 -> 选人（选指定人物）-> 开局
	_step(h, shell, log, "menu:new", "主菜单 → 新局")
	h.check("%s：选人页列出了该人物" % character_id, shell.has_button("setup:character:" + character_id))
	_step(h, shell, log, "setup:character:" + character_id, "选人：" + character_id)
	_step(h, shell, log, "setup:difficulty:relaxed", "难度：relaxed（试玩用，减少数值噪音）")
	_step(h, shell, log, "setup:start", "开始新局")
	h.eq("%s：开局进入地图" % character_id, shell.screen, GameConstants.SCREEN_MAP)
	h.eq("%s：开局人物正确" % character_id, String(shell.session.run.character_id), character_id)

	var visited := {}
	var battle_nodes := 0
	var real_battles := 0
	var boss_encounter := ""
	var pending_node := ""
	var term_path: Array = []
	for step in range(STEP_GUARD):
		var screen_name := String(shell.screen)
		visited[screen_name] = true
		# 上一轮进入的节点：界面必须与它进入后的 kind 对应
		if not pending_node.is_empty():
			var kind_now := _node_kind(shell, pending_node)
			h.eq("%s：进入节点 %s（kind=%s）后落在对应界面" % [character_id, pending_node, kind_now],
				screen_name, _screen_for_kind(kind_now))
			if RunNodeState.BATTLE_KINDS.has(kind_now):
				battle_nodes += 1
			pending_node = ""
		if screen_name == GameConstants.SCREEN_MAP:
			var next_id := _next_node(shell)
			if next_id.is_empty():
				h.check("%s：地图上还有可进入的节点" % character_id, false, "step=%d" % step)
				break
			pending_node = next_id
			if _step(h, shell, log, "node:" + next_id, "进入节点 %s" % next_id):
				pass
			continue
		if screen_name == GameConstants.SCREEN_BATTLE:
			if shell.has_button("battle:start") and not shell.button_disabled("battle:start"):
				var node_id := String(shell.view.get("current_node_id", ""))
				var enc := String(_view_dict(shell.view, "battle").get("encounter_id", ""))
				_step(h, shell, log, "battle:start", "战斗界面接管（遭遇 %s）" % enc)
				if _node_kind(shell, node_id) == RunNodeState.KIND_BOSS:
					boss_encounter = enc
				var drive := _drive_screen(screen)
				real_battles += 1
				_log(log, "  战斗界面驱动：%d 次循环 / %d 个已提交动作 / 结果 %s"
					% [int(drive.get("guard", 0)), screen.submitted_actions().size(), str(screen.outcome())])
				h.check("%s：这一场由界面 API 驱动到结束" % character_id, bool(screen.is_finished()))
				h.check("%s：界面输入数 > 3（不是空跑）" % character_id, screen.submitted_actions().size() > 3,
					"动作数=%d" % screen.submitted_actions().size())
				var outcome: Dictionary = shell.last_battle_outcome
				h.check("%s：shell 收到了 BattleOutcome" % character_id, not outcome.is_empty())
				if String(outcome.get("result", "")) != GameConstants.OUTCOME_WON:
					h.check("%s：这一场打赢了（试玩要求走到学期结束）" % character_id, false,
						"result=%s reason=%s" % [str(outcome.get("result")), str(outcome.get("reason"))])
					break
				continue
			_step(h, shell, log, "battle:leave", "战斗结算：离开节点")
			continue
		if screen_name == GameConstants.SCREEN_REWARD:
			var uid := _first_enabled_prefix(shell, "reward:", "reward:leave")
			if _first_enabled_prefix(shell, "reward:leave").is_empty() and not uid.is_empty():
				_step(h, shell, log, uid, "领奖励")
				continue
			_step(h, shell, log, "reward:leave", "奖励处理完 → 离开节点")
			continue
		if screen_name == GameConstants.SCREEN_SHOP:
			var buy := _first_enabled_prefix(shell, "shop:buy:")
			if not _shop_visited_once(shell) and not buy.is_empty():
				_step(h, shell, log, buy, "商店购买（至少成交一次）")
				continue
			_step(h, shell, log, "shop:leave", "离开商店")
			continue
		if screen_name == GameConstants.SCREEN_EVENT:
			var option := _first_enabled_prefix(shell, "event:", "event:leave")
			if option.is_empty():
				option = "event:leave"
			if not _step(h, shell, log, option, "事件选项 / 离开"):
				break
			continue
		if screen_name == GameConstants.SCREEN_REST:
			if shell.has_button("rest:leave") and not shell.button_disabled("rest:leave"):
				_step(h, shell, log, "rest:leave", "休息完毕 → 继续")
				continue
			_step(h, shell, log, "rest:take:heal", "休息：恢复精力")
			continue
		term_path = shell.session.run.node_path.duplicate()
		if screen_name == GameConstants.SCREEN_TERM:
			var term_uid := _first_enabled_prefix(shell, "term:", "term:menu")
			h.check("%s：学期结算有可点步骤" % character_id, not term_uid.is_empty())
			if term_uid.is_empty():
				break
			_step(h, shell, log, term_uid, "学期结算")
			break
		h.check("%s：走到了一学期的某个可处理界面" % character_id, false, "stuck at %s" % screen_name)
		break

	var run_state = shell.session.run
	h.eq("%s：走完第 1 学期 6 个节点" % character_id, term_path.size(), 6)
	h.eq("%s：路径按层推进" % character_id, _layers_of(term_path), [1, 2, 3, 4, 5, 6])
	h.check("%s：一路上打过战斗（真实界面驱动）" % character_id, real_battles >= 2, "real=%d" % real_battles)
	h.eq("%s：每个战斗节点都被打过" % character_id, real_battles, battle_nodes)
	h.check("%s：到达并开打了首领节点" % character_id, not boss_encounter.is_empty(), "encounter=%s" % boss_encounter)
	h.check("%s：首领遭遇在出厂清单里且是 boss 类" % character_id,
		db.is_enabled(GameConstants.KIND_ENCOUNTER, boss_encounter)
		and String(db.definition(GameConstants.KIND_ENCOUNTER, boss_encounter).get("kind", "")) == "boss",
		"encounter=%s" % boss_encounter)
	h.check("%s：本局没有失败（试玩要求走到第一学期完成）" % character_id, String(run_state.outcome).is_empty(),
		"outcome=%s" % run_state.outcome)
	h.eq("%s：第一学期结算后进入第 2 学期" % character_id, run_state.term, 2)
	h.check("%s：经过奖励页" % character_id, visited.has(GameConstants.SCREEN_REWARD))
	h.check("%s：经过商店页" % character_id, visited.has(GameConstants.SCREEN_SHOP))
	h.check("%s：经过休息页" % character_id, visited.has(GameConstants.SCREEN_REST))
	if visited.has(GameConstants.SCREEN_EVENT):
		h.check("%s：经过事件页（出厂清单已启用事件组）" % character_id, true)
	var log_path := _write_log(character_id, log)
	h.check("%s：试玩日志已落盘" % character_id, not log_path.is_empty(), log_path)
	print("[试玩] %s 一学期完成，真实战斗 %d 场（含首领 %s）；日志：%s" % [character_id, real_battles, boss_encounter, log_path])
	_cleanup(shell)
	screen.queue_free()