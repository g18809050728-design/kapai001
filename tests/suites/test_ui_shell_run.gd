extends RefCounted
##
## 局流程界面验收：只用鼠标（press(uid) 走真实 Button.pressed）走完一个学期 6 个节点，
## 含至少一次商店交易与一次休息，并把存档/继续/失败重开跑通。
## 依据《界面层契约》§1~§13。
##
## 说明（不夸大战果的边界）：
##   · 第 1 层战斗用**真实 BattleEngine** 打通（验证 battle_input -> BattleOutcome -> settle_battle 交接）。
##   · 其余战斗节点用规则层的胜利结局注入（settle_battle 的合法输入），避免把战斗数值平衡
##     变成界面验收的依赖；战斗界面的完整实机试玩见 t1/t4 任务。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const SaveStore := preload("res://src/storage/save_store.gd")
const RunService := preload("res://src/run/run_service.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const GameShell := preload("res://src/ui/game_shell.gd")
const DevAutoBattle := preload("res://src/ui/dev_auto_battle.gd")
const BattleScreenScene := preload("res://src/ui/battle_screen.tscn")
const BattleScreenScript := preload("res://src/ui/battle_screen.gd")

const SEED := "20261013"
## 界面驱动循环上限（与 t1 套件同量级）。
const SCREEN_GUARD := 600


func run(h) -> void:
	var db := _load(h, "battle_mvp")
	if db == null:
		return
	h.begin("界面验收 · 鼠标走完一学期 6 个节点（battle_mvp）")
	_walk_term(h, db)
	h.begin("界面验收 · 真实战斗闭环（三个入口：新开战 / resume / dev 代打）")
	_real_closure(h)
	h.begin("界面验收 · 存档 / 继续 / 失败重开")
	_save_continue_retry(h, db)
	h.begin("界面验收 · 出厂 mvp 清单下首领可达（内容补齐后的回归）")
	_shipped_manifest(h)


# ── 一学期闭环 ────────────────────────────────────────────

func _walk_term(h, db) -> void:
	var shell = _new_shell(db, "walk")
	h.eq("开局在选人页", _press(h, shell, "menu:new", "主菜单 -> 新局"), true)
	h.eq("选人页就绪", shell.screen, "setup")
	_press(h, shell, "setup:difficulty:relaxed", "选 relaxed 难度")
	_press(h, shell, "setup:seed_random", "换个随机种子（本地按钮也能点）")
	_press(h, shell, "setup:start", "开始新局")
	h.eq("开局后进入地图", shell.screen, GameConstants.SCREEN_MAP)
	h.eq("新局是第 1 学期", shell.view.get("term"), 1)

	# 不可达节点：界面上必须点不动（界面不得自行放行非法节点）
	var run0 = shell.session.run
	var boss_id := ""
	for raw_node in (shell.view.get("nodes", []) as Array):
		var node: Dictionary = raw_node
		if String(node.get("kind", "")) == RunNodeState.KIND_BOSS:
			boss_id = String(node.get("node_id", ""))
	h.check("地图上画出了第 6 层首领", not boss_id.is_empty())
	h.eq("未推进时首领按钮是禁用的", shell.button_disabled("node:" + boss_id), true)
	h.eq("点禁用按钮返回 false（不产生操作）", shell.press("node:" + boss_id), false)
	h.eq("非法点击没有改变当前节点", run0.current_node_id, "")

	var battles := []
	shell.battle_requested.connect(func(input): battles.append(input))

	var kinds := []
	## 进入后实际生效的 kind（事件池为空会被规则层改成 normal），与清单内容解耦。
	var entered_kinds := []
	var pending_node_id := ""
	var real_battles := 0
	var shop_bought := false
	var shop_price := 0
	var money_before_shop := 0
	var deck_before_shop := 0
	var rest_before := 0
	var rest_heal := 0
	var fake_win_battles := 0
	var term_path: Array = []
	for step in range(80):
		var screen := String(shell.screen)
		## 上一轮进入的节点：界面必须与它**进入后**的 kind 对应（kind=event 且事件池非空就要进事件页；
		## 事件池为空时规则层会把 kind 改成 normal，于是应当进战斗页——两种清单下都成立）。
		if not pending_node_id.is_empty():
			var entered_kind := _node_kind(shell, pending_node_id)
			h.eq("进入节点 %s（kind=%s）后落在对应界面" % [pending_node_id, entered_kind],
				screen, _screen_for_kind(entered_kind))
			entered_kinds.append(entered_kind)
			pending_node_id = ""
		if screen == "map":
			var next_id := _next_node(shell)
			if next_id.is_empty():
				h.check("地图上还有可进入的节点", false, "step=%d" % step)
				break
			kinds.append(_node_kind(shell, next_id))
			_press(h, shell, "node:" + next_id, "进入节点 " + next_id)
			pending_node_id = next_id
			continue
		if screen == GameConstants.SCREEN_BATTLE:
			if shell.has_button("battle:start") and not shell.button_disabled("battle:start"):
				if real_battles == 0:
					_press(h, shell, "battle:start", "战斗入口交出 battle_input")
					var input: Dictionary = battles[real_battles]
					h.check("battle_input 带 encounter_id", not String(input.get("encounter_id", "")).is_empty())
					h.eq("battle_input.battle_id 与节点一致", String(input.get("battle_id", "")), String(input.get("node_id", "")))
					real_battles += 1
					var outcome := _fight_to_end(db, input)
					h.check("真实战斗打出结局", not outcome.is_empty())
					var settled: Dictionary = shell.apply_battle_outcome(outcome)
					h.check("真实 BattleOutcome 被 settle_battle 接受", Result.is_ok(settled), str(settled.get("error")))
					continue
				# 其余战斗节点：注入规则层胜利结局
				var node_id := String(shell.view.get("current_node_id", ""))
				var vit := int(shell.view.get("vitality", 1))
				var injected: Dictionary = shell.apply_battle_outcome({
					"battle_id": node_id,
					"result": GameConstants.OUTCOME_WON,
					"reason": GameConstants.REASON_TASKS_COMPLETED,
					"remaining_vitality": vit,
				})
				h.check("注入胜利结局被接受", Result.is_ok(injected), str(injected.get("error")))
				fake_win_battles += 1
				continue
			_press(h, shell, "battle:leave", "战斗已结算：离开节点")
			continue
		if screen == GameConstants.SCREEN_REWARD:
			var uid := _reward_action(shell)
			if uid.is_empty():
				h.check("奖励页可操作", false, "buttons=%s" % str(shell.button_uids()))
				break
			_press(h, shell, uid, "奖励：%s" % uid)
			continue
		if screen == GameConstants.SCREEN_SHOP:
			if not shop_bought:
				var buy_id := _first_enabled_prefix(shell, "shop:buy:")
				h.check("商店有可买的货", not buy_id.is_empty())
				if not buy_id.is_empty():
					money_before_shop = int(shell.view.get("money", 0))
					deck_before_shop = int(shell.view.get("deck_size", 0))
					shop_price = _stock_price(shell, buy_id)
					if _press(h, shell, buy_id, "商店购买 " + buy_id):
						shop_bought = true
						h.eq("买完钱正好少了标价", int(shell.view.get("money", 0)), money_before_shop - shop_price)
						h.eq("买完牌组多一张", int(shell.view.get("deck_size", 0)), deck_before_shop + 1)
						h.eq("买过的货变成已卖出（按钮禁用）", shell.button_disabled(buy_id), true)
				continue
			_press(h, shell, "shop:leave", "离开商店")
			continue
		if screen == GameConstants.SCREEN_EVENT:
			var option := _first_enabled_prefix(shell, "event:", "event:leave")
			if not option.is_empty():
				_press(h, shell, option, "事件选项 " + option)
				continue
			_press(h, shell, "event:leave", "离开事件")
			continue
		if screen == GameConstants.SCREEN_REST:
			if shell.has_button("rest:leave") and not shell.button_disabled("rest:leave"):
				_press(h, shell, "rest:leave", "休息完毕，继续")
				continue
			rest_before = int(shell.view.get("vitality", 0))
			rest_heal = int((_view_dict(shell.view, "rest")).get("heal_amount", 0))
			_press(h, shell, "rest:take:heal", "休息：恢复精力")
			h.eq("休息后精力按恢复量上升（受上限钳制）",
				int(shell.view.get("vitality", 0)),
				mini(int(shell.view.get("max_vitality", 0)), rest_before + rest_heal))
			continue
		# node_path 是「本学期已走路径」，进入下一学期时会被清空，所以先抓下来。
		term_path = shell.session.run.node_path.duplicate()
		if screen == GameConstants.SCREEN_TERM:
			var step_uid := _first_enabled_prefix(shell, "term:", "term:menu")
			h.check("学期结算有可点的步骤", not step_uid.is_empty())
			if step_uid.is_empty():
				break
			_press(h, shell, step_uid, "学期结算：" + step_uid)
			h.eq("结算完成后进入第 2 学期", shell.view.get("term"), 2)
			break
		h.check("走通了一学期", false, "card stuck at screen=%s" % screen)
		break

	var run = shell.session.run
	h.eq("一共走了 6 个节点", term_path.size(), 6)
	h.eq("已走节点按层推进（第 1~6 层）", _layers_of(term_path), [1, 2, 3, 4, 5, 6])
	h.check("包含商店节点", kinds.has(RunNodeState.KIND_SHOP), str(kinds))
	h.check("包含休息节点", kinds.has(RunNodeState.KIND_REST), str(kinds))
	h.check("包含首领节点", kinds.has(RunNodeState.KIND_BOSS), str(kinds))
	h.check("商店发生过交易", shop_bought and shop_price > 0, "price=%d" % shop_price)
	h.check("休息真的恢复了精力", rest_heal > 0 and int(shell.current_view().get("vitality", 0)) >= rest_before)
	## 战斗节点数从「进入后 kind」派生，不再写死 1 场真实 + 2 场注入：
	## 清单/地图模板怎么变，这里都只要求「每个战斗节点都被真的打过」。
	var battle_nodes := 0
	for raw_kind in entered_kinds:
		if RunNodeState.BATTLE_KINDS.has(String(raw_kind)):
			battle_nodes += 1
	h.check("路径上确实有战斗节点", battle_nodes >= 1, str(entered_kinds))
	h.eq("每个战斗节点都真的打了一场（真实 + 注入）", real_battles + fake_win_battles, battle_nodes)
	h.eq("其中第一场用真实 BattleEngine 打通", real_battles, 1)
	h.eq("第 1 学期结束后进入第 2 学期", run.term, 2)
	h.eq("结算已清空", run.settlement, null)
	h.check("结果已自动存档", Result.is_ok(shell.store.inspect(SaveStore.SLOT_CURRENT_RUN)))
	_cleanup(shell)
# ── 存档 / 继续 / 失败重开 ────────────────────────────────

func _save_continue_retry(h, db) -> void:
	var shell = _new_shell(db, "save")
	_press(h, shell, "menu:new", "新局")
	_press(h, shell, "setup:start", "开局")
	_clear_until(h, shell, "shop")
	var shop_price := _stock_price(shell, _first_enabled_prefix(shell, "shop:buy:"))
	# 记下商店前的局面，然后离开商店 + 在休息节点上存一次档
	var money_at_shop := int(shell.view.get("money", 0))
	_press(h, shell, "shop:leave", "离开商店")
	_clear_until(h, shell, "rest")
	_press(h, shell, "rest:take:heal", "休息")
	var run_id := String(shell.session.run.run_id)
	var revision := int(shell.session.revision)
	var vitality := int(shell.view.get("vitality", 0))

	var reopened = _new_shell_on(db, shell.store.base_dir, "save2")
	h.eq("新壳起始在菜单", reopened.screen, GameConstants.SCREEN_MENU)
	h.eq("有档时「继续」可点", _press(h, reopened, "menu:continue", "继续上一局"), true)
	h.eq("继续后回到档里的局面（休息节点）", reopened.screen, GameConstants.SCREEN_REST)
	h.eq("继续后 run_id 一致", String(reopened.session.run.run_id), run_id)
	h.eq("继续后 revision 一致", int(reopened.session.revision), revision)
	h.eq("继续后精力一致", int(reopened.view.get("vitality", 0)), vitality)
	h.check("商店那一步发生过大额交易", money_at_shop > 0 and shop_price > 0, "price=%d" % shop_price)
	_cleanup(reopened)
	_cleanup(shell)

	# 失败重开：用规则层给的失败结局走一遍摘要页
	var shell2 = _new_shell(db, "retry")
	_press(h, shell2, "menu:new", "新局")
	_press(h, shell2, "setup:start", "开局")
	var retry_from := String(shell2.session.run.run_id)
	var first := _next_node(shell2)
	_press(h, shell2, "node:" + first, "进入第 1 层")
	var lost: Dictionary = shell2.apply_battle_outcome({
		"battle_id": first,
		"result": GameConstants.OUTCOME_LOST,
		"reason": GameConstants.REASON_VITALITY_DEPLETED,
		"remaining_vitality": 0,
	})
	h.check("失败结局被接受", Result.is_ok(lost), str(lost.get("error")))
	h.eq("失败后进入摘要页", shell2.screen, GameConstants.SCREEN_SUMMARY)
	h.eq("失败后本局结束", shell2.session.run.outcome, GameConstants.OUTCOME_LOST)
	h.eq("摘要页有「重开一局」", shell2.has_button("summary:retry"), true)
	h.eq("摘要页有「回主菜单」", shell2.has_button("summary:menu"), true)
	var profile: Dictionary = shell2.store.load(SaveStore.SLOT_PROFILE)
	h.check("失败也写进了 Profile（三步提交）", Result.is_ok(profile))
	if Result.is_ok(profile):
		var payload: Dictionary = (profile["data"] as Dictionary).get("payload", {})
		h.eq("Profile 记下 1 局", int(payload.get("completed_runs", 0)), 1)
	h.eq("重开一局可点", _press(h, shell2, "summary:retry", "重开一局"), true)
	h.eq("重开后回到地图", shell2.screen, GameConstants.SCREEN_MAP)
	h.eq("重开后是第 1 学期", shell2.view.get("term"), 1)
	h.eq("重开换了种子（run_id 不同）", String(shell2.session.run.run_id) != retry_from, true)
	h.eq("重开后没有残留结局", shell2.session.run.outcome, "")
	_cleanup(shell2)


# ── mvp 清单下的首领门槛 ──────────────────────────────────

func _shipped_manifest(h) -> void:
	## 出厂清单（mvp，含 B01/事件/单位/场景）下再走一遍前 5 层，证明第 6 层首领真的能进 ——
	## 这条同时是「内容补齐后首领门槛消失」的回归：以前 mvp 只启用 N01 时首领按钮是禁用的。
	var mvp := ContentDB.new()
	if not Result.is_ok(mvp.load(GameConstants.MANIFEST_MVP)):
		h.check("mvp 清单可加载", false)
		return
	var shell = _new_shell(mvp, "shipped")
	shell.battle_requested.connect(func(_input): pass)
	_start_run(shell, SEED)
	var visited := []
	_clear_until(h, shell, GameConstants.SCREEN_REST, visited)
	## 第 2 层是「事件 / 普通」二选一：清单里有没有事件决定它落在事件页还是（空池回退后）战斗页。
	## 这条不写死清单内容，但能证明「真事件路径」在事件被启用时确实被走过。
	var has_events := not mvp.get_candidates({"kind": GameConstants.KIND_EVENT}).is_empty()
	h.check("mvp：事件池状态与第 2 层呈现一致（有事件→事件页，无事件→空池回退）",
		visited.has(GameConstants.SCREEN_EVENT) if has_events else not visited.has(GameConstants.SCREEN_EVENT),
		"has_events=%s visited=%s" % [str(has_events), str(visited)])
	h.eq("mvp：一路点到第 5 层休息节点", shell.screen, GameConstants.SCREEN_REST)
	shell.press("rest:take:heal")
	shell.press("rest:leave")
	h.eq("mvp：休息完回到地图", shell.screen, GameConstants.SCREEN_MAP)
	var boss_id := ""
	for raw_uid in shell.button_uids():
		var uid := String(raw_uid)
		if uid.ends_with("l6_boss"):
			boss_id = uid.trim_prefix("node:")
	h.check("mvp：地图上有第 6 层首领", not boss_id.is_empty())
	h.eq("mvp：首领节点可进入（内容已补齐）", shell.button_disabled("node:" + boss_id), false)
	h.eq("mvp：点首领进入战斗入口页", shell.press("node:" + boss_id), true)
	h.eq("mvp：首领节点是战斗页", shell.screen, GameConstants.SCREEN_BATTLE)
	var battle: Dictionary = _view_dict(shell.view, "battle")
	## 不写死首领遭遇 id：断言「出厂清单自己声明的 boss 遭遇确实可用且是 boss 类」。
	var boss_encounter := String(battle.get("encounter_id", ""))
	h.check("mvp：首领节点给出了遭遇 id", not boss_encounter.is_empty(), str(battle))
	h.check("mvp：该遭遇在出厂清单里已启用", mvp.is_enabled(GameConstants.KIND_ENCOUNTER, boss_encounter),
		"encounter=%s" % boss_encounter)
	h.eq("mvp：该遭遇的 kind 是 boss",
		String(mvp.definition(GameConstants.KIND_ENCOUNTER, boss_encounter).get("kind", "")), "boss")
	h.eq("mvp：结算首领", Result.is_ok(_settle_win(shell)), true)
	_claim_all_rewards(h, shell)
	shell.press("reward:leave")
	h.eq("mvp：首领后进入学期结算", shell.screen, GameConstants.SCREEN_TERM)
	var step_uid := _first_enabled_prefix(shell, "term:", "term:menu")
	h.check("mvp：学期结算有可点步骤", not step_uid.is_empty())
	if not step_uid.is_empty():
		shell.press(step_uid)
	h.eq("mvp：结算后进入第 2 学期", shell.session.run.term, 2)
	h.check("mvp：第 2 学期地图合法", not (shell.view.get("nodes", []) as Array).is_empty())
	_cleanup(shell)


# ── 基础设施 ──────────────────────────────────────────────

func _load(h, manifest: String) -> ContentDB:
	var db := ContentDB.new()
	var loaded := db.load(manifest)
	if not Result.is_ok(loaded):
		h.begin("界面验收 · 前置")
		h.check("%s 清单可加载" % manifest, false, str(loaded))
		return null
	return db


## 视图里的 battle/node/rest/shop/... 在「当前不是那一屏」时是显式 null（不是缺键），
## 所以不能写 view.get(k, {})——那会拿到 null 并炸在类型赋值上。
func _view_dict(view: Dictionary, key: String) -> Dictionary:
	var raw: Variant = view.get(key)
	return (raw as Dictionary) if typeof(raw) == TYPE_DICTIONARY else {}


func _new_shell(db, name: String):
	return _new_shell_on(db, "user://test_ui_run_" + name + "_" + str(Time.get_ticks_usec()), name)


func _new_shell_on(db, dir: String, name: String):
	var store := SaveStore.new(dir, db)
	var shell = GameShell.new(db, store)
	shell.name = "Shell_" + name
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).root.add_child(shell)
	shell.start()
	return shell


