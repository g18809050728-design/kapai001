class_name RouteForecast
extends RefCounted

## Counts EXCLUDE selected node; node_ids INCLUDE it. Bounds are per path of at
## most depth next-layer edges in the same term, never a union of alternatives.
## rest = R (or legacy unspecified rest); service = L/LAB/T/C/I/ST opportunities.
## elite includes K; risk = elite/K. No cost, healing or reward is guaranteed.
## If complete=false, bounds describe recorded nodes only, not unknown branches.
const METRICS := ["steps", "shop", "rest", "service", "elite", "competition", "risk", "boss"]


static func describe(nodes: Array, node_id: String, depth: int = 3) -> Dictionary:
	var index := {}
	for value in nodes:
		if value is Dictionary and not str(value.get("node_id", "")).is_empty():
			index[str(value.node_id)] = value
	var empty := {"node_ids": [] as Array[String], "text": "请选择已生成地图中的节点，查看路线预告。", "minimums": _zero(), "maximums": _zero(), "path_count": 0, "forced_risk": false, "complete": true, "layers": []}
	if not index.has(node_id):
		return empty
	var horizon := clampi(depth, 0, index.size())
	var result := _walk(index, node_id, horizon, {})
	var ids: Array[String] = []
	for id in result.node_ids:
		ids.append(str(id))
	ids.sort_custom(func(a: String, b: String):
		var left: Dictionary = index[a]
		var right: Dictionary = index[b]
		if int(left.get("layer", 0)) != int(right.get("layer", 0)):
			return int(left.get("layer", 0)) < int(right.get("layer", 0))
		if int(left.get("column", 3)) != int(right.get("column", 3)):
			return int(left.get("column", 3)) < int(right.get("column", 3))
		return a < b)
	result.node_ids = ids
	result.forced_risk = int(result.minimums.risk) > 0 and bool(result.complete)
	var layers: Array = []
	for offset in range(1, horizon + 1):
		var layer := int(index[node_id].get("layer", 0)) + offset
		var layer_ids: Array[String] = []
		for id in ids:
			if int(index[id].get("layer", 0)) == layer:
				layer_ids.append(id)
		if not layer_ids.is_empty():
			layers.append({"layer": layer, "node_ids": layer_ids})
	result.layers = layers
	if int(result.maximums.steps) == 0:
		result.text = "路线预告 · 此节点没有已记录的后继。" if bool(result.complete) else "路线预告 · 后继记录不完整，暂不作必经保证。"
		return result
	var ranges: Array[String] = []
	for pair in [["shop", "商店"], ["rest", "休息"], ["service", "校园服务"], ["risk", "精英/竞赛"]]:
		var metric: String = pair[0]
		var low := int(result.minimums[metric])
		var high := int(result.maximums[metric])
		ranges.append("%s %s次" % [pair[1], str(low) if low == high else "%d–%d" % [low, high]])
	var risk := "必经风险：每条路线至少遇到%d次精英/竞赛。" % result.minimums.risk if result.forced_risk else ("可能遇到精英/竞赛，也有避开路线。" if int(result.maximums.risk) > 0 else "这段路线没有精英/竞赛；普通战斗仍有风险。")
	if not bool(result.complete):
		risk = "后继记录不完整，无法保证存在避开风险的路线，也无法保证服务机会。"
	result.text = "路线预告 · 向后最多%d层（不含所选节点） · %d种路线可能\n%s%s\n%s 服务为机会，仍需满足费用与条件。" % [horizon, result.path_count, "已记录部分：" if not bool(result.complete) else "", " · ".join(ranges), risk]
	for layer in layers:
		var possibilities: Array[String] = []
		for id in layer.node_ids:
			var label := _label(index[id])
			if not possibilities.has(label):
				possibilities.append(label)
		result.text += "\n第%d层可能：%s" % [layer.layer, " / ".join(possibilities)]
	return result


static func _walk(index: Dictionary, id: String, remaining: int, memo: Dictionary) -> Dictionary:
	var key := "%s:%d" % [id, remaining]
	if memo.has(key):
		return memo[key].duplicate(true)
	var node: Dictionary = index[id]
	var result := {"node_ids": [id], "minimums": _zero(), "maximums": _zero(), "path_count": 1, "complete": true}
	if remaining <= 0:
		return result
	var alternatives: Array = []
	var seen: Array[String] = []
	for edge in node.get("next_ids", []):
		var next_id := str(edge)
		if seen.has(next_id):
			continue
		seen.append(next_id)
		if not index.has(next_id) or int(index[next_id].get("term", node.get("term", 1))) != int(node.get("term", 1)) or int(index[next_id].get("layer", 0)) != int(node.get("layer", 0)) + 1:
			alternatives.append({"node_ids": [], "minimums": _zero(), "maximums": _zero(), "path_count": 1, "complete": false})
			continue
		var branch := _walk(index, next_id, remaining - 1, memo)
		var counts := _counts(index[next_id])
		for metric in METRICS:
			branch.minimums[metric] += counts[metric]
			branch.maximums[metric] += counts[metric]
		alternatives.append(branch)
	if alternatives.is_empty():
		return result
	result.path_count = 0
	result.minimums = alternatives[0].minimums.duplicate()
	for branch in alternatives:
		result.path_count += int(branch.path_count)
		result.complete = bool(result.complete) and bool(branch.complete)
		for next_id in branch.node_ids:
			if not result.node_ids.has(next_id):
				result.node_ids.append(next_id)
		for metric in METRICS:
			result.minimums[metric] = mini(int(result.minimums[metric]), int(branch.minimums[metric]))
			result.maximums[metric] = maxi(int(result.maximums[metric]), int(branch.maximums[metric]))
	memo[key] = result.duplicate(true)
	return result


static func _zero() -> Dictionary:
	var result := {}
	for metric in METRICS:
		result[metric] = 0
	return result


static func _label(node: Dictionary) -> String:
	var kinds := {"normal": "普通战斗", "elite": "精英战斗", "boss": "学年首领", "shop": "商店", "rest": "休息", "event": "校园事件"}
	var services := {"L": "图书馆", "LAB": "实验室", "T": "导师", "C": "社团", "I": "实习招聘", "ST": "毕设事项", "K": "竞赛精英"}
	return str(services.get(str(node.get("subtype", "")), kinds.get(str(node.get("kind", "")), "校园节点")))


static func _counts(node: Dictionary) -> Dictionary:
	var result := _zero()
	var kind := str(node.get("kind", ""))
	var subtype := str(node.get("subtype", ""))
	result.steps = 1
	result.shop = int(kind == "shop")
	result.rest = int(kind == "rest" and subtype in ["", "R"])
	result.service = int(subtype in ["L", "LAB", "T", "C", "I", "ST"])
	result.elite = int(kind == "elite" or subtype in ["EL", "K"])
	result.competition = int(subtype == "K")
	result.risk = result.elite
	result.boss = int(kind == "boss")
	return result
