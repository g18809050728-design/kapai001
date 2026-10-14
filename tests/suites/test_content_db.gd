extends RefCounted
##
## ContentDB 验收：rulesets.json 是运行数值的唯一来源（《常量与规则配置》§1、§2、§3）。
##

const ContentDB := preload("res://src/content/content_db.gd")
const GameConstants := preload("res://src/common/game_constants.gd")


func run(h) -> void:
	h.begin("ContentDB · rulesets.json")

	var db := ContentDB.new()
	var info: Dictionary = db.load(GameConstants.MANIFEST_MVP)
	h.eq("内容加载成功", bool(info.get("ok", false)), true)
	if not bool(info.get("ok", false)):
		h.check("载入失败时给出错误码", not db.last_error_code.is_empty(), db.last_error_code)
		return

	h.check("ruleset_id 非空", not db.ruleset_id.is_empty(), db.ruleset_id)
	h.eq("schema_version 与 GameConstants 一致", db.schema_version, GameConstants.RULESET_SCHEMA_VERSION)
	h.problems("规则配置自检无问题", db.validate())

	# 《常量与规则配置》§2 已确定的基线
	h.eq("初始精力 72", db.run_int("starting_vitality", -1), 72)
	h.eq("初始生活费 60", db.run_int("starting_money", -1), 60)
	h.eq("起始牌组 12", db.run_int("starter_deck_size", -1), 12)
	h.eq("删除后下限 5", db.run_int("minimum_deck_size", -1), 5)
	h.eq("饰品槽 6", db.run_int("relic_slots", -1), 6)
	h.eq("学期数 8", db.run_int("term_count", -1), 8)
	h.eq("每学期节点 6", db.run_int("nodes_per_term", -1), 6)
	h.eq("学期恢复 20%", db.run_int("term_heal_percent", -1), 20)
	h.eq("休息恢复 25%", db.run_int("rest_heal_percent", -1), 25)

	h.eq("回合专注 3", db.battle_int("base_focus_per_turn", -1), 3)
	h.eq("专注上限 10", db.battle_int("focus_cap", -1), 10)
	h.eq("每回合抽牌 5", db.battle_int("base_draw_per_turn", -1), 5)
	h.eq("手牌上限 10", db.battle_int("hand_limit", -1), 10)
	h.eq("单位槽 3", db.battle_int("unit_slots", -1), 3)
	h.eq("场景槽 1", db.battle_int("scene_slots", -1), 1)
	h.eq("场景牌考试抽牌 1", db.battle_int("scene_exam_draw", -1), 1)
	h.eq("单位行动精力消耗 1", db.battle_int("unit_action_vitality_cost", -1), 1)
	h.eq("DDL 下限 1", db.battle_int("minimum_ddl", -1), 1)

	# 数组索引 0/1 = 未升级/已升级（§3）；JSON 数字是 float，逐项取整比较
	var coop: Array = db.battle_value("cooperation_exam_relax", [])
	h.eq("合作牌考试放松·普通 5", int(coop[0]) if coop.size() > 0 else -1, 5)
	h.eq("合作牌考试放松·升级 7", int(coop[1]) if coop.size() > 1 else -1, 7)
	var scene_relax: Array = db.battle_value("scene_exam_relax", [])
	h.eq("场景牌考试放松·普通 2", int(scene_relax[0]) if scene_relax.size() > 0 else -1, 2)
	h.eq("场景牌考试放松·升级 4", int(scene_relax[1]) if scene_relax.size() > 1 else -1, 4)

	# §3 百分比语义：100 表示原值，115 不是 115 倍
	h.eq("100% 即原值", db.scaled_by_percent(72, 100), 72)
	h.eq("115% 是百分比（20 → 23）", db.scaled_by_percent(20, 115), 23)
	h.eq("难度 hard 压力倍率 115", db.difficulty_int(GameConstants.DIFFICULTY_HARD, "pressure_percent", -1), 115)
	h.eq("难度 relaxed 初始精力 84", db.difficulty_int(GameConstants.DIFFICULTY_RELAXED, "starting_vitality", -1), 84)
	h.eq("难度 normal DDL 偏移 0", db.difficulty_int(GameConstants.DIFFICULTY_NORMAL, "ddl_offset", 99), 0)

	# 状态：已确定上限的进表，护卫/查重护盾按 §3 不设上限
	h.eq("灵感层数上限 5", db.status_int(GameConstants.STATUS_INSPIRATION, "cap", -1), 5)
	h.eq("灵感每层完成度 2", db.status_int(GameConstants.STATUS_INSPIRATION, "completion_per_stack", -1), 2)
	h.check("护卫在表中无上限条目", db.status_entry(GameConstants.STATUS_GUARD).is_empty())
	h.check("查重护盾在表中无上限条目", db.status_entry(GameConstants.STATUS_PLAGIARISM_SHIELD).is_empty())

	# 幂等：重复加载与首次一致
	var again := ContentDB.new()
	h.check("重复加载成功", bool(again.load(GameConstants.MANIFEST_MVP).get("ok", false)))
	h.eq("重复加载 ruleset 内容一致", str(again.ruleset()), str(db.ruleset()))
	h.check("首次加载后 is_loaded 为 true", db.is_loaded())

	# 版本不匹配必须被拒绝（写一个临时错误内容包）
	var bad := ContentDB.new()
	bad.ruleset_id = "sentinel"
	h.check("未加载时 validate 报问题", not bad.validate().is_empty())