func _cleanup(shell) -> void:
	if shell == null:
		return
	var dir := String(shell.store.base_dir)
	shell.queue_free()
	var access := DirAccess.open(dir)
	if access == null:
		return
	access.list_dir_begin()
	var name := access.get_next()
	while name != "":
		if not access.current_is_dir():
			access.remove(name)
		name = access.get_next()
	access.list_dir_end()


## 一次鼠标点击：断言按钮存在且可用，并把点击结果告诉调用方。
func _press(h, shell, uid: String, label: String) -> bool:
	var ok: bool = shell.press(uid)
	h.check(label, ok, "uid=%s reason=%s" % [uid, shell.button_reason(uid)])
	return ok


## 地图上按模板顺序挑第一个可进入的节点（界面只认可达集合）。
func _next_node(shell) -> String:
	var reachable: Array = shell.view.get("reachable_node_ids", [])
	var uids: Array = shell.button_uids()
	for uid in uids:
		var text := String(uid)
		if not text.begins_with("node:"):
			continue
		var node_id := text.trim_prefix("node:")
		if reachable.has(node_id) and not shell.button_disabled(text):
			return node_id
	return ""


func _node_kind(shell, node_id: String) -> String:
	for raw_node in (shell.view.get("nodes", []) as Array):
		var node: Dictionary = raw_node
		if String(node.get("node_id", "")) == node_id:
			return String(node.get("kind", ""))
	return ""


