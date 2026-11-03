class_name UiGlossary
extends RefCounted

const ENTRIES := {
	"strategy":
	{
		"name": "策略",
		"type": "牌类型",
		"short": "安排顺序、取回或准备后续工作的牌。",
		"body": "策略牌本身通常不直接推进任务；它与相邻工作、连携和取回相关。具体限制以卡面为准。"
	},
	"work":
	{
		"name": "工作",
		"type": "牌类型",
		"short": "直接推进任务完成量的牌。",
		"body": "工作牌的完成量先扣任务屏障，再减少未完成量；直接完成量可受易伤影响。"
	},
	"cooperation":
	{"name": "合作", "type": "牌类型", "short": "与伙伴或协作相关的牌。", "body": "合作牌在考试替代面中仍保留合作类型；合作结算可触发角色被动。"},
	"focus":
	{
		"name": "专注",
		"type": "资源",
		"short": "每回合出牌的主要成本，自然 3，上限 10。",
		"body": "准备阶段先清剩余再计算；下回合恢复。弃牌不返还专注。"
	},
	"vitality":
	{
		"name": "精力",
		"type": "资源",
		"short": "跨节点生命；战后不自动回满。",
		"body": "压力先由放松抵挡，再扣精力。主动支付精力须至少保留 1；直接失去精力可归零并失败。"
	},
	"relax":
	{"name": "放松", "type": "资源", "short": "当轮抵挡压力，下次准备清旧值。", "body": "放松不是永久护甲；抵挡顺序和分段以任务压力结算为准。"},
	"ddl":
	{
		"name": "DDL",
		"type": "计时",
		"short": "剩余完整轮末次数；归零仍有任务即失败。",
		"body": "多个阶段共享 DDL；推进与延后以规则书和卡面为准。"
	},
	"complete":
	{
		"name": "完成量",
		"type": "任务输出",
		"short": "推进任务的主要数值，先扣屏障再扣未完成量。",
		"body": "状态完成量仍过屏障；易伤只增强工作牌直接完成量，不增强自动输出。"
	},
	"shield":
	{"name": "屏障", "type": "任务防护", "short": "任务的护盾，先于未完成量被扣。", "body": "屏障不是玩家放松；脆化只影响新获得的屏障。"},
	"negative":
	{
		"name": "负面状态",
		"type": "任务/玩家状态",
		"short": "挂在任务或玩家身上的不利状态。",
		"body": "六种任务负面、玩家负面和额外要求分别结算；不要把任务负面混入我方状态栏。"
	},
	"pressure":
	{"name": "压力", "type": "任务攻击", "short": "任务对玩家造成的攻击。", "body": "压力先由放松抵挡，再扣精力；乏力、虚弱等会改变每段压力。"},
	"erosion":
	{
		"name": "侵蚀",
		"type": "任务负面",
		"short": "任务准备时按层数造成持续完成量，结算后减 1。",
		"body": "自然结算后减 1；提前验算额外一次但不减层。状态完成量仍受屏障影响，不受易伤加成。"
	},
	"induced":
	{
		"name": "诱发",
		"type": "任务负面",
		"short": "成功出牌后按开始时层数追加完成量。",
		"body": "新施加不触发自身；每目标每回合默认与额外合计最多 4 次，行动结束清。"
	},
	"brittle":
	{"name": "脆化", "type": "任务负面", "short": "新获得的屏障减半，已有屏障不变。", "body": "按 50% 向下取整；压力窗口后减 1。"},
	"feebleness":
	{"name": "乏力", "type": "任务负面", "short": "每段压力先减去层数，最低到 0。", "body": "不是百分比减伤；任务实例内保持，换阶段清除。"},
	"weakness":
	{
		"name": "虚弱",
		"type": "任务负面",
		"short": "每段压力乘以 0.75 并向下取整。",
		"body": "压力窗口后减 1；与乏力分别结算，不能混为一谈。"
	},
	"vulnerability":
	{
		"name": "易伤",
		"type": "任务负面",
		"short": "工作牌直接完成量乘以 1.25 并向下取整。",
		"body": "不增强伙伴、章节自动或状态完成量；压力窗口后减 1。"
	},
	"anxiety":
	{"name": "焦虑", "type": "玩家负面", "short": "下次自然专注每层少 1。", "body": "对应准备生效后清；不是永久降低上限。"},
	"procrastination":
	{"name": "拖延", "type": "玩家负面", "short": "下次基础抽牌每层少 1。", "body": "只影响基础抽牌，不影响效果抽牌；对应抽牌生效后清。"},
	"drowsiness":
	{"name": "困倦", "type": "玩家负面", "short": "下次行动工作首段每层少 1。", "body": "对应行动结束清；不是整回合减伤。"},
	"extra_requirements":
	{
		"name": "额外要求",
		"type": "任务状态",
		"short": "任务压力每层 +2，本战仅明确移除。",
		"body": "不是普通任务负面；首期投放以 G0 为准。"
	},
	"guard":
	{"name": "护卫", "type": "伙伴能力", "short": "承接默认单体压力，不拦全体或点名。", "body": "单段过量不溢出；伙伴离场失效。"},
	"synergy":
	{"name": "协同", "type": "唐以宁资源", "short": "战内资源，上限 6，用于牌面或门槛。", "body": "不是专注；获得与消耗按卡面结算。"},
	"retrieve":
	{"name": "取回", "type": "牌区操作", "short": "从弃牌堆取回合法永久牌。", "body": "不减费、不刷新限次；满手时牌仍在弃牌堆。"},
	"exhaust":
	{"name": "耗尽", "type": "牌区状态", "short": "本战不再循环，不是删除永久牌。", "body": "耗尽牌进入消耗堆；该牌本场不再回到抽牌堆。"},
	"retain": {"name": "保留", "type": "牌区操作", "short": "保护下一次轮末弃牌。", "body": "离手即清；保留额度以当前视图为准。"},
	"paper_open":
	{"name": "开题", "type": "论文", "short": "开启论文记录，占用首次基础抽 5 的一格。", "body": "只有开题后才能记录进度、引用与发表。"},
	"paper_progress":
	{"name": "论文进度", "type": "论文", "short": "不同牌名首次实际使用累计，上限 10。", "body": "不是任务完成量；升级和复制不改牌名。"},
	"paper_citation":
	{
		"name": "引用",
		"type": "论文",
		"short": "重复牌名累计，上限 5，第 3/4/5 层分层付款。",
		"body": "付款使用主体结算后的余额；不足不加层改抽 1。"
	},
	"paper_modifier":
	{"name": "修正", "type": "论文", "short": "论文完成度的加减项。", "body": "不是永久属性；换题成功才修正 -1。"},
	"paper_amplify":
	{"name": "增幅", "type": "论文", "short": "强化下一张卡正文首个白名单正向数值。", "body": "不强化完成量、修正、发表、负面或自动/被动。"},
	"paper_publish":
	{
		"name": "发表",
		"type": "论文",
		"short": "一次兑现论文并退回全部章节。",
		"body": "主目标完成 C+10，其他 floor(C/2)；C=100 时全体再 +20。"
	},
	"chapter_deploy":
	{"name": "部署章节", "type": "章节", "short": "把章节放入三槽，下回合开始按槽序自动运行。", "body": "自动运行不算出牌、不记账；同名不可叠。"},
	"chapter_run":
	{"name": "运行章节", "type": "章节", "short": "按槽序触发章节的基础效果。", "body": "手动重用正常付费，只结算基础与记账；额外激活单独记次。"},
	"chapter_return":
	{"name": "收回章节", "type": "章节", "short": "把章节从槽位退回弃牌堆。", "body": "发表会退回全部章节；撤回不刷新限次。"},
	"swap_chapter_slots":
	{"name": "交换章节", "type": "章节", "short": "交换槽位顺序。", "body": "换序不刷新本轮限次，也不重新生效。"},
	"copy_chapter_to_hand":
	{"name": "复印章节", "type": "章节", "short": "复制章节到手中，使用源牌名。", "body": "复制不新增卡种；仍受手牌与限次约束。"},
	"change_topic":
	{"name": "换题", "type": "论文", "short": "移除一个已用名，成功才修正 -1。", "body": "不退已有进度/引用，不刷新同名限次。"},
	"gain_synergy":
	{"name": "获得协同", "type": "唐以宁", "short": "增加协同，上限 6。", "body": "协同用于牌面或门槛，不是专注。"},
	"spend_synergy":
	{"name": "消耗协同", "type": "唐以宁", "short": "消耗协同支付牌面或门槛。", "body": "不足时按卡面规则处理，不自动改为专注。"},
	"summon_partner":
	{"name": "召入伙伴", "type": "伙伴", "short": "把伙伴放入协作区，最多 3 位。", "body": "满槽需换班，换班不退卡。"},
	"partner_extra_action":
	{
		"name": "伙伴额外行动",
		"type": "伙伴",
		"short": "让伙伴在正常行动外再行动一次。",
		"body": "每实例每回合最多一次，也消耗续航；不能刷新旧实例记录。"
	},
	"partner_heal":
	{"name": "伙伴治疗", "type": "伙伴", "short": "按实例上限恢复伙伴续航。", "body": "恢复不超过短驻场上限；主动撤回不退卡。"},
	"partner_retreat":
	{"name": "伙伴撤回", "type": "伙伴", "short": "把伙伴移出协作区，不退卡。", "body": "撤回不牺牲已获得的协作收益。"}
}


