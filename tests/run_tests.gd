extends SceneTree
##
## 规则层验收测试。
##   A01~A25 …… 规格 §12 的验收场景（按新体系「点数与融牌」更新受影响项）
##   B01~B09 …… 设计元素表 19 项决定的逐条验收：融牌、三类相邻链、累计点数、
##               点数修正、特殊功能牌、临时衍生牌、场上监听、仆从护盾、牌组结构
##
## 运行： godot --headless --path . --script res://tests/run_tests.gd
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


## 从现有牌堆取一张；牌组外的候选池卡（count = 0）现场创建，方便逐条验收。
func take_card(e, def_id: String) -> int:
        for pile in [e.state.draw_pile, e.state.discard_pile]:
                for iid in pile.duplicate():
                        if e.state.def_id_of(int(iid)) == def_id:
                                pile.erase(iid)
                                return int(iid)
        if not CardDB.has_card(def_id):
                push_error("未知卡牌: " + def_id)
                return -1
        return e.state.create_instance(def_id, T.Zone.HAND)


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


## 生成一张临时衍生牌到手牌（模拟镜像回廊 / 战术号手的效果）。
func make_temp(e, def_id: String, points: int = 4) -> int:
        var iid: int = e.state.create_instance(def_id, T.Zone.HAND, true, points)
        e.state.hand.append(iid)
        return iid


func end_turn(e, keep: int = -1, extra: Array = []) -> Dictionary:
        var r = e.request_end_turn()
        if not r["ok"]:
                return r
        return e.confirm_end_turn(keep, extra)


## 跨区域收集所有实例 id，用于校验区域互斥（§6.3）。
func all_instance_ids(e) -> Array:
        var ids: Array = []
        ids.append_array(e.state.draw_pile)
        ids.append_array(e.state.hand)
        ids.append_array(e.state.discard_pile)
        ids.append_array(e.state.resolve_zone)
        ids.append_array(e.state.recall_wait)
        ids.append_array(e.state.exiled)
        for m in e.state.minions:
                ids.append(int(m["card_instance"]))
        if not e.state.scene.is_empty():
                ids.append(int(e.state.scene["card_instance"]))
        return ids


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


func events_of(events: Array, type: String) -> Array:
        var out: Array = []
        for ev in events:
                if String(ev.get("type", "")) == type:
                        out.append(ev)
        return out


func count_of(events: Array, type: String) -> int:
        return events_of(events, type).size()


# ══════════════════════════════════════════════════════════
#  测试主体
# ══════════════════════════════════════════════════════════

func _initialize() -> void:
        print("=== PVE 卡牌战斗 Demo · 规则层验收测试 ===")
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
        _b01_fusion()
        _b02_chains()
        _b03_cumulative()
        _b04_point_modify()
        _b05_function_cards()
        _b06_temp_cards()
        _b07_listeners()
        _b08_minion_shield()
        _b09_card_table()

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
        eq("能量上限 10", e.state.max_energy, 10)
        eq("本回合还没有上一张点数", e.state.last_point, 0)
        check("区域互斥完整", integrity_ok(e))


# ── A02 同回合连续使用多张零费牌 ──────────────────────────
func _a02() -> void:
        section("A02 同回合连续使用多张零费牌")
        var e := new_battle()
        var ids := set_hand(e, ["slash", "block", "meditate"])
        e.state.energy = 1
        var ok_all := true
        for iid in ids:
                var r := e.play_card(int(iid))
                if not r["ok"]:
                        ok_all = false
        check("零费牌同回合可全部使用（无出牌次数上限）", ok_all)
        eq("零费牌不扣能量，也没有默认回能：能量保持 1", e.state.energy, 1)
        eq("魔像生命 30（只有斩击 5 点伤害）", e.state.enemy_hp, 30)
        eq("玩家护盾 9（6+2，另加 1→3 因数关系 3 的 +1）", e.state.player_shield, 9)
        eq("本回合累计点数 2+3+1=6", e.state.points_total, 6)
        check("区域互斥完整", integrity_ok(e))


# ── A03 斩击命中无护盾敌人（M02：取消攻击牌默认回能）──────
func _a03() -> void:
        section("A03 斩击命中无护盾敌人")
        var e := new_battle()
        var ids := set_hand(e, ["slash"])
        e.state.energy = 0
        e.play_card(int(ids[0]))
        eq("敌人生命 -5", e.state.enemy_hp, 30)
        eq("攻击牌不再回能：能量仍为 0", e.state.energy, 0)
        eq("斩击点数 2", e.state.last_point, 2)


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
        eq("不回能（与是否打穿护盾无关）", e.state.energy, 0)


