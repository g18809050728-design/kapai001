class_name RunNodeState
extends RefCounted
##
## 地图节点（《数据库与实体关系设计》§5 NodeState；《统一设计文档》§10）。
##
## kind 是地图模板的稳定标识，只有 6 种；context 是受 kind 约束的联合类型（§5）：
##   battle 节点（normal/elite/boss）-> {"encounter_id": String}
##   shop 节点                      -> {"shop": ShopState}
##   event 节点                     -> {"event": EventState}
##   rest 节点                      -> {"used": bool}
## 不允许同时挂商店与事件数据。
##
## status：pending（可达但未进入）-> active（已进入，等待处理）-> completed（已结算）。
##

const RunCopy := preload("res://src/run/run_copy.gd")

const STATUS_PENDING := "pending"
const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"
const STATUS_IDS: Array[String] = [STATUS_PENDING, STATUS_ACTIVE, STATUS_COMPLETED]

const KIND_NORMAL := "normal"
const KIND_EVENT := "event"
const KIND_SHOP := "shop"
const KIND_REST := "rest"
const KIND_ELITE := "elite"
const KIND_BOSS := "boss"
const KIND_IDS: Array[String] = [KIND_NORMAL, KIND_EVENT, KIND_SHOP, KIND_REST, KIND_ELITE, KIND_BOSS]
## 需要开战的节点类型（普通/精英/首领）。
const BATTLE_KINDS: Array[String] = [KIND_NORMAL, KIND_ELITE, KIND_BOSS]

var node_id: String = ""
var term: int = 1
var layer: int = 1
var kind: String = KIND_NORMAL
var status: String = STATUS_PENDING
## 只能指向同学期、更高层的节点（§5「连线目标存在且只能前进」）。
var next_ids: Array = []
var context: Dictionary = {}


static func create(p_node_id: String, p_term: int, p_layer: int, p_kind: String) -> RunNodeState:
	var node: RunNodeState = load("res://src/run/run_node_state.gd").new()
	node.node_id = p_node_id
	node.term = p_term
	node.layer = p_layer
	node.kind = p_kind
	return node


func is_battle() -> bool:
	return BATTLE_KINDS.has(kind)


func is_pending() -> bool:
	return status == STATUS_PENDING


func is_active() -> bool:
	return status == STATUS_ACTIVE


func is_completed() -> bool:
	return status == STATUS_COMPLETED


func mark_active() -> void:
	status = STATUS_ACTIVE


func mark_completed() -> void:
	status = STATUS_COMPLETED


## 开战节点的战斗实例 ID：一个战斗节点只有一场战斗，所以直接用 node_id 作 battle_id；
## settle_battle 的幂等键（RunState.settled_battle_ids）也就是它。
func battle_id() -> String:
	return node_id


func copy_for_write() -> RunNodeState:
	var copied: RunNodeState = create(node_id, term, layer, kind)
	copied.status = status
	copied.next_ids = RunCopy.array(next_ids)
	copied.context = RunCopy.dictionary(context)
	return copied