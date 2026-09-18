class_name BattleEngine
extends RefCounted
##
## 战斗规则层。完全独立于界面与动画（规格 §1）。
##
## 公开规则入口：
##   init_battle / start_battle ……………… 初始化战斗
##   start_player_turn ………………………… 玩家回合开始（含待回收区归还、累计奖励抽牌）
##   play_card(instance_id, options) ……… 使用卡牌（点数快照 → 三链 → 场上监听 → 基础效果 → 分层强化 → 累计）
##   fuse_card(instance_id) ………………… 融牌充能（M21：不算出牌、不计点、不改变上一张）
##   resolve_tutor_choice(index) …………… 检索的待选择结算（S04）
##   request_end_turn / cancel_end_turn / confirm_end_turn …… 结束回合与保留牌
##   resolve_minion_attacks / enemy_phase / restart
##
## 每个公开入口返回有序事件数组，界面只播放事件、绝不自行计算伤害（§10）。
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")
const EnemyDB = preload("res://src/core/enemy_db.gd")
const BattleState = preload("res://src/core/battle_state.gd")

## 战斗序号，用于生成唯一战斗 ID。
static var _serial: int = 0

var state: BattleState = null

var _rng: RandomNumberGenerator = null
var _events: Array = []
## 本次敌方行动是否已发放过「承伤回能」（§6.5：每次行动最多一次）
var _enemy_action_energy_granted: bool = false


# ══════════════════════════════════════════════════════════
#  初始化 / 重新挑战
# ══════════════════════════════════════════════════════════

func init_battle(seed_value: int = 0) -> Array:
        _begin()
        state = BattleState.new()
        _serial += 1
        state.battle_id = "B%d-%d" % [seed_value, _serial]
        state.rng_seed = seed_value
        _rng = RandomNumberGenerator.new()
        _rng.seed = seed_value

        state.player_max_hp = T.PLAYER_MAX_HP
        state.player_hp = T.PLAYER_MAX_HP
        state.player_shield = 0
        state.energy = 0

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
        state.recall_wait = []
        state.exiled = []
        state.pending_choice = {}
        state.next_turn_extra_draw = 0
        state.reset_turn_chain()
        state.turn = 0
        state.result = T.Result.NONE
        state.log_lines = []
        state.phase = T.Phase.IDLE

        # 原型牌组：8 基础即时 + 6 功能 + 4 仆从 + 2 场景（M37）
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


func start_battle(seed_value: int = 0) -> Array:
        init_battle(seed_value)
        _start_player_turn()
        return _events


func restart(seed_value: int = -1) -> Array:
        if seed_value < 0:
                seed_value = make_seed()
        return start_battle(seed_value)


func make_seed() -> int:
        var r := RandomNumberGenerator.new()
        r.randomize()
        return absi(r.randi())


# ══════════════════════════════════════════════════════════
#  玩家回合开始（§6.2 固定顺序 + 新体系回合清理）
# ══════════════════════════════════════════════════════════

func start_player_turn() -> Array:
        _begin()
        _start_player_turn()
        return _events


func _start_player_turn() -> void:
        _set_phase(T.Phase.PLAYER_TURN_START)

        # 1. 回合数 +1，清空上一张、三类链层数、点数总和与同名首次触发记录（R12 / M34）
        state.turn += 1
        state.reset_turn_chain()
        _ev(T.EV_TURN_STARTED, {"turn": state.turn})
        _log("── 第 %d 回合 ──" % state.turn)

        # 2. 手牌临时点数修正失效（R18：普通保留不自动保留点数修正）
        state.clear_point_modifiers()

        # 3. 仆从护盾在下个玩家回合开始清除（M35）
        for m in state.minions:
                var ms := int(m.get("shield", 0))
                if ms > 0:
                        m["shield"] = 0
                        _ev(T.EV_MINION_SHIELD_CLEARED, {"slot": int(m["slot"]), "amount": ms})

        # 4. 玩家护盾清除
        if state.player_shield > 0:
                _ev(T.EV_SHIELD_CLEARED, {"side": T.Side.PLAYER, "amount": state.player_shield})
                _log("玩家护盾 %d 清除" % state.player_shield)
                state.player_shield = 0

        # 5. 待回收区 → 手牌（S05 / SC03）
        _return_recall_wait()

        # 7. 能量 +1，上限 10
        _gain_energy(1, "turn_start")

        # 8. 场景回合开始效果（旧版到期式场景）
        _resolve_scene_turn_start()

        # 9. 存活随从就绪
        for m in state.minions:
                if int(m["hp"]) > 0:
                        m["can_attack"] = true

        # 10. 抽 5 张 + 累计点数奖励的额外抽牌（R14 默认奖励）
        var draw_n := T.DRAW_PER_TURN + state.next_turn_extra_draw
        if state.next_turn_extra_draw > 0:
                _log("累计点数奖励：本回合额外抽 %d 张" % state.next_turn_extra_draw)
                state.next_turn_extra_draw = 0
        _draw_cards(draw_n)

        # 11. 公开本轮意图
        _reveal_intent()

        _set_phase(T.Phase.PLAYER_ACTION)


