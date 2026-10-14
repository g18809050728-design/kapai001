extends RefCounted
##
## 页面冒烟（t2 验收）：每个页面都能消费视图、只产出合法草稿，
## 且按钮可用性与 RunService.preview 的门控一致（界面不得自行放行非法操作）。
## 依据《界面层契约》§1~§13。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const Ids := preload("res://src/common/ids.gd")
const SaveStore := preload("res://src/storage/save_store.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const GameShell := preload("res://src/ui/game_shell.gd")
const MapPage := preload("res://src/ui/page_map.gd")
const EventPage := preload("res://src/ui/page_event.gd")
const TermPage := preload("res://src/ui/page_term.gd")
const SummaryPage := preload("res://src/ui/page_summary.gd")
const EndingPage := preload("res://src/ui/page_ending.gd")
const RandomSource := preload("res://src/common/random_source.gd")

const SEED := "20261013"

const KIND_LABELS := {
	"normal": "普通作业",
	"elite": "精英作业",
	"boss": "期末大作业",
	"shop": "商店",
	"event": "突发事件",
	"rest": "休息",
}


func run(h) -> void:
	var db := ContentDB.new()
	var loaded := db.load("battle_mvp")
	if not Result.is_ok(loaded):
		h.begin("页面冒烟 · 前置")
		h.check("battle_mvp 清单可加载", false, str(loaded))
		return
	h.begin("页面冒烟 · 主菜单 / 设置 / 自动存档开关")
	_menu_and_settings(h, db)
	h.begin("页面冒烟 · 选人与开局")
	_setup(h, db)
	h.begin("页面冒烟 · 地图：节点与可达性门控")
	_map(h, db)
	h.begin("页面冒烟 · 奖励页")
	_reward(h, db)
	h.begin("页面冒烟 · 商店页")
	_shop(h, db)
	h.begin("页面冒烟 · 休息页与学期结算页")
	_rest_and_term(h, db)
	h.begin("页面冒烟 · 战斗入口与摘要页")
	_battle_and_summary(h, db)
	h.begin("页面冒烟 · 事件 / 结算 / 摘要 / 结局的离线渲染")
	_offline_pages(h)
	h.begin("页面冒烟 · 战斗随机快照回填（读档续战一致性）")
	_battle_rng(h, db)
	h.begin("页面冒烟 · 事件页：无选择选项与选卡目标（t15 回归）")
	_event_plain_option(h)
	h.begin("页面冒烟 · 按钮表不残留（回归）")
	_no_stale_buttons(h)


# ── 主菜单 / 设置 ─────────────────────────────────────────

func _menu_and_settings(h, db) -> void:
	var shell = _new_shell(db, "menu")
	h.eq("起始页是主菜单", shell.screen, GameConstants.SCREEN_MENU)
	h.check("主菜单四个入口都在", shell.has_button("menu:new") and shell.has_button("menu:continue")
		and shell.has_button("menu:settings") and shell.has_button("menu:quit"))
	h.eq("无档时「继续」禁用", shell.button_disabled("menu:continue"), true)
	h.eq("无档时点「继续」无效", shell.press("menu:continue"), false)
	h.eq("「新局」可点", _press(h, shell, "menu:new", "主菜单 -> 新局"), true)
	h.eq("进入选人页", shell.screen, "setup")
	h.eq("应回主菜单", _press(h, shell, "setup:back", "选人页 -> 回主菜单"), true)
	h.eq("回到主菜单", shell.screen, GameConstants.SCREEN_MENU)
	h.eq("「设置」可点", _press(h, shell, "menu:settings", "主菜单 -> 设置"), true)
	h.eq("进入设置页", shell.screen, "settings")
	var page = shell.current_page()
	h.eq("切到 hard 难度", _press(h, shell, "settings:difficulty:hard", "设置：难度 hard"), true)
	h.eq("难度已记录", String(page.current_settings().get("difficulty", "")), GameConstants.DIFFICULTY_HARD)
	page.set_seed_text("4242")
	page.set_autosave(false)
	h.eq("保存设置", _press(h, shell, "settings:save", "设置：保存"), true)
	var settings_snapshot: Dictionary = shell.store.load(SaveStore.SLOT_SETTINGS)
	h.check("设置文档已落盘", Result.is_ok(settings_snapshot))
	if Result.is_ok(settings_snapshot):
		var payload: Dictionary = (settings_snapshot["data"] as Dictionary).get("payload", {})
		h.eq("设置内容：难度", String(payload.get("difficulty", "")), GameConstants.DIFFICULTY_HARD)
		h.eq("设置内容：种子", String(payload.get("seed", "")), "4242")
		h.eq("设置内容：自动存档关", bool(payload.get("autosave", true)), false)

	# 新壳读同一份设置：证明「设置入口」走的是 SaveStore，而不是界面自己的内存。
	var shell2 = _new_shell_on(db, shell.store.base_dir, "menu2")
	h.eq("新壳读到难度 hard", String(shell2.settings.get("difficulty", "")), GameConstants.DIFFICULTY_HARD)
	h.eq("新壳读到自动存档关", bool(shell2.settings.get("autosave", true)), false)
	# 自动存档关掉后，开局不会写档；点「保存进度」才写。
	_press(h, shell2, "menu:new", "新局")
	var page2 = shell2.current_page()
	page2.set_seed_text(SEED)
	_press(h, shell2, "setup:start", "开局")
	h.eq("自动存档关：开局不写档", Result.error_code(shell2.store.load(SaveStore.SLOT_CURRENT_RUN)),
		GameConstants.ERROR_SAVE_NOT_FOUND)
	h.eq("手动保存可点", _press(h, shell2, "map:save", "地图：保存进度"), true)
	h.check("手动保存写了档", Result.is_ok(shell2.store.load(SaveStore.SLOT_CURRENT_RUN)))
	h.eq("存档后「继续」可点", shell2.has_button("map:save"), true)
	_cleanup(shell)
	_cleanup(shell2)


# ── 选人 ──────────────────────────────────────────────────

func _setup(h, db) -> void:
	var shell = _new_shell(db, "setup")
	_press(h, shell, "menu:new", "新局")
	var page = shell.current_page()
	h.check("列出了已启用人物 P01", shell.has_button("setup:character:P01"))
	h.eq("默认难度是 normal", String(page.selected().get("difficulty", "")), GameConstants.DIFFICULTY_NORMAL)
	_press(h, shell, "setup:character:P01", "选人物 P01")
	_press(h, shell, "setup:difficulty:relaxed", "选难度 relaxed")
	page.set_seed_text(SEED)
	var draft: Dictionary = page.action_draft("setup:start")
	h.eq("开局草稿类型", String(draft.get("type", "")), "create_run")
	var payload: Dictionary = draft.get("payload", {})
	h.eq("草稿：人物", String(payload.get("character_id", "")), "P01")
	h.eq("草稿：难度", String(payload.get("difficulty", "")), GameConstants.DIFFICULTY_RELAXED)
	h.eq("草稿：种子", String(payload.get("seed", "")), SEED)
	_press(h, shell, "setup:start", "开始新局")
	h.eq("开局进入地图", shell.screen, GameConstants.SCREEN_MAP)
	h.eq("难度写进局状态", shell.session.run.difficulty, GameConstants.DIFFICULTY_RELAXED)
	h.eq("种子原样交给规则层", shell.session.run.run_id, Ids.run_id_from_seed(SEED.to_int()))
	h.eq("开局即第 1 学期", shell.session.run.term, 1)
	h.check("开局自动写档", Result.is_ok(shell.store.load(SaveStore.SLOT_CURRENT_RUN)))
	_cleanup(shell)


# ── 地图 ──────────────────────────────────────────────────

func _map(h, db) -> void:
	var shell = _new_shell(db, "map")
	_press(h, shell, "menu:new", "新局")
	_press(h, shell, "setup:start", "开局")
	var nodes: Array = shell.view.get("nodes", [])
	var reachable: Array = shell.view.get("reachable_node_ids", [])
	h.eq("地图画一学期 8 个节点", nodes.size(), 8)
	h.eq("开局只有 1 个可达节点", reachable.size(), 1)
	var mismatched := []
	for raw_node in nodes:
		var node: Dictionary = raw_node
		var node_id := String(node.get("node_id", ""))
		var uid := "node:" + node_id
		var should_be_enabled: bool = reachable.has(node_id)
		if shell.button_disabled(uid) == should_be_enabled:
			mismatched.append(node_id)
		if not shell.button_text(uid).contains(String(KIND_LABELS.get(String(node.get("kind", "")), ""))):
			mismatched.append("label:" + node_id)
	h.check("每个节点的可用性 = 是否在可达集合里，且标签带类型名", mismatched.is_empty(), str(mismatched))
	var boss_id := ""
	for raw_node in nodes:
		var node: Dictionary = raw_node
		if String(node.get("kind", "")) == RunNodeState.KIND_BOSS:
			boss_id = String(node.get("node_id", ""))
	h.eq("首领未可达：按钮禁用", shell.button_disabled("node:" + boss_id), true)
	h.eq("首领未可达：点不动", shell.press("node:" + boss_id), false)
	h.eq("非法点击没有副作用", shell.session.run.current_node_id, "")
	h.check("地图上有保存/放弃/回主菜单", shell.has_button("map:save") and shell.has_button("map:abandon")
		and shell.has_button("map:menu"))
	# 放弃本局：确认前没有规则操作，确认后本局结束
	h.eq("放弃需要二次确认", _press(h, shell, "map:abandon", "点「放弃本局…」"), true)
	h.eq("确认按钮出现", shell.has_button("map:abandon_confirm"), true)
	h.eq("确认放弃可点（preview 通过）", _press(h, shell, "map:abandon_confirm", "确认放弃本局"), true)
	h.eq("本局结局 = abandoned", shell.session.run.outcome, GameConstants.OUTCOME_ABANDONED)
	h.eq("进入摘要页", shell.screen, GameConstants.SCREEN_SUMMARY)
	_press(h, shell, "summary:menu", "摘要页 -> 回主菜单")
	h.eq("回到主菜单", shell.screen, GameConstants.SCREEN_MENU)
	_cleanup(shell)
# ── 奖励 ──────────────────────────────────────────────────

func _reward(h, db) -> void:
	var shell = _new_shell(db, "reward")
	shell.battle_requested.connect(func(_input): pass)
	_start_run(shell, SEED)
	_clear_until(h, shell, "battle")
	h.eq("战斗入口页在等开打", shell.screen, GameConstants.SCREEN_BATTLE)
	h.eq("未结算时不能离开节点", shell.button_disabled("battle:leave"), true)
	_settle_win(shell)
	h.eq("结算后进入奖励页", shell.screen, GameConstants.SCREEN_REWARD)
	var deck_before := int(shell.view.get("deck_size", 0))
	var relics_before := (shell.view.get("relics", []) as Array).size()
	h.eq("还有未处理项时不能离开奖励页", shell.button_disabled("reward:leave"), true)
	var claimed := 0
	for _step in range(8):
		if shell.screen != GameConstants.SCREEN_REWARD:
			break
		var uid := _first_claim_uid(shell)
		if uid.is_empty():
			uid = _first_skip_uid(shell)
		if uid.is_empty():
			break
		var draft: Dictionary = shell.current_page().action_draft(uid)
		if not uid.ends_with(":skip"):
			h.eq("领取草稿类型", String(draft.get("type", "")), GameConstants.ACTION_CLAIM_REWARD)
			var payload: Dictionary = draft.get("payload", {})
			h.eq("领取草稿带 offer_id", String(payload.get("offer_id", "")),
				String((_view_dict(shell.view, "pending_reward")).get("offer_id", "")))
			if uid.contains(":pick:"):
				h.eq("候选按钮的草稿带上该候选", String(payload.get("candidate_id", "")), uid.get_slice(":", 3))
			claimed += 1
		h.eq("点得动：" + uid, shell.press(uid), true)
	h.check("至少领取了一项奖励", claimed >= 1)
	h.check("牌组或饰品增加了", int(shell.view.get("deck_size", 0)) > deck_before
		or (shell.view.get("relics", []) as Array).size() > relics_before)
	h.eq("处理完后可以离开", shell.button_disabled("reward:leave"), false)
	_press(h, shell, "reward:leave", "奖励处理完 -> 离开节点")
	h.eq("回到地图", shell.screen, GameConstants.SCREEN_MAP)
	h.eq("节点被记为已走", shell.session.run.node_path.size(), 1)
	_cleanup(shell)


# ── 商店 ──────────────────────────────────────────────────

func _shop(h, db) -> void:
	var shell = _new_shell(db, "shop")
	shell.battle_requested.connect(func(_input): pass)
	_start_run(shell, SEED)
	_clear_until(h, shell, "shop")
	h.eq("进入商店页", shell.screen, GameConstants.SCREEN_SHOP)
	var shop: Dictionary = _view_dict(shell.view, "shop")
	var stocks: Array = shop.get("stocks", [])
	h.check("商店有货架", not stocks.is_empty())
	var money := int(shell.view.get("money", 0))
	var mismatched := []
	for raw_stock in stocks:
		var stock: Dictionary = raw_stock
		var uid := "shop:buy:" + String(stock.get("stock_id", ""))
		var should_disable: bool = bool(stock.get("sold", false)) or int(stock.get("price", 0)) > money
		if shell.button_disabled(uid) != should_disable:
			mismatched.append(uid)
	h.check("买得起的才有按钮，卖过的/买不起的都禁用", mismatched.is_empty(), str(mismatched))

	var buy_uid := _first_enabled_prefix(shell, "shop:buy:")
	h.check("至少有一件买得起", not buy_uid.is_empty())
	if not buy_uid.is_empty():
		var price := _stock_price(shell, buy_uid)
		var before := int(shell.view.get("money", 0))
		var deck_before := int(shell.view.get("deck_size", 0))
		h.eq("购买可点", _press(h, shell, buy_uid, "商店：购买 " + buy_uid), true)
		h.eq("买完正好少了标价", int(shell.view.get("money", 0)), before - price)
		h.check("买完牌组或饰品增加", int(shell.view.get("deck_size", 0)) > deck_before
			or (shell.view.get("relics", []) as Array).size() > 0)
		h.eq("同一件不能买第二次", shell.button_disabled(buy_uid), true)

	# 删牌：价格、次数、牌组下限三条门槛必须由 preview 门控体现出来
	var removal: Dictionary = (_view_dict(shell.view, "shop")).get("removal", {})
	var remove_ok: bool = bool(removal.get("available", false)) and int(removal.get("price", 0)) <= int(shell.view.get("money", 0))
	var remove_mismatch := []
	for raw_card in (shell.view.get("cards", []) as Array):
		var card: Dictionary = raw_card
		var uid := "shop:remove:" + String(card.get("card_id", ""))
		if shell.button_disabled(uid) == remove_ok:
			remove_mismatch.append(uid)
	h.check("删牌按钮只在服务可用时启用", remove_mismatch.is_empty(),
		"available=%s price=%s money=%s" % [str(remove_ok), str(removal.get("price", 0)), str(shell.view.get("money", 0))])
	h.eq("离开商店可点", _press(h, shell, "shop:leave", "离开商店"), true)
	h.eq("离开后回到地图", shell.screen, GameConstants.SCREEN_MAP)
	h.eq("商店节点记为已走（第 1~3 层都记了）", shell.session.run.node_path.size(), 3)
	h.check("路径最后一个是商店节点", String(shell.session.run.node_path[2]).ends_with("l3_shop"))
	_cleanup(shell)


# ── 休息与学期结算 ────────────────────────────────────────

func _rest_and_term(h, db) -> void:
	var shell = _new_shell(db, "rest")
	shell.battle_requested.connect(func(_input): pass)
	_start_run(shell, SEED)
	_clear_until(h, shell, "rest")
	h.eq("进入休息页", shell.screen, GameConstants.SCREEN_REST)
	var rest: Dictionary = _view_dict(shell.view, "rest")
	h.check("休息四选一都在", (rest.get("options", []) as Array).size() == 4)
	h.eq("恢复选项可点", shell.button_disabled("rest:take:heal"), false)
	h.eq("没休息不能离开", shell.button_disabled("rest:leave"), true)
	h.eq("没休息时点离开无效", shell.press("rest:leave"), false)
	var before := int(shell.view.get("vitality", 0))
	var heal := int(rest.get("heal_amount", 0))
	h.eq("恢复精力可点", _press(h, shell, "rest:take:heal", "休息：恢复精力"), true)
	h.eq("精力按恢复量上升（上限钳制）", int(shell.view.get("vitality", 0)),
		mini(int(shell.view.get("max_vitality", 0)), before + heal))
	h.eq("休息后可以离开", shell.button_disabled("rest:leave"), false)
	h.eq("离开休息节点", _press(h, shell, "rest:leave", "休息完毕 -> 继续"), true)
	h.eq("第 6 层首领现在可达", shell.button_disabled("node:" + _boss_id(shell)), false)

	# 打完首领 -> 学期结算
	_press(h, shell, "node:" + _boss_id(shell), "进入首领节点")
	_settle_win(shell)
	_claim_all_rewards(h, shell)
	_press(h, shell, "reward:leave", "奖励处理完 -> 离开首领节点")
	h.eq("离开首领后进入学期结算", shell.screen, GameConstants.SCREEN_TERM)
	var settlement: Dictionary = _view_dict(shell.view, "settlement")
	h.eq("第 1 学期只有方向奖励一步", (settlement.get("steps", []) as Array).size(), 1)
	var step: Dictionary = (settlement.get("steps", []) as Array)[0]
	h.eq("步骤类型是方向奖励", String(step.get("kind", "")), "direction_reward")
	var step_id := String(step.get("step_id", ""))
	var first_candidate := String((step.get("candidates", []) as Array)[0])
	h.check("每个候选一个按钮", shell.has_button("term:%s:choose:%s" % [step_id, first_candidate]))
	h.check("可以跳过方向奖励", shell.has_button("term:%s:skip" % step_id))
	var cards_before := int(shell.view.get("deck_size", 0))
	h.eq("跳过可点", _press(h, shell, "term:%s:skip" % step_id, "学期结算：跳过方向奖励"), true)
	h.eq("结算完成进入第 2 学期", shell.session.run.term, 2)
	h.eq("结算已清空", shell.session.run.settlement, null)
	h.eq("跳过就不会加牌", int(shell.view.get("deck_size", 0)), cards_before)
	_cleanup(shell)


# ── 战斗入口与摘要 ────────────────────────────────────────

func _battle_and_summary(h, db) -> void:
	var shell = _new_shell(db, "battle")
	var collected := []
	shell.battle_requested.connect(func(input): collected.append(input))
	_start_run(shell, SEED)
	var node_id := _next_node(shell)
	_press(h, shell, "node:" + node_id, "进入第 1 层")
	h.eq("战斗入口页", shell.screen, GameConstants.SCREEN_BATTLE)
	h.check("有战斗界面监听时不再启用开发回退", bool(shell.view.get("dev_fallback", true)) == false)
	var draft: Dictionary = shell.current_page().action_draft("battle:start")
	h.eq("进入战斗的草稿类型", String(draft.get("type", "")), "ui.start_battle")
	h.eq("点「进入战斗」", _press(h, shell, "battle:start", "战斗入口：进入战斗"), true)
	h.eq("battle_input 交给了战斗界面", collected.size(), 1)
	if collected.size() == 1:
		var input: Dictionary = collected[0]
		h.eq("battle_input.battle_id = 节点 ID", String(input.get("battle_id", "")), node_id)
		h.eq("battle_input.node_id 一致", String(input.get("node_id", "")), node_id)
		h.check("battle_input 带 encounter_id", not String(input.get("encounter_id", "")).is_empty())
		h.check("battle_input 带牌组快照", (input.get("cards", []) as Array).size() > 0)
		h.check("battle_input 带精力上下限", int(input.get("max_vitality", 0)) > 0)
	h.eq("交接后仍停在战斗入口页（等战斗界面回填）", shell.screen, GameConstants.SCREEN_BATTLE)
	h.check("交接后 battle_input 仍在壳里可复用", Result.is_ok(Result.ok(shell.take_battle_input())))
	_cleanup(shell)

	var shell2 = _new_shell(db, "summary")
	shell2.battle_requested.connect(func(_input): pass)
	_start_run(shell2, SEED)
	var first := _next_node(shell2)
	_press(h, shell2, "node:" + first, "进入第 1 层")
	var lost: Dictionary = shell2.apply_battle_outcome({
		"battle_id": first,
		"result": GameConstants.OUTCOME_LOST,
		"reason": GameConstants.REASON_DEADLINE_EXPIRED,
		"remaining_vitality": 3,
	})
	h.check("失败结局被接受", Result.is_ok(lost), str(lost.get("error")))
	h.eq("失败进入摘要页", shell2.screen, GameConstants.SCREEN_SUMMARY)
	var summary_draft: Dictionary = shell2.current_page().action_draft("summary:retry")
	h.eq("摘要页「重开一局」草稿", String(summary_draft.get("type", "")), "ui.retry")
	h.eq("摘要页「回主菜单」草稿", String(shell2.current_page().action_draft("summary:menu").get("type", "")), "ui.menu")
	var run_summary: Dictionary = _view_dict(shell2.view, "run_summary")
	h.eq("摘要带失败原因", String(run_summary.get("reason", "")), GameConstants.REASON_DEADLINE_EXPIRED)
	h.eq("摘要带本局结局", String(run_summary.get("result", "")), GameConstants.OUTCOME_LOST)
	_cleanup(shell2)
# ── 离线视图渲染（事件 / 学期结算 / 摘要 / 结局）───────────

func _offline_pages(h) -> void:
	# 事件页：带目标的选项 -> 每张牌一个按钮；被规则层标为不可选的选项 -> 直接禁用
	var event_page = EventPage.new()
	event_page.render(_event_view(false))
	h.check("事件：升级卡选项按牌展开", event_page.has_button("event:a:card:c1"))
	h.check("事件：随机收益选项按候选展开", event_page.has_button("event:b:pick:K13") and event_page.has_button("event:b:pick:K14"))
	h.check("事件：离开按钮一直在", event_page.has_button("event:leave"))
	h.eq("事件：不可选选项的按钮被禁用", event_page.button_disabled("event:b:pick:K13"), true)
	h.eq("事件：点不可选选项无效", event_page.press("event:b:pick:K13"), false)
	h.check("事件：不可选时不产生草稿", event_page.build_action().is_empty())
	h.eq("事件：选牌可点", event_page.press("event:a:card:c1"), true)
	var draft: Dictionary = event_page.build_action()
	h.eq("事件草稿类型", String(draft.get("type", "")), GameConstants.ACTION_CHOOSE_EVENT)
	var payload: Dictionary = draft.get("payload", {})
	h.eq("事件草稿：选项", String(payload.get("option_id", "")), "a")
	h.eq("事件草稿：目标卡", str(payload.get("selection_ids", [])), str(["c1"]))
	# shell 门控（preview 说不能提交）也要能禁掉按钮
	event_page.apply_gating({"event:b:pick:K13": {"ok": false, "reason": "error.preview_blocked"}})
	h.eq("事件：门控原因可见", event_page.button_reason("event:b:pick:K13"), "error.preview_blocked")
	h.eq("事件：门控后点不动", event_page.press("event:b:pick:K13"), false)
	h.eq("事件：未被门控的按钮不受影响", event_page.press("event:a:card:c1"), true)
	event_page.render(_event_view(true))
	h.check("事件：已选过的选项不再出按钮", not event_page.has_button("event:a:card:c1"))
	h.eq("事件：已解决后可以离开", event_page.press("event:leave"), true)
	h.eq("事件离开草稿", String(event_page.build_action().get("type", "")), GameConstants.ACTION_LEAVE_NODE)
	event_page.queue_free()

	# 学期结算页：第 5 学期前的履历方向（三选一，不可跳过）；已完成步骤不再出按钮
	var term_page = TermPage.new()
	term_page.render(_career_term_view())
	h.check("结算：三轨都在", term_page.has_button("term:step_career:track:research")
		and term_page.has_button("term:step_career:track:competition")
		and term_page.has_button("term:step_career:track:internship"))
	h.check("结算：已完成步骤没有按钮", not term_page.has_button("term:step_direction:choose:K01"))
	h.check("结算：当前步骤之外没有按钮", not term_page.has_button("term:step_career:skip"))
	h.eq("结算：选科研可点", term_page.press("term:step_career:track:research"), true)
	var track_draft: Dictionary = term_page.build_action()
	h.eq("结算草稿类型", String(track_draft.get("type", "")), GameConstants.ACTION_CHOOSE_TERM_OPTION)
	var track_payload: Dictionary = track_draft.get("payload", {})
	h.eq("结算草稿：轨道", String(track_payload.get("option_id", "")), "research")
	h.eq("结算草稿：步骤", String(track_payload.get("step_id", "")), "step_career")
	h.eq("结算草稿：结算 ID", String(track_payload.get("settlement_id", "")), "S1")
	term_page.queue_free()

	# 摘要页 / 结局页：只发导航动作
	var summary_page = SummaryPage.new()
	summary_page.render({"run_summary": {
		"run_id": "R1", "result": "lost", "reason": "vitality_depleted", "ending_id": "",
		"character_id": "P01", "difficulty": "normal", "term": 2,
		"stats": {"cards_played": 7, "rounds": 3}, "unlocked_ids": ["P02"],
	}})
	h.eq("摘要：重开草稿", String(summary_page.action_draft("summary:retry").get("type", "")), "ui.retry")
	h.eq("摘要：回主菜单草稿", String(summary_page.action_draft("summary:menu").get("type", "")), "ui.menu")
	h.eq("摘要：点重开", summary_page.press("summary:retry"), true)
	summary_page.queue_free()

	var ending_page = EndingPage.new()
	ending_page.render({"eligible_endings": ["employment", "abroad"]})
	h.check("结局：每个可选结局一个按钮", ending_page.has_button("ending:employment") and ending_page.has_button("ending:abroad"))
	h.eq("结局：选就业可点", ending_page.press("ending:employment"), true)
	var ending_draft: Dictionary = ending_page.build_action()
	h.eq("结局草稿类型", String(ending_draft.get("type", "")), GameConstants.ACTION_CHOOSE_ENDING)
	h.eq("结局草稿：结局 ID", String((ending_draft.get("payload", {}) as Dictionary).get("ending_id", "")), "employment")
	ending_page.queue_free()


# ── 按钮表不残留（回归）────────────────────────────────────

## 战斗随机快照：读档续战必须把 battle 流交回战斗界面，否则抽牌退化成零种子。
func _battle_rng(h, db) -> void:
	var shell = _new_shell(db, "rng")
	_start_run(shell, SEED)
	var fallback: Dictionary = shell.battle_rng_snapshot()
	var fallback_streams: Variant = fallback.get("streams")
	h.check("没有战斗时回落到局的随机快照（含 battle 流）",
		typeof(fallback_streams) == TYPE_DICTIONARY
		and (fallback_streams as Dictionary).has(GameConstants.RNG_BATTLE))
	var map_before := str((fallback_streams as Dictionary)["map"].get("state", ""))
	var progressed: Dictionary = fallback.duplicate(true)
	(progressed["streams"] as Dictionary)[GameConstants.RNG_BATTLE] = {"seed": "7", "state": "99"}
	shell.attach_battle_state(null, progressed)
	var attached: Dictionary = shell.battle_rng_snapshot()
	var attached_stream: Dictionary = (attached["streams"] as Dictionary)[GameConstants.RNG_BATTLE]
	h.eq("回填后取回的是战斗自己的快照", String(attached_stream.get("state", "")), "99")
	## 交给战斗界面的这份快照必须能被 RandomSource 接受（四条流齐全），
	## 否则 resume_battle 会退化成零种子、续战与原局不一致。
	var probe := RandomSource.new()
	h.check("这份随机快照能被 RandomSource.restore_state 接受", Result.is_ok(probe.restore_state(attached)))
	var run_stream: Dictionary = (shell.session.random_snapshot["streams"] as Dictionary)[GameConstants.RNG_BATTLE]
	h.eq("battle 流写回了局快照（存档能续战）", String(run_stream.get("state", "")), "99")
	h.eq("其它三条流没被动过",
		str((shell.session.random_snapshot["streams"] as Dictionary)["map"].get("state", "")), map_before)
	h.check("回填后可以存档", Result.is_ok(shell.save_now()))
	var reopened = _new_shell_on(db, shell.store.base_dir, "rng2")
	h.eq("读档可点继续", reopened.press("menu:continue"), true)
	var reloaded: Dictionary = (reopened.session.random_snapshot["streams"] as Dictionary)[GameConstants.RNG_BATTLE]
	h.eq("读档后 battle 流 state 一致", String(reloaded.get("state", "")), "99")
	h.eq("读档后 battle 流 seed 一致", String(reloaded.get("seed", "")), "7")
	shell.detach_battle_state()
	h.check("解绑后回到局的随机快照", shell.battle_rng_snapshot().has("streams"))
	_cleanup(reopened)
	_cleanup(shell)

func _no_stale_buttons(h) -> void:
	var page = MapPage.new()
	page.render(_fake_map_view(["n1", "n2"]))
	h.check("首次渲染画出 n1", page.has_button("node:n1"))
	page.render(_fake_map_view(["n3"]))
	h.eq("重渲染后旧按钮从表里消失", page.has_button("node:n1"), false)
	h.check("重渲染后新按钮在", page.has_button("node:n3"))
	h.eq("点旧按钮无效", page.press("node:n1"), false)
	page.queue_free()


# ── 视图样例 ──────────────────────────────────────────────

func _event_view(resolved: bool) -> Dictionary:
	return {
		"current_node_id": "n1",
		"cards": [{"card_id": "c1", "definition_id": "K01", "upgrade_level": 0}],
		"relics": [{"relic_id": "r1", "definition_id": "A01", "slot": 1}],
		"event": {
			"event_instance_id": "e1",
			"definition_id": "E01",
			"name_key": "event.e01.name",
			"resolved_option_id": "a" if resolved else "",
			"frozen_candidates": {},
			"relic_slots_full": false,
			"options": [
				{
					"option_id": "a",
					"label_key": "event.e01.a",
					"cost": {"money": 10},
					"effects": [{"op": "upgrade_card"}],
					"candidates": [],
					"enabled": true,
					"blocking": [],
				},
				{
					"option_id": "b",
					"label_key": "event.e01.b",
					"cost": {},
					"effects": [{"op": "gain_card"}],
					"candidates": ["K13", "K14"],
					"enabled": false,
					"blocking": ["error.event.empty_card_pool"],
				},
			],
		},
	}


func _career_term_view() -> Dictionary:
	return {
		"term": 5,
		"vitality": 40,
		"max_vitality": 72,
		"money": 12,
		"deck_size": 12,
		"settlement": {
			"settlement_id": "S1",
			"term": 4,
			"complete": false,
			"current_step_id": "step_career",
			"steps": [
				{
					"step_id": "step_direction",
					"kind": "direction_reward",
					"status": "done",
					"candidates": ["K01"],
					"skippable": true,
					"chosen_id": "K01",
				},
				{
					"step_id": "step_career",
					"kind": "career_track",
					"status": "pending",
					"candidates": ["research", "competition", "internship"],
					"skippable": false,
					"chosen_id": "",
				},
			],
		},
	}


func _fake_map_view(node_ids: Array) -> Dictionary:
	var nodes := []
	for raw_id in node_ids:
		nodes.append({
			"node_id": String(raw_id),
			"term": 1,
			"layer": 1,
			"kind": "normal",
			"status": "pending",
			"next_ids": [],
			"encounter_id": "",
			"event_definition_id": "",
		})
	return {
		"term": 1,
		"term_count": 8,
		"vitality": 72,
		"max_vitality": 72,
		"money": 60,
		"deck_size": 12,
		"relics": [],
		"relic_slots": 6,
		"removals_used": 0,
		"reachable_node_ids": [String(node_ids[0])] if not node_ids.is_empty() else [],
		"nodes": nodes,
		"node_path": [],
	}
# ── 基础设施 ──────────────────────────────────────────────

## 视图里的 battle/node/rest/shop/... 在「当前不是那一屏」时是显式 null（不是缺键），
## 所以不能写 view.get(k, {})——那会拿到 null 并炸在类型赋值上。
func _view_dict(view: Dictionary, key: String) -> Dictionary:
	var raw: Variant = view.get(key)
	return (raw as Dictionary) if typeof(raw) == TYPE_DICTIONARY else {}


func _new_shell(db, name: String):
	return _new_shell_on(db, "user://test_ui_pages_" + name + "_" + str(Time.get_ticks_usec()), name)


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


func _press(h, shell, uid: String, label: String) -> bool:
	var ok: bool = shell.press(uid)
	h.check(label, ok, "uid=%s reason=%s" % [uid, shell.button_reason(uid)])
	return ok


## 主菜单 ->（选人，填种子）-> 开局。
func _start_run(shell, seed: String) -> void:
	shell.press("menu:new")
	var page = shell.current_page()
	page.set_seed_text(seed)
	shell.press("setup:start")


## 地图上按模板顺序挑第一个可进入的节点（界面只认可达集合）。
func _next_node(shell) -> String:
	var reachable: Array = shell.view.get("reachable_node_ids", [])
	for raw_uid in shell.button_uids():
		var uid := String(raw_uid)
		if not uid.begins_with("node:"):
			continue
		var node_id := uid.trim_prefix("node:")
		if reachable.has(node_id) and not shell.button_disabled(uid):
			return node_id
	return ""


func _boss_id(shell) -> String:
	for raw_uid in shell.button_uids():
		var uid := String(raw_uid)
		if uid.ends_with("l6_boss"):
			return uid.trim_prefix("node:")
	return ""


## 用规则层接受的胜利结局把当前战斗节点结算掉（界面测试不依赖战斗数值平衡）。
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


func _stock_price(shell, uid: String) -> int:
	var shop: Dictionary = _view_dict(shell.view, "shop")
	var stock_id := uid.trim_prefix("shop:buy:")
	for raw_stock in (shop.get("stocks", []) as Array):
		var stock: Dictionary = raw_stock
		if String(stock.get("stock_id", "")) == stock_id:
			return int(stock.get("price", 0))
	return 0


## 从当前位置点到指定屏幕（战斗注入胜利、奖励按序处理、商店/事件直接走人）。
func _clear_until(h, shell, target_screen: String) -> void:
	for _step in range(40):
		var screen := String(shell.screen)
		if screen == target_screen:
			return
		if screen == "map":
			var next_id := _next_node(shell)
			if next_id.is_empty():
				return
			if not shell.press("node:" + next_id):
				h.check("可进入节点能点：" + next_id, false, shell.button_reason("node:" + next_id))
				return
			continue
		if screen == GameConstants.SCREEN_BATTLE:
			if shell.has_button("battle:start") and not shell.button_disabled("battle:start"):
				shell.press("battle:start")
				_settle_win(shell)
				continue
			shell.press("battle:leave")
			continue
		if screen == GameConstants.SCREEN_REWARD:
			_claim_all_rewards(h, shell)
			shell.press("reward:leave")
			continue
		if screen == GameConstants.SCREEN_SHOP:
			shell.press("shop:leave")
			continue
		if screen == GameConstants.SCREEN_EVENT:
			shell.press("event:leave")
			continue
		if screen == GameConstants.SCREEN_REST:
			shell.press("rest:take:heal")
			shell.press("rest:leave")
			continue
		return
## t15 回归：无选择的选项一次点击就选它（以前 _handle 只认 3/4 段 uid，点了毫无反应——
## 出厂 mvp 启用真事件后，「离开，无变化」这类选项在界面上根本选不了）。
## 顺带钉住 selection_candidates：选卡选项只出规则层给的合法目标。
func _event_plain_option(h) -> void:
	var page = EventPage.new()
	page.render(_event_plain_view())
	h.check("事件：无选择的选项给一个整项按钮", page.has_button("event:game"))
	h.check("事件：选卡选项按 selection_candidates 展开", page.has_button("event:pick_card:card:c1"))
	h.eq("事件：候选之外的牌不出按钮", page.has_button("event:pick_card:card:c2"), false)
	h.eq("事件：无选择的选项点得动", page.press("event:game"), true)
	var draft: Dictionary = page.build_action()
	h.eq("事件：草稿类型", String(draft.get("type", "")), GameConstants.ACTION_CHOOSE_EVENT)
	var payload: Dictionary = draft.get("payload", {})
	h.eq("事件：草稿 option_id", String(payload.get("option_id", "")), "game")
	h.check("事件：不需要选择时不带 selection_ids", not payload.has("selection_ids"))
	page.queue_free()


func _event_plain_view() -> Dictionary:
	return {
		"current_node_id": "n1",
		"cards": [
			{"card_id": "c1", "definition_id": "K01", "upgrade_level": 0},
			{"card_id": "c2", "definition_id": "K02", "upgrade_level": 0},
		],
		"relics": [],
		"event": {
			"event_instance_id": "e2",
			"definition_id": "V01",
			"name_key": "event.v01.name",
			"resolved_option_id": "",
			"frozen_candidates": {},
			"relic_slots_full": false,
			"options": [
				{
					"option_id": "pick_card",
					"label_key": "event.v01.pick_card",
					"cost": {},
					"effects": [{"op": "upgrade_card"}],
					"candidates": [],
					"selection_candidates": [{"card_id": "c1", "label": "K01"}],
					"enabled": true,
					"blocking": [],
				},
				{
					"option_id": "game",
					"label_key": "event.v01.game",
					"cost": {},
					"effects": [{"op": "heal", "amount": 24}],
					"candidates": [],
					"selection_candidates": [],
					"enabled": true,
					"blocking": [],
				},
			],
		},
	}