# ── A05 追击改用点数关系（M19）────────────────────────────
func _a05() -> void:
        section("A05 追击改用点数关系判定")
        var e := new_battle()
        var ids := set_hand(e, ["slash", "follow_up"])
        e.state.energy = 10
        # 2 → 4 是倍数关系：追击基础 3 改为 6，并再吃倍数第 1 层强化（伤害 +3）
        e.play_card(int(ids[0]))
        eq("斩击造成 5 伤害", e.state.enemy_hp, 30)
        e.play_card(int(ids[1]))
        eq("追击在倍数关系下造成 6+3=9 伤害", e.state.enemy_hp, 21)
        eq("倍数链第 1 层", e.state.mult_level, 1)
        eq("不依赖旧攻击牌次数：技能也不影响", e.state.same_level + e.state.factor_level, 0)
        # 单独打追击（无上一张）时只造成基础 3 伤害
        var e2 := new_battle()
        var ids2 := set_hand(e2, ["follow_up"])
        e2.state.energy = 10
        e2.play_card(int(ids2[0]))
        eq("无上一张时追击造成 3 伤害", e2.state.enemy_hp, 32)


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
        eq("失败出牌不断链、不累计", e.state.points_total, 0)


# ── A07 使用能量冲击造成伤害 ──────────────────────────────
func _a07() -> void:
        section("A07 使用能量冲击造成伤害")
        var e := new_battle()
        var ids := set_hand(e, ["energy_blast"])
        e.state.energy = 3
        e.play_card(int(ids[0]))
        eq("扣 3 能量", e.state.energy, 0)
        eq("造成 12 伤害", e.state.enemy_hp, 23)
        eq("技能不回能", e.state.energy, 0)
        eq("能量冲击点数 6", e.state.last_point, 6)


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
        eq("敌方阶段只回能一次", count_of(evs, T.EV_ENERGY_CHANGED), 1)


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
        eq("新回合清空上一张点数", e.state.last_point, 0)
        eq("新回合清空三类链", e.state.mult_level + e.state.factor_level + e.state.same_level, 0)
        check("区域互斥完整", integrity_ok(e))


# ── A10 空牌库且弃牌堆有牌时抽牌 ──────────────────────────
func _a10() -> void:
        section("A10 空牌库且弃牌堆有牌时抽牌")
        var e := new_battle()
        clear_hand(e)
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
        eq("一次结算只出手一次", count_of(evs, T.EV_MINION_ATTACKED), 1)
        eq("攻击后本回合不再就绪", bool(e.state.minions[0]["can_attack"]), false)
        eq("同一回合内重复结算不再出手",
                count_of(e.resolve_minion_attacks(), T.EV_MINION_ATTACKED), 0)


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


# ── A14 使用能量涌泉（旧版到期式场景保留）─────────────────
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
        e._start_player_turn()
        eq("第 3 次触发后能量", e.state.energy, 9)
        check("三次触发后场景清空", e.state.scene.is_empty())
        check("能量涌泉进入弃牌堆", e.state.discard_pile.has(es))
        check("区域互斥完整", integrity_ok(e))
        var e2 := new_battle()
        var ids2 := set_hand(e2, ["energy_spring"])
        e2.state.energy = 5
        e2.play_card(int(ids2[0]))
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
        check("未产生敌方行动事件", events_of(r["events"], T.EV_ENEMY_ACTED).is_empty())


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
        end_turn(e)
        eq("第 2 回合玩家行动期间魔像无护盾", e.state.enemy_shield, 0)
        end_turn(e)
        eq("第 3 回合玩家行动期间魔像仍有 8 护盾", e.state.enemy_shield, 8)
        eq("第 3 回合意图为重击 10", int(e.state.enemy_intent["value"]), 10)
        end_turn(e)
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
        eq("产生意图目标变化事件", count_of(evs, T.EV_INTENT_TARGET_CHANGED), 1)
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
        eq("组合状态清空", [e.state.last_point, e.state.mult_level, e.state.points_total], [0, 0, 0])
        check("待选择与临时牌状态清空", e.state.pending_choice.is_empty() and e.state.exiled.is_empty())
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
        check("终局后禁止融牌", not e.fuse_card(int(ids[0]))["ok"])
        check("终局后禁止结束回合", not e.request_end_turn()["ok"])


# ── A23 选中攻击牌后取消，或确认时目标无效 ────────────────
func _a23() -> void:
        section("A23 取消选择 / 目标无效时不结算")
        var e := new_battle()
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
        var total_before := e.state.points_total
        var r := e.play_card(st)
        check("确认时校验失败，不执行", not r["ok"])
        eq("不移牌", e.state.hand.size(), hand_before)
        eq("不扣费", e.state.energy, energy_before)
        eq("不产生弃牌", e.state.discard_pile.size(), discard_before)
        eq("失败不累计点数", e.state.points_total, total_before)
        check("区域互斥完整", integrity_ok(e))
        # 需要目标的牌没有目标时也必须拒绝
        e.state.energy = 12
        # can_play 允许暂缺目标（界面据此判断「可选」），但确认出牌必须补齐目标
        var tids := set_hand(e, ["tune", "slash"])
        check("需要目标的牌在未选目标时仍显示为可选", e.can_play(int(tids[0]))["ok"])
        var v2 := e.play_card(int(tids[0]))
        check("缺目标时拒绝结算", not v2["ok"], String(v2["reason"]))
        eq("缺目标时不扣费", e.state.energy, 12)
        check("缺目标时目标牌仍在手牌", e.state.hand.size() == 2)


