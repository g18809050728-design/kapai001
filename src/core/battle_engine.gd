class_name BattleEngine
extends RefCounted
##
## 战斗规则层。完全独立于界面与动画（规格 §1「战斗规则应独立于界面和动画」）。
##
## 公开规则入口与规格 §10 的「建议规则入口」一一对应：
##   init_battle / start_battle ……… 初始化战斗（§3、§9）
##   start_player_turn ……………… 开始玩家回合（§6.2 固定 8 步）
##   play_card ……………………… 使用卡牌（§5.1、§7）
##   request_end_turn / cancel_end_turn / confirm_end_turn … 结束回合与保留牌（§5.3）
##   resolve_minion_attacks ……… 结算随从自动攻击（§5.2、§6.7）
##   enemy_phase ……………………… 执行敌方阶段（§6.6）
##   restart …………………………… 重新挑战（§9）
##
## 每个公开入口返回有序事件数组，界面只播放事件、绝不自行计算伤害（§10）。
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")
const EnemyDB = preload("res://src/core/enemy_db.gd")
const BattleState = preload("res://src/core/battle_state.gd")

## 战斗序号，用于生成唯一战斗 ID（§10：战斗 ID）。
static var _serial: int = 0

var state: BattleState = null

var _rng: RandomNumberGenerator = null
var _events: Array = []
## 本次敌方行动是否已发放过「承伤回能」（§6.5：每次行动最多一次）
var _enemy_action_energy_granted: bool = false


# ══════════════════════════════════════════════════════════
#  初始化 / 重新挑战
# ══════════════════════════════════════════════════════════

## 初始化战斗但不开始回合（§3）。返回事件。
func init_battle(seed_value: int = 0) -> Array:
	_begin()
	state = BattleState.new()
	_serial += 1
	state.battle_id = "B%d-%d" % [seed_value, _serial]
	state.rng_seed = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	# 玩家（§6.1）
	state.player_max_hp = T.PLAYER_MAX_HP
	state.player_hp = T.PLAYER_MAX_HP
	state.player_shield = 0
	state.energy = 0

	# 敌人（§8）
	var enc := EnemyDB.encounter()
	var edef := EnemyDB.get_enemy(String(enc["enemy_id"]))
	state.enemy_def_id = String(edef["id"])
	state.enemy_name = String(edef["name"])
	state.enemy_max_hp = int(edef["max_hp"])
	state.enemy_hp = int(edef["max_hp"])
	state.enemy_shield = int(edef.get("initial_shield", 0))
	state.enemy_cursor = 0
	state.enemy_intent = {}

	state.minions = []
	state.scene = {}
	state.attacks_played_this_turn = 0
	state.turn = 0
	state.result = T.Result.NONE
	state.log_lines = []
	state.phase = T.Phase.IDLE

	# 固定 20 张牌 → 洗入抽牌堆
	for def_id in CardDB.initial_deck():
		var iid := state.create_instance(String(def_id), T.Zone.DRAW_PILE)
		state.draw_pile.append(iid)
	_shuffle(state.draw_pile)

	_ev(T.EV_BATTLE_STARTED, {
		"battle_id": state.battle_id,
		"seed": seed_value,
		"title": enc["title"],
	})
	_log("战斗开始：%s" % enc["title"])
	return _events


## 初始化 + 执行第一个玩家回合开始流程（§3、§6.1）。
func start_battle(seed_value: int = 0) -> Array:
	init_battle(seed_value)
	_start_player_turn()
	return _events


## 重新挑战（§9）：全部状态清空、固定 20 张牌重新洗牌、再执行首回合开始流程。
func restart(seed_value: int = -1) -> Array:
	if seed_value < 0:
		seed_value = make_seed()
	return start_battle(seed_value)


func make_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return absi(r.randi())


# ══════════════════════════════════════════════════════════
#  玩家回合开始（§6.2 固定顺序）
# ══════════════════════════════════════════════════════════

