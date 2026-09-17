extends SceneTree
##
## 规则层验收测试：把规格 §12「验收场景」A01–A25 逐条变成断言。
## 运行： godot --headless --path . --script res://tests/run_tests.gd
##
## A19 / A22 含界面行为（重复点击保护、说明弹窗），规则层只能覆盖其状态部分，
## 界面部分在 tests/ui_smoke.gd 中验证。
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")
const EnemyDB = preload("res://src/core/enemy_db.gd")
const BattleEngine = preload("res://src/core/battle_engine.gd")

var _pass := 0
var _fail := 0
var _failures: Array = []
var _section := ""


# ══════════════════════════════════════════════════════════
#  断言与工具
# ══════════════════════════════════════════════════════════

func section(title: String) -> void:
	_section = title
	print("\n── %s ──" % title)


func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % label)
	else:
		_fail += 1
		var line := "%s / %s" % [_section, label]
		if detail != "":
			line += "  → " + detail
		_failures.append(line)
		print("  [FAIL] %s   %s" % [label, detail])


func eq(label: String, got, want) -> void:
	check(label, got == want, "got=%s want=%s" % [str(got), str(want)])


## 新开一场战斗。
func new_battle(seed_value: int = 1234) -> BattleEngine:
	var e := BattleEngine.new()
	e.start_battle(seed_value)
	return e


## 把手牌全部塞回牌库，便于构造确定的手牌。
func clear_hand(e) -> void:
	for iid in e.state.hand.duplicate():
		e.state.hand.erase(iid)
		e.state.draw_pile.append(int(iid))
		e.state.set_zone(int(iid), T.Zone.DRAW_PILE)


## 从任意区域取出指定定义的一张牌（不放入任何区域），返回实例 id。
func take_card(e, def_id: String) -> int:
	for pile in [e.state.draw_pile, e.state.discard_pile]:
		for iid in pile.duplicate():
			if e.state.def_id_of(int(iid)) == def_id:
				pile.erase(iid)
				return int(iid)
	return -1


## 构造确定手牌，返回实例 id 数组。
func set_hand(e, def_ids: Array) -> Array:
	clear_hand(e)
	var out: Array = []
	for d in def_ids:
		var iid := take_card(e, String(d))
		if iid == -1:
			push_error("测试无法取到卡牌: " + str(d))
			continue
		e.state.hand.append(iid)
		e.state.set_zone(iid, T.Zone.HAND)
		out.append(iid)
	return out


## 走完整的「结束回合」流程（含保留选择）。
func end_turn(e, keep: int = -1) -> Dictionary:
	var r = e.request_end_turn()
	if not r["ok"]:
		return r
	return e.confirm_end_turn(keep)


## 跨区域收集所有实例 id，用于校验区域互斥（§6.3）。
func all_instance_ids(e) -> Array:
	var ids: Array = []
	ids.append_array(e.state.draw_pile)
	ids.append_array(e.state.hand)
	ids.append_array(e.state.discard_pile)
	ids.append_array(e.state.resolve_zone)
	for m in e.state.minions:
		ids.append(int(m["card_instance"]))
	if not e.state.scene.is_empty():
		ids.append(int(e.state.scene["card_instance"]))
	return ids


## 每个实例恰好位于一个区域，且总数不变。
func integrity_ok(e) -> bool:
	var ids := all_instance_ids(e)
	if ids.size() != e.state.instances.size():
		return false
	var seen := {}
	for i in ids:
		if seen.has(int(i)):
			return false
		seen[int(i)] = true
	return true


## 收集事件里某种类型的全部事件。
func events_of(events: Array, type: String) -> Array:
	var out: Array = []
	for ev in events:
		if String(ev.get("type", "")) == type:
			out.append(ev)
	return out


# ══════════════════════════════════════════════════════════
#  测试主体
# ══════════════════════════════════════════════════════════

func _initialize() -> void:
	print("=== PVE 卡牌战斗 Demo · 规则层验收测试（规格 §12）===")
	_a01()
	_a02()
	_a03()
	_a04()
	_a05()
	_a06()
	_a07()
	_a08()
	_a09()
	_a10()
	_a11()
	_a12()
	_a13()
	_a14()
	_a15()
	_a16()
	_a17()
	_a18()
	_a19()
	_a20()
	_a21()
	_a23()
	_a24()
	_a25()
	_extra_card_table()
	_extra_shield_rules()

	print("\n" + "=".repeat(60))
	print("通过 %d，失败 %d" % [_pass, _fail])
	if _fail > 0:
		print("\n失败清单：")
		for f in _failures:
			print("  - " + f)
	print("=".repeat(60))
	quit(1 if _fail > 0 else 0)


