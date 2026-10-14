class_name RunMap
extends RefCounted
##
## 一学期地图模板（《统一设计文档》§10「八学期地图与局内成长」）。
##
## 每学期 6 层、实际经过 6 个节点；第 2、4 层是二选一分支，因此每学期生成 8 个 NodeState：
##   第 1 层 普通作业      1 个
##   第 2 层 事件/作业分支 2 个（事件、普通）
##   第 3 层 商店          1 个
##   第 4 层 普通/精英分支 2 个（普通、精英）—— 保证一条不打精英的通路
##   第 5 层 休息          1 个
##   第 6 层 首领          1 个
## 相邻层全连接（最多 2×2 条边），只向前、不回退；同一学期内同一层同一类型只会有一个节点，
## 所以节点 ID 由 run_id + 学期 + 层 + 类型唯一确定，可以按 ID 查询。
##
## 骨架生成不消费任何随机流（同种子得到同一张地图）；map 流只在进入节点抽遭遇/事件时推进。
##

const RunCopy := preload("res://src/run/run_copy.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")

const LAYER_TEMPLATE: Array = [
	{"layer": 1, "kinds": [RunNodeState.KIND_NORMAL]},
	{"layer": 2, "kinds": [RunNodeState.KIND_EVENT, RunNodeState.KIND_NORMAL]},
	{"layer": 3, "kinds": [RunNodeState.KIND_SHOP]},
	{"layer": 4, "kinds": [RunNodeState.KIND_NORMAL, RunNodeState.KIND_ELITE]},
	{"layer": 5, "kinds": [RunNodeState.KIND_REST]},
	{"layer": 6, "kinds": [RunNodeState.KIND_BOSS]},
]


## 层数（= 每学期实际经过的节点数，也就是 rulesets.run.nodes_per_term）。
static func layer_count() -> int:
	return LAYER_TEMPLATE.size()


static func node_id_of(run_id: String, term: int, layer: int, kind: String) -> String:
	return "%s|t%dl%d_%s" % [run_id, term, layer, kind]


## 生成整局地图骨架（term_count 个学期）。确定性、不消费随机。
static func build(run_id: String, term_count: int) -> Array:
	var nodes := []
	for term in range(1, term_count + 1):
		var term_nodes := []
		for entry in LAYER_TEMPLATE:
			var layer := int(entry["layer"])
			for raw_kind in (entry["kinds"] as Array):
				var kind := String(raw_kind)
				term_nodes.append(RunNodeState.create(node_id_of(run_id, term, layer, kind), term, layer, kind))
		for raw_node in term_nodes:
			var node: RunNodeState = raw_node
			node.next_ids = _next_ids(term_nodes, node)
		nodes.append_array(term_nodes)
	return nodes


## 相邻层全连接；next_ids 保持模板顺序（普通在前、精英在后），UI 直接按此顺序展示。
static func _next_ids(term_nodes: Array, from: RunNodeState) -> Array:
	var ids := []
	for raw_node in term_nodes:
		var candidate: RunNodeState = raw_node
		if candidate.layer == from.layer + 1:
			ids.append(candidate.node_id)
	return ids


static func find(nodes: Array, node_id: String) -> RunNodeState:
	for raw_node in nodes:
		var node: RunNodeState = raw_node
		if node.node_id == node_id:
			return node
	return null


static func of_term(nodes: Array, term: int) -> Array:
	var matched := []
	for raw_node in nodes:
		var node: RunNodeState = raw_node
		if node.term == term:
			matched.append(node)
	return matched


## 学期入口：第 1 层节点 ID（模板顺序）。
static func first_layer_ids(nodes: Array, term: int) -> Array:
	var ids := []
	for raw_node in nodes:
		var node: RunNodeState = raw_node
		if node.term == term and node.layer == 1:
			ids.append(node.node_id)
	return ids