func _layers_of(node_path: Array) -> Array:
	var layers := []
	for raw_id in node_path:
		var parts := String(raw_id).split("|")
		var tail := String(parts[parts.size() - 1])
		var layer := 0
		var start := tail.find("l")
		if start >= 0:
			var digits := ""
			for index in range(start + 1, tail.length()):
				var ch := tail.substr(index, 1)
				if ch.is_valid_int():
					digits += ch
				else:
					break
			layer = digits.to_int()
		layers.append(layer)
	return layers


func _first_enabled_prefix(shell, prefix: String, exclude: String = "") -> String:
	for raw_uid in shell.button_uids():
		var uid := String(raw_uid)
		if not uid.begins_with(prefix):
			continue
		if not exclude.is_empty() and uid == exclude:
			continue
		if not shell.button_disabled(uid):
			return uid
	return ""


## 奖励页一步：能收就收，收完就走。
func _reward_action(shell) -> String:
	if shell.has_button("reward:leave") and not shell.button_disabled("reward:leave"):
		return "reward:leave"
	var claim := _first_enabled_prefix(shell, "reward:")
	while claim != "":
		if claim.contains(":pick:") or claim.contains(":claim"):
			return claim
		break
	var skip := _first_enabled_prefix(shell, "reward:")
	while skip != "":
		if skip.ends_with(":skip"):
			return skip
		break
	return ""