func _return_recall_wait() -> void:
        for iid in state.recall_wait.duplicate():
                if state.hand.size() >= T.MAX_HAND:
                        _move_instance(int(iid), T.Zone.DISCARD)
                        continue
                _move_instance(int(iid), T.Zone.HAND)
                _log("待回收牌「%s」加入手牌" % CardDB.card_name(state.def_id_of(int(iid))))


# ══════════════════════════════════════════════════════════
#  出牌校验（§5.1 + 新体系目标）
# ══════════════════════════════════════════════════════════

func can_play(instance_id: int, options: Dictionary = {}) -> Dictionary:
        if state == null:
                return _no("尚未初始化战斗")
        if state.battle_over():
                return _no("战斗已结束")
        if state.phase != T.Phase.PLAYER_ACTION:
                return _no("当前阶段不能出牌")
        if not state.pending_choice.is_empty():
                return _no("请先处理待选择的效果")
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
        if tt == T.TargetType.OTHER_HAND:
                if state.hand.size() < 2:
                        return _no("需要另一张手牌作为目标")
                var tgt := int(options.get("hand_target", -1))
                if tgt != -1:
                        if tgt == instance_id:
                                return _no("不能选择本牌自己")
                        if state.zone_of(tgt) != T.Zone.HAND:
                                return _no("目标不在手牌中")
        if tt == T.TargetType.READY_MINION:
                var slot := int(options.get("minion_slot", -1))
                if slot != -1 and not state.ready_minion_slots().has(slot):
                        return _no("该仆从不是「已就绪且本轮未攻击」")
                if state.ready_minions().is_empty():
                        return _no("没有已就绪且本轮未攻击的仆从")
        # 检索只能查看当时实际存在的牌，不为凑够数量而洗牌（S04）
        if def_id == "search" and state.draw_pile.is_empty():
                return _no("抽牌堆没有可查看的牌")
        return {"ok": true, "reason": ""}


## 确认出牌时缺少必需目标的原因（空串表示目标齐备）。
func _missing_target_reason(instance_id: int, options: Dictionary) -> String:
        var def_id := state.def_id_of(instance_id)
        var tt := int(CardDB.get_card(def_id).get("target", T.TargetType.NONE))
        if tt == T.TargetType.OTHER_HAND and int(options.get("hand_target", -1)) == -1:
                return "请先选择另一张手牌作为目标"
        if tt == T.TargetType.READY_MINION and int(options.get("minion_slot", -1)) == -1:
                return "请先选择一只已就绪且本轮未攻击的仆从"
        return ""


## 组合预览（§11）：不改变状态，推测本牌出牌后命中的关系与层数。
func preview_chain(instance_id: int) -> Dictionary:
        var point := state.effective_points(instance_id)
        var relation := T.ChainRelation.NONE
        var level := 0
        var prev := state.last_point
        if prev > 0:
                if point == prev:
                        relation = T.ChainRelation.SAME
                        level = state.same_level + 1
                elif point > prev and point % prev == 0:
                        relation = T.ChainRelation.MULTIPLE
                        level = state.mult_level + 1
                elif point < prev and prev % point == 0:
                        relation = T.ChainRelation.FACTOR
                        level = state.factor_level + 1
        return {
                "point": point, "last_point": prev, "relation": relation, "level": level,
                "total_after": state.points_total + point,
        }


# ══════════════════════════════════════════════════════════
#  使用卡牌
# ══════════════════════════════════════════════════════════

func play_card(instance_id: int, options: Dictionary = {}) -> Dictionary:
        _begin()
        var v := can_play(instance_id, options)
        if not v["ok"]:
                # 取消出牌、费用不足或目标无效都不算成功使用：不点数、不断链（R19）
                return {"ok": false, "reason": v["reason"], "events": []}

        # 确认出牌时必须补齐目标：can_play 允许暂缺目标（界面用它判断「可选」），
        # 但真正结算前必须给出，避免无目标空放（S01 / S04 / S07）。
        var miss := _missing_target_reason(instance_id, options)
        if miss != "":
                return {"ok": false, "reason": miss, "events": []}

        var def_id := state.def_id_of(instance_id)
        var card := CardDB.get_card(def_id)
        var name := String(card.get("name", ""))
        var cost := int(card.get("cost", 0))

        if cost > 0:
                state.energy -= cost
                _ev(T.EV_ENERGY_CHANGED, {"delta": -cost, "value": state.energy, "reason": "cost"})

        _move_instance(instance_id, T.Zone.RESOLVE)
        _ev(T.EV_CARD_PLAYED, {"instance_id": instance_id, "def_id": def_id, "name": name})
        _log("使用「%s」" % name)

        # 1) 点数快照（R18）+ 更新三类链、上一张与累计总和（R05~R14）
        var point := state.effective_points(instance_id)
        var chain := _update_chain(point)
        state.points_total += point
        _ev(T.EV_CHAIN_UPDATED, {
                "instance_id": instance_id, "def_id": def_id, "point": point,
                "last_point": state.last_point,
                "relation": int(chain["relation"]), "level": int(chain["level"]),
                "mult_level": state.mult_level, "factor_level": state.factor_level,
                "same_level": state.same_level,
        })
        _ev(T.EV_POINTS_TOTAL_CHANGED, {
                "point": point, "total": state.points_total,
                "threshold": T.POINTS_THRESHOLD,
                "triggers": state.cumulative_triggers,
        })
        if int(chain["level"]) > 0:
                _log("点数 %d（上一张 %d）：%s第 %d 层" % [
                        point, state.last_point,
                        String(T.CHAIN_NAME.get(int(chain["relation"]), "")), int(chain["level"])])
        else:
                _log("点数 %d（本回合累计 %d）" % [point, state.points_total])

        # 2) 场上监听（M36：只有出牌前已在场的来源监听本次出牌）
        _fire_chain_listeners(int(chain["relation"]), int(chain["level"]), point)

        # 3) 效果队列：基础效果 + 本次命中的那一类链的分层强化（R06~R11）
        var queue: Array = []
        queue.append_array(card.get("ops", []))
        if int(chain["level"]) > 0:
                queue.append_array(CardDB.scaled_ops(
                        CardDB.chain_ops(def_id, int(chain["relation"])), int(chain["level"])))
        var ctx := {
                "options": options,
                "relation": int(chain["relation"]),
                "level": int(chain["level"]),
                "def_id": def_id,
        }
        _run_queue(queue, 0, instance_id, name, ctx)
        return {
                "ok": true, "reason": "", "events": _events,
                "pending": not state.pending_choice.is_empty(),
        }


