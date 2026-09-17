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

	# ── 场景 C：右键取消 ───────────────────────────────────
	if inst.engine.state.hand.size() > 0:
		var c3 = inst._hand_area.get_child(0)
		var id3: int = int(c3.instance_id)
		click_at(vp, c3.get_global_rect().get_center())
		await process_frame
		eq("选中待取消的牌", inst._selected, id3)
		click_at(vp, Vector2(800, 400), MOUSE_BUTTON_RIGHT)
		await process_frame
		eq("右键取消选中", inst._selected, -1)

	# ── 场景 D：点击空白处取消 ─────────────────────────────
	if inst.engine.state.hand.size() > 0:
		var c4 = inst._hand_area.get_child(0)
		var id4: int = int(c4.instance_id)
		click_at(vp, c4.get_global_rect().get_center())
		await process_frame
		eq("选中待取消的牌", inst._selected, id4)
		click_at(vp, Vector2(800, 300))
		await process_frame
		eq("点击空白处取消选中", inst._selected, -1)

	print("\n" + "=".repeat(60))
	print("真实输入测试：通过 %d，失败 %d" % [_pass, _fail])
	for f in _failures:
		print("  - " + f)
	print("=".repeat(60))
	quit(1 if _fail > 0 else 0)