func start_player_turn() -> Array:
	_begin()
	_start_player_turn()
	return _events


func _start_player_turn() -> void:
	_set_phase(T.Phase.PLAYER_TURN_START)

	# 1. 回合数 +1，本回合普通攻击使用次数清零
	state.turn += 1
	state.attacks_played_this_turn = 0
	_ev(T.EV_TURN_STARTED, {"turn": state.turn})
	_log("── 第 %d 回合 ──" % state.turn)

	# 2. 玩家护盾清零
	if state.player_shield > 0:
		_ev(T.EV_SHIELD_CLEARED, {"side": T.Side.PLAYER, "amount": state.player_shield})
		_log("玩家护盾 %d 清除" % state.player_shield)
		state.player_shield = 0

	# 3. 能量 +1，上限 10，溢出丢弃
	_gain_energy(1, "turn_start")

	# 4. 结算场景回合开始效果，并更新持续次数
	_resolve_scene_turn_start()

	# 5. 存活随从设置为本回合可攻击
	for m in state.minions:
		if int(m["hp"]) > 0:
			m["can_attack"] = true

	# 6. 抽 5 张（保留牌不会减少抽牌数量）
	_draw_cards(T.DRAW_PER_TURN)

	# 7. 根据敌人行为游标确定并公开本轮意图
	_reveal_intent()

	# 8. 进入玩家行动阶段
	_set_phase(T.Phase.PLAYER_ACTION)


# ══════════════════════════════════════════════════════════
#  使用卡牌（§5.1、§7）
# ══════════════════════════════════════════════════════════

## 校验是否可出牌。返回 {ok, reason}；reason 直接可显示给玩家（§4.3）。
func can_play(instance_id: int) -> Dictionary:
	if state == null:
		return _no("尚未初始化战斗")
	if state.battle_over():
		return _no("战斗已结束")
	if state.phase != T.Phase.PLAYER_ACTION:
		return _no("当前阶段不能出牌")
	var def_id := state.def_id_of(instance_id)
	if def_id == "":
		return _no("卡牌不存在")
	if state.zone_of(instance_id) != T.Zone.HAND:
		return _no("该牌不在手牌中")

	var card := CardDB.get_card(def_id)
	var cost := int(card.get("cost", 0))
	if cost > state.energy:
		return _no("需要 %d 能量，当前 %d" % [cost, state.energy])

	var tt := int(card.get("target", T.TargetType.NONE))
	if tt == T.TargetType.SINGLE_ENEMY and state.enemy_hp <= 0:
		return _no("没有合法目标")
	if tt == T.TargetType.MINION_SLOT and state.free_minion_slots().is_empty():
		return _no("随从槽位已满")
	return {"ok": true, "reason": ""}


## 确认使用一张手牌。校验成功后才扣费并执行（§5.1 步骤 5）。
func play_card(instance_id: int) -> Dictionary:
	_begin()
	var v := can_play(instance_id)
	if not v["ok"]:
		# 取消出牌或目标无效不算成功使用，不移牌、不回能（§6.5、A23）
		return {"ok": false, "reason": v["reason"], "events": []}

	var def_id := state.def_id_of(instance_id)
	var card := CardDB.get_card(def_id)
	var name := String(card.get("name", ""))
	var cost := int(card.get("cost", 0))

	if cost > 0:
		state.energy -= cost
		_ev(T.EV_ENERGY_CHANGED, {"delta": -cost, "value": state.energy, "reason": "cost"})

	# 手牌 → 结算区（§6.3：普通牌确认使用后先进入结算区）
	_move_instance(instance_id, T.Zone.RESOLVE)
	_ev(T.EV_CARD_PLAYED, {"instance_id": instance_id, "def_id": def_id, "name": name})
	_log("使用「%s」" % name)

	# 攻击牌计数：先快照「此前」数量，再自增（§7 追击读取此前使用过的攻击牌数）
	var ctx := {"attacks_before": state.attacks_played_this_turn}
	if CardDB.is_attack_card(def_id):
		state.attacks_played_this_turn += 1
		_ev(T.EV_ATTACK_CARD_USED, {
			"instance_id": instance_id,
			"count": state.attacks_played_this_turn,
		})

	_resolve_ops(card.get("ops", []), instance_id, name, ctx)

	# 效果全部结束后仍在结算区的牌进入弃牌堆；
	# 随从牌/场景牌已进入对应场上区域，不同时进入弃牌堆（§6.3）。
	if state.zone_of(instance_id) == T.Zone.RESOLVE:
		_move_instance(instance_id, T.Zone.DISCARD)

	return {"ok": true, "reason": "", "events": _events}