## 顺序执行效果队列；遇到检索（S04）时挂起，等待玩家选择后继续。
func _run_queue(queue: Array, start_index: int, card_instance: int,
                source_name: String, ctx: Dictionary) -> void:
        var i := start_index
        while i < queue.size():
                if state.battle_over():
                        break
                var op: Dictionary = queue[i]
                if String(op.get("op", "")) == CardDB.OP_TUTOR:
                        if _begin_tutor(op, card_instance, source_name, ctx, queue, i + 1):
                                return
                        i += 1
                        continue
                _exec_op(op, card_instance, source_name, ctx)
                i += 1
        _finish_card(card_instance, source_name)


func _finish_card(card_instance: int, source_name: String) -> void:
        # 累计点数（R14/R15）：独立结算，不贡献也不消耗相邻链层数
        _check_cumulative()
        var zone := state.zone_of(card_instance)
        if zone == T.Zone.RESOLVE:
                if state.is_temp(card_instance):
                        # A10：临时衍生牌用后移出战斗，不进弃牌堆、不洗回
                        _move_instance(card_instance, T.Zone.EXILED)
                        _ev(T.EV_CARD_EXILED, {
                                "instance_id": card_instance,
                                "def_id": state.def_id_of(card_instance),
                                "name": CardDB.card_name(state.def_id_of(card_instance)),
                        })
                else:
                        _move_instance(card_instance, T.Zone.DISCARD)


func _check_cumulative() -> void:
        while state.points_total >= (state.cumulative_triggers + 1) * T.POINTS_THRESHOLD:
                state.cumulative_triggers += 1
                state.next_turn_extra_draw += T.CUMULATIVE_EXTRA_DRAW
                var threshold := state.cumulative_triggers * T.POINTS_THRESHOLD
                _ev(T.EV_CUMULATIVE_TRIGGERED, {
                        "total": state.points_total, "threshold": threshold,
                        "bonus_draw": T.CUMULATIVE_EXTRA_DRAW,
                        "next_turn_extra_draw": state.next_turn_extra_draw,
                })
                _log("累计点数达到 %d：下回合额外抽 %d 张" % [threshold, T.CUMULATIVE_EXTRA_DRAW])


## 三类相邻链的独立判定与断链（R05~R13）。
func _update_chain(point: int) -> Dictionary:
        var relation := T.ChainRelation.NONE
        var level := 0
        var prev := state.last_point
        if prev > 0:
                if point == prev:
                        state.same_level += 1
                        state.mult_level = 0
                        state.factor_level = 0
                        relation = T.ChainRelation.SAME
                        level = state.same_level
                elif point > prev and point % prev == 0:
                        state.mult_level += 1
                        state.factor_level = 0
                        state.same_level = 0
                        relation = T.ChainRelation.MULTIPLE
                        level = state.mult_level
                elif point < prev and prev % point == 0:
                        state.factor_level += 1
                        state.mult_level = 0
                        state.same_level = 0
                        relation = T.ChainRelation.FACTOR
                        level = state.factor_level
                else:
                        # 不匹配：三条链全部归零，切换关系也从第 1 层重新开始（R09/R16）
                        state.mult_level = 0
                        state.factor_level = 0
                        state.same_level = 0
        state.last_point = point
        return {"relation": relation, "level": level}


# ══════════════════════════════════════════════════════════
#  融牌充能（M21 / R01~R03）
# ══════════════════════════════════════════════════════════