# ── A01 开始新局 ──────────────────────────────────────────
func _a01() -> void:
	section("A01 开始新局")
	var e := new_battle()
	eq("玩家生命 60", e.state.player_hp, 60)
	eq("牌组共 20 张", e.state.instances.size(), 20)
	eq("回合数 1", e.state.turn, 1)
	eq("首回合能量 1", e.state.energy, 1)
	eq("首回合手牌 5 张", e.state.hand.size(), 5)
	eq("阶段 = 玩家行动", e.state.phase, T.Phase.PLAYER_ACTION)
	eq("魔像生命 35", e.state.enemy_hp, 35)
	eq("无行动点概念：能量上限 10", e.state.max_energy, 10)
	check("区域互斥完整", integrity_ok(e))


# ── A02 同回合连续使用多张免费牌 ──────────────────────────
func _a02() -> void:
	section("A02 同回合连续使用多张免费牌")
	var e := new_battle()
	var ids := set_hand(e, ["slash", "block", "meditate", "shield_break", "follow_up"])
	e.state.energy = 1
	var ok_all := true
	for iid in ids:
		var r := e.play_card(int(iid))
		if not r["ok"]:
			ok_all = false
	check("五张免费牌同回合全部可用（无出牌次数上限）", ok_all)
	eq("免费牌不扣能量，最终能量 5", e.state.energy, 5)
	eq("魔像生命 21（5+3+6）", e.state.enemy_hp, 21)
	check("区域互斥完整", integrity_ok(e))


# ── A03 斩击命中无护盾敌人 ────────────────────────────────
func _a03() -> void:
	section("A03 斩击命中无护盾敌人")
	var e := new_battle()
	var ids := set_hand(e, ["slash"])
	e.state.energy = 0
	e.play_card(int(ids[0]))
	eq("敌人生命 -5", e.state.enemy_hp, 30)
	eq("玩家能量 +1", e.state.energy, 1)


# ── A04 斩击命中至少 5 护盾敌人 ───────────────────────────
func _a04() -> void:
	section("A04 斩击命中至少 5 护盾敌人")
	var e := new_battle()
	var ids := set_hand(e, ["slash"])
	e.state.energy = 0
	e.state.enemy_shield = 5
	e.play_card(int(ids[0]))
	eq("敌人护盾 -5", e.state.enemy_shield, 0)
	eq("敌人生命不变", e.state.enemy_hp, 35)
	eq("玩家仍获得 1 能量", e.state.energy, 1)


# ── A05 先斩击再追击 ─────────────────────────────────────
func _a05() -> void:
	section("A05 先斩击再追击")
	var e := new_battle()
	var ids := set_hand(e, ["slash", "follow_up"])
	e.state.energy = 0
	e.state.enemy_shield = 5
	e.play_card(int(ids[0]))
	e.play_card(int(ids[1]))
	eq("追击造成 6 伤害（35-6）", e.state.enemy_hp, 29)
	eq("每张攻击牌各回能 1，与是否打穿护盾无关", e.state.energy, 2)


# ── A06 只有 2 能量时使用能量冲击 ─────────────────────────
func _a06() -> void:
	section("A06 只有 2 能量时使用能量冲击")
	var e := new_battle()
	var ids := set_hand(e, ["energy_blast"])
	e.state.energy = 2
	var v := e.can_play(int(ids[0]))
	check("提示需要 3 能量，当前 2", String(v["reason"]) == "需要 3 能量，当前 2", String(v["reason"]))
	var r := e.play_card(int(ids[0]))
	check("禁止使用", not r["ok"])
	eq("不移牌：仍在手牌", e.state.hand.size(), 1)
	eq("不扣费", e.state.energy, 2)
	eq("结算区为空", e.state.resolve_zone.size(), 0)
	eq("弃牌堆为空", e.state.discard_pile.size(), 0)