func _resolve_ops(ops: Array, card_instance: int, source_name: String, ctx: Dictionary) -> void:
	for op in ops:
		# §6.4：一旦进入终局，停止后续效果
		if state.battle_over():
			break
		var kind := String(op.get("op", ""))
		if kind == CardDB.OP_GAIN_ENERGY:
			_gain_energy(int(op.get("amount", 0)), "card")
			_ev(T.EV_CARD_GAINED_ENERGY, {
				"instance_id": card_instance,
				"def_id": state.def_id_of(card_instance),
				"amount": int(op.get("amount", 0)),
			})
		elif kind == CardDB.OP_GAIN_SHIELD:
			_gain_player_shield(int(op.get("amount", 0)))
		elif kind == CardDB.OP_DAMAGE:
			var dmg := int(op.get("amount", 0))
			var alt_when := String(op.get("alt_when", ""))
			if alt_when == "target_has_shield":
				# 破盾击：按本次伤害结算「前」目标是否有护盾判定（§7）
				if state.enemy_shield > 0:
					dmg = int(op.get("alt", dmg))
			elif alt_when == "attacked_this_turn":
				# 追击：本回合此前已成功使用过攻击牌
				if int(ctx.get("attacks_before", 0)) > 0:
					dmg = int(op.get("alt", dmg))
			_damage_enemy(dmg, source_name)
		elif kind == CardDB.OP_DRAW:
			_draw_cards(int(op.get("amount", 0)))
		elif kind == CardDB.OP_SUMMON:
			_summon(op, card_instance)
		elif kind == CardDB.OP_SCENE_SPRING:
			_play_scene(op, card_instance)


# ══════════════════════════════════════════════════════════
#  结束回合与保留牌（§5.3）
# ══════════════════════════════════════════════════════════

## 点击「结束回合」。返回 {ok, reason, needs_keep, events}。
## needs_keep = true 表示有手牌，需进入保留选择模式。
func request_end_turn() -> Dictionary:
	_begin()
	if state == null or state.battle_over():
		return {"ok": false, "reason": "战斗已结束", "needs_keep": false, "events": _events}
	if state.phase != T.Phase.PLAYER_ACTION:
		return {"ok": false, "reason": "当前阶段不能结束回合", "needs_keep": false, "events": _events}
	if state.hand.is_empty():
		# 无手牌时直接结束
		return {"ok": true, "reason": "", "needs_keep": false, "events": _events}
	_set_phase(T.Phase.KEEP_SELECT)
	return {"ok": true, "reason": "", "needs_keep": true, "events": _events}


## 取消保留选择，返回行动阶段。
func cancel_end_turn() -> Dictionary:
	_begin()
	if state == null or state.phase != T.Phase.KEEP_SELECT:
		return {"ok": false, "reason": "当前不在保留选择阶段", "events": _events}
	_set_phase(T.Phase.PLAYER_ACTION)
	return {"ok": true, "reason": "", "events": _events}