static func label(key: String) -> String:
	var existing := UiStyle.label(key)
	if existing != key:
		return existing
	var entry: Dictionary = ENTRIES.get(key, {})
	return str(entry.get("name", key)) if not entry.is_empty() else key


static func describe(key: String) -> String:
	var entry: Dictionary = ENTRIES.get(key, {})
	if entry.is_empty():
		return "词条：%s\n当前版本暂无详细解释。" % UiStyle.label(key)
	var lines: PackedStringArray = [
		"%s · %s" % [label(key), str(entry.get("type", ""))],
		str(entry.get("short", "")),
	]
	var body := str(entry.get("body", ""))
	if not body.is_empty():
		lines.append(body)
	lines.append("来源：卡牌名词与Buff效果说明；规则书。")
	return "\n".join(lines)


static func keys_for_effects(effects: Array) -> Array[String]:
	var result: Array[String] = []
	for value in effects:
		if not value is Dictionary:
			continue
		var effect: Dictionary = value
		for field in ["status", "op"]:
			var key := str(effect.get(field, ""))
			if ENTRIES.has(key) and not result.has(key):
				result.append(key)
		if str(effect.get("category", "")) == "negative" and not result.has("negative"):
			result.append("negative")
	return result


static func keys_for_types(types: Array) -> Array[String]:
	var result: Array[String] = []
	for value in types:
		var key := str(value)
		if ENTRIES.has(key) and not result.has(key):
			result.append(key)
	return result
