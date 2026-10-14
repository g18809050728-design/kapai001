class_name BattleCardRules
extends RefCounted
##
## 出牌解析（《类与方法设计》CardResolver 节）：有效卡面、费用报价与合法性预检。
##
## 设计约定：
##   · 全部为静态函数，不持有可变状态；preview 与 apply 调同一套函数，保证
##     「界面预览与实际执行使用同一卡面」（《游戏规则书》[EXM-002]）。
##   · 只读状态、不做任何写入；随机、抽牌与扣费都在 BattleEngine 里发生。
##   · 有效卡面顺序 = 基础定义 → 升级整体替换 → 考试替代面（《统一设计文档》§3.4）。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const BattleState := preload("res://src/battle/battle_state.gd")

const SCOPE_ROUND := GameConstants.COUNTER_SCOPE_ROUND
const SCOPE_BATTLE := GameConstants.COUNTER_SCOPE_BATTLE


## 当前生效的饰品 hook：按时点 + 卡过滤（card_type / definition_id）+ 回合过滤 + 限次筛选。
## 只读、不消费计数（消费由调用方在效果真正生效后做）。返回
## [{hook, relic_id, hook_index, owner_key, per, trigger}]。
static func matched_relic_hooks(catalog, state, at: String, face: Dictionary = {}) -> Array:
        var matched := []
        if catalog == null or state == null:
                return matched
        for raw_relic_id in state.relics:
                var relic_id := String(raw_relic_id)
                var relic: Dictionary = catalog.definition(GameConstants.KIND_RELIC, relic_id)
                var hooks: Variant = relic.get("hooks")
                if typeof(hooks) != TYPE_ARRAY:
                        continue
                var hook_list: Array = hooks
                for index in range(hook_list.size()):
                        var hook: Dictionary = hook_list[index]
                        if String(hook.get("at", "")) != at:
                                continue
                        if not _face_matches_hook(hook, face):
                                continue
                        var rounds: Variant = hook.get("rounds")
                        if typeof(rounds) == TYPE_ARRAY and not (rounds as Array).is_empty():
                                # JSON 数字都是 float：Array.has(3) 对 [3.0] 是 false，必须按整数比。
                                var round_hit := false
                                for raw_round in (rounds as Array):
                                        if int(raw_round) == state.round_index:
                                                round_hit = true
                                                break
                                if not round_hit:
                                        continue
                        var owner_key := "%s%s:%d" % [GameConstants.COUNTER_OWNER_RELIC_HOOK_PREFIX, relic_id, index]
                        var limit: Variant = hook.get("limit")
                        var per := GameConstants.COUNTER_SCOPE_BATTLE
                        var times := 0
                        if typeof(limit) == TYPE_DICTIONARY:
                                per = String((limit as Dictionary).get("per", GameConstants.COUNTER_SCOPE_BATTLE))
                                times = maxi(1, int((limit as Dictionary).get("times", 1)))
                        if times > 0 and _counter_count(state, per, owner_key, GameConstants.COUNTER_TRIGGER_HOOK) >= times:
                                continue
                        matched.append({
                                "hook": hook,
                                "relic_id": relic_id,
                                "hook_index": index,
                                "owner_key": owner_key,
                                "per": per,
                                "trigger": GameConstants.COUNTER_TRIGGER_HOOK,
                        })
        return matched


## 费用报价期的饰品 hook（relics.json 的 hooks[].at == "cost_quote"）。
## 返回 {focus_discount, vitality_discount, sources, matches}：sources 是 CostQuote 的展示/审计字段，
## matches 供 BattleEngine 在出牌成功后消费同一批计数。
static func relic_cost_hooks(catalog, state, face: Dictionary) -> Dictionary:
        var result := {
                "focus_discount": 0,
                "vitality_discount": 0,
                "sources": [],
                "matches": [],
        }
        var vitality_base := maxi(0, int(face.get("vitality_cost", 0)))
        for entry in matched_relic_hooks(catalog, state, GameConstants.HOOK_COST_QUOTE, face):
                var hook: Dictionary = entry["hook"]
                var amount := maxi(0, int(hook.get("discount", 0)))
                var skip_vitality := bool(hook.get("skip_vitality_cost", false))
                if amount <= 0 and not skip_vitality:
                        continue
                result["sources"].append(String(entry["owner_key"]))
                result["matches"].append(entry)
                result["focus_discount"] = int(result["focus_discount"]) + amount
                if skip_vitality:
                        result["vitality_discount"] = int(result["vitality_discount"]) + vitality_base
        return result