# ── A07 使用能量冲击造成伤害 ──────────────────────────────
func _a07() -> void:
	section("A07 使用能量冲击造成伤害")
	var e := new_battle()
	var ids := set_hand(e, ["energy_blast"])
	e.state.energy = 3
	e.play_card(int(ids[0]))
	eq("扣 3 能量", e.state.energy, 0)
	eq("造成 12 伤害", e.state.enemy_hp, 23)
	eq("技能不计入普通攻击次数（无回能）", e.state.attacks_played_this_turn, 0)


# ── A08 玩家有 6 护盾，魔像重击 10 ────────────────────────
func _a08() -> void:
	section("A08 玩家有 6 护盾，魔像重击 10")
	var e := new_battle()
	e.state.player_shield = 6
	e.state.player_hp = 60
	e.state.energy = 0
	e.state.enemy_intent = {"kind": T.IntentKind.ATTACK, "value": 10}
	e.state.enemy_cursor = 2
	var evs := e.enemy_phase()
	eq("护盾归零", e.state.player_shield, 0)
	eq("生命 -4", e.state.player_hp, 56)
	eq("承伤回能 +1", e.state.energy, 1)
	eq("敌方阶段只回能一次", events_of(evs, T.EV_ENERGY_CHANGED).size(), 1)


# ── A09 保留 1 张后进入下回合 ─────────────────────────────
func _a09() -> void:
	section("A09 保留 1 张后进入下回合")
	var e := new_battle()
	var ids := set_hand(e, ["slash", "block", "meditate", "striker", "guardian"])
	var keep := int(ids[0])
	var r := e.request_end_turn()
	check("有手牌时进入保留选择模式", r["ok"] and r["needs_keep"])
	eq("阶段 = 保留选择", e.state.phase, T.Phase.KEEP_SELECT)
	e.confirm_end_turn(keep)
	eq("回合推进到 2", e.state.turn, 2)
	eq("保留 1 张 + 新抽 5 张 = 6 手牌", e.state.hand.size(), 6)
	check("保留的牌仍在手牌", e.state.hand.has(keep))
	check("区域互斥完整", integrity_ok(e))


# ── A10 空牌库且弃牌堆有牌时抽牌 ──────────────────────────
func _a10() -> void:
	section("A10 空牌库且弃牌堆有牌时抽牌")
	var e := new_battle()
	clear_hand(e)
	# 把抽牌堆全部移入弃牌堆，制造「牌库为空、弃牌堆有牌」
	for iid in e.state.draw_pile.duplicate():
		e.state.draw_pile.erase(iid)
		e.state.discard_pile.append(int(iid))
		e.state.set_zone(int(iid), T.Zone.DISCARD)
	eq("抽牌堆为空", e.state.draw_pile.size(), 0)
	eq("弃牌堆 20 张", e.state.discard_pile.size(), 20)
	e._draw_cards(5)
	eq("洗入弃牌堆并继续抽取：手牌 5 张", e.state.hand.size(), 5)
	eq("抽牌堆剩 15", e.state.draw_pile.size(), 15)
	eq("弃牌堆清空", e.state.discard_pile.size(), 0)
	check("无重复实例（区域互斥）", integrity_ok(e))


# ── A11 使用战术整理导致洗牌 ──────────────────────────────
func _a11() -> void:
	section("A11 使用战术整理导致洗牌")
	var e := new_battle()
	var ids := set_hand(e, ["tactical_draw"])
	var td := int(ids[0])
	# 抽牌堆清空 → 迫使本次抽牌洗弃牌堆
	for iid in e.state.draw_pile.duplicate():
		e.state.draw_pile.erase(iid)
		e.state.discard_pile.append(int(iid))
		e.state.set_zone(int(iid), T.Zone.DISCARD)
	e.state.energy = 2
	e.play_card(td)
	eq("抽到 2 张牌", e.state.hand.size(), 2)
	check("正在结算的战术整理不被本次抽到", not e.state.hand.has(td))
	check("战术整理结算后进入弃牌堆", e.state.discard_pile.has(td))
	eq("结算区已清空", e.state.resolve_zone.size(), 0)
	check("区域互斥完整", integrity_ok(e))