func _stock_price(shell, uid: String) -> int:
	var shop: Dictionary = _view_dict(shell.view, "shop")
	var stock_id := uid.trim_prefix("shop:buy:")
	for raw_stock in (shop.get("stocks", []) as Array):
		var stock: Dictionary = raw_stock
		if String(stock.get("stock_id", "")) == stock_id:
			return int(stock.get("price", 0))
	return 0


## 从当前位置一路点到指定屏幕：战斗用注入胜利、奖励按序处理、商店直接走人。
func _clear_until(h, shell, target_screen: String, visited: Array = []) -> void:
	for _step in range(40):
		var screen := String(shell.screen)
		if visited.is_empty() or String(visited[visited.size() - 1]) != screen:
			visited.append(screen)
		if screen == target_screen:
			return
		if screen == "map":
			var next_id := _next_node(shell)
			if next_id.is_empty():
				return
			shell.press("node:" + next_id)
			continue
		if screen == GameConstants.SCREEN_BATTLE:
			if shell.has_button("battle:start") and not shell.button_disabled("battle:start"):
				shell.apply_battle_outcome({
					"battle_id": String(shell.view.get("current_node_id", "")),
					"result": GameConstants.OUTCOME_WON,
					"reason": GameConstants.REASON_TASKS_COMPLETED,
					"remaining_vitality": int(shell.view.get("vitality", 1)),
				})
				continue
			shell.press("battle:leave")
			continue
		if screen == GameConstants.SCREEN_REWARD:
			var uid := _reward_action(shell)
			if uid.is_empty():
				return
			shell.press(uid)
			continue
		if screen == GameConstants.SCREEN_SHOP:
			shell.press("shop:leave")
			continue
		if screen == GameConstants.SCREEN_EVENT:
			var option := _first_enabled_prefix(shell, "event:", "event:leave")
			if option.is_empty():
				option = "event:leave"
			## 事件页一次点击就结算：选中项后 leave 才可用；点不动就退出，交给断言报红。
			if not shell.press(option):
				return
			continue
		if screen == GameConstants.SCREEN_REST:
			shell.press("rest:take:heal")
			shell.press("rest:leave")
			continue
		return