## 确认结束回合。keep_instance_id 为要保留的手牌实例（-1 表示不保留）。
## 流程：保留牌 → 其余弃置 → 随从自动攻击 → 敌方阶段 → 新的玩家回合（§5.3、§10.1）
func confirm_end_turn(keep_instance_id: int = -1) -> Dictionary:
	_begin()
	if state == null or state.battle_over():
		return {"ok": false, "reason": "战斗已结束", "events": _events}
	if state.phase != T.Phase.KEEP_SELECT and state.phase != T.Phase.PLAYER_ACTION:
		return {"ok": false, "reason": "当前阶段不能结束回合", "events": _events}
	if state.phase == T.Phase.PLAYER_ACTION and not state.hand.is_empty():
		return {"ok": false, "reason": "有手牌时必须先进入保留选择", "events": _events}

	var kept := -1
	var discarded: Array = []
	for iid in state.hand.duplicate():
		if iid == keep_instance_id:
			kept = iid
			continue
		_move_instance(int(iid), T.Zone.DISCARD)
		discarded.append(iid)
	if kept != -1:
		_log("保留「%s」，其余 %d 张进入弃牌堆" % [
			CardDB.card_name(state.def_id_of(kept)), discarded.size()])
	else:
		_log("不保留手牌，%d 张进入弃牌堆" % discarded.size())

	_resolve_minion_attacks()
	# §6.7：魔像死亡立即胜利，停止剩余攻击与敌方行动
	if not state.battle_over():
		_enemy_phase()
	if state.battle_over():
		return {"ok": true, "reason": "", "events": _events}

	_start_player_turn()
	return {"ok": true, "reason": "", "events": _events}


# ══════════════════════════════════════════════════════════
#  随从自动攻击（§5.2、§6.7）
# ══════════════════════════════════════════════════════════

func resolve_minion_attacks() -> Array:
	_begin()
	_resolve_minion_attacks()
	return _events


func _resolve_minion_attacks() -> void:
	_set_phase(T.Phase.MINION_ATTACK)
	# 按槽位从左到右依次结算，每次攻击后检查终局
	for m in state.living_minions_ordered():
		if state.battle_over():
			break
		if not bool(m["can_attack"]):
			continue
		m["can_attack"] = false
		var label := CardDB.card_name(state.def_id_of(int(m["card_instance"])))
		_ev(T.EV_MINION_ATTACKED, {
			"slot": int(m["slot"]),
			"attack": int(m["attack"]),
			"card_instance": int(m["card_instance"]),
			"name": label,
		})
		_log("随从「%s」自动攻击" % label)
		_damage_enemy(int(m["attack"]), label)


# ══════════════════════════════════════════════════════════
#  敌方阶段（§6.6）
# ══════════════════════════════════════════════════════════

func enemy_phase() -> Array:
	_begin()
	_enemy_phase()
	return _events


func _enemy_phase() -> void:
	if state.battle_over():
		return
	_set_phase(T.Phase.ENEMY_PHASE)

	# 1. 清除魔像剩余护盾（§6.4：敌人护盾在下个敌方阶段开始时统一清除）
	if state.enemy_shield > 0:
		_ev(T.EV_SHIELD_CLEARED, {"side": T.Side.ENEMY, "amount": state.enemy_shield})
		_log("%s护盾 %d 清除" % [state.enemy_name, state.enemy_shield])
		state.enemy_shield = 0

	# 2. 执行本轮已公开的意图（数值在展示后锁定）
	_enemy_action_energy_granted = false
	var intent: Dictionary = state.enemy_intent
	if intent.is_empty():
		return
	var kind := int(intent.get("kind", -1))
	var value := int(intent.get("value", 0))
	_ev(T.EV_ENEMY_ACTED, {"kind": kind, "value": value, "name": state.enemy_name})

	if kind == T.IntentKind.DEFEND:
		state.enemy_shield += value
		_ev(T.EV_SHIELD_GAINED, {
			"side": T.Side.ENEMY,
			"amount": value,
			"value": state.enemy_shield,
		})
		_log("%s获得 %d 护盾" % [state.enemy_name, value])
	elif kind == T.IntentKind.ATTACK:
		# 攻击时按嘲讽规则确定目标（§6.7），召唤守卫后目标立即更新（§6.6）
		var target := state.leftmost_taunt_minion()
		if target.is_empty():
			_log("%s攻击玩家 %d" % [state.enemy_name, value])
			_damage_player(value, true, state.enemy_name)
		else:
			var mname := CardDB.card_name(state.def_id_of(int(target["card_instance"])))
			_log("%s攻击随从「%s」%d" % [state.enemy_name, mname, value])
			_damage_minion(target, value, state.enemy_name)

	# 3. 死亡与终局检查已在伤害函数内完成

	# 4. 若战斗继续，魔像行为游标前进一格并循环
	if not state.battle_over():
		_advance_enemy_cursor()