# ── A24 两只就绪随从，左侧攻击击败魔像 ────────────────────
func _a24() -> void:
        section("A24 两只就绪随从，左侧攻击击败魔像")
        var e := new_battle()
        var ids := set_hand(e, ["striker", "guardian"])
        e.state.energy = 6
        e.play_card(int(ids[0]))
        e.play_card(int(ids[1]))
        e.state.minions[0]["can_attack"] = true
        e.state.minions[1]["can_attack"] = true
        e.state.enemy_hp = 3
        clear_hand(e)
        var r := e.confirm_end_turn(-1)
        eq("立即胜利", e.state.result, T.Result.VICTORY)
        eq("只有左侧随从出手", count_of(r["events"], T.EV_MINION_ATTACKED), 1)
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
        var total_before := e.state.points_total
        var evs = e.resolve_minion_attacks()
        eq("正常结算伤害（35-3）", e.state.enemy_hp, 32)
        eq("不给玩家回能", e.state.energy, energy_before)
        eq("自动攻击不额外计点（召唤牌本身的 4 点不变）", e.state.points_total, total_before)
        eq("无需玩家选目标，只攻击魔像", count_of(evs, T.EV_MINION_ATTACKED), 1)


# ══════════════════════════════════════════════════════════
#  B01 融牌充能（M21 / R01~R03）
# ══════════════════════════════════════════════════════════

func _b01_fusion() -> void:
        section("B01 融牌：把手牌弃进弃牌堆换能量")
        var e := new_battle()
        var ids := set_hand(e, ["slash", "block"])
        var fused := int(ids[0])
        e.state.energy = 2
        var r := e.fuse_card(fused)
        check("融牌成功", r["ok"], String(r["reason"]))
        eq("基础 +1 能量", e.state.energy, 3)
        eq("卡牌进入弃牌堆", e.state.zone_of(fused), T.Zone.DISCARD)
        check("不再在手牌", not e.state.hand.has(fused))
        eq("融牌不算出牌：上一张点数仍为空", e.state.last_point, 0)
        eq("融牌不计点数：累计仍为 0", e.state.points_total, 0)
        eq("三类链不变", e.state.mult_level + e.state.factor_level + e.state.same_level, 0)
        eq("产生融牌事件", count_of(r["events"], T.EV_CARD_FUSED), 1)
        check("区域互斥完整", integrity_ok(e))

        # 打不出去的牌也能融：费用不足 / 没有合法目标
        var e2 := new_battle()
        var i2 := set_hand(e2, ["energy_blast", "command"])
        e2.state.energy = 0
        var v_play := e2.can_play(int(i2[0]))
        check("能量冲击当前打不出去（费用不足）", not v_play["ok"], String(v_play["reason"]))
        var r2 := e2.fuse_card(int(i2[0]))
        check("费用不足的牌依然可以融掉", r2["ok"], String(r2["reason"]))
        eq("它照样进入弃牌堆", e2.state.zone_of(int(i2[0])), T.Zone.DISCARD)
        var v_cmd := e2.can_play(int(i2[1]))
        check("指令当前没有合法目标", not v_cmd["ok"], String(v_cmd["reason"]))
        var r2b := e2.fuse_card(int(i2[1]))
        check("没有合法目标的牌依然可以融掉", r2b["ok"], String(r2b["reason"]))

        # 能量已满：融牌依然成立，只是不获得能量
        var e3 := new_battle()
        var i3 := set_hand(e3, ["block"])
        e3.state.energy = e3.state.max_energy
        var r3 := e3.fuse_card(int(i3[0]))
        check("能量已满时允许融牌", r3["ok"], String(r3["reason"]))
        eq("能量保持 10（本次不获得能量）", e3.state.energy, 10)
        eq("卡牌照样进入弃牌堆", e3.state.zone_of(int(i3[0])), T.Zone.DISCARD)
        eq("事件里 energy_gained = 0",
                int(events_of(r3["events"], T.EV_CARD_FUSED)[0]["energy_gained"]), 0)
        check("区域互斥完整", integrity_ok(e3))

        # 临时衍生牌不能融牌
        var e4 := new_battle()
        var temp := make_temp(e4, "echo_slip", 4)
        var v4 := e4.can_fuse(temp)
        check("临时衍生牌不能融牌", not v4["ok"], String(v4["reason"]))

        # 融牌之后这张牌仍可能被洗回牌库（弃牌堆会在牌库抽空时重洗）
        var e5 := new_battle()
        var i5 := set_hand(e5, ["slash"])
        var sid := int(i5[0])
        e5.state.energy = 2
        e5.fuse_card(sid)
        check("融掉的牌躺在弃牌堆里（之后可被洗回牌库）", e5.state.discard_pile.has(sid))
        check("区域互斥完整", integrity_ok(e5))