func can_fuse(instance_id: int) -> Dictionary:
        if state == null:
                return _no("尚未初始化战斗")
        if state.battle_over():
                return _no("战斗已结束")
        if state.phase != T.Phase.PLAYER_ACTION:
                return _no("当前阶段不能融牌")
        if not state.pending_choice.is_empty():
                return _no("请先处理待选择的效果")
        if state.zone_of(instance_id) != T.Zone.HAND:
                return _no("该牌不在手牌中")
        if state.is_temp(instance_id):
                return _no("临时衍生牌不能融牌")
        # 融牌只要求「这张牌在你手里」：能不能打出（费用不足 / 没有合法目标 / 场上条件不满足）
        # 都不影响融牌；能量已满时也允许融牌，只是这一次不再获得能量。
        return {"ok": true, "reason": ""}


## 融牌：把一张手牌弃进弃牌堆，并尽量获得 1 能量。
## 不算出牌（不计点数、不改变上一张、不断链）；任何手牌都能融，包括当前打不出去的牌；
## 能量已满时融牌依然成立，只是这次不获得能量（相当于单纯弃掉这张牌）。
func fuse_card(instance_id: int) -> Dictionary:
        _begin()
        var v := can_fuse(instance_id)
        if not v["ok"]:
                return {"ok": false, "reason": v["reason"], "events": _events}
        var def_id := state.def_id_of(instance_id)
        var name := CardDB.card_name(def_id)
        var point := state.effective_points(instance_id)
        _move_instance(instance_id, T.Zone.DISCARD)
        var gained := _gain_energy(T.FUSION_ENERGY, "fusion")
        _ev(T.EV_CARD_FUSED, {
                "instance_id": instance_id, "def_id": def_id, "name": name,
                "point": point, "energy_gained": gained,
                "energy": state.energy,
        })
        if gained > 0:
                _log("融掉「%s」（%d 点）进入弃牌堆 → 能量 +%d；出牌链与累计点数不变" % [name, point, gained])
        else:
                _log("融掉「%s」（%d 点）进入弃牌堆；能量已满，本次不获得能量" % [name, point])
        _fire_fuse_listeners()
        return {"ok": true, "reason": "", "events": _events}


func _fire_fuse_listeners() -> void:
        for src in _listener_sources():
                var def_id := state.def_id_of(int(src["card_instance"]))
                var mon := CardDB.monitor(def_id)
                if String(mon.get("event", "")) != CardDB.MON_FUSE:
                        continue
                _exec_monitor(mon, src, {})


func _fire_chain_listeners(relation: int, level: int, point: int) -> void:
        if relation == T.ChainRelation.NONE or level <= 0:
                return
        for src in _listener_sources():
                var def_id := state.def_id_of(int(src["card_instance"]))
                var mon := CardDB.monitor(def_id)
                if String(mon.get("event", "")) != CardDB.MON_CHAIN:
                        continue
                if int(mon.get("relation", -1)) != relation:
                        continue
                if int(mon.get("level", 0)) != level:
                        continue
                _exec_monitor(mon, src, {"point": point})


## 出牌前已在场的监听来源（M36）：随从按槽位顺序，场景最后。
func _listener_sources() -> Array:
        var out: Array = []
        for m in state.living_minions_ordered():
                out.append({"minion": m, "card_instance": int(m["card_instance"]), "kind": "minion"})
        if not state.scene.is_empty():
                out.append({"minion": {}, "card_instance": int(state.scene["card_instance"]), "kind": "scene"})
        return out


## 执行一次场上监听：同名卡每回合只触发一次（M34）。
func _exec_monitor(mon: Dictionary, src: Dictionary, ctx: Dictionary) -> void:
        var def_id := state.def_id_of(int(src["card_instance"]))
        var key := "%s|%d|%d" % [String(mon.get("event", "")), int(mon.get("relation", -1)), int(mon.get("level", -1))]
        if not state.try_first_trigger(def_id, key):
                return
        var name := CardDB.card_name(def_id)
        _ev(T.EV_FIRST_TRIGGER, {
                "def_id": def_id, "name": name,
                "slot": int(src["minion"].get("slot", -1)) if not src["minion"].is_empty() else -1,
                "kind": String(src.get("kind", "")),
                "desc": String(mon.get("desc", "")),
        })
        _log("场上监听「%s」触发：%s" % [name, String(mon.get("desc", ""))])
        for op in mon.get("ops", []):
                _exec_op(op, int(src["card_instance"]), name, ctx, src)


# ══════════════════════════════════════════════════════════
#  原子效果
# ══════════════════════════════════════════════════════════