func _advance_enemy_cursor() -> void:
	var bs := EnemyDB.behaviors(state.enemy_def_id)
	if bs.is_empty():
		return
	var idx := state.enemy_cursor % bs.size()
	var b: Dictionary = bs[idx]
	state.enemy_cursor = int(b.get("next", (idx + 1) % bs.size()))


func _reveal_intent() -> void:
	var bs := EnemyDB.behaviors(state.enemy_def_id)
	if bs.is_empty():
		return
	var b: Dictionary = bs[state.enemy_cursor % bs.size()]
	state.enemy_intent = {"kind": int(b["kind"]), "value": int(b["value"])}
	var view := get_intent_view()
	_ev(T.EV_INTENT_REVEALED, {
		"kind": int(state.enemy_intent["kind"]),
		"value": int(state.enemy_intent["value"]),
		"target_side": view.get("target_side", ""),
		"target_slot": view.get("target_slot", -1),
		"text": view.get("text", ""),
	})
	_log("敌人意图：%s" % view.get("text", ""))


## 意图显示视图（§4.2：显示实际数值和目标）。
func get_intent_view() -> Dictionary:
	if state == null or state.enemy_intent.is_empty():
		return {}
	var kind := int(state.enemy_intent.get("kind", -1))
	var value := int(state.enemy_intent.get("value", 0))
	if kind == T.IntentKind.DEFEND:
		return {
			"kind": kind, "value": value,
			"target_side": "self", "target_slot": -1,
			"text": "防御：获得 %d 护盾" % value,
		}
	var t := state.leftmost_taunt_minion()
	if t.is_empty():
		return {
			"kind": kind, "value": value,
			"target_side": "player", "target_slot": -1,
			"text": "攻击玩家：%d" % value,
		}
	var mname := CardDB.card_name(state.def_id_of(int(t["card_instance"])))
	return {
		"kind": kind, "value": value,
		"target_side": "minion", "target_slot": int(t["slot"]),
		"target_name": mname,
		"text": "攻击%s：%d" % [mname, value],
	}


# ══════════════════════════════════════════════════════════
#  伤害与护盾（§6.4）
# ══════════════════════════════════════════════════════════

func _gain_player_shield(amount: int) -> void:
	if amount <= 0:
		return
	state.player_shield += amount
	_ev(T.EV_SHIELD_GAINED, {
		"side": T.Side.PLAYER,
		"amount": amount,
		"value": state.player_shield,
	})
	_log("获得 %d 护盾（当前 %d）" % [amount, state.player_shield])


func _damage_enemy(amount: int, source_name: String) -> void:
	if amount <= 0:
		return
	var absorbed := mini(state.enemy_shield, amount)
	state.enemy_shield -= absorbed
	var hp_loss := amount - absorbed
	state.enemy_hp = maxi(0, state.enemy_hp - hp_loss)
	_ev(T.EV_DAMAGE, {
		"target": T.Side.ENEMY, "amount": amount, "absorbed": absorbed,
		"hp_loss": hp_loss, "hp": state.enemy_hp, "shield": state.enemy_shield,
		"source": source_name,
	})
	_log("%s" % _damage_text(source_name, state.enemy_name, amount, absorbed, hp_loss))
	_check_endgame()