## hook 的卡过滤：card_type 按卡面类型（考试备考面只换正文、类型不变，因此天然命中）；
## definition_id 按卡定义（升级前后同一定义都命中）。
static func _face_matches_hook(hook: Dictionary, face: Dictionary) -> bool:
        if face.is_empty():
                return true
        var definition_id := String(hook.get("definition_id", ""))
        if not definition_id.is_empty() and definition_id != String(face.get("definition_id", "")):
                return false
        var card_type := String(hook.get("card_type", ""))
        if not card_type.is_empty() and card_type != String(face.get("type", "")):
                return false
        return true


## Result<EffectiveCard>：基础/升级/考试后的卡面。
static func resolve_face(catalog, state, card_id: String) -> Dictionary:
        if state == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.play.no_state", {})
        var card = state.get_card(card_id)
        if card == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.play.unknown_card", {"card_id": card_id})
        var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
        if definition.is_empty():
                return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.content.unknown_definition", {
                        "kind": GameConstants.KIND_CARD,
                        "id": card.definition_id,
                })

        var face = {
                "card_id": card.card_id,
                "definition_id": card.definition_id,
                "name_key": String(definition.get("name_key", "")),
                "type": String(definition.get("type", "")),
                "rarity": definition.get("rarity"),
                "tags": (definition.get("tags", []) as Array).duplicate(),
                "cost": int(definition.get("cost", 0)),
                "vitality_cost": int(definition.get("vitality_cost", 0)),
                "target": String(definition.get("target", "")),
                "exhaust": bool(definition.get("exhaust", false)),
                "effects": (definition.get("effects", []) as Array).duplicate(true),
                "limit": definition.get("limit"),
                "upgrade_level": card.upgrade_level,
                "exam_face": "",
                "unit_bonus": {},
                "unplayable": bool(definition.get("unplayable", false)),
                "pre_effects": (definition.get("pre_effects", []) as Array).duplicate(true),
        }

        var upgrade: Variant = definition.get("upgrade")
        if card.upgrade_level > 0 and typeof(upgrade) == TYPE_DICTIONARY:
                for key in (upgrade as Dictionary):
                        if key == "effects":
                                face["effects"] = ((upgrade as Dictionary)[key] as Array).duplicate(true)
                        else:
                                face[key] = (upgrade as Dictionary)[key]

        face["cost"] = int(face.get("cost", 0))
        face["vitality_cost"] = int(face.get("vitality_cost", 0))
        face["exhaust"] = bool(face.get("exhaust", false))

        var card_type = String(face.get("type", ""))
        if card_type == GameConstants.CARD_COOPERATION and state.has_exam_limit(GameConstants.EXAM_INDEPENDENT_ANSWER):
                var level = 1 if card.upgrade_level > 0 else 0
                var relax = _indexed(catalog.battle_value("cooperation_exam_relax", [5, 7]), level, 5)
                face["effects"] = [{"op": GameConstants.OP_RELAX, "amount": relax}]
                face["target"] = GameConstants.TARGET_SELF
                face["exam_face"] = GameConstants.EXAM_FACE_PREPARE
                face["pre_effects"] = []
        elif card_type == GameConstants.CARD_SCENE and state.has_exam_limit(GameConstants.EXAM_FIXED_ROOM):
                var level_recall = 1 if card.upgrade_level > 0 else 0
                var relax_recall = _indexed(catalog.battle_value("scene_exam_relax", [2, 4]), level_recall, 2)
                var draw_count = catalog.battle_int("scene_exam_draw", 1)
                face["effects"] = [
                        {"op": GameConstants.OP_DRAW, "amount": draw_count},
                        {"op": GameConstants.OP_RELAX, "amount": relax_recall},
                ]
                face["target"] = GameConstants.TARGET_SELF
                face["exam_face"] = GameConstants.EXAM_FACE_RECALL
                face["pre_effects"] = []
        return Result.ok(face)