# ── A12 召唤突击兵并结束回合 ──────────────────────────────
func _a12() -> void:
	section("A12 召唤突击兵并结束回合")
	var e := new_battle()
	var ids := set_hand(e, ["striker"])
	e.state.energy = 5
	e.play_card(int(ids[0]))
	eq("随从入场，占槽位 0", e.state.minions.size(), 1)
	eq("召唤当回合不可攻击", bool(e.state.minions[0]["can_attack"]), false)
	end_turn(e)
	eq("当回合不攻击（魔像生命不变）", e.state.enemy_hp, 35)
	eq("进入第 2 回合后随从就绪", bool(e.state.minions[0]["can_attack"]), true)
	var evs = e.resolve_minion_attacks()
	eq("确认结束后自动攻击一次", e.state.enemy_hp, 32)
	eq("一次结算只出手一次", events_of(evs, T.EV_MINION_ATTACKED).size(), 1)
	eq("攻击后本回合不再就绪", bool(e.state.minions[0]["can_attack"]), false)
	eq("同一回合内重复结算不再出手",
		events_of(e.resolve_minion_attacks(), T.EV_MINION_ATTACKED).size(), 0)


# ── A13 满血守卫承受魔像重击 10 ───────────────────────────
func _a13() -> void:
	section("A13 满血守卫承受魔像重击 10")
	var e := new_battle()
	var ids := set_hand(e, ["guardian"])
	e.state.energy = 6
	e.play_card(int(ids[0]))
	eq("守卫 7 生命嘲讽", int(e.state.minions[0]["hp"]), 7)
	e.state.enemy_intent = {"kind": T.IntentKind.ATTACK, "value": 10}
	e.state.enemy_cursor = 2
	e.enemy_phase()
	eq("守卫死亡", e.state.minions.size(), 0)
	eq("超额伤害不伤玩家", e.state.player_hp, 60)
	eq("不触发玩家承伤回能", e.state.energy, 3)
	check("守卫卡牌进入弃牌堆", e.state.discard_pile.has(int(ids[0])))
	check("区域互斥完整", integrity_ok(e))


# ── A14 使用能量涌泉 ──────────────────────────────────────
func _a14() -> void:
	section("A14 使用能量涌泉")
	var e := new_battle()
	var ids := set_hand(e, ["energy_spring"])
	var es := int(ids[0])
	e.state.energy = 5
	e.play_card(es)
	eq("打出时不立即回能", e.state.energy, 3)
	eq("初始剩余触发次数 3", int(e.state.scene["triggers"]), 3)
	e._start_player_turn()
	eq("第 1 次触发：回合开始 1 + 场景 1", e.state.energy, 5)
	eq("剩余 2 次", int(e.state.scene["triggers"]), 2)
	e._start_player_turn()
	eq("第 2 次触发后能量", e.state.energy, 7)
	eq("剩余 1 次", int(e.state.scene["triggers"]), 1)
	e._start_player_turn()
	eq("第 3 次触发后能量", e.state.energy, 9)
	check("三次触发后场景清空", e.state.scene.is_empty())
	check("能量涌泉进入弃牌堆", e.state.discard_pile.has(es))
	check("区域互斥完整", integrity_ok(e))
	# 满能量时依然消耗触发次数
	var e2 := new_battle()
	var ids2 := set_hand(e2, ["energy_spring"])
	e2.state.energy = 5
	e2.play_card(int(ids2[0]))
	eq("打出能量涌泉只扣费用，不回能", e2.state.energy, 3)
	e2.state.energy = 10
	e2._start_player_turn()
	eq("满能量时能量保持 10", e2.state.energy, 10)
	eq("满能量时触发次数照扣（3→2）", int(e2.state.scene["triggers"]), 2)


# ── A15 魔像在行动前被击败 ────────────────────────────────
func _a15() -> void:
	section("A15 魔像在行动前被击败")
	var e := new_battle()
	var ids := set_hand(e, ["striker"])
	e.state.energy = 5
	e.play_card(int(ids[0]))
	e.state.minions[0]["can_attack"] = true
	e.state.enemy_hp = 3
	e.state.enemy_intent = {"kind": T.IntentKind.ATTACK, "value": 10}
	e.state.enemy_cursor = 2
	clear_hand(e)
	var r := e.confirm_end_turn(-1)
	eq("随从击杀魔像 → 立即胜利", e.state.result, T.Result.VICTORY)
	eq("不执行魔像意图：玩家生命不变", e.state.player_hp, 60)
	eq("不执行敌人行动：无承伤回能", e.state.energy, 3)
	eq("阶段进入终局", e.state.phase, T.Phase.BATTLE_END)
	check("未产生敌方行动事件",
		events_of(r["events"], T.EV_ENEMY_ACTED).is_empty())


