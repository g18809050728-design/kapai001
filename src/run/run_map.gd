class_name RunMap
extends RefCounted

const LAYERS := [["normal"], ["event", "normal"], ["shop"], ["normal", "elite"], ["rest"], ["boss"]]


static func build(run_id: String, term_count: int) -> Array[RunNodeState]:
	var nodes: Array[RunNodeState] = []
	for term in range(1, term_count + 1):
		for index in range(LAYERS.size()):
			for kind in LAYERS[index]:
				var next_ids: Array[String] = []
				if index + 1 < LAYERS.size():
					for next_kind in LAYERS[index + 1]:
						next_ids.append(_node_id(run_id, term, index + 2, next_kind))
				(
					nodes
					. append(
						(
							RunNodeState
							. create(
								{
									"node_id": _node_id(run_id, term, index + 1, kind),
									"term": term,
									"layer": index + 1,
									"kind": kind,
									"next_ids": next_ids,
								}
							)
						)
					)
				)
	return nodes


static func _node_id(run_id: String, term: int, layer: int, kind: String) -> String:
	return "%s|t%dl%d_%s" % [run_id, term, layer, kind]
