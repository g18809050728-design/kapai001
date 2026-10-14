extends RefCounted
##
## 内容定义 / 清单 / 候选池验收（《接口文档》§6、《数据库与实体关系设计》§4、§9）。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const RunServiceScript := preload("res://src/run/run_service.gd")
const GameConstants := preload("res://src/common/game_constants.gd")

## 冻结夹具清单（队长裁决 ①）：本套件只钉 ContentDB 的机制，数字全部来自冻结夹具；
## MVP 真实清单的内容事实钉在 test_content_mvp.gd。
const FIXTURE_MANIFEST := "test_minimal"


func run(h) -> void:
	h.begin("ContentDB · 定义与清单")

	var db := ContentDB.new()
	var info: Dictionary = db.load(FIXTURE_MANIFEST)
	h.check("MVP 清单加载成功", Result.is_ok(info))
	if not Result.is_ok(info):
		h.check("失败时给出错误码", not db.last_error_code.is_empty(), db.last_error_code)
		h.check("失败原因带诊断明细", Result.error_detail(info, "problems", []) != [], "")
		return

	h.eq("manifest_id", db.manifest_id, FIXTURE_MANIFEST)
	h.eq("content_version", db.content_version, "test-minimal-1")
	h.eq("content_hash 为 64 位十六进制", db.content_hash.length(), 64)

	var counts: Dictionary = info["data"]["counts"]
	h.eq("夹具启用卡牌 6 张", int(counts.get(GameConstants.KIND_CARD, -1)), 6)
	h.eq("夹具启用人物 1 个", int(counts.get(GameConstants.KIND_CHARACTER, -1)), 1)
	h.eq("夹具启用饰品 1 个", int(counts.get(GameConstants.KIND_RELIC, -1)), 1)
	h.eq("夹具启用任务 1 个", int(counts.get(GameConstants.KIND_TASK, -1)), 1)
	h.eq("夹具启用遭遇 1 个", int(counts.get(GameConstants.KIND_ENCOUNTER, -1)), 1)

	# 定义内容与《统一设计文档》数值一致
	var k01: Dictionary = db.get_definition(GameConstants.KIND_CARD, "K01")
	h.check("拿得到 K01", Result.is_ok(k01))
	var k01_def: Dictionary = k01["data"]
	h.eq("K01 费用 1", int(k01_def["cost"]), 1)
	h.eq("K01 基础完成量 6", int(k01_def["effects"][0]["amount"]), 6)
	h.eq("K01 升级后完成量 8", int(k01_def["upgrade"]["effects"][0]["amount"]), 8)
	h.eq("K01 带基础标签", k01_def["tags"].has("basic"), true)

	var k14_def: Dictionary = db.definition(GameConstants.KIND_CARD, "K14")
	h.eq("K14 有编译条件加值 3", int(k14_def["effects"][0]["bonus_if"]["amount"]), 3)
	h.eq("K13 每实例每回合限 1 次", int(db.definition(GameConstants.KIND_CARD, "K13")["limit"]["times"]), 1)

	# 引用完整性
	var p01: Dictionary = db.definition(GameConstants.KIND_CHARACTER, "P01")
	var starters: Array = p01["starter_cards"]
	h.eq("P01 额外起始牌 2 张", starters.size(), 2)
	h.check("起始牌都在启用清单内",
		db.is_enabled(GameConstants.KIND_CARD, String(starters[0]))
		and db.is_enabled(GameConstants.KIND_CARD, String(starters[1])))
	h.check("初始饰品在启用清单内", db.is_enabled(GameConstants.KIND_RELIC, String(p01["starter_relic_id"])))
	h.eq("P01 被动第 3 张工作牌触发", int(p01["passive"]["count"]), 3)

	var n01: Dictionary = db.definition(GameConstants.KIND_TASK, "N01")
	h.eq("N01 DDL 8", int(n01["ddl"]), 8)
	h.eq("N01 单一阶段", (n01["phases"] as Array).size(), 1)
	h.eq("N01 未完成量 24", int(n01["phases"][0]["work"]), 24)
	h.eq("N01 意图两段", (n01["phases"][0]["intents"] as Array).size(), 2)
	h.eq("N01 意图 A 压力 5", int(n01["phases"][0]["intents"][0]["pressure"]), 5)
	h.eq("N01 意图 B 压力 7", int(n01["phases"][0]["intents"][1]["pressure"]), 7)

	var encounter: Dictionary = db.definition(GameConstants.KIND_ENCOUNTER, "N01")
	h.eq("遭遇引用任务 N01", String(encounter["tasks"][0]), "N01")
	h.check("遭遇的任务已启用", db.is_enabled(GameConstants.KIND_TASK, "N01"))

	# 未定义 / 未启用
	var missing: Dictionary = db.get_definition(GameConstants.KIND_CARD, "K99")
	h.check("未定义的卡被拒绝", not Result.is_ok(missing))
	h.eq("未定义错误码", Result.error_code(missing), GameConstants.ERROR_CONTENT_INVALID)
	h.check("夹具未启用的 kind 一律拒绝", not Result.is_ok(db.get_definition(GameConstants.KIND_UNIT, "F01")))

	# 候选池：只过滤、不抽取、按 ID 稳定排序
	var all_cards: Array = db.get_candidates({"kind": GameConstants.KIND_CARD})
	h.eq("全部启用卡 6 张", all_cards.size(), 6)
	h.eq("候选池按 ID 稳定排序", all_cards[0], "K01")
	var reward_pool: Array = db.get_candidates({"kind": GameConstants.KIND_CARD, "exclude_tag": "basic"})
	h.eq("基础标签不进奖励池", reward_pool, ["K13", "K14"])
	var white_pool: Array = db.get_candidates({"kind": GameConstants.KIND_CARD, "rarity": "white"})
	h.eq("按品质过滤", white_pool.size(), 6)
	var excluded: Array = db.get_candidates({"kind": GameConstants.KIND_CARD, "excluded_ids": ["K01", "K02"]})
	h.eq("排除已选 ID", excluded.size(), 4)
	h.eq("未启用 kind 返回空", db.get_candidates({"kind": "unit"}).size(), 0)

	# 《类与方法设计》：加载失败时保留原可用索引，不发布半套内容
	var broken: Dictionary = db.load("no_such_manifest")
	h.check("未知清单被拒绝", not Result.is_ok(broken))
	h.check("失败后仍能读到原索引", Result.is_ok(db.get_definition(GameConstants.KIND_CARD, "K01")))
	h.eq("失败后清单名未被改写", db.manifest_id, FIXTURE_MANIFEST)

	# 幂等：重复加载得到同一内容哈希
	var hash_before := db.content_hash
	var again: Dictionary = db.load(FIXTURE_MANIFEST)
	h.check("重复加载成功", Result.is_ok(again))
	h.eq("内容哈希稳定", db.content_hash, hash_before)
	_event_ops(h)

## 事件 op 的权威实现在 RunService；这里钉住两份清单不许漂移。
func _event_ops(h) -> void:
	h.eq("ContentDB.EVENT_OPS 有 8 个", ContentDB.EVENT_OPS.size(), 8)
	h.eq("事件 op 与 RunService.EVENT_OPS 一致", str(ContentDB.EVENT_OPS), str(RunServiceScript.EVENT_OPS))
	h.check("events.json 已接入 kind 映射", ContentDB.KIND_FILES.has(GameConstants.KIND_EVENT))