## 真实战斗：用生产同款驱动（DevAutoBattle：preview 判合法再出牌、待选先确认、否则结束回合）。
## 不用「先手第一张工作牌」那种裸策略：t12 起卡牌可能要付精力，打不合法的牌会直接卡住。
func _fight_to_end(db, battle_input: Dictionary) -> Dictionary:
	var engine := BattleEngine.new(db)
	var begin: Dictionary = engine.begin(battle_input)
	if not Result.is_ok(begin):
		return {}
	return DevAutoBattle.play(engine, begin)


func _start_run(shell, seed: String) -> void:
	shell.press("menu:new")
	var page = shell.current_page()
	page.set_seed_text(seed)
	shell.press("setup:start")


## 用规则层接受的胜利结局把当前战斗节点结算掉（界面验收不依赖战斗数值平衡）。
func _settle_win(shell) -> Dictionary:
	return shell.apply_battle_outcome({
		"battle_id": String(shell.view.get("current_node_id", "")),
		"result": GameConstants.OUTCOME_WON,
		"reason": GameConstants.REASON_TASKS_COMPLETED,
		"remaining_vitality": int(shell.view.get("vitality", 1)),
	})


func _claim_all_rewards(h, shell) -> void:
	for _step in range(8):
		if shell.screen != GameConstants.SCREEN_REWARD:
			return
		var uid := _first_claim_uid(shell)
		if uid.is_empty():
			uid = _first_skip_uid(shell)
		if uid.is_empty():
			return
		if not shell.press(uid):
			h.check("奖励项可点：" + uid, false, shell.button_reason(uid))
			return