## CostQuote：费用 = max(0, 基础费用 + 加费 - 减费)；不消费优惠、不改状态。
static func cost_quote(catalog, state, face: Dictionary) -> Dictionary:
        var base = int(face.get("cost", 0))
        var added = 0
        var discount = 0
        # 主动支付的精力代价（《游戏规则书》[ENG-003]）：与专注一样先算减免、再进实际支付校验。
        # 减免源（A08「免除本战首次 K10 精力代价」）接在这里，见 t10。
        var vitality_base = maxi(0, int(face.get("vitality_cost", 0)))
        var vitality_discount = 0
        var sources = []
        var card_type = String(face.get("type", ""))

        # 场景 L03 自习室：每回合第一张工作牌费用 -1（最低 0）。
        if state != null and state.scene != null and card_type == GameConstants.CARD_WORK:
                var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, state.scene.definition_id)
                var modifiers: Variant = scene_def.get("modifiers")
                if typeof(modifiers) == TYPE_DICTIONARY:
                        var per_work = int((modifiers as Dictionary).get("first_work_cost_discount", 0))
                        var owner_key = "scene:" + String(state.scene.definition_id)
                        if per_work > 0 and _counter_count(state, SCOPE_ROUND, owner_key, "first_work_cost") == 0:
                                discount += per_work
                                sources.append(owner_key)

        # 饰品「费用减免 / 精力免除」hook：数据驱动（以前 A04 是硬编码分支）。
        # 只读、不消费——预检与预览会反复调用；消费在 BattleEngine._consume_cost_sources。
        var relic_quote := relic_cost_hooks(catalog, state, face)
        discount += int(relic_quote["focus_discount"])
        vitality_discount += int(relic_quote["vitality_discount"])
        for source_key in (relic_quote["sources"] as Array):
                if not sources.has(String(source_key)):
                        sources.append(String(source_key))

        return {
                "base": base,
                "added": added,
                "discount": discount,
                "cost": maxi(0, base + added - discount),
                "sources": sources,
                "vitality_base": vitality_base,
                "vitality_discount": vitality_discount,
                "vitality_cost": maxi(0, vitality_base - vitality_discount),
        }


