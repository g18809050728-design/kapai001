class_name BattleStyle
extends RefCounted
##
## 界面配色与控件外观工厂（src/ui/battle 专用，纯展示）。
##
## 约定：全部由代码生成 StyleBoxFlat，不引入 .tres 主题资源——
## 无头测试与正式运行共用同一套外观，少一个可失效的资源依赖。
## 本文件不读取任何规则状态。
##

const GameConstants := preload("res://src/common/game_constants.gd")

const BG := Color("#11141a")
const PANEL := Color("#1a1f28")
const PANEL_HI := Color("#222836")
const BORDER := Color("#333c4b")
const TEXT := Color("#e7ecf3")
const TEXT_DIM := Color("#94a1b2")
const ACCENT := Color("#4f8cff")
const COST := Color("#46b7ff")
const WORK_COLOR := Color("#ffb454")
const STRATEGY_COLOR := Color("#7fd1c1")
const ABILITY_COLOR := Color("#b47cff")
const COOPERATION_COLOR := Color("#f78fb3")
const SCENE_COLOR := Color("#a3e635")
const DANGER := Color("#ff6259")
const OK := Color("#4fd97a")
const WARN := Color("#ffd166")
const SHIELD := Color("#69b7ff")

const FONT_H1 := 22
const FONT_H2 := 17
const FONT_BODY := 14
const FONT_SMALL := 12


static func flat(fill: Color, border_color: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: int = 6) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.set_corner_radius_all(radius)
    if border_width > 0:
        box.border_color = border_color
        box.set_border_width_all(border_width)
    box.content_margin_left = 10.0
    box.content_margin_right = 10.0
    box.content_margin_top = 8.0
    box.content_margin_bottom = 8.0
    return box


static func panel_box() -> StyleBoxFlat:
    return flat(PANEL, BORDER, 1, 8)


static func card_box(fill: Color, border_color: Color, border_width: int = 2) -> StyleBoxFlat:
    return flat(fill, border_color, border_width, 10)


static func card_type_color(card_type: String) -> Color:
    match card_type:
        GameConstants.CARD_WORK:
            return WORK_COLOR
        GameConstants.CARD_STRATEGY:
            return STRATEGY_COLOR
        GameConstants.CARD_ABILITY:
            return ABILITY_COLOR
        GameConstants.CARD_COOPERATION:
            return COOPERATION_COLOR
        GameConstants.CARD_SCENE:
            return SCENE_COLOR
    return TEXT_DIM


static func rarity_color(rarity: String) -> Color:
    match rarity:
        "white":
            return Color("#d5dae2")
        "blue":
            return Color("#63a4ff")
        "purple":
            return Color("#b47cff")
        "gold":
            return Color("#ffc94d")
    return BORDER


static func title(text: String, size: int = FONT_H2, color: Color = TEXT) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    return label


static func body_label(text: String, color: Color = TEXT, size: int = FONT_BODY) -> Label:
    var label := Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    return label


static func button(text: String, tone: Color = ACCENT) -> Button:
    var node := Button.new()
    node.text = text
    node.add_theme_font_size_override("font_size", FONT_BODY)
    node.add_theme_color_override("font_color", TEXT)
    node.add_theme_stylebox_override("normal", flat(tone.darkened(0.55), tone.darkened(0.2), 1, 6))
    node.add_theme_stylebox_override("hover", flat(tone.darkened(0.4), tone, 1, 6))
    node.add_theme_stylebox_override("pressed", flat(tone.darkened(0.7), tone, 2, 6))
    node.add_theme_stylebox_override("disabled", flat(Color("#1d222b"), BORDER, 1, 6))
    node.add_theme_color_override("font_disabled_color", TEXT_DIM)
    return node


static func panel() -> PanelContainer:
    var node := PanelContainer.new()
    node.add_theme_stylebox_override("panel", panel_box())
    return node


static func spacer(min_size: Vector2, horizontal: bool = true) -> Control:
    var node := Control.new()
    node.custom_minimum_size = min_size
    if horizontal:
        node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    else:
        node.size_flags_vertical = Control.SIZE_EXPAND_FILL
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func hline() -> HSeparator:
    var node := HSeparator.new()
    node.add_theme_color_override("separator", BORDER)
    return node


static func progress(value: int, maximum: int, tone: Color) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.min_value = 0
    bar.max_value = maxi(1, maximum)
    bar.value = clampi(value, 0, maxi(1, maximum))
    bar.show_percentage = false
    bar.custom_minimum_size = Vector2(0, 10)
    var fill := StyleBoxFlat.new()
    fill.bg_color = tone
    fill.set_corner_radius_all(5)
    var back := StyleBoxFlat.new()
    back.bg_color = Color("#2a313d")
    back.set_corner_radius_all(5)
    bar.add_theme_stylebox_override("fill", fill)
    bar.add_theme_stylebox_override("background", back)
    return bar


static func chip(text: String, tone: Color) -> PanelContainer:
    var box := panel()
    box.add_theme_stylebox_override("panel", flat(tone.darkened(0.6), tone.darkened(0.1), 1, 10))
    var label := body_label(text, TEXT, FONT_SMALL)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(label)
    return box


static func ignore_mouse(node: Control) -> void:
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for child in node.get_children():
        if child is Control:
            ignore_mouse(child)