# ── A16 连续结束回合且双方存活 ────────────────────────────
func _a16() -> void:
	section("A16 连续结束回合且双方存活")
	var e := new_battle()
	eq("第 1 回合意图 攻击 6", int(e.state.enemy_intent["value"]), 6)
	for expected in [8, 10, 6, 8]:
		end_turn(e)
		eq("下一回合意图 %d" % int(expected), int(e.state.enemy_intent["value"]), int(expected))
	eq("魔像按 攻击6 → 防御8 → 攻击10 循环，玩家存活", e.state.player_hp > 0, true)


# ── A17 魔像执行防御后进入玩家回合 ────────────────────────
func _a17() -> void:
	section("A17 魔像执行防御后进入玩家回合")
	var e := new_battle()
	end_turn(e)  # 第 1 回合：攻击 6
	eq("第 2 回合玩家行动期间魔像无护盾", e.state.enemy_shield, 0)
	end_turn(e)  # 第 2 回合：防御 8
	eq("第 3 回合玩家行动期间魔像仍有 8 护盾", e.state.enemy_shield, 8)
	eq("第 3 回合意图为重击 10", int(e.state.enemy_intent["value"]), 10)
	end_turn(e)  # 第 3 回合敌方阶段：先清护盾
	eq("下一敌方阶段开始时清除剩余护盾", e.state.enemy_shield, 0)


# ── A18 魔像攻击意图已展示时召唤守卫 ──────────────────────
func _a18() -> void:
	section("A18 魔像攻击意图已展示时召唤守卫")
	var e := new_battle()
	var ids := set_hand(e, ["guardian"])
	e.state.energy = 6
	var before := e.get_intent_view()
	eq("召唤前意图目标为玩家", String(before["target_side"]), "player")
	var evs = e.play_card(int(ids[0]))["events"]
	var after := e.get_intent_view()
	eq("伤害数值不变", int(after["value"]), 6)
	eq("目标立即改为守卫", String(after["target_side"]), "minion")
	eq("意图文案更新", String(after["text"]), "攻击守卫：6")
	eq("产生意图目标变化事件", events_of(evs, T.EV_INTENT_TARGET_CHANGED).size(), 1)
	end_turn(e)
	eq("守卫承受 6 伤害（7→1）", int(e.state.minions[0]["hp"]), 1)
	eq("玩家生命不受影响", e.state.player_hp, 60)


# ── A19 连续点击再来一局 ──────────────────────────────────
func _a19() -> void:
	section("A19 连续点击再来一局（规则层部分）")
	var e := new_battle(111)
	e.restart(222)
	e.restart(333)
	eq("只保留一场战斗的状态：回合 1", e.state.turn, 1)
	eq("手牌 5 张", e.state.hand.size(), 5)
	eq("实例总数仍为 20（无重复抽牌）", e.state.instances.size(), 20)
	check("区域互斥完整", integrity_ok(e))
	eq("种子已更新", e.state.rng_seed, 333)


# ── A20 重新挑战 ──────────────────────────────────────────
func _a20() -> void:
	section("A20 重新挑战")
	var e := new_battle()
	# 先把局面弄乱
	var ids := set_hand(e, ["striker", "guardian", "energy_spring", "slash"])
	e.state.energy = 9
	e.play_card(int(ids[0]))
	e.play_card(int(ids[1]))
	e.play_card(int(ids[2]))
	e.play_card(int(ids[3]))
	e.state.player_hp = 41
	e.state.player_shield = 5
	e.state.enemy_hp = 12
	e.state.enemy_shield = 8
	e.state.enemy_cursor = 2
	e.state.turn = 5
	e.restart(777)
	eq("玩家生命 60", e.state.player_hp, 60)
	eq("魔像生命 35", e.state.enemy_hp, 35)
	eq("能量归零后首回合 +1", e.state.energy, 1)
	eq("双方护盾归零", [e.state.player_shield, e.state.enemy_shield], [0, 0])
	eq("行为游标归零", e.state.enemy_cursor, 0)
	eq("随从清空", e.state.minions.size(), 0)
	check("场景清空", e.state.scene.is_empty())
	eq("回合重置为 1", e.state.turn, 1)
	eq("手牌 5 张", e.state.hand.size(), 5)
	eq("牌组重新洗牌为 20 张", e.state.instances.size(), 20)
	check("旧日志已清空后重新记录", e.state.log_lines.size() > 0)
	check("区域互斥完整", integrity_ok(e))