func _damage_player(amount: int, allow_energy: bool, source_name: String) -> void:
	if amount <= 0:
		return
	var absorbed := mini(state.player_shield, amount)
	state.player_shield -= absorbed
	var hp_loss := amount - absorbed
	state.player_hp = maxi(0, state.player_hp - hp_loss)
	_ev(T.EV_DAMAGE, {
		"target": T.Side.PLAYER, "amount": amount, "absorbed": absorbed,
		"hp_loss": hp_loss, "hp": state.player_hp, "shield": state.player_shield,
		"source": source_name,
	})
	_log("%s" % _damage_text(source_name, "玩家", amount, absorbed, hp_loss))
	# §6.5：敌人的一次行动造成玩家生命伤害才 +1，完全被护盾吸收不触发
	if hp_loss > 0 and allow_energy and not _enemy_action_energy_granted:
		_enemy_action_energy_granted = true
		_gain_energy(1, "damage_taken")
	_check_endgame()


func _damage_minion(minion: Dictionary, amount: int, source_name: String) -> void:
	if amount <= 0 or minion.is_empty():
		return
	var mname := CardDB.card_name(state.def_id_of(int(minion["card_instance"])))
	var hp_loss := amount
	minion["hp"] = maxi(0, int(minion["hp"]) - hp_loss)
	_ev(T.EV_DAMAGE, {
		"target": T.Side.MINION, "slot": int(minion["slot"]),
		"amount": amount, "absorbed": 0, "hp_loss": hp_loss,
		"hp": int(minion["hp"]), "source": source_name,
	})
	_log("%s对随从「%s」造成 %d 伤害（剩余 %d）" % [source_name, mname, amount, int(minion["hp"])])
	if int(minion["hp"]) <= 0:
		# §6.7：单段伤害击败随从后的超额伤害不溢出给玩家，也不触发承伤回能
		_kill_minion(minion)


func _kill_minion(minion: Dictionary) -> void:
	var key_before := _intent_target_key()
	var ci := int(minion["card_instance"])
	var slot := int(minion["slot"])
	var mname := CardDB.card_name(state.def_id_of(ci))
	state.minions.erase(minion)
	_move_instance(ci, T.Zone.DISCARD)
	_ev(T.EV_MINION_DIED, {"slot": slot, "card_instance": ci, "name": mname})
	_log("随从「%s」死亡（卡牌进入弃牌堆）" % mname)
	_refresh_intent_target(key_before)


func _damage_text(source_name: String, target_name: String, amount: int, absorbed: int, hp_loss: int) -> String:
	if absorbed > 0 and hp_loss > 0:
		return "%s对%s造成 %d 伤害（护盾吸收 %d，生命 -%d）" % [source_name, target_name, amount, absorbed, hp_loss]
	if absorbed > 0 and hp_loss == 0:
		return "%s对%s造成 %d 伤害（全部被护盾吸收）" % [source_name, target_name, amount]
	return "%s对%s造成 %d 伤害" % [source_name, target_name, amount]


func _check_endgame() -> void:
	if state.result != T.Result.NONE:
		return
	# §6.9：玩家生命为 0 失败；魔像生命为 0 且玩家存活时胜利
	if state.player_hp <= 0:
		state.result = T.Result.DEFEAT
	elif state.enemy_hp <= 0:
		state.result = T.Result.VICTORY
	if state.result != T.Result.NONE:
		_set_phase(T.Phase.BATTLE_END)
		_ev(T.EV_BATTLE_ENDED, {
			"result": state.result,
			"turn": state.turn,
			"player_hp": state.player_hp,
			"enemy_hp": state.enemy_hp,
		})
		_log("战斗胜利" if state.result == T.Result.VICTORY else "挑战失败")


# ══════════════════════════════════════════════════════════
#  随从与场景
# ══════════════════════════════════════════════════════════