# ══════════════════════════════════════════════════════════
#  B02 三类相邻链与独立断链（M23~M27 / R05~R17）
# ══════════════════════════════════════════════════════════

func _b02_chains() -> void:
        section("B02 三类相邻链与独立断链")

        # 倍数连续：1 → 2 → 4 → 8
        var e := new_battle()
        var ids := set_hand(e, ["meditate", "slash", "tune", "tactical_draw", "block"])
        e.state.energy = 20
        e.play_card(int(ids[0]))
        eq("1 点建立基准：无关系", e.state.mult_level, 0)
        e.play_card(int(ids[1]))
        eq("1→2：倍数第 1 层", e.state.mult_level, 1)
        e.play_card(int(ids[2]), {"hand_target": int(ids[4]), "point_delta": 1})
        eq("2→4：倍数第 2 层", e.state.mult_level, 2)
        e.play_card(int(ids[3]))
        eq("4→8：倍数第 3 层", e.state.mult_level, 3)
        eq("因数链保持 0", e.state.factor_level, 0)
        eq("同点链保持 0", e.state.same_level, 0)
        eq("回合点数和 1+2+4+8=15", e.state.points_total, 15)

        # 因数连续：8 → 4 → 2 → 1
        var e2 := new_battle()
        var i2 := set_hand(e2, ["tactical_draw", "tune", "slash", "meditate", "block"])
        e2.state.energy = 20
        e2.play_card(int(i2[0]))
        eq("8 点基准", e2.state.factor_level, 0)
        e2.play_card(int(i2[1]), {"hand_target": int(i2[4]), "point_delta": 1})
        eq("8→4：因数第 1 层", e2.state.factor_level, 1)
        e2.play_card(int(i2[2]))
        eq("4→2：因数第 2 层", e2.state.factor_level, 2)
        e2.play_card(int(i2[3]))
        eq("2→1：因数第 3 层", e2.state.factor_level, 3)
        eq("倍数链保持 0", e2.state.mult_level, 0)

        # 相邻同点：4 → 4 → 4
        var e3 := new_battle()
        var i3 := set_hand(e3, ["tune", "tune", "striker", "block"])
        e3.state.energy = 20
        e3.play_card(int(i3[0]), {"hand_target": int(i3[3]), "point_delta": 1})
        e3.play_card(int(i3[1]), {"hand_target": int(i3[3]), "point_delta": 1})
        eq("4→4：同点第 1 层", e3.state.same_level, 1)
        eq("相等不算倍数", e3.state.mult_level, 0)
        eq("相等不算因数", e3.state.factor_level, 0)
        e3.play_card(int(i3[2]))
        eq("4→4→4：同点第 2 层", e3.state.same_level, 2)

        # 方向切换：2 → 4 → 2（倍数 1 → 因数 1，没有同点）
        var e4 := new_battle()
        var i4 := set_hand(e4, ["slash", "tune", "slash", "block"])
        e4.state.energy = 20
        e4.play_card(int(i4[0]))
        e4.play_card(int(i4[1]), {"hand_target": int(i4[3]), "point_delta": 1})
        eq("2→4：倍数第 1 层", e4.state.mult_level, 1)
        e4.play_card(int(i4[2]))
        eq("4→2：切换为因数第 1 层", e4.state.factor_level, 1)
        eq("倍数链清零（不暂存）", e4.state.mult_level, 0)
        eq("非相邻同点不触发", e4.state.same_level, 0)

        # 同点断开：4 → 2 → 4
        var e5 := new_battle()
        var i5 := set_hand(e5, ["tune", "slash", "tune", "block"])
        e5.state.energy = 20
        e5.play_card(int(i5[0]), {"hand_target": int(i5[3]), "point_delta": 1})
        e5.play_card(int(i5[1]))
        eq("4→2：因数第 1 层", e5.state.factor_level, 1)
        e5.play_card(int(i5[2]), {"hand_target": int(i5[3]), "point_delta": 1})
        eq("4→2→4：仍无同点", e5.state.same_level, 0)
        eq("2→4：倍数第 1 层", e5.state.mult_level, 1)

        # 不匹配断链：2 → 4 → 3 → 6
        var e6 := new_battle()
        var i6 := set_hand(e6, ["slash", "tune", "block", "energy_blast", "meditate"])
        e6.state.energy = 20
        e6.play_card(int(i6[0]))
        e6.play_card(int(i6[1]), {"hand_target": int(i6[4]), "point_delta": 1})
        eq("2→4：倍数第 1 层", e6.state.mult_level, 1)
        e6.play_card(int(i6[2]))
        eq("4→3 不匹配：三条链全部归零",
                e6.state.mult_level + e6.state.factor_level + e6.state.same_level, 0)
        e6.play_card(int(i6[3]))
        eq("3→6：重新从倍数第 1 层开始", e6.state.mult_level, 1)

        # 取消递增奖励：1 → 2 → 3
        var e7 := new_battle()
        var i7 := set_hand(e7, ["meditate", "slash", "block"])
        e7.state.energy = 20
        e7.play_card(int(i7[0]))
        e7.play_card(int(i7[1]))
        eq("1→2：倍数第 1 层", e7.state.mult_level, 1)
        e7.play_card(int(i7[2]))
        eq("2→3 没有递增奖励：三条链归零",
                e7.state.mult_level + e7.state.factor_level + e7.state.same_level, 0)