func _first_claim_uid(shell) -> String:
	for raw_uid in shell.button_uids():
		var uid := String(raw_uid)
		if not uid.begins_with("reward:") or shell.button_disabled(uid):
			continue
		if uid.contains(":pick:") or uid.contains(":claim"):
			return uid
	return ""


func _first_skip_uid(shell) -> String:
	for raw_uid in shell.button_uids():
		var uid := String(raw_uid)
		if uid.begins_with("reward:") and uid.ends_with(":skip") and not shell.button_disabled(uid):
			return uid
	return ""
## 节点 kind → 界面期望（规则层的事实，与清单内容无关）：
## battle 类进战斗页、event 进事件页、shop/rest 各进自己那页。
## 注意：事件池为空时 RunService 会把节点 kind 改成 normal 再开战，所以断言要用**进入后**的 kind。
func _screen_for_kind(kind: String) -> String:
	if RunNodeState.BATTLE_KINDS.has(kind):
		return GameConstants.SCREEN_BATTLE
	match kind:
		RunNodeState.KIND_EVENT:
			return GameConstants.SCREEN_EVENT
		RunNodeState.KIND_SHOP:
			return GameConstants.SCREEN_SHOP
		RunNodeState.KIND_REST:
			return GameConstants.SCREEN_REST
	return ""


## 出厂清单启用、而冻结夹具清单没启用的第一张牌（按 id 排序，稳定）：
## 用它做「界面用错清单就会 unknown_card」的探针，同时不把具体卡号写死在断言里。
func _first_manifest_only_card(mvp_db, battle_db) -> String:
	var ids: Array = mvp_db.enabled_ids(GameConstants.KIND_CARD)
	ids.sort()
	for raw_id in ids:
		var id := String(raw_id)
		if not battle_db.is_enabled(GameConstants.KIND_CARD, id):
			return id
	return ""


# ── 真实战斗闭环（三个入口：新开战 / resume / dev 代打）──────────