func _summon(op: Dictionary, card_instance: int) -> void:
	var slots := state.free_minion_slots()
	if slots.is_empty():
		return
	var key_before := _intent_target_key()
	var slot: int = int(slots[0])
	var hp := int(op.get("hp", 1))
	var m := {
		"card_instance": card_instance,
		"slot": slot,
		"attack": int(op.get("attack", 0)),
		"hp": hp,
		"max_hp": hp,
		"taunt": bool(op.get("taunt", false)),
		"can_attack": false,   # §6.7：召唤当回合不能攻击
	}
	state.minions.append(m)
	# 必须走 _move_instance 才能把实例从结算区移出（§6.3 区域互斥）
	_move_instance(card_instance, T.Zone.MINION_FIELD)
	var mname := CardDB.card_name(state.def_id_of(card_instance))
	_ev(T.EV_MINION_SUMMONED, {
		"slot": slot, "card_instance": card_instance, "name": mname,
		"attack": m["attack"], "hp": hp, "taunt": m["taunt"], "can_attack": false,
	})
	_log("召唤「%s」（%d 攻击 / %d 生命%s），本回合不可攻击" % [
		mname, int(m["attack"]), hp, "，嘲讽" if bool(m["taunt"]) else ""])
	_refresh_intent_target(key_before)


func _play_scene(op: Dictionary, card_instance: int) -> void:
	# §6.8：玩家场上仅能存在一张场景牌，新场景立即替换旧场景
	if not state.scene.is_empty():
		var old := int(state.scene["card_instance"])
		_move_instance(old, T.Zone.DISCARD)
		_ev(T.EV_SCENE_EXPIRED, {"card_instance": old, "reason": "replaced"})
		state.scene = {}
	var triggers := int(op.get("triggers", T.SCENE_SPRING_TRIGGERS))
	state.scene = {
		"card_instance": card_instance,
		"effect_id": "energy_spring",
		"triggers": triggers,
	}
	_move_instance(card_instance, T.Zone.SCENE_FIELD)
	_ev(T.EV_SCENE_PLAYED, {
		"card_instance": card_instance,
		"effect_id": "energy_spring",
		"triggers": triggers,
	})
	# §6.8：能量涌泉打出时不立即回能
	_log("场景「能量涌泉」生效，剩余 %d 次触发" % triggers)


func _resolve_scene_turn_start() -> void:
	if state.scene.is_empty():
		return
	var s: Dictionary = state.scene
	_gain_energy(1, "scene")
	var left := int(s["triggers"]) - 1
	s["triggers"] = left
	_ev(T.EV_SCENE_TRIGGERED, {
		"card_instance": int(s["card_instance"]),
		"effect_id": s["effect_id"],
		"triggers_left": left,
	})
	_log("场景「能量涌泉」触发：额外 1 能量（剩余 %d 次）" % left)
	# 满能量时依然消耗一次触发次数；第三次触发后进入弃牌堆
	if left <= 0:
		var ci := int(s["card_instance"])
		_move_instance(ci, T.Zone.DISCARD)
		state.scene = {}
		_ev(T.EV_SCENE_EXPIRED, {"card_instance": ci, "reason": "triggers_exhausted"})
		_log("能量涌泉触发完毕，进入弃牌堆")


# ══════════════════════════════════════════════════════════
#  意图目标联动（§6.6）
# ══════════════════════════════════════════════════════════

func _intent_target_key() -> String:
	if state == null or state.enemy_intent.is_empty():
		return ""
	if int(state.enemy_intent.get("kind", -1)) != T.IntentKind.ATTACK:
		return ""
	var t := state.leftmost_taunt_minion()
	if t.is_empty():
		return "player"
	return "minion:%d" % int(t["slot"])


func _refresh_intent_target(key_before: String) -> void:
	var key_after := _intent_target_key()
	if key_before == key_after or key_after == "":
		return
	var view := get_intent_view()
	_ev(T.EV_INTENT_TARGET_CHANGED, {
		"target_side": view.get("target_side", ""),
		"target_slot": view.get("target_slot", -1),
		"text": view.get("text", ""),
	})
	_log("敌人意图目标更新：%s" % view.get("text", ""))


