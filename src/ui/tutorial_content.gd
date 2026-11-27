class_name UiTutorialContent
extends RefCounted

## Short first-run teaching copy. Rule numbers mirror
## data/four_year/definitions/rulesets.json (focus 3 / cap 10, draw 5, hand 10)
## and the glossary in ui_glossary.gd. Every visible string owns a stable
## `tutorial:<page>.<field>` UID so the text editor can override it without
## touching rules, anchors, triggers or the drawing of the overlay.

const PAGES := [
	{
		"id": "intro_1",
		"kind": "intro",
		"icon": "info",
		"chapter": "开局",
		"title": "三个数值",
		"body": "先认清精力、金钱和 DDL。",
		"bullets": [
			{"key": "vitality", "term": "精力", "text": "生命；战后不回满，压力先扣放松。"},
			{"key": "money", "term": "金钱", "text": "在商店和事件中使用。"},
			{"key": "ddl", "term": "DDL", "text": "轮末减 1；归零仍有任务则失败。"},
		],
		"anchor": "",
	},
	{
		"id": "intro_2",
		"kind": "intro",
		"icon": "map",
		"chapter": "路线",
		"title": "地图",
		"body": "每年一张路线图，从下往上走。",
		"bullets": [
			{"key": "enter", "term": "进入", "text": "点可达节点预选，再点一次进入。"},
			{"key": "view", "term": "查看", "text": "其他节点只看路线，不会前进。"},
			{"key": "year", "term": "学年", "text": "学年结束会恢复部分精力。"},
		],
		"anchor": "map_node",
	},
	{
		"id": "intro_3",
		"kind": "intro",
		"icon": "focus",
		"chapter": "战斗",
		"title": "战斗准备",
		"body": "每回合抽 5 张，获得 3 点专注。",
		"bullets": [
			{"key": "focus", "term": "专注", "text": "支付卡牌费用，上限 10。"},
			{"key": "play", "term": "出牌", "text": "点牌再点目标，或拖到目标上。"},
			{"key": "keys", "term": "操作", "text": "1—9 选牌，右键或 Esc 取消。"},
			{"key": "turn", "term": "回合", "text": "点右下「结束回合」结束行动。"},
		],
		"anchor": "",
		"next": "开始冒险",
	},
	{
		"id": "battle_1",
		"kind": "battle",
		"icon": "rules",
		"chapter": "战斗",
		"title": "先读敌人",
		"body": "先看意图，再决定打谁。",
		"bullets": [
			{"key": "intent", "term": "意图", "text": "下回合会做什么。"},
			{"key": "shield", "term": "屏障", "text": "先扣盾，再扣完成量。"},
			{"key": "ddl", "term": "DDL", "text": "轮末减 1；归零仍有任务则失败。"},
			{"key": "vitality", "term": "精力", "text": "压力先扣放松，再扣精力。"},
		],
		"anchor": "battle_intents",
	},
	{
		"id": "battle_2",
		"kind": "battle",
		"icon": "focus",
		"chapter": "战斗",
		"title": "专注",
		"body": "左下是剩余专注，牌角数字是费用。",
		"bullets": [
			{"key": "round", "term": "每回合 3 点", "text": "上限 10。"},
			{"key": "cost", "term": "费用不足", "text": "牌会变暗，不能打出。"},
			{"key": "piles", "term": "牌堆", "text": "点两侧牌堆可查看。"},
		],
		"anchor": "battle_focus",
	},
	{
		"id": "battle_3",
		"kind": "battle",
		"icon": "deck",
		"chapter": "战斗",
		"title": "出牌与结束回合",
		"body": "点牌再点目标；无目标牌直接打出。",
		"bullets": [
			{"key": "keys", "term": "选牌", "text": "1—9 选牌，右键或 Esc 取消。"},
			{"key": "end", "term": "结束回合", "text": "弃手牌，敌人行动，抽新牌。"},
			{"key": "order", "term": "顺序", "text": "先看意图，留够专注防守。"},
		],
		"anchor": "battle_end_turn",
		"next": "开始战斗",
	},
]


static func intro_steps() -> Array:
	return _resolved("intro")


static func battle_steps() -> Array:
	return _resolved("battle")


static func entity_pages() -> Array:
	return PAGES.duplicate(true)


static func page_uid(page_id: String, field: String) -> String:
	return "tutorial:%s.%s" % [page_id, field]


static func bullet_uid(page_id: String, index: int, field: String) -> String:
	return "tutorial:%s.bullet_%d.%s" % [page_id, index + 1, field]


static func page_kind_label(page: Dictionary) -> String:
	return "开局" if str(page.get("kind", "")) == "intro" else "战斗"


static func _resolved(kind: String) -> Array:
	var result: Array = []
	for raw in PAGES:
		if str(raw.get("kind", "")) != kind:
			continue
		var page_id := str(raw.id)
		var step: Dictionary = raw.duplicate(true)
		step["chapter"] = TextOverrides.text(page_uid(page_id, "chapter"), str(raw.chapter))
		step["title"] = TextOverrides.text(page_uid(page_id, "title"), str(raw.title))
		step["body"] = TextOverrides.text(page_uid(page_id, "body"), str(raw.body))
		var bullets: Array = []
		for index in raw.bullets.size():
			var bullet: Dictionary = raw.bullets[index]
			bullets.append(
				{
					"term": TextOverrides.text(
						bullet_uid(page_id, index, "term"), str(bullet.term)
					),
					"text": TextOverrides.text(
						bullet_uid(page_id, index, "text"), str(bullet.text)
					),
				}
			)
		step["bullets"] = bullets
		if raw.has("next"):
			step["next"] = TextOverrides.text(page_uid(page_id, "next"), str(raw.next))
		result.append(step)
	return result
