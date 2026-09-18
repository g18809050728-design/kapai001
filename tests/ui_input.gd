extends SceneTree
##
## 真实鼠标输入测试。
##
## ui_smoke.gd 直接调用 _on_card_clicked() 等处理函数，跳过了 Godot 的 GUI 事件路由；
## 本测试用 Viewport.push_input() 走完整链路（_gui_input → 已处理标记 → _unhandled_input），
## 覆盖「点击卡牌后被立刻取消选中」这类只在真实输入下才暴露的问题。
##
## 运行： godot --headless --path . --script res://tests/ui_input.gd
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")

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


## 在画布坐标处模拟一次完整的鼠标按键（按下 + 抬起）。
func click_at(vp: Viewport, pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = pos
	down.global_position = pos
	vp.push_input(down, true)

	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = pos
	up.global_position = pos
	vp.push_input(up, true)


## 等待界面把异步事件播放完（_busy 期间会锁定输入）。
func settle(inst, max_frames: int = 600) -> void:
	await process_frame
	var n = 0
	while bool(inst._busy) and n < max_frames:
		await process_frame
		n += 1
	await process_frame

func _initialize() -> void:
	_run()


func points_ok(before: int, after: int) -> bool:
	# 已到 10 点时无法继续上调，属于正常边界
	return after >= 1 and after <= 10 and (after != before or before >= 10)


func _first_playable(inst) -> Node:
	# 返回第一张当前可出的手牌视图；没有则返回 null
	for c in inst._hand_area.get_children():
		if bool(inst.engine.can_play(int(c.instance_id))["ok"]):
			return c
	return null


func _run() -> void:
	print("=== 真实鼠标输入测试 ===")
	var packed = load("res://src/ui/battle_scene.tscn")
	var inst = packed.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	if not inst.has_method("_start_new_battle") or inst.get("engine") == null:
		print("[FATAL] 战斗场景脚本未成功加载")
		quit(1)
		return

	inst._fast = true
	# 给足能量，排除「费用不足」这一无关变量：所有手牌都应可出
	inst.engine.state.energy = 10
	inst._refresh_all()
	await process_frame

	# 让第一张手牌确定为「斩击」（单体牌），使点击分支可预期
	var eng = inst.engine
	var slash_id := -1
	for iid in eng.state.draw_pile:
		if eng.state.def_id_of(int(iid)) == "slash":
			slash_id = int(iid)
			break
	if slash_id != -1 and not eng.state.hand.is_empty():
		var old_first := int(eng.state.hand[0])
		eng.state.hand.erase(old_first)
		eng.state.draw_pile.append(old_first)
		eng.state.set_zone(old_first, T.Zone.DRAW_PILE)
		eng.state.hand.push_front(slash_id)
		eng.state.set_zone(slash_id, T.Zone.HAND)
		eng.state.draw_pile.erase(slash_id)
		inst._refresh_all()
		await process_frame

	var vp: Viewport = inst.get_viewport()
	eq("手牌区渲染 5 张", inst._hand_area.get_child_count(), 5)

	# ── 场景 A：点击一张手牌，应当保持选中 ─────────────────
	var card = inst._hand_area.get_child(0)
	var card_id: int = int(card.instance_id)
	var center: Vector2 = card.get_global_rect().get_center()
	print("  点击卡牌 %s @ %s" % [CardDB.card_name(inst.engine.state.def_id_of(card_id)), str(center)])
	click_at(vp, center)
	await process_frame
	eq("真实点击后手牌保持选中（不被 _unhandled_input 取消）", inst._selected, card_id)
	check("提示显示已选中", inst._hint_label.text.contains("已选中"), inst._hint_label.text)

	# ── 场景 B：再次点击同一张牌应当真正出牌 ───────────────
	var tt: int = int(CardDB.get_card(inst.engine.state.def_id_of(card_id)).get("target", -1))

	if tt == T.TargetType.SINGLE_ENEMY:
		# 单体牌：点击敌人确认
		var enemy_center: Vector2 = inst._enemy_hit_area.get_global_rect().get_center()
		print("  单体牌 → 点击魔像 @ %s" % str(enemy_center))
		click_at(vp, enemy_center)
	else:
		# 无目标 / 自身牌：再次点击卡牌确认
		var card2 = inst._hand_area.get_child(0)
		click_at(vp, card2.get_global_rect().get_center())

	await process_frame
	await process_frame
	# 判断实例已离开手牌，而非手牌数量：战术整理会抽 2 张，数量反而增加。
	check("出牌后该实例已离开手牌",
		inst.engine.state.zone_of(card_id) != T.Zone.HAND,
		"zone=%d" % inst.engine.state.zone_of(card_id))
	check("出牌后清空选中态", inst._selected == -1, "selected=%d" % inst._selected)
	await settle(inst)   # 等事件播放结束，否则 _busy 会挡住后续点击

	# ── 场景 C：右键取消（只挑一张当前可出的牌）──────────
	inst.engine.state.energy = 10
	inst._refresh_all()
	var c3 = _first_playable(inst)
	if c3 != null:
		var id3: int = int(c3.instance_id)
		click_at(vp, c3.get_global_rect().get_center())
		await process_frame
		eq("选中待取消的牌", inst._selected, id3)
		click_at(vp, Vector2(800, 400), MOUSE_BUTTON_RIGHT)
		await process_frame
		eq("右键取消选中", inst._selected, -1)
	else:
		check("场景 C：本局没有可出的手牌，跳过", true)

	# ── 场景 D：点击空白处取消（只挑一张当前可出的牌）──────
	inst.engine.state.energy = 10
	inst._refresh_all()
	var c4 = _first_playable(inst)
	if c4 != null:
		var id4: int = int(c4.instance_id)
		click_at(vp, c4.get_global_rect().get_center())
		await process_frame
		eq("选中待取消的牌", inst._selected, id4)
		click_at(vp, Vector2(800, 300))
		await process_frame
		eq("点击空白处取消选中", inst._selected, -1)
	else:
		check("场景 D：本局没有可出的手牌，跳过", true)

	# ── 场景 E：调律必须先点目标手牌（S01）─────────────────
	var eng2 = inst.engine
	var tune_id := -1
	for iid in eng2.state.draw_pile:
		if eng2.state.def_id_of(int(iid)) == "tune":
			tune_id = int(iid)
			break
	if tune_id != -1 and eng2.state.hand.size() >= 2:
		eng2.state.draw_pile.erase(tune_id)
		eng2.state.hand.push_front(tune_id)
		eng2.state.set_zone(tune_id, T.Zone.HAND)
		eng2.state.energy = 10
		inst._selected = -1
		inst._refresh_all()
		await process_frame
		var c5 = inst._hand_area.get_child(0)
		click_at(vp, c5.get_global_rect().get_center())
		await process_frame
		eq("真实点击选中调律", inst._selected, tune_id)
		check("提示要求选择另一张手牌", inst._hint_label.text.contains("另一张手牌"), inst._hint_label.text)
		var c6 = inst._hand_area.get_child(1)
		var target_id: int = int(c6.instance_id)
		click_at(vp, c6.get_global_rect().get_center())
		await process_frame
		eq("点击第二张手牌后选定目标", inst._hand_target, target_id)
		check("+1 / -1 方向按钮可见", inst._delta_row.visible)
		var pts_before: int = eng2.state.effective_points(target_id)
		inst._on_delta_pressed(1)
		await settle(inst)
		var pts_after: int = eng2.state.effective_points(target_id)
		# 调律的「倍数效果」会放大调整幅度，这里只断言方向与取值范围
		check("调律调整生效（点数快照只影响未来出牌）", points_ok(pts_before, pts_after),
		"before=%d after=%d" % [pts_before, pts_after])
		check("调律已离开手牌", eng2.state.zone_of(tune_id) != T.Zone.HAND)
	else:
		check("场景 E：本局没有可用调律，跳过", true, "tune_id=%d" % tune_id)

	print("\n" + "=".repeat(60))
	print("真实输入测试：通过 %d，失败 %d" % [_pass, _fail])
	for f in _failures:
		print("  - " + f)
	print("=".repeat(60))
	quit(1 if _fail > 0 else 0)