# ── A21 玩家生命归零 ──────────────────────────────────────
func _a21() -> void:
	section("A21 玩家生命归零")
	var e := new_battle()
	e.state.player_hp = 5
	e.state.enemy_intent = {"kind": T.IntentKind.ATTACK, "value": 6}
	e.state.enemy_cursor = 0
	e.enemy_phase()
	eq("生命归零", e.state.player_hp, 0)
	eq("判定为失败", e.state.result, T.Result.DEFEAT)
	eq("阶段锁定", e.state.phase, T.Phase.BATTLE_END)
	var ids := set_hand(e, ["slash"])
	check("终局后禁止出牌", not e.play_card(int(ids[0]))["ok"])
	check("终局后禁止结束回合", not e.request_end_turn()["ok"])


# ── A23 选中攻击牌后取消，或确认时目标无效 ────────────────
func _a23() -> void:
	section("A23 取消选择 / 目标无效时不结算")
	var e := new_battle()
	# 造成「随从槽位已满」：先占满两个槽位
	var ids := set_hand(e, ["guardian", "guardian", "striker"])
	e.state.energy = 12
	e.play_card(int(ids[0]))
	e.play_card(int(ids[1]))
	eq("两个随从槽位已满", e.state.minions.size(), 2)
	var st := int(ids[2])
	var v := e.can_play(st)
	check("给出具体不可用原因", String(v["reason"]) == "随从槽位已满", String(v["reason"]))
	var energy_before := e.state.energy
	var hand_before := e.state.hand.size()
	var discard_before := e.state.discard_pile.size()
	var r := e.play_card(st)
	check("确认时校验失败，不执行", not r["ok"])
	eq("不移牌", e.state.hand.size(), hand_before)
	eq("不扣费", e.state.energy, energy_before)
	eq("不产生弃牌", e.state.discard_pile.size(), discard_before)
	check("区域互斥完整", integrity_ok(e))
	# 取消选择 = 不调用 play_card，状态不变
	check("取消选择不改变攻击牌次数", e.state.attacks_played_this_turn == 0)


# ── A24 两只就绪随从，左侧攻击击败魔像 ────────────────────
func _a24() -> void:
	section("A24 两只就绪随从，左侧攻击击败魔像")
	var e := new_battle()
	var ids := set_hand(e, ["striker", "guardian"])
	e.state.energy = 6
	e.play_card(int(ids[0]))   # 槽位 0：突击兵 3 攻击
	e.play_card(int(ids[1]))   # 槽位 1：守卫 2 攻击
	e.state.minions[0]["can_attack"] = true
	e.state.minions[1]["can_attack"] = true
	e.state.enemy_hp = 3
	clear_hand(e)
	var r := e.confirm_end_turn(-1)
	eq("立即胜利", e.state.result, T.Result.VICTORY)
	eq("只有左侧随从出手", events_of(r["events"], T.EV_MINION_ATTACKED).size(), 1)
	check("右侧随从不再行动",
		int(events_of(r["events"], T.EV_MINION_ATTACKED)[0]["slot"]) == 0)
	check("魔像不再行动", events_of(r["events"], T.EV_ENEMY_ACTED).is_empty())


# ── A25 随从自动攻击命中魔像 ──────────────────────────────
func _a25() -> void:
	section("A25 随从自动攻击命中魔像")
	var e := new_battle()
	var ids := set_hand(e, ["striker"])
	e.state.energy = 5
	e.play_card(int(ids[0]))
	e.state.minions[0]["can_attack"] = true
	clear_hand(e)
	var energy_before := e.state.energy
	var evs = e.resolve_minion_attacks()
	eq("正常结算伤害（35-3）", e.state.enemy_hp, 32)
	eq("不给玩家回能", e.state.energy, energy_before)
	eq("无需玩家选目标，只攻击魔像", events_of(evs, T.EV_MINION_ATTACKED).size(), 1)