# ══════════════════════════════════════════════════════════
#  B03 累计点数（M28 / R14）
# ══════════════════════════════════════════════════════════

func _b03_cumulative() -> void:
        section("B03 累计点数")
        var e := new_battle()
        var ids := set_hand(e, ["shield_break", "counter_stance"])
        e.state.energy = 20
        e.play_card(int(ids[0]))
        eq("7 点未到档", e.state.cumulative_triggers, 0)
        var r := e.play_card(int(ids[1]))
        eq("7→5 无倍因关系", e.state.mult_level + e.state.factor_level, 0)
        eq("累计 12 触发一次", e.state.cumulative_triggers, 1)
        eq("触发事件 1 次", count_of(r["events"], T.EV_CUMULATIVE_TRIGGERED), 1)
        eq("默认奖励：下回合额外抽 1 张", e.state.next_turn_extra_draw, 1)
        check("累计不贡献相邻链层数",
                e.state.mult_level + e.state.factor_level + e.state.same_level == 0)

        clear_hand(e)
        e._start_player_turn()
        eq("下回合抽 5+1=6 张", e.state.hand.size(), 6)
        eq("奖励已消耗", e.state.next_turn_extra_draw, 0)

        # 允许跨过阈值，并按档位多次触发
        var e2 := new_battle()
        var i2 := set_hand(e2, ["tactical_draw", "tactical_draw", "tactical_draw", "tactical_draw"])
        e2.state.energy = 40
        e2.play_card(int(i2[0]))
        e2.play_card(int(i2[1]))
        eq("16 点跨过 12：触发 1 次", e2.state.cumulative_triggers, 1)
        e2.play_card(int(i2[2]))
        eq("24 点达到第 2 档", e2.state.cumulative_triggers, 2)


# ══════════════════════════════════════════════════════════
#  B04 点数快照与临时修正（R18 / S01 / S04）
# ══════════════════════════════════════════════════════════

func _b04_point_modify() -> void:
        section("B04 点数快照与临时修正")
        var e := new_battle()
        var ids := set_hand(e, ["tune", "slash", "block"])
        e.state.energy = 20
        var target := int(ids[1])
        eq("斩击原始点数 2", e.state.effective_points(target), 2)
        var r := e.play_card(int(ids[0]), {"hand_target": target, "point_delta": -1})
        eq("调律 -1：有效点数变为 1", e.state.effective_points(target), 1)
        eq("产生点数修正事件", count_of(r["events"], T.EV_POINT_MODIFIED), 1)
        e._start_player_turn()
        eq("回合结束后临时修正清除", e.state.effective_points(target), 2)

        # 夹在 1~10：对 1 点牌再 -1 不会越界
        var e2 := new_battle()
        var i2 := set_hand(e2, ["tune", "meditate"])
        e2.state.energy = 20
        e2.play_card(int(i2[0]), {"hand_target": int(i2[1]), "point_delta": -1})
        eq("1 点牌 -1 后仍为 1（不越界）", e2.state.effective_points(int(i2[1])), 1)

        # 快照只影响未来：已出牌记录不改写
        var e3 := new_battle()
        var i3 := set_hand(e3, ["slash", "tune", "block"])
        e3.state.energy = 20
        e3.play_card(int(i3[0]))
        eq("已出牌的点数快照为 2", e3.state.last_point, 2)
        e3.play_card(int(i3[1]), {"hand_target": int(i3[2]), "point_delta": 1})
        eq("修改手牌不回写上一张快照", e3.state.last_point, 4)

        # 映片：把目标手牌改成自己的点数
        var e4 := new_battle()
        var i4 := set_hand(e4, ["block", "meditate"])
        e4.state.energy = 20
        var slip := make_temp(e4, "echo_slip", 9)
        eq("映片点数为生成时快照", e4.state.effective_points(slip), 9)
        e4.play_card(slip, {"hand_target": int(i4[0])})
        eq("目标手牌点数被改为映片点数", e4.state.effective_points(int(i4[0])), 9)
        check("映片用后离场（不进入弃牌堆）", e4.state.exiled.has(slip))


