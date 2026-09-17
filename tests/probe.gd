extends SceneTree
## 语法机制探针：验证 preload 常量 + 跨脚本枚举 + const 字典在 headless 下可用。

const T = preload("res://src/core/battle_types.gd")

const DICT := {
	"a": T.CardType.ATTACK,
	"b": [T.Phase.PLAYER_ACTION, T.Phase.KEEP_SELECT],
	"c": T.MAX_ENERGY,
}

const ALIAS := T.IntentKind.ATTACK

enum Local { X, Y }
const LOCAL_DICT := {Local.X: "x", Local.Y: "y"}


func _initialize() -> void:
	print("enum_access=", T.CardType.ATTACK, " name=", T.CARD_TYPE_NAME[T.CardType.ATTACK])
	print("const_dict=", DICT)
	print("alias=", ALIAS)
	print("local_dict=", LOCAL_DICT)
	var inst = T.new()
	print("preload_new_ok=", inst != null)
	print("PROBE_OK")
	quit(0)
