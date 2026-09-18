extends SceneTree
##
## 事件链示例：把规则层产生的有序事件逐条打印出来。
## 运行： godot --headless --path . --script res://tests/event_trace.gd
##
## 这个文件本身就是「规则层与界面层如何协作」的说明：
##   规则层是唯一权威 —— 伤害、能量、抽牌只在这里算一次；
##   每个规则入口返回一个「有序事件数组」，界面照着播放即可，绝不自行推导数值。
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")
const BattleEngine = preload("res://src/core/battle_engine.gd")

var _seq := 0


func _initialize() -> void:
	_scenario_a()
	_scenario_b()
	_scenario_c()
	_scenario_d()
	print("")
	print("═".repeat(78))
	quit(0)


# ══════════════════════════════════════════════════════════
#  场景 A：规格 §8.2「第一回合交互示例」的完整事件链
# ══════════════════════════════════════════════════════════

func _scenario_a() -> void:
	_banner("场景 A　规格 §8.2 第一回合交互示例（固定手牌）")
	var e = BattleEngine.new()

	_step("初始化战斗 + 首个玩家回合（start_battle）")
	_dump(e.start_battle(20240917))

	_force_hand(e, ["slash", "follow_up", "energy_blast", "block", "meditate"])
	_line("构造手牌", "斩击 / 追击 / 能量冲击 / 格挡 / 调息　（能量 %d）" % e.state.energy)

	_step("使用「斩击」（2 点）—— 攻击牌不再自带回能，点数建立比较基准")
	_call("play_card(斩击)", e.play_card(_hand_id(e, "slash")))

	_step("使用「追击」（4 点）—— 2→4 是倍数关系：基础 3 改 6，再吃倍数第 1 层强化 +3")
	_call("play_card(追击)", e.play_card(_hand_id(e, "follow_up")))

	_step("使用「能量冲击」（6 点）—— 4→6 无倍因关系：三条链归零，技能也不回能")
	_call("play_card(能量冲击)", e.play_card(_hand_id(e, "energy_blast")))

	_step("使用「格挡」")
	_call("play_card(格挡)", e.play_card(_hand_id(e, "block")))

	_step("使用「调息」")
	_call("play_card(调息)", e.play_card(_hand_id(e, "meditate")))

	_step("结束回合：request_end_turn → confirm_end_turn")
	var req = e.request_end_turn()
	_line("request_end_turn", "needs_keep=%s　（手牌已空，直接结束，跳过保留选择）" % str(req["needs_keep"]))
	_call("confirm_end_turn(-1)", e.confirm_end_turn(-1))

	_footer(e, "对照规格：魔像 35→30→24→12；玩家 60 生命、剩 2 护盾；伤害被护盾吸完所以未触发展伤回能；\n" +
		"　　　　　第 2 回合清除护盾、能量 2、抽 5 张、魔像展示「防御：获得 8 护盾」——与 §8.2 完全一致。")


# ══════════════════════════════════════════════════════════
#  场景 B：嘲讽改目标 → 随从击杀 → 终局截断
# ══════════════════════════════════════════════════════════

func _scenario_b() -> void:
	_banner("场景 B　嘲讽随从实时改变意图目标 → 随从击杀魔像 → 终局截断后续事件")
	var e = BattleEngine.new()
	e.start_battle(7)
	e.state.energy = 9
	_force_hand(e, ["guardian", "striker"])

	_step("当前意图（攻击 6，默认目标是玩家）")
	_line("get_intent_view()", String(e.get_intent_view()["text"]))

	_step("召唤「守卫」（嘲讽）—— 意图数值锁定，但目标立即更新")
	_call("play_card(守卫)", e.play_card(_hand_id(e, "guardian")))
	_line("get_intent_view()", String(e.get_intent_view()["text"]) + "　← 数值仍是 6，目标已改为守卫")

	_step("再召唤「突击兵」占满两个槽位")
	_call("play_card(突击兵)", e.play_card(_hand_id(e, "striker")))

	_step("结束回合：两只随从都是刚召唤的（准备中），敌方 6 点由嘲讽随从承受")
	_force_hand(e, [])
	_call("request_end_turn", e.request_end_turn())
	_call("confirm_end_turn(-1)", e.confirm_end_turn(-1))
	_line("解读", "随从阶段只有 phase_changed —— 两只随从都没出手；敌方 6 点打在守卫身上（7→1），玩家满血")

	_step("把魔像压到 2 点生命：本回合槽位 0 的守卫（2 攻）将击杀它")
	e.state.enemy_hp = 2
	_call("request_end_turn", e.request_end_turn())
	_call("confirm_end_turn(-1)", e.confirm_end_turn(-1))

	_footer(e, "关键：槽位 0 的守卫击杀魔像后立即判定胜利，\n" +
		"　　　槽位 1 的突击兵没有出手，整个敌方阶段也没有产生任何事件 —— 终局截断。")