# ══════════════════════════════════════════════════════════
#  B05 特殊功能牌（M29 / M30）
# ══════════════════════════════════════════════════════════

func _b05_function_cards() -> void:
        section("B05 特殊功能牌")

        # 封存：本回合额外保留 1 张
        var e := new_battle()
        var ids := set_hand(e, ["seal", "slash", "block", "meditate"])
        e.state.energy = 20
        var r := e.play_card(int(ids[0]))
        eq("封存后额外保留额度 1", e.state.extra_keep, 1)
        e.request_end_turn()
        e.confirm_end_turn(int(ids[1]), [int(ids[2])])
        check("两张牌都被保留", e.state.hand.has(int(ids[1])) and e.state.hand.has(int(ids[2])))
        eq("下回合仍正常抽 5 张：2+5=7", e.state.hand.size(), 7)
        eq("额外保留额度在回合结束后归零", e.state.extra_keep, 0)

        # 检索：查看牌库顶 3 张，选 1 张，其余按原顺序置底
        var e2 := new_battle()
        var i2 := set_hand(e2, ["search"])
        e2.state.energy = 20
        var r2 := e2.play_card(int(i2[0]))
        eq("产生待选择", e2.state.pending_choice.is_empty(), false)
        var opened := events_of(r2["events"], T.EV_TUTOR_OPENED)
        eq("打开检索事件 1 次", opened.size(), 1)
        var revealed: Array = opened[0]["instance_ids"]
        eq("查看 3 张", revealed.size(), 3)
        check("结算区中的检索牌不能被本次检索选中", not revealed.has(int(i2[0])))
        var rest_before := e2.state.draw_pile.size()
        var res := e2.resolve_tutor_choice(1)
        check("选择成功", res["ok"], String(res["reason"]))
        check("选中的牌加入手牌", e2.state.hand.has(int(revealed[1])))
        eq("选中的 1 张离开牌库，其余 2 张回到牌库底", e2.state.draw_pile.size(), rest_before - 1)
        eq("其余牌按原顺序置于牌库底（第 1 张）", int(e2.state.draw_pile[0]), int(revealed[0]))
        eq("其余牌按原顺序置于牌库底（第 2 张）", int(e2.state.draw_pile[1]), int(revealed[2]))
        check("检索牌进入弃牌堆", e2.state.discard_pile.has(int(i2[0])))
        check("待选择已清空", e2.state.pending_choice.is_empty())
        check("区域互斥完整", integrity_ok(e2))

        # 指令：让已就绪仆从立即攻击，并消耗其本轮攻击机会
        var e3 := new_battle()
        var i3 := set_hand(e3, ["striker", "command"])
        e3.state.energy = 20
        e3.play_card(int(i3[0]))
        var v := e3.can_play(int(i3[1]), {"minion_slot": 0})
        check("准备中的仆从不是合法目标", not v["ok"], String(v["reason"]))
        e3._start_player_turn()
        check("新回合仆从就绪", bool(e3.state.minion_at_slot(0)["can_attack"]))
        var r3 := e3.play_card(int(i3[1]), {"minion_slot": 0})
        check("指令成功", r3["ok"], String(r3["reason"]))
        eq("仆从立即造成 3 伤害", e3.state.enemy_hp, 32)
        eq("指令计点：点数 8", e3.state.last_point, 8)
        eq("该仆从本轮攻击机会被消耗", bool(e3.state.minion_at_slot(0)["can_attack"]), false)
        eq("本轮结束不再重复攻击",
                count_of(e3.resolve_minion_attacks(), T.EV_MINION_ATTACKED), 0)


# ══════════════════════════════════════════════════════════
#  B06 临时衍生牌（M31 / A09 / A10）
# ══════════════════════════════════════════════════════════