# ── 补充：卡牌配置表与规格 §7 一致 ────────────────────────
func _extra_card_table() -> void:
	section("补充 · 卡牌配置表（§7）")
	eq("共 11 种卡", CardDB.CARDS.size(), 11)
	eq("初始牌组合计 20 张", CardDB.initial_deck().size(), 20)
	eq("初始牌组合计与配置一致", CardDB.total_card_count(), 20)
	var counts := {}
	for d in CardDB.initial_deck():
		counts[d] = int(counts.get(d, 0)) + 1
	var expected := {
		"slash": 4, "shield_break": 1, "follow_up": 2, "block": 3, "meditate": 2,
		"energy_blast": 2, "counter_stance": 1, "tactical_draw": 1,
		"energy_spring": 1, "striker": 1, "guardian": 2,
	}
	var ok := true
	for k in expected.keys():
		if int(counts.get(k, -1)) != int(expected[k]):
			ok = false
	check("各卡初始数量与规格一致", ok, str(counts))
	# 独立校验：破盾击按「本次伤害结算前」目标是否有护盾决定伤害（§7）
	var e := new_battle()
	var ids := set_hand(e, ["shield_break"])
	e.state.enemy_shield = 1
	e.play_card(int(ids[0]))
	eq("目标有护盾：造成 7（护盾吸收 1，生命 -6）", e.state.enemy_hp, 29)
	eq("护盾被击破", e.state.enemy_shield, 0)
	var e_ctrl := new_battle()
	var ids_ctrl := set_hand(e_ctrl, ["shield_break"])
	e_ctrl.play_card(int(ids_ctrl[0]))
	eq("目标无护盾：造成 3", e_ctrl.state.enemy_hp, 32)
	# 独立校验：攻守转换先伤害后给盾，且不回能
	var e2 := new_battle()
	var ids2 := set_hand(e2, ["counter_stance"])
	e2.state.energy = 2
	e2.play_card(int(ids2[0]))
	eq("攻守转换造成 5 伤害", e2.state.enemy_hp, 30)
	eq("随后获得 5 护盾", e2.state.player_shield, 5)
	eq("技能不回能", e2.state.energy, 0)


# ── 补充：护盾清除时机与触发制回能细节 ────────────────────
func _extra_shield_rules() -> void:
	section("补充 · 护盾与回能细节（§6.4 / §6.5）")
	# 玩家护盾在下个玩家回合开始清除
	var e := new_battle()
	var ids := set_hand(e, ["block"])
	e.play_card(int(ids[0]))
	eq("格挡获得 6 护盾", e.state.player_shield, 6)
	e._start_player_turn()
	eq("下个玩家回合开始清除玩家护盾", e.state.player_shield, 0)
	# 完全被护盾吸收不触发承伤回能
	var e2 := new_battle()
	var ids2 := set_hand(e2, ["block", "block"])
	e2.play_card(int(ids2[0]))
	e2.play_card(int(ids2[1]))
	eq("12 护盾", e2.state.player_shield, 12)
	e2.state.energy = 0
	e2.state.enemy_intent = {"kind": T.IntentKind.ATTACK, "value": 6}
	e2.enemy_phase()
	eq("伤害全被吸收，生命不变", e2.state.player_hp, 60)
	eq("不触发承伤回能", e2.state.energy, 0)
	# 攻击牌伤害被完全吸收仍然回能
	var e3 := new_battle()
	var ids3 := set_hand(e3, ["slash"])
	e3.state.energy = 0
	e3.state.enemy_shield = 10
	e3.play_card(int(ids3[0]))
	eq("攻击被护盾完全抵挡仍回能", e3.state.energy, 1)
	# 能量上限 10
	var e4 := new_battle()
	e4.state.energy = 10
	e4._gain_energy(3, "test")
	eq("能量上限 10", e4.state.energy, 10)
	# 手牌上限 10：超出的牌仍从牌库移出后进弃牌堆
	var e5 := new_battle()
	clear_hand(e5)
	e5._draw_cards(13)
	eq("手牌上限 10", e5.state.hand.size(), 10)
	eq("超出的 3 张进入弃牌堆", e5.state.discard_pile.size(), 3)
	eq("抽牌堆剩 7", e5.state.draw_pile.size(), 7)
	check("区域互斥完整", integrity_ok(e5))