# ══════════════════════════════════════════════════════════
#  场景 C：回合开始的固定顺序（§6.2 步骤 3 → 步骤 4）
# ══════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════
#  场景 D：新体系 —— 融牌弃牌 / 点数三链 / 累计点数
# ══════════════════════════════════════════════════════════
func _scenario_d() -> void:
	_banner("场景 D　融牌与点数三链：1→2→4→8 建立倍数 3 层，弃牌与累计点数独立结算")
	var e = BattleEngine.new()
	e.start_battle(4242)
	e.state.energy = 9

	_force_hand(e, ["meditate", "slash", "tune", "tactical_draw", "block"])
	_line("构造手牌", "调息(1 点) / 斩击(2 点) / 调律(4 点) / 战术整理(8 点) / 格挡(3 点)")

	_step("融掉「格挡」——融牌不是出牌：不计点、不断链，只把这张牌弃进弃牌堆换 1 能量")
	_call("fuse_card(格挡)", e.fuse_card(_hand_id(e, "block")))
	_line("解读", "只有 card_fused 与 energy_changed(+1)；没有 points/chain 事件，上一张点数仍为空，牌直接进弃牌堆")

	_step("1 → 2 → 4 → 8：连续倍数关系，只强化本次命中的「倍数效果」")
	_call("play_card(调息 1 点)", e.play_card(_hand_id(e, "meditate")))
	_call("play_card(斩击 2 点)", e.play_card(_hand_id(e, "slash")))
	var tune_id := _hand_id(e, "tune")
	var target_id := _hand_id(e, "block")
	_call("play_card(调律 4 点 → 目标格挡 +1 点)", e.play_card(tune_id, {"hand_target": target_id, "point_delta": 1}))
	_call("play_card(战术整理 8 点)", e.play_card(_hand_id(e, "tactical_draw")))
	_line("解读", "倍数 1 → 2 → 3 层；因数/同点保持 0；累计 1+2+4+8=15 点，跨过 12 触发 1 次累计奖励")

	_step("结束回合：临时点数修正与三类链清空（融掉的牌早已在弃牌堆里）")
	_force_hand(e, [])
	_call("confirm_end_turn(-1)", e.confirm_end_turn(-1))
	_line("解读", "turn_started 之后依次出现 energy_changed(+1, turn_start) → 抽牌；\n" +
		"　　　第 2 回合 last_point / 三条链 / 累计点数都归零，链层不跨回合保留。")

	_footer(e, "对照《设计元素表》：M21 融牌独立于出牌、M23~M26 三类链独立叠层与断链、\n" +
		"　　　M28 累计点数独立统计；设计表把 12 点阈值标为「示例」，此处按原型阈值实现。")


func _scenario_c() -> void:
	_banner("场景 C　回合开始固定顺序：先「回合 +1 能量」，再「场景触发 +1 能量」")
	var e = BattleEngine.new()
	e.start_battle(99)
	e.state.energy = 5
	_force_hand(e, ["energy_spring"])

	_step("使用「能量涌泉」—— 打出当回合不回能，只建立持续效果")
	_call("play_card(能量涌泉)", e.play_card(_hand_id(e, "energy_spring")))
	_line("解读", "只有 energy_changed(-2) 是费用；没有任何回能事件")

	_step("结束回合 → 敌方攻击命中玩家（造成生命伤害 → 承伤回能 +1）→ 进入第 2 回合")
	_force_hand(e, [])
	_call("confirm_end_turn(-1)", e.confirm_end_turn(-1))

	_footer(e, "在第 2 回合的开始事件里能清楚看到顺序：\n" +
		"　　　energy_changed(+1, turn_start) 先于 energy_changed(+1, scene)，然后是 scene_triggered 报出剩余次数。\n" +
		"　　　连续结束回合即可看到触发次数 2→1→0，并在第 3 次触发后进入弃牌堆。")


