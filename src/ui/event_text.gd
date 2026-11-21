class_name EventText
extends RefCounted

## Shared default event option names. Kept outside page_flow so the text
## library can show the same fallback text the game actually uses.

const OPTION_NAMES := {
	"return_home": "回家看看",
	"travel": "出去旅行",
	"play_games": "打会儿游戏",
	"leave": "暂时离开",
	"consult": "向学长请教",
	"drop": "放下一点基础负担",
	"rest": "好好休息",
	"upgrade_work": "认真复习",
	"return_card": "归还校园卡",
	"service_desk": "前往服务台",
}


static func option_name(option_id: String, label_key: String = "") -> String:
	if OPTION_NAMES.has(option_id):
		return str(OPTION_NAMES[option_id])
	if not label_key.is_empty():
		return UiStyle.label(label_key)
	return UiStyle.label(option_id)
