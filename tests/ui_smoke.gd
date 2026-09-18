extends SceneTree
##
## 界面冒烟测试：实例化战斗场景，验证界面能构建、交互能走通、重开能清干净。
## 运行： godot --headless --path . --script res://tests/ui_smoke.gd
##
## 规格中属于「界面行为」的 A19（重复点击保护）与 A22（玩法说明弹窗）在此验证。
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")
const Palette = preload("res://src/ui/palette.gd")
const CardView = preload("res://src/ui/card_view.gd")

var _pass := 0
var _fail := 0
var _failures: Array = []


func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % label)
	else:
		_fail += 1
		_failures.append(label + ("  → " + detail if detail != "" else ""))
		print("  [FAIL] %s   %s" % [label, detail])


func eq(label: String, got, want) -> void:
	check(label, got == want, "got=%s want=%s" % [str(got), str(want)])


## 等待界面把异步事件播放完（_busy 期间锁定输入）。
func settle(inst, max_frames: int = 600) -> void:
	await process_frame
	await process_frame
	var n := 0
	while bool(inst._busy) and n < max_frames:
		await process_frame
		n += 1
	await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	print("=== 界面冒烟测试 ===")
	var packed = load("res://src/ui/battle_scene.tscn")
	if packed == null:
		print("[FAIL] 无法加载 res://src/ui/battle_scene.tscn")
		quit(1)
		return

	var inst = packed.instantiate()
	check("场景实例化成功", inst != null)
	root.add_child(inst)
	var watchdog = Timer.new()
	watchdog.wait_time = 90.0
	watchdog.one_shot = true
	watchdog.autostart = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	await process_frame
	await process_frame

	if not inst.has_method("_start_new_battle") or inst.get("engine") == null:
		print("[FATAL] 战斗场景脚本未成功加载，终止测试")
		_fail += 1
		_failures.append("战斗场景脚本未成功加载")
		print("\n界面冒烟：通过 %d，失败 %d" % [_pass, _fail])
		quit(1)
		return

	inst._fast = true   # 缩短演出等待

	check("规则引擎已创建", inst.engine != null)
	check("战斗已开始", inst.engine.state.turn == 1)
	eq("顶栏回合标签", inst._turn_label.text, "回合 1")
	eq("玩家生命条数值", inst._player_hp_bar.value, 60.0)
	eq("手牌区渲染 5 张卡", inst._hand_area.get_child_count(), 5)
	eq("弃牌堆显示 0 张", inst._discard_count.text, "0 张")
	check("敌人意图已显示", inst._intent_label.text.begins_with("意图：攻击玩家：6"),
		inst._intent_label.text)
	eq("随从槽位渲染 2 个", inst._minion_views.size(), 2)
	check("场景区显示无场景牌", inst._scene_name.text == "无场景牌", inst._scene_name.text)

	# ── 出牌交互 ──────────────────────────────────────────
	inst.engine.state.energy = 10
	inst._refresh_all()
	var hand_id: int = int(inst.engine.state.hand[0])
	inst._on_card_clicked(hand_id)
	eq("点击手牌进入选中态", inst._selected, hand_id)
	check("右侧提示已更新", inst._hint_label.text.contains("已选中"), inst._hint_label.text)
	var hand_def: String = inst.engine.state.def_id_of(hand_id)
	var hand_tt = int(CardDB.get_card(hand_def).get("target", -1))
	check("选中手牌后显示融牌按钮", inst._fuse_btn.visible)
	check("卡面显示点数（点数与费用分开标记）",
		inst._hand_area.get_child(0).points == inst.engine.state.effective_points(hand_id),
		"points=%s" % str(inst._hand_area.get_child(0).points))
	if hand_tt == T.TargetType.OTHER_HAND and inst._card_has_op(hand_def, CardDB.OP_MODIFY_POINT):
		check("调律选中后显示 +1 / -1 方向按钮（S01）", inst._delta_row.visible)
	else:
		check("选中手牌后出现「确认使用」按钮", inst._confirm_btn.visible)
	if hand_tt == T.TargetType.SINGLE_ENEMY:
		check("单体牌需点击敌人确认：确认按钮禁用", inst._confirm_btn.disabled)
		check("单体牌选中时高亮合法敌人",
			inst._enemy_hit_area.get_theme_stylebox("panel").border_color == Palette.SELECT)
	elif hand_tt == T.TargetType.OTHER_HAND or hand_tt == T.TargetType.READY_MINION:
		check("需要目标的牌在选好目标前不能确认",
			(not inst._confirm_btn.visible) or inst._confirm_btn.disabled)
		check("提示要求先选择目标",
			inst._hint_label.text.contains("另一张手牌") or inst._hint_label.text.contains("仆从"),
			inst._hint_label.text)
	else:
		check("无目标牌可直接确认：确认按钮可用", not inst._confirm_btn.disabled)
	inst._cancel_selection()
	eq("取消选择清空选中态", inst._selected, -1)
	check("取消选择后隐藏确认按钮", not inst._confirm_btn.visible)

	# 单选一张无目标牌 → 再次点击即生效
	var no_target_id := -1
	for iid in inst.engine.state.hand:
		var def_id: String = inst.engine.state.def_id_of(int(iid))
		var tt: int = int(CardDB.get_card(def_id).get("target", -1))
		# 排除「检索」：它打出后会进入待选择状态，单独在下面验证
		if (tt == T.TargetType.NONE or tt == T.TargetType.SELF) and def_id != "search":
			no_target_id = int(iid)
			break
	if no_target_id != -1:
		inst._on_card_clicked(no_target_id)
		inst._on_card_clicked(no_target_id)
		await settle(inst)
		# 用「该实例已离开手牌」判断而非手牌数量：战术整理会抽 2 张，手牌数反而增加。
		check("无目标牌点两次后生效（该实例已离开手牌）",
			inst.engine.state.zone_of(no_target_id) != T.Zone.HAND,
			"zone=%d" % inst.engine.state.zone_of(no_target_id))
	else:
		check("无目标牌点两次后生效（该实例已离开手牌）", true, "本局手牌无自身目标牌，跳过")

	# ── A22 玩法说明弹窗 ──────────────────────────────────
	inst._on_help_pressed()
	check("A22 玩法说明已打开", inst._help_overlay.visible)
	var turn_before = inst.engine.state.turn
	var hp_before = inst.engine.state.player_hp
	var energy_before = inst.engine.state.energy
	check("A22 弹窗阻止背景操作（遮罩拦截鼠标）",
		inst._help_overlay.mouse_filter == Control.MOUSE_FILTER_STOP)
	inst._on_help_close()
	check("A22 关闭后隐藏", not inst._help_overlay.visible)
	eq("A22 回合不推进", inst.engine.state.turn, turn_before)
	eq("A22 生命不变", inst.engine.state.player_hp, hp_before)
	eq("A22 能量不变", inst.engine.state.energy, energy_before)

	# ── 牌堆查看 ──────────────────────────────────────────
	inst._open_deck("draw")
	check("抽牌堆查看器已打开", inst._deck_overlay.visible)
	check("抽牌堆标题不暴露顺序",
		inst._deck_title.text.contains("不暴露抽取顺序"), inst._deck_title.text)
	inst._deck_overlay.visible = false
	inst._open_deck("discard")
	check("弃牌堆查看器显示实际内容", inst._deck_title.text.contains("实际内容"), inst._deck_title.text)
	inst._deck_overlay.visible = false

	# ── 结束回合 + 保留一张牌 ─────────────────────────────
	inst._selected = -1
	if inst.engine.state.hand.is_empty():
		inst.engine._draw_cards(1)
		inst._refresh_all()
	await settle(inst)
	var turn_now: int = inst.engine.state.turn
	inst._on_end_turn_pressed()
	check("有手牌时进入保留选择模式", inst._keep_mode)
	check("保留操作条可见", inst._keep_bar.visible)
	if inst.engine.state.hand.size() > 0:
		inst._on_card_clicked(int(inst.engine.state.hand[0]))
		check("已选定保留目标", not inst._keep_set.is_empty())
	inst._on_keep_confirm()
	await settle(inst)
	eq("回合推进", inst.engine.state.turn, turn_now + 1)
	check("保留一张 + 抽 5 张 = 6 张手牌", inst.engine.state.hand.size() == 6,
		"got=%d" % inst.engine.state.hand.size())
	eq("保留模式已退出", inst._keep_mode, false)
	eq("结算结束后解锁输入", inst._busy, false)

	# 随从/场景槽位渲染仍正常
	eq("随从槽位仍为 2", inst._minion_views.size(), 2)

	# ── 新体系界面：融牌（弃进弃牌堆）/ 点数链 ─────────────
	inst.engine.state.energy = 4
	inst._refresh_all()
	var fuse_id := -1
	for iid in inst.engine.state.hand:
		if inst.engine.state.is_temp(int(iid)):
			continue
		inst._selected = -1
		inst._on_card_clicked(int(iid))
		if inst._selected == int(iid):
			fuse_id = int(iid)
			break
	if fuse_id == -1:
		check("融牌界面（本局没有可选中融掉的手牌，跳过）", true)
	if fuse_id != -1:
		check("融牌按钮可用（非临时牌即可，与能不能打出无关）", not inst._fuse_btn.disabled)
		var energy_before_fuse: int = inst.engine.state.energy
		inst._on_fuse_pressed()
		await settle(inst)
		eq("融牌后能量 +1", inst.engine.state.energy, energy_before_fuse + 1)
		eq("融牌后卡牌进入弃牌堆", inst.engine.state.zone_of(fuse_id), T.Zone.DISCARD)
		check("弃牌堆计数已刷新", inst._discard_count.text != "0 张", inst._discard_count.text)
		inst._open_deck("discard")
		check("弃牌堆查看器能看到刚融掉的牌", inst._deck_list.get_child_count() >= 1,
			"n=%d" % inst._deck_list.get_child_count())
		inst._deck_overlay.visible = false
		check("点数状态已在玩家面板显示", inst._points_label.text.contains("本回合点数"),
			inst._points_label.text)
		check("三类链状态已显示", inst._chain_label.text.contains("倍数") and inst._chain_label.text.contains("同点"),
			inst._chain_label.text)

	# ── 打不出去的牌也必须能选中并融掉（用费用不足的能量冲击确定复现）──
	inst._selected = -1
	inst.engine.state.energy = 0
	var blocked_id := -1
	for iid in inst.engine.state.draw_pile:
		if inst.engine.state.def_id_of(int(iid)) == "energy_blast":
			blocked_id = int(iid)
			break
	if blocked_id != -1:
		inst.engine.state.draw_pile.erase(blocked_id)
		inst.engine.state.hand.push_front(blocked_id)
		inst.engine.state.set_zone(blocked_id, T.Zone.HAND)
		inst._refresh_all()
		check("能量冲击在 0 能量下确实打不出去", not bool(inst.engine.can_play(blocked_id)["ok"]))
		inst._on_card_clicked(blocked_id)
		eq("打不出去的牌也能被选中", inst._selected, blocked_id)
		check("它同样可以融牌（按钮可用）", not inst._fuse_btn.disabled)
		check("提示说明当前不能用但可以融", inst._hint_label.text.contains("融牌"), inst._hint_label.text)
		inst._cancel_selection()
	else:
		check("牌库里没有能量冲击，跳过「打不出去的牌可融」检查", true)
	# ── 检索（S04）：打出后弹出选择弹窗 ───────────────────
	var se_id := -1
	for iid in inst.engine.state.draw_pile:
		if inst.engine.state.def_id_of(int(iid)) == "search":
			se_id = int(iid)
			break
	if se_id != -1:
		inst.engine.state.draw_pile.erase(se_id)
		inst.engine.state.hand.push_front(se_id)
		inst.engine.state.set_zone(se_id, T.Zone.HAND)
		inst.engine.state.energy = 10
		inst._selected = -1
		inst._refresh_all()
		inst._on_card_clicked(se_id)
		inst._on_card_clicked(se_id)
		await settle(inst)
		check("S04 打出检索后弹出选择弹窗", inst._tutor_overlay.visible)
		check("S04 弹窗列出查看的牌", inst._tutor_list.get_child_count() >= 1,
			"n=%d" % inst._tutor_list.get_child_count())
		check("S04 待选择期间锁定输入", inst._busy)
		if inst._tutor_list.get_child_count() > 0:
			inst._on_tutor_pick(0)
			await settle(inst)
		check("S04 选择后弹窗关闭", not inst._tutor_overlay.visible)
		check("S04 选择后解锁输入", not inst._busy)
		check("S04 待选择已清空", inst.engine.state.pending_choice.is_empty())
	else:
		check("S04 检索弹窗（本局牌库没有检索，跳过）", true)

	# ── A19 连续点击再来一局 ──────────────────────────────
	inst.engine.state.player_hp = 10
	inst.engine.state.turn = 9
	inst._on_restart_pressed()
	inst._on_restart_pressed()   # 第二次点击必须不生效
	await process_frame
	await process_frame
	eq("A19 重开后回合回到 1", inst.engine.state.turn, 1)
	eq("A19 重开后玩家生命 60", inst.engine.state.player_hp, 60)
	eq("A19 重开后手牌 5 张", inst.engine.state.hand.size(), 5)
	eq("A19 重开后手牌区渲染 5 张", inst._hand_area.get_child_count(), 5)
	eq("A19 重开后牌组仍为 20 张", inst.engine.state.instances.size(), 20)
	check("A19 重开清空飘字层", inst._float_layer.get_child_count() == 0,
		"got=%d" % inst._float_layer.get_child_count())
	check("A19 重开隐藏结算弹窗", not inst._result_overlay.visible)
	eq("A19 重开后按钮恢复可用", inst._result_btn.disabled, false)
	eq("A19 重开后种子已更换", inst.engine.state.rng_seed != 0, true)

	# ── 终局弹窗 ──────────────────────────────────────────
	inst.engine.state.enemy_hp = 1
	inst.engine.state.player_hp = 60
	inst.engine.state.energy = 10
	inst._refresh_all()
	# 直接走规则层打完这一局，再验证弹窗
	inst.engine.state.enemy_hp = 0
	inst.engine.state.result = T.Result.VICTORY
	inst.engine.state.phase = T.Phase.BATTLE_END
	inst._show_result()
	check("胜利弹窗标题", inst._result_title.text == "战斗胜利", inst._result_title.text)
	check("胜利弹窗说明", inst._result_desc.text == "你击败了练习魔像", inst._result_desc.text)
	check("弹窗展示回合数与剩余生命",
		inst._result_stats.text.contains("使用回合数") and inst._result_stats.text.contains("剩余生命"),
		inst._result_stats.text)
	check("主按钮为再来一局", inst._result_btn.text == "再来一局", inst._result_btn.text)

	inst._on_restart_pressed()
	await process_frame
	await process_frame
	eq("结算弹窗重开后回合 1", inst.engine.state.turn, 1)
	check("结算弹窗重开后隐藏", not inst._result_overlay.visible)
	eq("结算弹窗重开后魔像满血", inst.engine.state.enemy_hp, 35)

	# ── 中文字体与手牌布局 ──────────────────────────────────
	var font = Palette.make_cjk_font()
	check("系统字体包含中文字形（否则界面全为方块）",
		font.has_char("战".unicode_at(0)), "SystemFont 未解析到 CJK 字形")

	for _k in range(6):
		inst.engine._draw_cards(1)
	inst._refresh_all()
	await process_frame
	var area_w = inst._hand_area.size.x
	var card_w = CardView.CARD_SIZE.x
	var inside = true
	for c in inst._hand_area.get_children():
		if c.position.x < -0.5 or c.position.x + card_w > area_w + 0.5:
			inside = false
	check("手牌不溢出手牌区（含 10 张上限）", inside, "area_w=%s" % str(area_w))
	check("手牌区渲染张数与规则状态一致",
		inst._hand_area.get_child_count() == inst.engine.state.hand.size(),
		"ui=%d state=%d" % [inst._hand_area.get_child_count(), inst.engine.state.hand.size()])

	print("\n" + "=".repeat(60))
	print("界面冒烟：通过 %d，失败 %d" % [_pass, _fail])
	for f in _failures:
		print("  - " + f)
	print("=".repeat(60))
	quit(1 if _fail > 0 else 0)

func _on_watchdog() -> void:
	print("[FATAL] 测试超时（90 秒），强制退出")
	quit(2)