# ══════════════════════════════════════════════════════════
#  输出工具
# ══════════════════════════════════════════════════════════

func _banner(s: String) -> void:
	print("")
	print("═".repeat(78))
	print("  " + s)
	print("═".repeat(78))


func _step(s: String) -> void:
	_seq = 0
	print("")
	print("▶ " + s)


func _line(k: String, v: String) -> void:
	print("   · %s：%s" % [k, v])


func _footer(e, note: String) -> void:
	print("")
	print("   最终状态：%s" % _state_line(e))
	print("   " + note)


## 调用一个规则入口：先报成功/被拒，再逐条列出它产生的事件。
func _call(label: String, r: Dictionary) -> void:
	if bool(r.get("ok", true)):
		_line("调用", label)
	else:
		_line("调用", "%s　→ 被拒绝：%s" % [label, String(r.get("reason", ""))])
	_dump(r.get("events", []))


func _dump(events: Array) -> void:
	if events.is_empty():
		print("      （无事件产生）")
		return
	for ev in events:
		_seq += 1
		var t := String(ev.get("type", ""))
		print("      %2d. %-22s %s" % [_seq, t, _fmt(t, ev)])


func _fmt(t: String, ev: Dictionary) -> String:
	if t == T.EV_BATTLE_STARTED:
		return "battle_id=%s seed=%s　%s" % [ev["battle_id"], ev["seed"], ev["title"]]
	if t == T.EV_TURN_STARTED:
		return "第 %d 回合" % int(ev["turn"])
	if t == T.EV_PHASE_CHANGED:
		return _phase_name(int(ev["phase"]))
	if t == T.EV_SHIELD_CLEARED:
		return "%s 清除 %d 点护盾" % [_side_name(int(ev["side"])), int(ev["amount"])]
	if t == T.EV_ENERGY_CHANGED:
		return "delta=%+d → %d　（来源 %s）" % [int(ev["delta"]), int(ev["value"]), _reason_name(String(ev["reason"]))]
	if t == T.EV_CARDS_DRAWN:
		return "抽到 %d 张" % int(ev["count"])
	if t == T.EV_CARD_MOVED:
		return "%s　%s → %s" % [CardDB.card_name(String(ev["def_id"])),
			_zone_name(int(ev["from"])), _zone_name(int(ev["to"]))]
	if t == T.EV_CARD_PLAYED:
		return "打出「%s」" % ev["name"]
	if t == T.EV_CARD_GAINED_ENERGY:
		return "「%s」作为卡牌效果回能 %d" % [CardDB.card_name(String(ev.get("def_id", ""))), int(ev["amount"])]
	if t == T.EV_POINTS_TOTAL_CHANGED:
		return "点数 %d → 本回合累计 %d（阈值 %d，已到档 %d 次）" % [
			int(ev["point"]), int(ev["total"]), int(ev["threshold"]), int(ev["triggers"])]
	if t == T.EV_CHAIN_UPDATED:
		var rel := int(ev["relation"])
		var lv := int(ev["level"])
		var rel_text := "无关系：三条链归零" if lv == 0 else "%s第 %d 层" % [String(T.CHAIN_NAME.get(rel, "")), lv]
		return "上一张 %d → 本次 %d：%s（倍数 %d ｜ 因数 %d ｜ 同点 %d）" % [
			int(ev["last_point"]), int(ev["point"]), rel_text,
			int(ev["mult_level"]), int(ev["factor_level"]), int(ev["same_level"])]
	if t == T.EV_CUMULATIVE_TRIGGERED:
		return "累计点数到档 %d：下回合额外抽 %d 张（不贡献相邻链层）" % [
			int(ev["threshold"]), int(ev["bonus_draw"])]
	if t == T.EV_CARD_FUSED:
		if int(ev["energy_gained"]) > 0:
			return "融牌「%s」（%d 点）弃进弃牌堆 → 能量 +%d；不算出牌、不断链" % [
				ev["name"], int(ev["point"]), int(ev["energy_gained"])]
		return "融牌「%s」（%d 点）弃进弃牌堆；能量已满，不获得能量" % [ev["name"], int(ev["point"])]
	if t == T.EV_POINT_MODIFIED:
		return "手牌点数修正「%s」%d → %d（本回合有效，不追溯已出牌）" % [
			ev.get("name", ""), int(ev["before"]), int(ev["after"])]
	if t == T.EV_TEMP_CARD_ADDED:
		return "生成临时牌「%s」（%d 点，不可融 / 不可保留）" % [ev["name"], int(ev["points"])]
	if t == T.EV_TEMP_CARD_EXPIRED:
		return "临时牌「%s」回合结束离场" % ev.get("name", "")
	if t == T.EV_CARD_EXILED:
		return "临时牌「%s」用后移出战斗" % ev.get("name", "")
	if t == T.EV_FIRST_TRIGGER:
		return "场上监听「%s」触发：%s" % [ev["name"], ev["desc"]]
	if t == T.EV_MINION_SHIELD_GAINED:
		return "仆从「%s」获得 %d 护盾 → 共 %d（下个玩家回合清除）" % [
			ev["name"], int(ev["amount"]), int(ev["shield"])]
	if t == T.EV_MINION_SHIELD_CLEARED:
		return "仆从槽位 %d 护盾 %d 清除" % [int(ev["slot"]), int(ev["amount"])]
	if t == T.EV_MINION_BUFFED:
		return "随从「%s」本轮攻击 +%d → %d" % [ev["name"], int(ev["amount"]), int(ev["attack"])]
	if t == T.EV_MINION_HEALED:
		return "随从「%s」恢复 %d 生命 → %d" % [ev["name"], int(ev["amount"]), int(ev["hp"])]
	if t == T.EV_MINION_COMMANDED:
		return "指令：随从「%s」立即攻击 %d" % [ev["name"], int(ev["attack"])]
	if t == T.EV_TUTOR_OPENED:
		return "检索：查看牌库顶 %d 张（%s）" % [ev["instance_ids"].size(), "、".join(ev["names"])]
	if t == T.EV_TUTOR_RESOLVED:
		return "检索选择「%s」%s" % [ev["name"], "加入手牌" if bool(ev["to_hand"]) else "进入弃牌堆"]
	if t == T.EV_DAMAGE:
		return "%s 受到 %d 伤害（护盾吸收 %d，生命 -%d）→ 剩余生命 %d" % [
			_side_name(int(ev["target"])), int(ev["amount"]),
			int(ev["absorbed"]), int(ev["hp_loss"]), int(ev["hp"])]
	if t == T.EV_SHIELD_GAINED:
		return "%s 获得 %d 护盾 → 共 %d" % [_side_name(int(ev["side"])), int(ev["amount"]), int(ev["value"])]
	if t == T.EV_MINION_SUMMONED:
		return "「%s」进入槽位 %d（%d 攻 / %d 生命，嘲讽=%s，本回合不可攻击）" % [
			ev["name"], int(ev["slot"]), int(ev["attack"]), int(ev["hp"]), str(ev["taunt"])]
	if t == T.EV_MINION_ATTACKED:
		return "「%s」自动攻击 %d" % [ev["name"], int(ev["attack"])]
	if t == T.EV_MINION_DIED:
		return "「%s」死亡，卡牌进弃牌堆" % ev["name"]
	if t == T.EV_SCENE_PLAYED:
		return "场景「%s」生效，剩余 %d 次" % [ev["effect_id"], int(ev["triggers"])]
	if t == T.EV_SCENE_TRIGGERED:
		return "场景「%s」触发，剩余 %d 次" % [ev["effect_id"], int(ev["triggers_left"])]
	if t == T.EV_SCENE_EXPIRED:
		return "场景结束（原因 %s）" % String(ev.get("reason", "-"))
	if t == T.EV_INTENT_REVEALED:
		return "公开意图「%s」" % ev["text"]
	if t == T.EV_INTENT_TARGET_CHANGED:
		return "意图目标实时更新为「%s」" % ev["text"]
	if t == T.EV_ENEMY_ACTED:
		return "%s 执行「%s %d」" % [ev["name"], _intent_name(int(ev["kind"])), int(ev["value"])]
	if t == T.EV_BATTLE_ENDED:
		return "%s（第 %d 回合，玩家剩余 %d 生命）" % [
			"胜利" if int(ev["result"]) == T.Result.VICTORY else "失败",
			int(ev["turn"]), int(ev["player_hp"])]
	return ""