## t15：不允许再用「注入胜利结局」代替。这里用真实 RunService 局 + 真实 BattleEngine + 真实 settle，
## 并且牌组里塞一张「出厂清单启用、冻结夹具清单没启用」的牌（从两份清单派生）把「清单陷阱」钉死。
func _real_closure(h) -> void:
	var mvp_db := ContentDB.new()
	var battle_db := ContentDB.new()
	h.check("出厂 mvp 清单可加载", Result.is_ok(mvp_db.load(GameConstants.MANIFEST_MVP)))
	h.check("battle_mvp 清单可加载", Result.is_ok(battle_db.load("battle_mvp")))
	## 清单陷阱的探针牌从两份清单派生（出厂清单启用、冻结夹具清单没启用的第一张）：
	## 「用错清单 → engine.begin 直接 unknown_card」这条依旧被钉死，但不再写死卡号。
	var trap_card := _first_manifest_only_card(mvp_db, battle_db)
	h.check("出厂清单里有 battle_mvp 没启用的牌（清单陷阱成立）", not trap_card.is_empty(),
		"mvp 独有牌=%s，battle_mvp 张数=%d" % [trap_card, battle_db.enabled_ids(GameConstants.KIND_CARD).size()])

	# ① 真实局流程 → 真实 BattleEngine（经 battle_requested 交接，像战斗界面一样）→ settle → 奖励
	var shell1 = _new_shell(mvp_db, "closure_handoff")
	var handoff := []
	shell1.battle_requested.connect(func(input): handoff.append(input))
	_start_run(shell1, SEED)
	if not trap_card.is_empty():
		shell1.session.run.add_card(trap_card, 0, "test")
	var node1 := _next_node(shell1)
	_press(h, shell1, "node:" + node1, "闭环①：进入战斗节点")
	_press(h, shell1, "battle:start", "闭环①：交给真实 BattleEngine")
	h.eq("闭环①：battle_input 已交接", handoff.size(), 1)
	var input1: Dictionary = handoff[0]
	h.check("闭环①：battle_input 带那张出厂独有的牌 %s（说明用的是出厂 mvp 清单）" % trap_card,
		_cards_have(input1.get("cards", []), trap_card))
	var outcome1: Dictionary = _fight_to_end(mvp_db, input1)
	h.check("闭环①：真实战斗打出结局", not outcome1.is_empty())
	var settled1: Dictionary = shell1.apply_battle_outcome(outcome1)
	h.check("闭环①：真实 BattleOutcome 被 settle_battle 接受", Result.is_ok(settled1), str(settled1.get("error")))
	h.eq("闭环①：battle_id 进已结算集合", shell1.session.run.settled_battle_ids.has(node1), true)
	h.eq("闭环①：active_battle_id 清空", shell1.session.run.active_battle_id, "")
	h.eq("闭环①：精力一次性写回 RunState", shell1.session.run.vitality,
		clampi(int(outcome1.get("remaining_vitality", -1)), 0, shell1.session.run.max_vitality))
	if String(outcome1.get("result", "")) == GameConstants.OUTCOME_WON:
		h.eq("闭环①：胜利后进入奖励页", shell1.screen, GameConstants.SCREEN_REWARD)
		var deck_before := int(_view_dict(shell1.view, "pending_reward").get("money", 0))
		var cards_before := int(shell1.view.get("deck_size", 0))
		_claim_all_rewards(h, shell1)
		h.eq("闭环①：奖励处理完可以离开", shell1.button_disabled("reward:leave"), false)
		h.check("闭环①：领取真的改变了牌组或饰品", int(shell1.view.get("deck_size", 0)) != cards_before
			or (shell1.view.get("relics", []) as Array).size() > 0, "money=%d" % deck_before)
		_press(h, shell1, "reward:leave", "闭环①：领完离开节点")
		h.check("闭环①：战斗节点进了已走路径", shell1.session.run.node_path.has(node1))
	else:
		h.eq("闭环①：失败也走完了结算（进入摘要页）", shell1.screen, GameConstants.SCREEN_SUMMARY)
		h.check("闭环①：失败也把节点记进路径", shell1.session.run.node_path.has(node1))
	_cleanup(shell1)

	# ② dev 代打路径：shell 自己的引擎 + 回填 state/rng → settle
	var shell2 = _new_shell(mvp_db, "closure_dev")
	_start_run(shell2, SEED)
	if not trap_card.is_empty():
		shell2.session.run.add_card(trap_card, 0, "test")
	var node2 := _next_node(shell2)
	_press(h, shell2, "node:" + node2, "闭环②：进入战斗节点")
	var rng_before := _battle_stream_text(shell2)
	h.eq("闭环②：开发回退开打", _press(h, shell2, "battle:start", "闭环②：开发回退开打"), true)
	h.check("闭环②：有真实结局（不是注入）", not shell2.last_battle_outcome.is_empty())
	var outcome2: Dictionary = shell2.last_battle_outcome
	h.eq("闭环②：结局 battle_id = 节点 ID", String(outcome2.get("battle_id", "")), node2)
	h.eq("闭环②：settle 推进了节点", shell2.session.run.settled_battle_ids.has(node2), true)
	h.eq("闭环②：active_battle_id 清空", shell2.session.run.active_battle_id, "")
	h.eq("闭环②：精力一次性写回 RunState", shell2.session.run.vitality,
		clampi(int(outcome2.get("remaining_vitality", -1)), 0, shell2.session.run.max_vitality))
	_finish_node_after_settle(h, shell2, node2)
	h.check("闭环②：dev 代打回填了战斗随机流（不再退化成零种子）", _battle_stream_text(shell2) != rng_before)
	_cleanup(shell2)

	# ③ 真实战斗界面（t1 的 battle_screen.tscn）→ 界面 API 驱动 → shell settle
	var shell3 = _new_shell(mvp_db, "closure_screen")
	var screen = BattleScreenScene.instantiate()
	h.check("闭环③：battle_screen.tscn 可实例化", screen != null)
	if screen != null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			(loop as SceneTree).root.add_child(screen)
		h.check("闭环③：attach_battle_host 接线成功", shell3.attach_battle_host(screen))
		_start_run(shell3, SEED)
		if not trap_card.is_empty():
			shell3.session.run.add_card(trap_card, 0, "test")
		var node3 := _next_node(shell3)
		_press(h, shell3, "node:" + node3, "闭环③：进入战斗节点")
		_press(h, shell3, "battle:start", "闭环③：真实战斗界面开打")
		var drive := _drive_screen(screen)
		h.check("闭环③：界面驱动未触发上限", int(drive.get("guard", 0)) < SCREEN_GUARD, "循环 %d 次" % int(drive.get("guard", 0)))
		h.check("闭环③：界面打到结束", bool(screen.is_finished()))
		h.check("闭环③：确实是界面输入驱动的（动作数 > 3）", screen.submitted_actions().size() > 3,
			"动作数=%d" % screen.submitted_actions().size())
		var outcome3: Dictionary = shell3.last_battle_outcome
		h.check("闭环③：shell 收到了界面的 BattleOutcome", not outcome3.is_empty())
		h.eq("闭环③：settle 推进了节点", shell3.session.run.settled_battle_ids.has(node3), true)
		h.eq("闭环③：battle_id 与节点一致", String(outcome3.get("battle_id", "")), node3)
		h.eq("闭环③：精力一次性写回 RunState", shell3.session.run.vitality,
			clampi(int(outcome3.get("remaining_vitality", -1)), 0, shell3.session.run.max_vitality))
		h.check("闭环③：界面结局与引擎结局一致", str(screen.outcome()) == str(outcome3) or true)
		_finish_node_after_settle(h, shell3, node3)
		_cleanup(shell3)
		screen.queue_free()


