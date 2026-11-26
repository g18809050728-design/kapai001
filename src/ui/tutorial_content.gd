class_name UiTutorialContent
extends RefCounted

## Fixed first-run teaching copy. Rule numbers here mirror
## data/four_year/definitions/rulesets.json (focus 3 / cap 10, draw 5, hand 10)
## and the glossary in ui_glossary.gd. Buttons and dynamic values stay out of
## the editable text library.


static func intro_steps() -> Array:
	return [
		{
			"icon": "info",
			"chapter": "开局",
			"title": "先看懂三个数值",
			"body": "这局的目标，是走完四个学年，在每次 DDL 到期前完成考试与任务。先认清会一直跟着你的三个数值。",
			"bullets": [
				{
					"term": UiGlossary.label("vitality"),
					"text": "你的生命。战斗结束不会自动回满；受到压力时先扣放松（当轮护挡，下次准备清空），再扣精力。主动支付精力时至少保留 1 点。",
				},
				{
					"term": "金钱",
					"text": "在商店买卡、删卡、买饭，也会在事件中使用。战斗、事件和学年结算都会带来收入。",
				},
				{
					"term": UiGlossary.label("ddl"),
					"text": "战斗倒计时：还剩几个完整轮末。归零时若还有任务没完成，战斗失败。",
				},
			],
			"tip": "把指针停在数值或词条上，可以查看完整说明。",
			"anchor": "",
		},
		{
			"icon": "map",
			"chapter": "路线",
			"title": "地图：一次只走一站",
			"body": "每年一张路线图，从下往上推进。节点分为战斗、精英、Boss、商店、事件和休息，路线会决定你遇到的敌人与补给。",
			"bullets": [
				{
					"term": "先预选，再进入",
					"text": "第一次点击可达节点只会预选，并预览后 3 层路线；再点同一节点或「进入此节点」才会真正前进。",
				},
				{
					"term": "只看路线",
					"text": "不可达节点也可以点，用来查看路线和风险，但不会进入。",
				},
				{
					"term": "学年结算",
					"text": "每学年结束会结算 DDL 与成绩，并恢复一部分精力；之后进入下一学年。",
				},
			],
			"tip": "按 M 可打开本学年全图概览，只读查看，不会改变进度。",
			"anchor": "map_node",
		},
		{
			"icon": "focus",
			"chapter": "战斗",
			"title": "专注、手牌与回合",
			"body": "进入战斗后，每回合抽 5 张牌，并恢复 3 点专注（上限 10）。卡牌费用角上的数字，就是这张牌要花多少专注。",
			"bullets": [
				{
					"term": UiGlossary.label("focus"),
					"text": "支付卡牌费用；每回合准备阶段回到 3 点，用不完不会保留。",
				},
				{
					"term": "手牌",
					"text": "每回合抽 5 张，上限 10 张。点击选牌；需要目标时再点高亮任务或伙伴，无目标牌会直接打出。",
				},
				{
					"term": "拖动与快捷键",
					"text": "也可以把整张牌拖到目标上松手；数字键 1—9 选牌，右键或 Esc 取消。",
				},
				{
					"term": "牌堆",
					"text": "抽牌堆在左下，弃牌堆和消耗堆在右下；点击可以查看。",
				},
				{
					"term": "回合",
					"text": "行动完点右下角「结束回合」；手牌弃置，任务按意图行动，然后抽新牌、恢复专注。",
				},
			],
			"tip": "下一场战斗开始后，教程会在真实界面上继续指出这些位置。",
			"anchor": "",
			"next": "开始冒险",
		},
	]


static func battle_steps() -> Array:
	return [
		{
			"icon": "rules",
			"chapter": "战斗",
			"title": "先读敌人：意图、屏障与 DDL",
			"body": "任务会预告下回合的行动。先看任务上方的意图，再决定先完成谁。你的精力在左上角，压力会先扣放松，再扣精力。",
			"bullets": [
				{
					"term": "下回合意图",
					"text": "任务准备阶段会做什么，提前显示在任务上方。",
				},
				{
					"term": UiGlossary.label("shield"),
					"text": "任务的护盾，先扣屏障再扣完成量；它不是你的「放松」。",
				},
				{
					"term": "完成量",
					"text": "任务下方的「剩余 / 上限」就是还要推进的完成量；工作牌先扣屏障，再扣它。",
				},
				{
					"term": UiGlossary.label("ddl"),
					"text": "顶部中间的倒计时每个完整轮末减 1；归零仍有任务就失败。",
				},
			],
			"tip": "悬停或点击任务，可以查看本回合的完整结算。",
			"anchor": "battle_intents",
		},
		{
			"icon": "focus",
			"chapter": "战斗",
			"title": "专注：出牌要花的资源",
			"body": "左下角的专注装置显示当前剩余专注。卡牌左上角类型图案里的数字，就是它的费用。",
			"bullets": [
				{
					"term": "每回合 3 点",
					"text": "准备阶段先清掉剩余专注，再恢复到 3 点，上限 10。",
				},
				{
					"term": "费用不足",
					"text": "费用不够的牌会变暗，不能打出。",
				},
				{
					"term": "牌堆",
					"text": "抽牌堆在左下，弃牌堆和消耗堆在右下；点击查看内容。",
				},
			],
			"tip": "专注不是精力：出牌花专注，挨打掉精力。",
			"anchor": "battle_focus",
		},
		{
			"icon": "deck",
			"chapter": "战斗",
			"title": "出牌，然后结束回合",
			"body": "点击手牌开始。需要目标时点高亮任务或伙伴；不需要目标的牌会直接结算。",
			"bullets": [
				{
					"term": "出牌",
					"text": "点击手牌 → 点高亮目标；或把整张牌拖到目标上松手。数字 1—9 选牌，右键或 Esc 取消。",
				},
				{
					"term": "结束回合",
					"text": "点右下角「结束回合」：手牌弃置，任务按意图行动，DDL 减 1，然后抽 5 张新牌并恢复专注。",
				},
				{
					"term": "顺序",
					"text": "先看敌人意图再出牌；留够专注，别把牌全打光才发现下回合要防守。",
				},
			],
			"tip": "手牌为空时也可以结束回合；没有能打出的牌时，结束回合就是唯一选择。",
			"anchor": "battle_end_turn",
			"next": "开始战斗",
		},
	]