# ══════════════════════════════════════════════════════════
#  能量与抽牌
# ══════════════════════════════════════════════════════════

func _gain_energy(amount: int, reason: String) -> int:
	if amount <= 0:
		return 0
	var before := state.energy
	state.energy = mini(state.max_energy, state.energy + amount)
	var gained := state.energy - before
	_ev(T.EV_ENERGY_CHANGED, {
		"delta": gained, "value": state.energy, "reason": reason,
	})
	if gained > 0:
		_log("能量 +%d（当前 %d）" % [gained, state.energy])
	return gained


## 抽牌（§6.3）。超出上限的牌仍从牌库移出后进入弃牌堆；牌库不足时洗入弃牌堆。
func _draw_cards(n: int) -> Array:
	var to_hand: Array = []
	var overflow: Array = []
	for _i in range(n):
		if state.draw_pile.is_empty():
			if state.discard_pile.is_empty():
				# 两个牌堆都为空：停止抽取，Demo 没有疲劳伤害
				break
			var recycled := state.discard_pile.duplicate()
			_shuffle(recycled)
			state.draw_pile = recycled
			state.discard_pile.clear()
			for iid in state.draw_pile:
				state.set_zone(int(iid), T.Zone.DRAW_PILE)
			_log("弃牌堆洗入抽牌堆（%d 张）" % state.draw_pile.size())
		var iid: int = int(state.draw_pile.pop_back())
		if state.hand.size() < T.MAX_HAND:
			state.hand.append(iid)
			state.set_zone(iid, T.Zone.HAND)
			to_hand.append(iid)
		else:
			# 手牌上限 10：仍从牌库移出，直接进入弃牌堆
			state.discard_pile.append(iid)
			state.set_zone(iid, T.Zone.DISCARD)
			overflow.append(iid)
	if not to_hand.is_empty() or not overflow.is_empty():
		_ev(T.EV_CARDS_DRAWN, {
			"instance_ids": to_hand,
			"overflow": overflow,
			"count": to_hand.size(),
		})
	return to_hand


# ══════════════════════════════════════════════════════════
#  内部工具
# ══════════════════════════════════════════════════════════

func _begin() -> void:
	_events = []


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _ev(type: String, data: Dictionary = {}) -> void:
	var e := data.duplicate()
	e["type"] = type
	_events.append(e)


func _log(text: String) -> void:
	if state != null:
		state.log_lines.append(text)


func _set_phase(p: int) -> void:
	if state == null or state.phase == p:
		return
	state.phase = p
	_ev(T.EV_PHASE_CHANGED, {"phase": p})


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 移动卡牌实例到目标区域，同时维护区域数组（§6.3 各区互斥）。
func _move_instance(instance_id: int, zone: int) -> void:
	var from := state.zone_of(instance_id)
	if from == zone:
		return
	if from == T.Zone.DRAW_PILE:
		state.draw_pile.erase(instance_id)
	elif from == T.Zone.HAND:
		state.hand.erase(instance_id)
	elif from == T.Zone.DISCARD:
		state.discard_pile.erase(instance_id)
	elif from == T.Zone.RESOLVE:
		state.resolve_zone.erase(instance_id)
	state.set_zone(instance_id, zone)
	if zone == T.Zone.DRAW_PILE:
		state.draw_pile.append(instance_id)
	elif zone == T.Zone.HAND:
		state.hand.append(instance_id)
	elif zone == T.Zone.DISCARD:
		state.discard_pile.append(instance_id)
	elif zone == T.Zone.RESOLVE:
		state.resolve_zone.append(instance_id)
	# MINION_FIELD / SCENE_FIELD 由调用方登记到 minions / scene
	_ev(T.EV_CARD_MOVED, {
		"instance_id": instance_id,
		"def_id": state.def_id_of(instance_id),
		"from": from,
		"to": zone,
	})