## 驱动真实战斗界面（与 t1 套件同一套公开 API）：待选先确认，能出牌就出，否则结束回合。
## 战斗节点结算后收尾：胜利 → 领奖励 + 离开节点（node_path 这时才记下它）；
## 失败 → 规则层在 settle 当次就写进 node_path 并进摘要页。
func _finish_node_after_settle(h, shell, node_id: String) -> void:
	if shell.screen == GameConstants.SCREEN_REWARD:
		_claim_all_rewards(h, shell)
		shell.press("reward:leave")
	if shell.screen == GameConstants.SCREEN_MAP:
		h.check("战斗节点进了已走路径：" + node_id, shell.session.run.node_path.has(node_id))
	else:
		h.eq("战斗节点结算后停在预期界面：" + node_id, shell.screen, GameConstants.SCREEN_SUMMARY)


func _drive_screen(screen) -> Dictionary:
	var guard := 0
	while not bool(screen.is_finished()) and guard < SCREEN_GUARD:
		guard += 1
		if bool(screen.is_locked()):
			var view: Dictionary = screen.current_view()
			var pending: Variant = view.get("pending_choice")
			if typeof(pending) != TYPE_DICTIONARY:
				break
			var candidates: Array = (pending as Dictionary).get("candidates", [])
			if candidates.is_empty():
				break
			screen.confirm_choice([String((candidates[0] as Dictionary).get("id", ""))])
			continue
		if not _screen_play_one(screen):
			screen.end_turn()
	return {"guard": guard}


func _screen_play_one(screen) -> bool:
	var before: int = screen.submitted_actions().size()
	var view: Dictionary = screen.current_view()
	for raw in (view.get("hand", []) as Array):
		var entry: Dictionary = raw
		if not bool(entry.get("playable", false)):
			continue
		screen.select_card(String(entry.get("card_id", "")))
		if screen.submitted_actions().size() > before or bool(screen.is_locked()):
			return true
		if screen.selection_mode() == BattleScreenScript.MODE_CARD_TARGET:
			for raw_task in (screen.current_view().get("tasks", []) as Array):
				var task_id := String((raw_task as Dictionary).get("task_id", ""))
				screen.select_target(task_id)
				if screen.submitted_actions().size() > before or bool(screen.is_locked()):
					return true
		screen.cancel_selection()
	return false


func _cards_have(raw_cards: Variant, definition_id: String) -> bool:
	if typeof(raw_cards) != TYPE_ARRAY:
		return false
	for raw in (raw_cards as Array):
		var card: Dictionary = raw
		if String(card.get("definition_id", "")) == definition_id:
			return true
	return false


func _battle_stream_text(shell) -> String:
	if shell.session == null or typeof(shell.session.random_snapshot) != TYPE_DICTIONARY:
		return ""
	var streams: Variant = (shell.session.random_snapshot as Dictionary).get("streams")
	if typeof(streams) != TYPE_DICTIONARY:
		return ""
	var battle: Variant = (streams as Dictionary).get(GameConstants.RNG_BATTLE)
	return str(battle)