func _b06_temp_cards() -> void:
        section("B06 临时衍生牌")
        var e := new_battle()
        var ids := set_hand(e, ["mirror_hall", "tune", "tune", "slash"])
        e.state.energy = 20
        e.play_card(int(ids[0]))
        check("场景常驻（triggers = -1）", int(e.state.scene["triggers"]) == -1)
        e._start_player_turn()
        e.play_card(int(ids[1]), {"hand_target": int(ids[3]), "point_delta": 1})
        e.play_card(int(ids[2]), {"hand_target": int(ids[3]), "point_delta": 1})
        eq("同点第 1 层", e.state.same_level, 1)
        var slip := -1
        for iid in e.state.hand:
                if e.state.def_id_of(int(iid)) == "echo_slip":
                        slip = int(iid)
        check("镜像回廊生成临时「映片」", slip != -1)
        eq("映片点数 = 触发牌点数 4", e.state.effective_points(slip), 4)
        check("映片被标记为临时牌", e.state.is_temp(slip))
        var v := e.can_fuse(slip)
        check("临时牌不能融牌", not v["ok"], String(v["reason"]))

        var r := e.play_card(slip, {"hand_target": int(ids[3])})
        check("映片可以使用", r["ok"], String(r["reason"]))
        eq("映片延续同点链到第 2 层", e.state.same_level, 2)
        check("映片用后移出战斗", e.state.zone_of(slip) == T.Zone.EXILED)
        check("映片不进入弃牌堆", not e.state.discard_pile.has(slip))
        eq("同名场景每回合只触发一次映片", _count_temp(e, "echo_slip"), 0)
        check("区域互斥完整", integrity_ok(e))

        # 临时牌不能保留：回合结束时离场
        var e2 := new_battle()
        var t2 := make_temp(e2, "short_order", 4)
        e2.request_end_turn()
        var evs2 = e2.confirm_end_turn(-1)["events"]
        check("回合结束时临时牌离场", e2.state.zone_of(t2) == T.Zone.EXILED)
        eq("产生临时牌到期事件", count_of(evs2, T.EV_TEMP_CARD_EXPIRED), 1)
        check("临时牌不进入弃牌堆", not e2.state.discard_pile.has(t2))
        check("区域互斥完整", integrity_ok(e2))


func _count_temp(e, def_id: String) -> int:
        var n := 0
        for iid in e.state.hand:
                if e.state.def_id_of(int(iid)) == def_id:
                        n += 1
        return n


# ══════════════════════════════════════════════════════════
#  B07 场上监听窗口与同名每回合首次触发（M34 / M36）
# ══════════════════════════════════════════════════════════

func _b07_listeners() -> void:
        section("B07 场上监听与同名首次触发")

        # 铸能工匠：每回合首次融牌额外 +1 能量
        var e := new_battle()
        var ids := set_hand(e, ["artificer", "slash", "block", "meditate"])
        e.state.energy = 20
        e.play_card(int(ids[0]))
        eq("工匠入场", e.state.minions.size(), 1)
        e.state.energy = 2
        e._start_player_turn()
        eq("回合开始后能量 3", e.state.energy, 3)
        var r := e.fuse_card(int(ids[1]))
        eq("融牌 1+工匠 1 = 能量 5", e.state.energy, 5)
        eq("产生同名首次触发事件", count_of(r["events"], T.EV_FIRST_TRIGGER), 1)
        e.state.energy = 2
        e.fuse_card(int(ids[2]))
        eq("同名每回合只触发一次：本次只 +1", e.state.energy, 3)

        # 新召唤的随从不监听自己这一次出牌（M36）
        var e2 := new_battle()
        var i2 := set_hand(e2, ["meditate", "slash", "striker", "block"])
        e2.state.energy = 20
        e2.play_card(int(i2[0]))
        e2.play_card(int(i2[1]))
        e2.play_card(int(i2[2]))
        eq("1→2→4：倍数第 2 层", e2.state.mult_level, 2)
        eq("刚入场的突击兵不监听自己的出牌", int(e2.state.minion_at_slot(0)["attack"]), 3)

        # 已在场的突击兵：倍数第 2 层时本轮攻击 +2
        var e3 := new_battle()
        var i3 := set_hand(e3, ["striker", "meditate", "slash", "hornist", "block"])
        e3.state.energy = 20
        e3.play_card(int(i3[0]))
        e3._start_player_turn()
        e3.play_card(int(i3[1]))
        e3.play_card(int(i3[2]))
        eq("1→2：倍数第 1 层", e3.state.mult_level, 1)
        var r3 := e3.play_card(int(i3[3]))
        eq("2→4：倍数第 2 层", e3.state.mult_level, 2)
        eq("在场突击兵本轮攻击 3+2=5", int(e3.state.minion_at_slot(0)["attack"]), 5)
        eq("产生监听事件", count_of(r3["events"], T.EV_FIRST_TRIGGER), 1)

        # 守卫：同点首次 → 本单位 +3 护盾（M35 仆从护盾）
        var e4 := new_battle()
        var i4 := set_hand(e4, ["guardian", "tune", "tune", "slash"])
        e4.state.energy = 20
        e4.play_card(int(i4[0]))
        e4._start_player_turn()
        e4.play_card(int(i4[1]), {"hand_target": int(i4[3]), "point_delta": 1})
        e4.play_card(int(i4[2]), {"hand_target": int(i4[3]), "point_delta": 1})
        eq("守卫获得 3 点仆从护盾", int(e4.state.minion_at_slot(0).get("shield", 0)), 3)

        # 蓄能矩阵：倍数第 2 层 → +1 能量
        var e5 := new_battle()
        var i5 := set_hand(e5, ["charge_matrix", "slash", "tune", "tactical_draw", "block"])
        e5.state.energy = 20
        e5.play_card(int(i5[0]))
        e5._start_player_turn()
        e5.state.energy = 5
        e5.play_card(int(i5[1]))
        e5.play_card(int(i5[2]), {"hand_target": int(i5[4]), "point_delta": 1})
        eq("进度：倍数第 1 层", e5.state.mult_level, 1)
        e5.state.energy = 5
        var r5 := e5.play_card(int(i5[3]))
        eq("倍数第 2 层触发场景：5 - 2 费 + 1 = 4", e5.state.energy, 4)
        eq("场景监听事件", count_of(r5["events"], T.EV_FIRST_TRIGGER), 1)