func _phase_name(p: int) -> String:
	match p:
		T.Phase.PLAYER_TURN_START: return "阶段 → 玩家回合开始"
		T.Phase.PLAYER_ACTION: return "阶段 → 玩家行动"
		T.Phase.KEEP_SELECT: return "阶段 → 保留选择"
		T.Phase.MINION_ATTACK: return "阶段 → 随从自动攻击"
		T.Phase.ENEMY_PHASE: return "阶段 → 敌方阶段"
		T.Phase.BATTLE_END: return "阶段 → 终局（锁定输入）"
	return "阶段 → %d" % p


func _side_name(s: int) -> String:
	match s:
		T.Side.PLAYER: return "玩家"
		T.Side.ENEMY: return "魔像"
		T.Side.MINION: return "随从"
	return "?"


func _intent_name(k: int) -> String:
	return "攻击" if k == T.IntentKind.ATTACK else "防御"


func _reason_name(r: String) -> String:
	match r:
		"turn_start": return "回合开始 +1"
		"scene": return "场景效果"
		"card": return "卡牌效果"
		"cost": return "支付费用"
		"damage_taken": return "承伤回能"
	return r


func _zone_name(z: int) -> String:
	return String(T.ZONE_NAME.get(z, "场上区域"))


func _state_line(e) -> String:
	var s = e.state
	var sname := "无"
	if not s.scene.is_empty():
		sname = "%s（剩 %d 次）" % [CardDB.card_name(s.def_id_of(int(s.scene["card_instance"]))), int(s.scene["triggers"])]
	return "回合 %d　｜　玩家 %d/%d 生命 %d 护盾 能量 %d　｜　魔像 %d 生命 %d 护盾 游标 %d　｜　手牌 %d 抽牌堆 %d 弃牌堆 %d　｜　随从 %d，场景 %s" % [
		s.turn, s.player_hp, s.player_max_hp, s.player_shield, s.energy,
		s.enemy_hp, s.enemy_shield, s.enemy_cursor,
		s.hand.size(), s.draw_pile.size(), s.discard_pile.size(),
		s.minions.size(), sname]


# ══════════════════════════════════════════════════════════
#  构造确定性手牌（演示用）
# ══════════════════════════════════════════════════════════

func _force_hand(e, def_ids: Array) -> void:
	for iid in e.state.hand.duplicate():
		e.state.hand.erase(iid)
		e.state.draw_pile.append(int(iid))
		e.state.set_zone(int(iid), T.Zone.DRAW_PILE)
	for d in def_ids:
		var iid := -1
		for src in [e.state.draw_pile, e.state.discard_pile]:
			for x in src.duplicate():
				if e.state.def_id_of(int(x)) == String(d):
					iid = int(x)
					break
			if iid != -1:
				break
		if iid == -1:
			# 牌组外的候选池卡（count = 0）现场创建，便于逐条演示
			if CardDB.has_card(String(d)):
				iid = e.state.create_instance(String(d), T.Zone.HAND)
			else:
				continue
		e.state.draw_pile.erase(iid)
		e.state.discard_pile.erase(iid)
		e.state.hand.append(iid)
		e.state.set_zone(iid, T.Zone.HAND)


func _hand_id(e, def_id: String) -> int:
	return e.state.find_in_hand(def_id)