## mon_source 非空表示这次 op 来自场上监听（随从 / 场景）。
func _exec_op(op: Dictionary, card_instance: int, source_name: String,
                ctx: Dictionary, mon_source: Dictionary = {}) -> void:
        var kind := String(op.get("op", ""))
        var amount := int(op.get("amount", 0))
        var options: Dictionary = ctx.get("options", {})

        if kind == CardDB.OP_GAIN_ENERGY:
                _gain_energy(amount, "monitor" if not mon_source.is_empty() else "card")
                if mon_source.is_empty():
                        _ev(T.EV_CARD_GAINED_ENERGY, {
                                "instance_id": card_instance,
                                "def_id": state.def_id_of(card_instance),
                                "amount": amount,
                        })
        elif kind == CardDB.OP_GAIN_SHIELD:
                _gain_player_shield(amount)
        elif kind == CardDB.OP_DAMAGE:
                var dmg := amount
                var alt := int(op.get("alt", dmg))
                var alt_when := String(op.get("alt_when", ""))
                if alt_when == "target_has_shield":
                        if state.enemy_shield > 0:
                                dmg = alt
                elif alt_when == "mult_relation":
                        # 追击（M19）：改为「本次是否为倍数关系」，不再统计攻击牌次数
                        if int(ctx.get("relation", T.ChainRelation.NONE)) == T.ChainRelation.MULTIPLE:
                                dmg = alt
                _damage_enemy(dmg, source_name)
        elif kind == CardDB.OP_DRAW:
                _draw_cards(amount)
        elif kind == CardDB.OP_SUMMON:
                _summon(op, card_instance)
        elif kind == CardDB.OP_SCENE:
                _play_scene(op, card_instance)
        elif kind == CardDB.OP_MODIFY_POINT:
                _modify_hand_point(int(options.get("hand_target", -1)),
                        int(options.get("point_delta", 1)), maxi(1, amount))
        elif kind == CardDB.OP_SET_POINT:
                _set_hand_point(int(options.get("hand_target", -1)), card_instance)
        elif kind == CardDB.OP_EXTRA_KEEP:
                state.extra_keep = mini(T.MAX_EXTRA_KEEP, state.extra_keep + maxi(1, amount))
                _log("本回合可额外保留 %d 张手牌" % state.extra_keep)
        elif kind == CardDB.OP_COMMAND:
                _command_minion(int(options.get("minion_slot", -1)), amount)
        elif kind == CardDB.OP_BUFF_ATTACK:
                _buff_minion_attack(mon_source.get("minion", {}), amount)
        elif kind == CardDB.OP_MINION_SHIELD:
                _gain_minion_shield(mon_source.get("minion", {}), amount)
        elif kind == CardDB.OP_HEAL_MINION:
                _heal_minion(amount)
        elif kind == CardDB.OP_GENERATE_TEMP:
                var tdef := String(op.get("def_id", ""))
                var override := -1
                if bool(op.get("point_from_trigger", false)):
                        override = int(ctx.get("point", 0))
                _generate_temp(tdef, override)


func _modify_hand_point(target: int, delta_sign: int, magnitude: int) -> void:
        if state.zone_of(target) != T.Zone.HAND or magnitude <= 0:
                return
        var rec := state.record(target)
        var before := state.effective_points_of(rec)
        var want := clampi(before + signi(delta_sign) * magnitude, T.POINTS_MIN, T.POINTS_MAX)
        rec["point_mod"] = int(rec.get("point_mod", 0)) + (want - before)
        _ev(T.EV_POINT_MODIFIED, {
                "instance_id": target, "def_id": String(rec.get("def_id", "")),
                "name": CardDB.card_name(String(rec.get("def_id", ""))),
                "before": before, "after": want, "delta": want - before,
        })
        _log("「%s」点数 %d → %d（本回合有效，不追溯已出牌）" % [
                CardDB.card_name(String(rec.get("def_id", ""))), before, want])


func _set_hand_point(target: int, source_instance: int) -> void:
        if state.zone_of(target) != T.Zone.HAND:
                return
        var rec := state.record(target)
        var base := CardDB.card_points(String(rec.get("def_id", "")))
        if rec.has("point_override"):
                base = int(rec["point_override"])
        var want := state.effective_points(source_instance)
        var before := state.effective_points_of(rec)
        rec["point_mod"] = want - base
        _ev(T.EV_POINT_MODIFIED, {
                "instance_id": target, "def_id": String(rec.get("def_id", "")),
                "name": CardDB.card_name(String(rec.get("def_id", ""))),
                "before": before, "after": state.effective_points_of(rec),
                "delta": state.effective_points_of(rec) - before,
        })
        _log("「%s」点数 %d → %d（映片，本回合有效）" % [
                CardDB.card_name(String(rec.get("def_id", ""))), before, state.effective_points_of(rec)])


func _command_minion(slot: int, bonus: int) -> void:
        var m := state.minion_at_slot(slot)
        if m.is_empty() or int(m["hp"]) <= 0 or not bool(m["can_attack"]):
                return
        m["can_attack"] = false
        var ci := int(m["card_instance"])
        var label := CardDB.card_name(state.def_id_of(ci))
        var atk := int(m["attack"]) + bonus
        _ev(T.EV_MINION_COMMANDED, {"slot": slot, "name": label, "attack": atk})
        _ev(T.EV_MINION_ATTACKED, {
                "slot": slot, "attack": atk, "card_instance": ci, "name": label, "commanded": true,
        })
        _log("指令：随从「%s」立即攻击 %d" % [label, atk])
        _damage_enemy(atk, label)


func _buff_minion_attack(minion: Dictionary, amount: int) -> void:
        if minion.is_empty() or amount == 0:
                return
        minion["attack"] = int(minion["attack"]) + amount
        var label := CardDB.card_name(state.def_id_of(int(minion["card_instance"])))
        _ev(T.EV_MINION_BUFFED, {
                "slot": int(minion["slot"]), "name": label, "amount": amount,
                "attack": int(minion["attack"]),
        })
        _log("随从「%s」本轮攻击 +%d（当前 %d）" % [label, amount, int(minion["attack"])])