# ══════════════════════════════════════════════════════════
#  B08 仆从护盾（M35）
# ══════════════════════════════════════════════════════════

func _b08_minion_shield() -> void:
        section("B08 仆从护盾")
        var e := new_battle()
        var ids := set_hand(e, ["guardian", "tune", "tune", "slash"])
        e.state.energy = 20
        e.play_card(int(ids[0]))
        e._start_player_turn()
        e.play_card(int(ids[1]), {"hand_target": int(ids[3]), "point_delta": 1})
        e.play_card(int(ids[2]), {"hand_target": int(ids[3]), "point_delta": 1})
        var g: Dictionary = e.state.minion_at_slot(0)
        eq("守卫护盾 3", int(g["shield"]), 3)

        # 护盾先于生命吸收伤害，超额伤害不溢出给玩家
        e.state.enemy_intent = {"kind": T.IntentKind.ATTACK, "value": 4}
        e.state.enemy_cursor = 0
        e.enemy_phase()
        eq("护盾吸收 3", int(e.state.minion_at_slot(0).get("shield", 0)), 0)
        eq("只有 1 点打到生命（7→6）", int(e.state.minion_at_slot(0)["hp"]), 6)
        eq("玩家生命不受影响", e.state.player_hp, 60)

        # 下个玩家回合开始时清除仆从护盾
        e.state.minion_at_slot(0)["shield"] = 5
        e._start_player_turn()
        eq("仆从护盾在玩家回合开始清除", int(e.state.minion_at_slot(0).get("shield", 0)), 0)
        check("区域互斥完整", integrity_ok(e))


# ══════════════════════════════════════════════════════════
#  B09 卡表与原型牌组结构（M22 / M37）
# ══════════════════════════════════════════════════════════

func _b09_card_table() -> void:
        section("B09 卡表与原型牌组结构")
        eq("卡牌定义 21 种（含 2 张临时牌）", CardDB.CARDS.size(), 21)
        eq("原型牌组 20 张", CardDB.initial_deck().size(), 20)
        eq("数量合计一致", CardDB.total_card_count(), 20)
        var st := CardDB.deck_structure()
        eq("8 张基础即时牌", int(st["instant"]), 8)
        eq("6 张特殊功能牌", int(st["function"]), 6)
        eq("4 张仆从牌", int(st["minion"]), 4)
        eq("2 张场景牌", int(st["scene"]), 2)

        var points_ok := true
        var cost_ok := true
        for def_id in CardDB.CARDS.keys():
                var c: Dictionary = CardDB.CARDS[def_id]
                var p := int(c.get("points", 0))
                if p < T.POINTS_MIN or p > T.POINTS_MAX:
                        points_ok = false
                if p == int(c.get("cost", 0)) and String(def_id) == "energy_blast":
                        cost_ok = false
        check("所有卡牌点数都在 1~10", points_ok)
        check("点数与费用相互独立（能量冲击 6 点 / 3 费）", cost_ok)
        eq("斩击 2 点 0 费", [CardDB.card_points("slash"), int(CardDB.get_card("slash")["cost"])], [2, 0])
        eq("守卫 9 点 3 费", [CardDB.card_points("guardian"), int(CardDB.get_card("guardian")["cost"])], [9, 3])
        check("临时牌不进原型牌组",
                not CardDB.initial_deck().has("echo_slip") and not CardDB.initial_deck().has("short_order"))
        check("临时牌标记正确",
                CardDB.is_temp("echo_slip") and CardDB.is_temp("short_order"))
        check("每张即时牌都配置了三类强化之一",
                not CardDB.chain_ops("slash", T.ChainRelation.MULTIPLE).is_empty()
                and not CardDB.chain_ops("slash", T.ChainRelation.FACTOR).is_empty()
                and not CardDB.chain_ops("slash", T.ChainRelation.SAME).is_empty())