## Result<PlayPlan>：目标、费用与实例限次全部通过才返回。
static func validate_play(catalog, state, payload: Dictionary) -> Dictionary:
        if state == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.play.no_state", {})
        if state.resolution != null:
                return Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.play.choice_pending", {})
        if String(state.phase) != GameConstants.PHASE_PLAYER_ACTION:
                return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.play.not_player_action", {
                        "phase": state.phase,
                })
        var card_id = String(payload.get("card_id", ""))
        if card_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.play.card_id_required", {})
        if state.zone_of(card_id) != GameConstants.ZONE_HAND:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.play.card_not_in_hand", {
                        "card_id": card_id,
                        "zone": state.zone_of(card_id),
                })

        var face_result = resolve_face(catalog, state, card_id)
        if not Result.is_ok(face_result):
                return face_result
        var face: Dictionary = face_result["data"]

        # 不可打出的牌（X01 等临时/特殊牌）在预检就拒绝，不扣费、不移牌。
        if bool(face.get("unplayable", false)):
                return Result.fail(GameConstants.ERROR_UNPLAYABLE, "error.play.unplayable", {
                        "card_id": card_id,
                        "definition_id": face.get("definition_id"),
                })

        # K07「无目标不可用」：弃牌堆可选目标不足时整张牌不可用，未支付即拒绝。
        var recall_needed := 0
        for raw_effect in (face.get("effects", []) as Array):
                if typeof(raw_effect) == TYPE_DICTIONARY and String((raw_effect as Dictionary).get("op", "")) == GameConstants.OP_RECALL_FROM_DISCARD:
                        recall_needed += maxi(1, int((raw_effect as Dictionary).get("amount", 1)))
        if recall_needed > 0 and state.zones.discard.size() < recall_needed:
                return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.play.no_recall_target", {
                        "required": recall_needed,
                        "available": state.zones.discard.size(),
                })

        var limit: Variant = face.get("limit")
        if typeof(limit) == TYPE_DICTIONARY:
                var per = String((limit as Dictionary).get("per", ""))
                var times = int((limit as Dictionary).get("times", 1))
                var owner_key = instance_owner(state, card_id)
                var trigger_key = limit_trigger(face)
                if _counter_count(state, per, owner_key, trigger_key) >= times:
                        return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.play.limit_reached", {
                                "definition_id": face.get("definition_id"),
                                "per": per,
                                "times": times,
                        })

        var quote = cost_quote(catalog, state, face)
        var focus_cost = int(quote.get("cost", 0))
        if state.player == null or state.player.focus < focus_cost:
                return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.play.not_enough_focus", {
                        "required": focus_cost,
                        "available": 0 if state.player == null else state.player.focus,
                })

        # 主动支付精力绕过放松，支付后必须至少剩 minimum_vitality_after_payment（[ENG-003]）。
        var vitality_cost = int(quote.get("vitality_cost", 0))
        var vitality_floor: int = catalog.battle_int("minimum_vitality_after_payment", 1)
        if vitality_cost > 0 and (state.player == null or state.player.vitality - vitality_cost < vitality_floor):
                return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.play.not_enough_vitality", {
                        "required": vitality_cost,
                        "available": 0 if state.player == null else state.player.vitality,
                        "must_keep": vitality_floor,
                })

        var target_ids: Array = (payload.get("target_ids", []) as Array).duplicate()
        if String(face.get("target", "")) == GameConstants.TARGET_TASK:
                if target_ids.size() != 1:
                        return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.play.target_required", {
                                "required": 1,
                                "got": target_ids.size(),
                        })
                var task = state.find_task(String(target_ids[0]))
                if task == null or task.work_remaining <= 0:
                        return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.play.target_gone", {
                                "task_id": target_ids[0],
                        })

        var replace_unit_id: Variant = payload.get("replace_unit_id")
        if String(face.get("type", "")) == GameConstants.CARD_COOPERATION and String(face.get("exam_face", "")).is_empty():
                var unit_slots: int = catalog.battle_int("unit_slots", 3)
                if state.units.size() >= unit_slots:
                        if replace_unit_id == null or state.find_unit(String(replace_unit_id)) == null:
                                return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.play.unit_slots_full", {
                                        "slots": unit_slots,
                                })

        return Result.ok({
                "card_id": card_id,
                "card": state.get_card(card_id),
                "face": face,
                "quote": quote,
                "target_ids": target_ids,
                "replace_unit_id": replace_unit_id,
        })


## 实例限次归属：优先原始卡实例（换场/回收不重置），衍生牌才退回战斗牌实例。
static func instance_owner(state, card_id: String) -> String:
        var card = state.get_card(card_id)
        if card == null:
                return card_id
        if card.origin_card_id != null:
                return String(card.origin_card_id)
        return card.card_id


static func limit_trigger(face: Dictionary) -> String:
        return "limit:%s:%s" % [String(face.get("definition_id", "")), String(face.get("exam_face", ""))]


static func _indexed(raw: Variant, index: int, fallback: int) -> int:
        if typeof(raw) == TYPE_ARRAY and (raw as Array).size() > index:
                return int((raw as Array)[index])
        return fallback


static func _counter_count(state, scope: String, owner_key: String, trigger_key: String) -> int:
        if state == null:
                return 0
        var key = BattleState.counter_key(scope, owner_key, trigger_key)
        var counter = state.counters.get(key)
        if counter == null:
                return 0
        if scope != GameConstants.COUNTER_SCOPE_BATTLE and counter.round != state.round_index:
                return 0
        return int(counter.count)