"""Rebuild the isolated four-year package and its exact map specification."""
from pathlib import Path
import copy
import json

ROOT = Path(__file__).resolve().parents[1]


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


# Prefix identifies a visible subtype; runtime kinds stay within the established codec.
KIND = {"N": "normal", "E": "event", "S": "shop", "EL": "elite", "K": "elite", "B": "boss"}
RAW = [
    ["N:课后习题", "E:社团招新|N:英语小作文", "S:校园商店", "N:C语言练习|EL:随堂小测", "R:宿舍休息", "N:基础课程阶段作业",
     "N:课后习题A|N:英语小作文B", "E:室友夜谈|N:C语言练习C|C:社团活动", "S:校园商店|L:图书馆", "N:实验预习|EL:期中考试", "R:宿舍休息|C:社团聚会", "B:大一学年综合考核"],
    ["N:专业课作业|N:英语文献", "E:专业分流宣讲|N:课程设计|C:社团换届", "S:教材商店|LAB:实验室", "N:课程设计实践|K:学科竞赛|EL:课程设计中期检查", "R:休息|T:导师|C:社团活动", "N:专业基础阶段作业",
     "N:实验报告|N:课程设计", "E:竞赛报名|N:文献综述|C:社团活动", "S:教材商店|LAB:实验室|L:图书馆", "N:课程设计总结|K:学科竞赛|EL:期中考试", "R:休息|T:导师", "B:大二学年综合评测"],
    ["N:专业课程|N:文献阅读", "E:保研政策宣讲|N:课程作业|I:实习投递", "S:书店|LAB:实验室|L:图书馆", "N:课程作业实践|K:学科竞赛|EL:小组项目冲刺", "R:休息|T:导师|I:招聘会", "N:科研组会|N:课程作业总结|ST:导师项目", "N:阶段成果汇报",
     "N:专业课程|N:文献阅读", "E:秋招宣讲|N:课程作业|I:实习面试", "S:书店|LAB:实验室|L:图书馆", "N:课程作业实践|K:学科竞赛|EL:实习群面", "R:休息|T:导师|I:招聘会", "N:科研组会|N:课程作业总结|EL:保研夏令营", "B:大三学年综合评测"],
    ["N:毕设文献A|N:毕设文献B|N:课程作业", "ST:开题答辩|N:课程实践|E:导师约谈", "S:打印店|LAB:实验室|L:图书馆", "N:课程总结|LAB:实验补测|EL:小组项目冲刺", "T:导师|I:招聘会|R:休息", "ST:中期检查|E:论文投稿|I:实习", "ST:预答辩|N:阶段综合作业|ST:毕业规划",
     "N:毕设文献|N:求职材料|N:考研真题", "E:查重说明|N:课程作业|ST:延期咨询", "S:打印店|LAB:实验室|L:图书馆", "N:毕业课程实践|K:学科竞赛|EL:补考", "T:导师|I:招聘会|R:休息", "ST:盲审查重|E:毕业旅行|I:实习", "B:毕业去向终局"],
]


def maps():
    result = []
    for year, layers in enumerate(RAW, 1):
        nodes = []
        for layer, row in enumerate(layers, 1):
            for slot, item in enumerate(row.split("|")):
                subtype, title = item.split(":")
                nodes.append(dict(key=f"y{year}l{layer}s{slot}", year=year, layer=layer, subtype=subtype,
                                  title=title, kind=KIND.get(subtype, "rest"), next=[]))
        for node in nodes:
            targets = [n for n in nodes if n["layer"] == node["layer"] + 1]
            sub, layer = node["subtype"], node["layer"]
            # Risk chains from the source design; all edges remain adjacent-layer edges.
            if year >= 2 and sub == "LAB" and layer in ([3, 9] if year == 2 else [3, 10]):
                allowed = ["K", "EL", "LAB"] if not (year == 4 and layer == 10) else ["N", "EL"]
                targets = [n for n in targets if n["subtype"] in allowed]
            if sub == "L" and year >= 2:
                allowed = ["N", "EL"] if year in [2, 4] and layer != 10 else ["N"]
                targets = [n for n in targets if n["subtype"] in allowed]
            if year >= 2 and layer in ([4, 10] if year == 2 else [4, 11]):
                targets = [n for n in targets if n["subtype"] in [("R" if sub == "N" else "T"), "C", "I"]]
            if year == 4 and layer == 2 and sub == "ST":
                targets = [n for n in targets if n["subtype"] in ["LAB", "L"]]
            if year == 4 and layer == 6:
                targets = [n for n in targets if n["subtype"] == ("ST" if sub == "ST" else "N")]
            node["next"] = [n["key"] for n in targets]
        assert len(nodes) == [20, 28, 36, 40][year - 1]
        reachable = {n["key"] for n in nodes if n["layer"] == 1}
        for node in nodes:
            if node["key"] in reachable:
                reachable.update(node["next"])
            assert node["next"] or node["subtype"] == "B", node["key"]
        assert reachable == {n["key"] for n in nodes}, f"Unreachable nodes in year {year}"
        result.append(dict(year=year, title=["适应与基础", "分流与专业", "冲刺与选择", "收束与毕业"][year - 1],
                           layers=len(layers), relic_layers=[3, 9] if year < 3 else [4, 11], nodes=nodes))
    return result


