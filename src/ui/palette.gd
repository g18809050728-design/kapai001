extends RefCounted
## 「遗迹 · 自然」配色与美术资源路径。
##
## 美术方向：暖色石灰岩 + 羊皮纸 + 土性颜料色。
## 与旧版（深蓝黑背景 + 高饱和霓虹色 + 大量硬边框面板）相比，这一版：
##   · 背景与面板改用暖灰褐，明度层级靠「同一色系的 4 级明度」拉开，而不是靠色相
##   · 卡牌改为羊皮纸卡面 + 颜料色卡头，正文用墨色，接近真实的纸质卡牌
##   · 氛围交给环境图与光影（火把暖光、暗角），减少硬矩形面板

const T = preload("res://src/core/battle_types.gd")

# ── 界面底色：暖石灰岩，4 级明度 ──────────────────────────
const BG_DEEP := Color("#171310")
const BG_STONE := Color("#2a231c")
const BG_FLOOR := Color("#241e18")
const PANEL := Color("#332a22")
const PANEL_HI := Color("#40352a")
const BORDER := Color("#57493b")
const BORDER_HI := Color("#7d6a53")

# ── 文字 ─────────────────────────────────────────────────
const TEXT := Color("#ece3d4")
const TEXT_DIM := Color("#a79883")
## 羊皮纸卡面上的墨色文字
const TEXT_INK := Color("#3b3024")
const TEXT_INK_DIM := Color("#6b5b45")

# ── 强调与状态 ───────────────────────────────────────────
const GOLD := Color("#d9a441")
const SELECT := Color("#f2dc9e")
const HP := Color("#b0432f")
const HP_BG := Color("#3a2620")
const SHIELD := Color("#6f8fa8")
const ENERGY := Color("#e0a94a")
const GOOD := Color("#7a9a5a")
const WARN := Color("#c98a4b")
const TAUNT := Color("#c9924a")

# ── 羊皮纸卡面 ───────────────────────────────────────────
const PAPER := Color("#e9dcc3")
const PAPER_EDGE := Color("#c9b691")

# ── 土性颜料色：卡牌类型 ─────────────────────────────────
const CARD_COLORS := {
	T.CardType.ATTACK: Color("#a8442f"),
	T.CardType.DEFENSE: Color("#4a6f8f"),
	T.CardType.SKILL: Color("#7a5a8f"),
	T.CardType.SCENE: Color("#b08a3c"),
	T.CardType.MINION: Color("#5f8a5a"),
}

# ── 美术资源（由 tools/make_art_assets.py 生成）────────────
const ART_BG := "res://assets/art/bg_ruins.png"
const ART_VIGNETTE := "res://assets/art/vignette.png"
const ART_ADVENTURER := "res://assets/art/char_adventurer.png"
const ART_GOLEM := "res://assets/art/char_golem.png"


static func card_color(ctype: int) -> Color:
	return CARD_COLORS.get(ctype, PANEL)


## 基础样式盒：柔和投影 + 细描边。用光影表达层级，而不是靠粗边框。
static func box(bg: Color, radius: int = 10, border_w: int = 1,
		border_c: Color = BORDER, shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_c
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.38)
		sb.shadow_size = 7
		sb.shadow_offset = Vector2(0, 3)
	return sb


## 半透明石材面板：让背景的火光与石纹透出来，画面才有空气感。
static func panel_box(hi: bool = false, radius: int = 10) -> StyleBoxFlat:
	var c := PANEL_HI if hi else PANEL
	c.a = 0.84
	return box(c, radius, 1, BORDER_HI if hi else BORDER)


## 羊皮纸卡面：外部用类型色描边，内部是纸色。
static func paper_box(type_color: Color, radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var sb := box(PAPER, radius, border_w, type_color)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
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
