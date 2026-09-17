extends RefCounted
## 界面配色。对应规格 §4.1「视觉方向」：遗迹石室背景低对比，角色与卡牌高对比；
## 攻击红 / 防御蓝 / 技能紫 / 场景金 / 随从绿，并始终配合类型文字。

const T = preload("res://src/core/battle_types.gd")

const BG := Color("#141518")
const BG_FIELD := Color("#1e2027")
const PANEL := Color("#282b36")
const PANEL_HI := Color("#333747")
const BORDER := Color("#4a5065")
const SELECT := Color("#f2d16b")
const TEXT := Color("#e9eaf0")
const TEXT_DIM := Color("#98a0b6")
const HP_COLOR := Color("#c0392b")
const HP_BG := Color("#3a2222")
const SHIELD_COLOR := Color("#3f8fd0")
const ENERGY_COLOR := Color("#e0b23a")
const GOOD := Color("#4caf50")
const WARN := Color("#e08a3c")
const TAUNT := Color("#e0a030")

const CARD_COLORS := {
	T.CardType.ATTACK: Color("#b8342a"),
	T.CardType.DEFENSE: Color("#2b6cb0"),
	T.CardType.SKILL: Color("#7d3cb5"),
	T.CardType.SCENE: Color("#b8912a"),
	T.CardType.MINION: Color("#2e8b57"),
}


static func card_color(ctype: int) -> Color:
	return CARD_COLORS.get(ctype, PANEL)


## 生成一个带圆角/描边的样式盒。
static func box(bg: Color, radius: int = 8, border_w: int = 0, border_c: Color = BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_c
	return sb


## 创建中文可用的系统字体（Godot 内置默认字体不含 CJK 字形）。
static func make_cjk_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "SimHei", "黑体",
		"Noto Sans CJK SC", "PingFang SC", "Hiragino Sans GB",
		"WenQuanYi Micro Hei", "sans-serif",
	])
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f