func _gain_minion_shield(minion: Dictionary, amount: int) -> void:
        if minion.is_empty() or amount <= 0:
                return
        minion["shield"] = int(minion.get("shield", 0)) + amount
        var label := CardDB.card_name(state.def_id_of(int(minion["card_instance"])))
        _ev(T.EV_MINION_SHIELD_GAINED, {
                "slot": int(minion["slot"]), "name": label, "amount": amount,
                "shield": int(minion["shield"]),
        })
        _log("随从「%s」获得 %d 护盾（当前 %d）" % [label, amount, int(minion["shield"])])


func _heal_minion(amount: int) -> void:
        var wounded := state.wounded_minions()
        if wounded.is_empty():
                _log("没有受伤的己方仆从，本次治疗机会消耗")
                return
        var target: Dictionary = wounded[0]
        var before := int(target["hp"])
        target["hp"] = mini(int(target["max_hp"]), before + amount)
        var label := CardDB.card_name(state.def_id_of(int(target["card_instance"])))
        _ev(T.EV_MINION_HEALED, {
                "slot": int(target["slot"]), "name": label, "amount": int(target["hp"]) - before,
                "hp": int(target["hp"]),
        })
        _log("随从「%s」恢复 %d 生命（当前 %d）" % [label, int(target["hp"]) - before, int(target["hp"])])


## 生成临时衍生牌（M31 / A10）：手牌已满则生成失败并消耗本次首次机会。
func _generate_temp(def_id: String, point_override: int = -1) -> int:
        if def_id == "" or not CardDB.has_card(def_id):
                return -1
        if state.hand.size() >= T.MAX_HAND:
                _ev(T.EV_TEMP_CARD_FAILED, {"def_id": def_id, "reason": "hand_full"})
                _log("手牌已满，临时牌「%s」生成失败" % CardDB.card_name(def_id))
                return -1
        var iid := state.create_instance(def_id, T.Zone.HAND, true, point_override)
        state.hand.append(iid)
        _ev(T.EV_TEMP_CARD_ADDED, {
                "instance_id": iid, "def_id": def_id, "name": CardDB.card_name(def_id),
                "points": state.effective_points(iid),
        })
        _log("生成临时牌「%s」（%d 点，不可融 / 不可保留）" % [
                CardDB.card_name(def_id), state.effective_points(iid)])
        return iid


# ══════════════════════════════════════════════════════════
#  检索（S04）：查看牌库顶，选 1 张加入手牌
# ══════════════════════════════════════════════════════════

func _begin_tutor(op: Dictionary, card_instance: int, source_name: String,
                ctx: Dictionary, queue: Array, next_index: int) -> bool:
        var n := int(op.get("range", 3)) + int(op.get("range_add", 0))
        var total := state.draw_pile.size()
        var take := mini(n, total)
        if take <= 0:
                return false
        var revealed: Array = []
        for k in range(take):
                revealed.append(int(state.draw_pile[total - 1 - k]))
        state.pending_choice = {
                "kind": "tutor", "card_instance": card_instance, "source_name": source_name,
                "queue": queue, "index": next_index, "ctx": ctx, "revealed": revealed,
        }
        var names: Array = []
        for iid in revealed:
                names.append(CardDB.card_name(state.def_id_of(int(iid))))
        _ev(T.EV_TUTOR_OPENED, {
                "instance_ids": revealed, "names": names,
                "card_instance": card_instance, "source_name": source_name,
        })
        _log("检索：查看牌库顶 %d 张（%s）" % [revealed.size(), "、".join(names)])
        return true


## 玩家从查看的牌中选一张（index 为 revealed 中的下标）。
func resolve_tutor_choice(index: int) -> Dictionary:
        _begin()
        if state == null or state.pending_choice.is_empty():
                return {"ok": false, "reason": "当前没有待选择的检索", "events": _events}
        var pc: Dictionary = state.pending_choice
        var revealed: Array = pc["revealed"]
        if index < 0 or index >= revealed.size():
                return {"ok": false, "reason": "无效的选择", "events": _events}
        state.pending_choice = {}

        var chosen := int(revealed[index])
        # 其余按原顺序置于牌库底
        var rest: Array[int] = []
        for iid in state.draw_pile:
                if not revealed.has(int(iid)):
                        rest.append(int(iid))
        for k in range(revealed.size() - 1, -1, -1):
                if int(revealed[k]) == chosen:
                        continue
                rest.push_front(int(revealed[k]))
        state.draw_pile = rest

        if state.hand.size() < T.MAX_HAND:
                state.hand.append(chosen)
                state.set_zone(chosen, T.Zone.HAND)
                _log("检索获得「%s」" % CardDB.card_name(state.def_id_of(chosen)))
        else:
                state.discard_pile.append(chosen)
                state.set_zone(chosen, T.Zone.DISCARD)
                _log("手牌已满，检索的牌进入弃牌堆")
        _ev(T.EV_TUTOR_RESOLVED, {
                "chosen": chosen, "def_id": state.def_id_of(chosen),
                "name": CardDB.card_name(state.def_id_of(chosen)),
                "to_hand": state.zone_of(chosen) == T.Zone.HAND,
        })

        _run_queue(pc["queue"], int(pc["index"]), int(pc["card_instance"]),
                String(pc["source_name"]), pc["ctx"])
        return {"ok": true, "reason": "", "events": _events}