def main():
    src, dst = ROOT / "data/v3", ROOT / "data/four_year"
    definitions = {p.stem: json.loads(p.read_text(encoding="utf-8-sig")) for p in (src / "definitions").glob("*.json")}
    manifest = json.loads((src / "manifests/campus_v3.json").read_text(encoding="utf-8-sig"))
    manifest.update(id="campus_four_year", content_version="campus_four_year.v1")
    manifest["enabled"]["encounter"] = [x for x in manifest["enabled"]["encounter"] if not x.startswith("R3-AC")]
    manifest["enabled"]["task"] = [x for x in manifest["enabled"]["task"] if not x.startswith("R3-AC")]
    definitions["encounters"] = [x for x in definitions["encounters"] if not x["id"].startswith("R3-AC")]
    definitions["tasks"] = [x for x in definitions["tasks"] if not x["id"].startswith("R3-AC")]
    for group in ["encounters", "events"]:
        for d in definitions[group]:
            d["terms"] = sorted(set((t + 1) // 2 for t in d["terms"]))
    for event in definitions["events"]:
        for option in event["options"]:
            option["effects"] = [dict(op="gain_money", amount=20) if e["op"] == "gain_relic" else e for e in option["effects"]]
    base = next(x for x in definitions["encounters"] if x["id"] == "B01")
    base_task = next(x for x in definitions["tasks"] if x["id"] == "B01")
    # Explicit prototype profiles using existing phase/pressure mechanics, no new operations.
    for year in range(1, 5):
        d = copy.deepcopy(base)
        d.update(id=f"FY_B{year}", name_key=["大一学年综合考核", "大二学年综合评测", "大三学年综合评测", "毕业答辩"][year - 1], terms=[year])
        task = copy.deepcopy(base_task)
        task.update(id=f"FY_B{year}_TASK", name_key=d["name_key"])
        names = [["基础练习", "实验综合", "独立论证"], ["概念理解", "课程实践", "综合应用"], ["成果整理", "项目评审", "路线答辩"], ["材料复核", "答辩陈述", "综合问答"]][year - 1]
        for index, phase in enumerate(task["phases"]):
            phase["name_key"] = names[index]
            phase["work_max"] += 5 * (year - 1)
            for intent in phase["intents"]:
                for key in ["pressure", "shield"]:
                    if key in intent:
                        intent[key] += year - 1
                        intent["text_key"] = ("评审催促" if key == "pressure" else "补充材料") + str(intent[key])
        definitions["tasks"].append(task)
        manifest["enabled"]["task"].append(task["id"])
        d["members"] = [task["id"]]
        if "initial_members" in d:
            d["initial_members"] = [task["id"]]
        definitions["encounters"].append(d)
        manifest["enabled"]["encounter"].append(d["id"])
    for name, title in [("job", "秋招终面"), ("exam", "考研复试"), ("research", "保研答辩"), ("abroad", "留学面试"), ("deferred", "延期答辩")]:
        d = copy.deepcopy(base)
        d.update(id="FY_FINAL_" + name, name_key=title, terms=[4])
        d["members"] = ["FY_B4_TASK"]
        if "initial_members" in d:
            d["initial_members"] = ["FY_B4_TASK"]
        d["base_ddl"] = int(base["base_ddl"]) + (3 if name == "deferred" else 0)
        definitions["encounters"].append(d)
        manifest["enabled"]["encounter"].append(d["id"])
    relics = []
    themes = [
        [("校园导览册", "event_money", 5), ("食堂饭卡", "rest_heal", 3), ("旧书签", "service_discount", 5), ("社团徽章", "service_money", 5)],
        [("实验室门卡", "service_discount", 8), ("竞赛纪念章", "elite_money", 8), ("工程笔记本", "battle_money", 4), ("专业书签", "rest_heal", 4)],
        [("实习工牌", "service_money", 10), ("推荐信封", "event_money", 8), ("科研笔记", "elite_money", 12), ("通勤卡", "battle_money", 6)],
        [("答辩纪念笔", "service_discount", 10), ("毕业合影", "rest_heal", 6), ("远行车票", "service_money", 12), ("学位纪念章", "battle_money", 8)],
    ]
    for year, items in enumerate(themes, 1):
        for index, (name, effect, amount) in enumerate(items, 1):
            relics.append(dict(id=f"FY_Y{year}_{index}", name_key=name, availability="drop", rarity=["white", "blue", "purple", "gold"][index - 1], tags=["four_year"],
                               campaign=dict(year=year, effect=effect, amount=amount)))
    definitions["relics"] = relics
    labels_path = ROOT / "src/ui/ui_labels.json"
    labels = json.loads(labels_path.read_text(encoding="utf-8-sig"))
    labels["labels"].update({r["id"]: r["name_key"] for r in relics})
    labels["labels"].update({d["id"]: d["name_key"] for d in definitions["encounters"] if d["id"].startswith("FY_")})
    labels["labels"].update({d["id"]: d["name_key"] for d in definitions["tasks"] if d["id"].startswith("FY_")})
    labels["labels"].update(campus_four_year="四学年冒险", campus_v3="v3 历史切片", campus_mvp="v1 历史切片")
    write(labels_path, labels)
    manifest["enabled"]["relic"] = [x["id"] for x in relics]
    for c in definitions["characters"]:
        c["starter_relic_id"] = relics[0]["id"]  # Schema reference only: campaign has no starter relic.
    rules = definitions["rulesets"][0]
    rules["run"].update(term_count=4, relic_slots=3)
    rules["rewards"]["normal_money_by_term"] = [15, 20, 25, 30]
    rules["shop"]["relic_stock"] = dict(white=0, blue=0)
    rules["shop"].update(card_prices=dict(white=35, blue=55, purple=85))
    for name, value in definitions.items():
        write(dst / "definitions" / (name + ".json"), value)
    write(dst / "manifests/campus_four_year.json", manifest)
    schedule = maps()
    # Code constant is validated together with the run's full frozen topology.
    (ROOT / "src/run/campaign_map.gd").write_text(
        'class_name CampaignMap\nextends RefCounted\n\nconst MAPS = ' + json.dumps(schedule, ensure_ascii=False, indent="\t") + '''

static func build(run_id: String) -> Array[RunNodeState]:
	var result: Array[RunNodeState] = []
	for map in MAPS:
		for item in map.nodes:
			var next_ids: Array[String] = []
			for key in item.next:
				next_ids.append(run_id + "|" + key)
			result.append(RunNodeState.create({"node_id": run_id + "|" + item.key,
				"term": map.year, "layer": item.layer, "kind": item.kind, "next_ids": next_ids}))
	return result

static func metadata(node_id: String) -> Dictionary:
	var key := node_id.get_slice("|", 1)
	for map in MAPS:
		for item in map.nodes:
			if item.key == key:
				return item.duplicate(true)
	return {}
''', encoding="utf-8")
    doc = ROOT / "docs/四大地图复杂化设计方案.md"
    text = '''# 四大地图复杂化设计方案

版本：v1.0｜日期：2026-11-04｜状态：四学年实现基线；试玩数值，未代表 G0/G8 验收。

用户已明确：**不分学期，学年作为基础单位，只需要四张图**。本版完整替代八学期候选；旧稿已清理，追溯见[清理记录](执行记录核对与旧版清理_20261104.md)。实现授权与未豁免出口见[根计划 §0.6](../实施计划与验收基线.md)，工程与命令见[实现设计](plans/2026-11-04-four-year-design.md)。

## 1. 四年连续流程

| 学年 | 主题 | 层数/路线长度 | 候选节点 | 饰品触发层（完成后） | 终点 |
|---|---|---:|---:|---|---|
| 大一 | 适应与基础 | 12 | 20 | 3、9 | 学年综合考核 |
| 大二 | 分流与专业 | 12 | 28 | 3、9 | 学年综合评测 |
| 大三 | 冲刺与选择 | 14 | 36 | 4、11 | 学年综合评测 |
| 大四 | 收束与毕业 | 14 | 40 | 4、11 | 去向终局/延期答辩 |

共 124 个候选节点；每条完整路线 52 层。每层选一站、仅沿相邻层的边前进，不回退、不跳层。原区段中途终点改为阶段作业或服务，无学期转换、学期领奖、假期小图或学期末回血。每学年只有末层一个 Boss 槽位，大四根据去向切换定义。牌组、金钱、精力和饰品跨年继承，跨年无额外自动恢复，恢复来自休息/服务/大奖励。

每学年两次饰品奖励，共八次；每学年 Boss 后一次大奖励，共四次。奖励不占节点或层，必须领取、折算或放弃后才能推进。详见[奖励契约](饰品奖励与学期结束大奖励设计_v0.md)；该文件名保留兼容链接，正文统一为学年。

## 2. 节点与限定边

N 普通战斗；E 事件；S 商店；EL 精英；K 竞赛（精英战斗）；R 休息；L 图书馆；LAB 实验室；C 社团；T 导师；I 实习/招聘；ST 剧情/毕设服务；B 学年 Boss。

默认连接下一层全部节点；以下各表逐节点列出精确后继。实验室通常只通向竞赛/精英，普通作业通向休息，风险战斗通向导师；同层的社团/实习提供可达的服务支线。每图保留无精英通路、商店/事件/休息；每层最多三候选，所有候选节点均可达。没有隐藏节点，不用随机失败封路。服务在现有 rest codec 上运行，由节点元数据标识具体语义，画面显示真实服务名称。

'''
    for m in schedule:
        text += f'## {m["year"] + 2}. 大{["一", "二", "三", "四"][m["year"]-1]}：{m["title"]}\n\n| 节点 | 层 | 类型与名称 | 后继 |\n|---|---:|---|---|\n'
        for n in m["nodes"]:
            text += f'| {n["key"]} | {n["layer"]} | {n["subtype"]} {n["title"]} | {"、".join(n["next"]) or "学年大奖励"} |\n'
        text += '\n'
    text += '''## 7. 学年机制与试玩参数

- 大一探索 0–6：首次访问一种可见节点类型 +1。探索进度在地图可见；4 点在事件后的地图服务可选择“校园熟人”（获得 10 金钱），6 点学年大奖励经济选项额外 20 金钱。无战斗数值加成。
- 大二开图选择理论/工程/竞赛/实践。理论图书馆服务减 10；工程实验室服务减 10；竞赛精英额外 10 金钱；实践社团/实习额外 10 金钱。可在该年后半程节点服务中花 30 改一次方向。方向不锁卡池。
- 大三履历 0–6：完成实习、竞赛、导师、科研组会或导师项目 +1，每节点一次。2 点服务费用减 5；4 点精英奖励候选由 3 增为 4；6 点进入大四获得 30 金钱。未刷满仍可通关。
- 大四开图选择就业/考研/保研/出国。开题、实验、中期、导师、预答辩、盲审推进毕设，0–5 封顶。小于 2 进入延期答辩（DDL +3）；2–3 为去向终局；4–5 学年大奖励经济选项额外 20 金钱。四年 Boss 复用既有三阶段机制，各年拥有独立任务、阶段名称；以 B01 的20/25/25完成量为基数，每年各阶段增加5，压力/护盾意图每年增加1。去向终局共享大四阶段模板，延期增加3 DDL。数值为试玩配置，去向专属战斗机制与平衡仍待后续实测。

服务一次一选：图书馆/导师升级或移除（基础费用 20/10）；实验室花 15 金钱与 5 精力升级，不能支付至零；社团回复 8 精力或获得 15 金钱；实习/招聘获得 25 金钱；剧情推进毕设并回复 4 精力；所有服务可跳过。空升级池时仍有移除/跳过，低资源有合法退路。费用可由方向、履历、饰品减免，最低为零。

## 8. 实现与验收边界

独立入口 campus_four_year 默认供四年模式使用；campus_v3 与 campus_mvp 保留历史切片。内部 term 字段仅为存档兼容，在四年模式表示学年 1–4，所有可见文案使用学年。

节点图由 tools/build_four_year_content.py 与本文精确表共同生成，改图时重新生成并运行拓扑、整条路径、冻结奖励/读档、幂等及旧版回归。图片提示词不等于图片落盘；占位音效不等于正式音乐完成。具体完成状态、真实测试命令和剩余工作以本轮实现记录为准。
'''
    doc.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