# ══════════════════════════════════════════════════════════
#  结束回合与保留牌（§5.3 + 封存 / 临时牌）
# ══════════════════════════════════════════════════════════

func request_end_turn() -> Dictionary:
        _begin()
        if state == null or state.battle_over():
                return {"ok": false, "reason": "战斗已结束", "needs_keep": false, "events": _events}
        if not state.pending_choice.is_empty():
                return {"ok": false, "reason": "请先处理待选择的效果", "needs_keep": false, "events": _events}
        if state.phase != T.Phase.PLAYER_ACTION:
                return {"ok": false, "reason": "当前阶段不能结束回合", "needs_keep": false, "events": _events}
        if state.hand.is_empty():
                return {"ok": true, "reason": "", "needs_keep": false, "events": _events}
        _set_phase(T.Phase.KEEP_SELECT)
        return {"ok": true, "reason": "", "needs_keep": true, "events": _events}


func cancel_end_turn() -> Dictionary:
        _begin()
        if state == null or state.phase != T.Phase.KEEP_SELECT:
                return {"ok": false, "reason": "当前不在保留选择阶段", "events": _events}
        _set_phase(T.Phase.PLAYER_ACTION)
        return {"ok": true, "reason": "", "events": _events}


func confirm_end_turn(keep_instance_id: int = -1, extra_keep_ids: Array = []) -> Dictionary:
        _begin()
        if state == null or state.battle_over():
                return {"ok": false, "reason": "战斗已结束", "events": _events}
        if not state.pending_choice.is_empty():
                return {"ok": false, "reason": "请先处理待选择的效果", "events": _events}
        if state.phase != T.Phase.KEEP_SELECT and state.phase != T.Phase.PLAYER_ACTION:
                return {"ok": false, "reason": "当前阶段不能结束回合", "events": _events}
        if state.phase == T.Phase.PLAYER_ACTION and not state.hand.is_empty():
                return {"ok": false, "reason": "有手牌时必须先进入保留选择", "events": _events}

        # 临时衍生牌在本回合结束移出战斗（A10）
        for iid in state.hand.duplicate():
                if state.is_temp(int(iid)):
                        _ev(T.EV_TEMP_CARD_EXPIRED, {
                                "instance_id": int(iid),
                                "def_id": state.def_id_of(int(iid)),
                                "name": CardDB.card_name(state.def_id_of(int(iid))),
                                "reason": "turn_end",
                        })
                        _move_instance(int(iid), T.Zone.EXILED)

        var allowed := 1 + int(state.extra_keep)
        var keep_set: Array = []
        if keep_instance_id != -1:
                keep_set.append(keep_instance_id)
        for k in extra_keep_ids:
                if int(k) != -1 and not keep_set.has(int(k)):
                        keep_set.append(int(k))
        if keep_set.size() > allowed:
                keep_set = keep_set.slice(0, allowed)

        var discarded: Array = []
        for iid in state.hand.duplicate():
                if keep_set.has(int(iid)):
                        continue
                _move_instance(int(iid), T.Zone.DISCARD)
                discarded.append(iid)
        var kept_names: Array = []
        for iid in keep_set:
                kept_names.append(CardDB.card_name(state.def_id_of(int(iid))))
        if keep_set.is_empty():
                _log("不保留手牌，%d 张进入弃牌堆" % discarded.size())
        else:
                _log("保留「%s」共 %d 张，其余 %d 张进入弃牌堆" % [
                        "、".join(kept_names), keep_set.size(), discarded.size()])

        _resolve_minion_attacks()
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
                        "commanded": false,
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

        if state.enemy_shield > 0:
                _ev(T.EV_SHIELD_CLEARED, {"side": T.Side.ENEMY, "amount": state.enemy_shield})
                _log("%s护盾 %d 清除" % [state.enemy_name, state.enemy_shield])
                state.enemy_shield = 0

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
                        "side": T.Side.ENEMY, "amount": value, "value": state.enemy_shield,
                })
                _log("%s获得 %d 护盾" % [state.enemy_name, value])
        elif kind == T.IntentKind.ATTACK:
                var target := state.leftmost_taunt_minion()
                if target.is_empty():
                        _log("%s攻击玩家 %d" % [state.enemy_name, value])
                        _damage_player(value, true, state.enemy_name)
                else:
                        var mname := CardDB.card_name(state.def_id_of(int(target["card_instance"])))
                        _log("%s攻击随从「%s」%d" % [state.enemy_name, mname, value])
                        _damage_minion(target, value, state.enemy_name)

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
#  伤害与护盾（§6.4 + M35 仆从护盾）
# ══════════════════════════════════════════════════════════

func _gain_player_shield(amount: int) -> void:
        if amount <= 0:
                return
        state.player_shield += amount
        _ev(T.EV_SHIELD_GAINED, {
                "side": T.Side.PLAYER, "amount": amount, "value": state.player_shield,
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
        if hp_loss > 0 and allow_energy and not _enemy_action_energy_granted:
                _enemy_action_energy_granted = true
                _gain_energy(1, "damage_taken")
        _check_endgame()


func _damage_minion(minion: Dictionary, amount: int, source_name: String) -> void:
        if amount <= 0 or minion.is_empty():
                return
        var mname := CardDB.card_name(state.def_id_of(int(minion["card_instance"])))
        var shield := int(minion.get("shield", 0))
        var absorbed := mini(shield, amount)
        minion["shield"] = shield - absorbed
        var hp_loss := amount - absorbed
        minion["hp"] = maxi(0, int(minion["hp"]) - hp_loss)
        _ev(T.EV_DAMAGE, {
                "target": T.Side.MINION, "slot": int(minion["slot"]),
                "amount": amount, "absorbed": absorbed, "hp_loss": hp_loss,
                "hp": int(minion["hp"]), "shield": int(minion["shield"]), "source": source_name,
        })
        _log("%s对随从「%s」造成 %d 伤害（护盾吸收 %d，剩余 %d）" % [
                source_name, mname, amount, absorbed, int(minion["hp"])])
        if int(minion["hp"]) <= 0:
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
                "shield": 0,
                "taunt": bool(op.get("taunt", false)),
                "can_attack": false,
        }
        state.minions.append(m)
        _move_instance(card_instance, T.Zone.MINION_FIELD)
        var mname := CardDB.card_name(state.def_id_of(card_instance))
        _ev(T.EV_MINION_SUMMONED, {
                "slot": slot, "card_instance": card_instance, "name": mname,
                "attack": m["attack"], "hp": hp, "shield": 0,
                "taunt": m["taunt"], "can_attack": false,
        })
        _log("召唤「%s」（%d 攻击 / %d 生命%s），本回合不可攻击" % [
                mname, int(m["attack"]), hp, "，嘲讽" if bool(m["taunt"]) else ""])
        _refresh_intent_target(key_before)


func _play_scene(op: Dictionary, card_instance: int) -> void:
        # §6.8：场上仅能存在一张场景牌，新场景立即替换旧场景（M32）
        if not state.scene.is_empty():
                var old := int(state.scene["card_instance"])
                _move_instance(old, T.Zone.DISCARD)
                _ev(T.EV_SCENE_EXPIRED, {"card_instance": old, "reason": "replaced"})
                state.scene = {}
        var effect_id := String(op.get("effect_id", ""))
        var triggers := int(op.get("triggers", -1))
        state.scene = {
                "card_instance": card_instance,
                "effect_id": effect_id,
                "triggers": triggers,
        }
        _move_instance(card_instance, T.Zone.SCENE_FIELD)
        _ev(T.EV_SCENE_PLAYED, {
                "card_instance": card_instance,
                "effect_id": effect_id,
                "triggers": triggers,
                "name": CardDB.card_name(state.def_id_of(card_instance)),
        })
        if triggers < 0:
                _log("场景「%s」生效（本战常驻直到被替换）" % CardDB.card_name(state.def_id_of(card_instance)))
        else:
                _log("场景「%s」生效，剩余 %d 次触发" % [
                        CardDB.card_name(state.def_id_of(card_instance)), triggers])


func _resolve_scene_turn_start() -> void:
        if state.scene.is_empty():
                return
        var s: Dictionary = state.scene
        var effect_id := String(s.get("effect_id", ""))
        # 只有旧版到期式场景在回合开始触发；常驻场景改为监听出牌（M32）
        if effect_id != "energy_spring":
                return
        _gain_energy(1, "scene")
        var left := int(s["triggers"]) - 1
        s["triggers"] = left
        _ev(T.EV_SCENE_TRIGGERED, {
                "card_instance": int(s["card_instance"]),
                "effect_id": effect_id,
                "triggers_left": left,
        })
        _log("场景「能量涌泉」触发：额外 1 能量（剩余 %d 次）" % left)
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
        match from:
                T.Zone.DRAW_PILE:
                        state.draw_pile.erase(instance_id)
                T.Zone.HAND:
                        state.hand.erase(instance_id)
                T.Zone.DISCARD:
                        state.discard_pile.erase(instance_id)
                T.Zone.RESOLVE:
                        state.resolve_zone.erase(instance_id)
                T.Zone.RECALL_WAIT:
                        state.recall_wait.erase(instance_id)
                T.Zone.EXILED:
                        state.exiled.erase(instance_id)
        state.set_zone(instance_id, zone)
        match zone:
                T.Zone.DRAW_PILE:
                        state.draw_pile.append(instance_id)
                T.Zone.HAND:
                        state.hand.append(instance_id)
                T.Zone.DISCARD:
                        state.discard_pile.append(instance_id)
                T.Zone.RESOLVE:
                        state.resolve_zone.append(instance_id)
                T.Zone.RECALL_WAIT:
                        state.recall_wait.append(instance_id)
                T.Zone.EXILED:
                        state.exiled.append(instance_id)
        # MINION_FIELD / SCENE_FIELD 由调用方登记到 minions / scene
        _ev(T.EV_CARD_MOVED, {
                "instance_id": instance_id,
                "def_id": state.def_id_of(instance_id),
                "from": from,
                "to": zone,
        })