extends Control
##
## 战斗场景：把规则层返回的有序事件播放成界面表现（规格 §4 布局、§5 交互、§9 结算弹窗）。
##
## 关键约定（§10）：界面不计算伤害、不推进回合，只调用规则层入口并播放事件；
## 动画与节奏完全不影响规则结果，并提供「快速」开关跳过非必要演出（§4.1）。
##

const T = preload("res://src/core/battle_types.gd")
const CardDB = preload("res://src/core/card_db.gd")
const EnemyDB = preload("res://src/core/enemy_db.gd")
const BattleEngine = preload("res://src/core/battle_engine.gd")
const CardView = preload("res://src/ui/card_view.gd")
const MinionView = preload("res://src/ui/minion_view.gd")
const Palette = preload("res://src/ui/palette.gd")

const VIEW := Vector2(1600, 900)
const SLOT_SIZE := Vector2(130, 146)
## 中央场地区。这一版不再铺实心面板（石室背景与角色直接露出），
## 该范围仍用于标注、飘字锚点与后续多敌人站位参考。
const FIELD_RECT := Rect2(336, 66, 928, 542)

var engine = null

# ── 运行期状态 ─────────────────────────────────────────────
var _token: int = 0          # 战斗代号：重开后旧协程据此自行退出
var _busy: bool = false      # 结算期间锁定输入
var _selected: int = -1      # 当前选中的手牌实例
var _keep_mode: bool = false
var _keep_choice: int = -1
var _fast: bool = false
var _restarting: bool = false

# ── 节点引用 ───────────────────────────────────────────────
var _title_label: Label
var _turn_label: Label
var _hint_label: Label
var _end_turn_btn: Button
var _confirm_btn: Button
var _help_btn: Button
var _fast_btn: Button
var _restart_btn: Button

var _player_hp_bar: ProgressBar
var _player_hp_text: Label
var _player_shield_label: Label
var _energy_label: Label
var _energy_pips: Array = []

var _enemy_name_label: Label
var _enemy_hp_bar: ProgressBar
var _enemy_hp_text: Label
var _enemy_shield_label: Label
var _intent_box: PanelContainer
var _intent_label: Label
var _enemy_hit_area: PanelContainer

var _hand_area: Control
var _minion_views: Array = []
var _draw_count: Label
var _discard_count: Label
var _scene_name: Label
var _scene_desc: Label
var _scene_triggers: Label
var _log_scroll: ScrollContainer
var _log_box: VBoxContainer
var _false_btn: Button

var _bg_catcher: Control
var _bg_tex: TextureRect
var _vignette: TextureRect
var _char_player: TextureRect
var _char_enemy: TextureRect
var _float_layer: Control
var _keep_bar: HBoxContainer
var _keep_confirm_btn: Button

var _help_overlay: Control
var _result_overlay: Control
var _result_title: Label
var _result_desc: Label
var _result_stats: Label
var _result_btn: Button
var _deck_overlay: Control
var _deck_title: Label
var _deck_list: VBoxContainer


# ══════════════════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════════════════

func _ready() -> void:
	# 根 Control 若保持默认的 MOUSE_FILTER_STOP，会吃掉空白处的鼠标事件，
	# 导致 _unhandled_input 收不到「点击空白处 / 右键取消」（§5.1）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_theme()
	_build_ui()
	_start_new_battle(_random_seed())


func _apply_theme() -> void:
	# Godot 内置默认字体不含中文字形，必须挂系统 CJK 字体
	var th = Theme.new()
	th.default_font = Palette.make_cjk_font()
	th.default_font_size = 15
	theme = th


func _random_seed() -> int:
	var r = RandomNumberGenerator.new()
	r.randomize()
	return absi(r.randi())


# ══════════════════════════════════════════════════════════
#  界面构建
# ══════════════════════════════════════════════════════════

func _panel(rect: Rect2, bg: Color, radius: int = 10, border: int = 0,
		border_c: Color = Palette.BORDER, alpha: float = 0.84) -> PanelContainer:
	var p = PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.custom_minimum_size = rect.size
	# 不透明色统一降为半透明石材面板：让背景的火光与石纹透出来，画面才有空气感。
	# 已经带透明度的调用（如敌人热区）保持原样。
	var c := bg
	if c.a >= 0.999:
		c.a = alpha
	p.add_theme_stylebox_override("panel", Palette.box(c, radius, border, border_c))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _content(parent: Control, m: int = 12) -> VBoxContainer:
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, m)
	parent.add_child(margin)
	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)
	return col


func _label(text: String, size: int = 15, color: Color = Palette.TEXT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 给按钮套上暖色石材样式。未套样式的按钮会用 Godot 默认灰主题，和整体色调冲突。
func _style_button(b: Button, accent: Color, size: int = 14) -> Button:
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s = Palette.box(accent, 8, 1, accent.lightened(0.30), false)
		if st == "hover":
			s.bg_color = accent.lightened(0.14)
		elif st == "pressed":
			s.bg_color = accent.darkened(0.18)
		elif st == "disabled":
			s.bg_color = accent.darkened(0.60)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM)
	return b


func _button(text: String, rect: Rect2, accent: Color, size: int = 16) -> Button:
	var b = Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.custom_minimum_size = rect.size
	_style_button(b, accent, size)
	return b


func _bar(rect: Rect2, fill: Color) -> ProgressBar:
	var pb = ProgressBar.new()
	pb.position = rect.position
	pb.size = rect.size
	pb.custom_minimum_size = rect.size
	pb.show_percentage = false
	pb.max_value = 100
	pb.value = 100
	pb.add_theme_stylebox_override("background", Palette.box(Palette.HP_BG, 6))
	pb.add_theme_stylebox_override("fill", Palette.box(fill, 6))
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _build_ui() -> void:
	# 空白处点击 catcher：必须最先加入（绘制在最底层、命中优先级最低），
	# 这样卡牌与按钮会先拿到事件，只有点空白处才取消当前选择。
	_bg_catcher = Control.new()
	_bg_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg_catcher.gui_input.connect(_on_background_input)
	add_child(_bg_catcher)

	# ── 绘制顺序（从下到上必须严格是这样）────────────────
	# 1) 石室背景  2) 场景中的角色  3) 暗角  4) 全部 UI 面板  5) 飘字
	# 暗角夹在角色与 UI 之间：让四周沉下去、视线集中在中间，同时不压暗任何 UI。

	_bg_tex = TextureRect.new()
	_bg_tex.texture = load(Palette.ART_BG)
	_bg_tex.position = Vector2.ZERO
	_bg_tex.size = VIEW
	_bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_tex)

	_build_characters()

	_vignette = TextureRect.new()
	_vignette.texture = load(Palette.ART_VIGNETTE)
	_vignette.position = Vector2.ZERO
	_vignette.size = VIEW
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

	_build_top_bar()
	_build_player_panel()
	_build_minion_panel()
	_build_enemy_panel()
	_build_field()
	_build_log_panel()
	_build_bottom()

	# 飘字层放最上（§4.2：伤害与效果飘字）
	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)

	_build_keep_bar()
	_build_help_overlay()
	_build_result_overlay()
	_build_deck_overlay()


func _build_top_bar() -> void:
	_panel(Rect2(0, 0, VIEW.x, 54), Palette.PANEL, 0)
	_title_label = _label(EnemyDB.encounter()["title"], 20)
	_title_label.position = Vector2(20, 14)
	_title_label.size = Vector2(560, 28)
	add_child(_title_label)

	_turn_label = _label("回合 1", 20, Palette.SELECT)
	_turn_label.position = Vector2(600, 14)
	_turn_label.size = Vector2(200, 28)
	add_child(_turn_label)

	_help_btn = _button("玩法说明", Rect2(VIEW.x - 232, 10, 104, 34), Palette.PANEL_HI, 15)
	_help_btn.pressed.connect(_on_help_pressed)
	add_child(_help_btn)

	_fast_btn = _button("快速：关", Rect2(VIEW.x - 120, 10, 104, 34), Palette.PANEL_HI, 15)
	_fast_btn.pressed.connect(_on_fast_toggled)
	add_child(_fast_btn)


func _build_player_panel() -> void:
	var p = _panel(Rect2(20, 66, 300, 336), Palette.PANEL, 10, 1)
	var col = _content(p, 14)
	col.add_child(_label("玩家", 18, Palette.TEXT))

	_player_hp_bar = _bar(Rect2(0, 0, 264, 26), Palette.HP)
	col.add_child(_player_hp_bar)

	_player_hp_text = _label("60 / 60", 15)
	_player_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_player_hp_text)

	_player_shield_label = _label("护盾 0", 14, Palette.SHIELD)
	col.add_child(_player_shield_label)

	_energy_label = _label("能量 0 / 10", 15, Palette.ENERGY)
	col.add_child(_energy_label)

	var pips = HBoxContainer.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_theme_constant_override("separation", 3)
	col.add_child(pips)
	for _i in range(T.MAX_ENERGY):
		var pip = ColorRect.new()
		pip.custom_minimum_size = Vector2(22, 12)
		pip.color = Color(1, 1, 1, 0.12)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
		_energy_pips.append(pip)

	var ph = Label.new()
	ph.text = ""
	ph.add_theme_font_size_override("font_size", 13)
	ph.add_theme_color_override("font_color", Palette.TEXT_DIM)
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ph)


func _build_minion_panel() -> void:
	var p = _panel(Rect2(20, 412, 300, 196), Palette.PANEL, 10, 1)
	var col = _content(p, 12)
	col.add_child(_label("随从区（两个固定槽位）", 15, Palette.TEXT))

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for s in range(T.MINION_SLOTS):
		var mv = MinionView.new()
		mv.slot = s
		mv.custom_minimum_size = SLOT_SIZE
		mv.size = SLOT_SIZE
		row.add_child(mv)
		_minion_views.append(mv)


func _build_enemy_panel() -> void:
	var p = _panel(Rect2(1280, 66, 300, 336), Palette.PANEL, 10, 1)
	var col = _content(p, 14)

	_enemy_name_label = _label("练习魔像", 18)
	col.add_child(_enemy_name_label)

	_enemy_hp_bar = _bar(Rect2(0, 0, 264, 26), Palette.HP)
	col.add_child(_enemy_hp_bar)

	_enemy_hp_text = _label("35 / 35", 15)
	_enemy_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_enemy_hp_text)

	_enemy_shield_label = _label("护盾 0", 14, Palette.SHIELD)
	col.add_child(_enemy_shield_label)

	_intent_box = PanelContainer.new()
	_intent_box.add_theme_stylebox_override("panel", Palette.box(Color("#3a2020"), 8, 1, Color("#ff8a7a")))
	_intent_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_intent_box)
	var im = MarginContainer.new()
	im.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right"]:
		im.add_theme_constant_override("margin_" + s, 10)
	for s in ["top", "bottom"]:
		im.add_theme_constant_override("margin_" + s, 8)
	_intent_box.add_child(im)
	_intent_label = _label("意图：—", 16)
	_intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	im.add_child(_intent_label)

	var tip = _label("点击此处确认对魔像使用单体牌", 12, Palette.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(tip)

	# 可点击的敌人热区（§5.1 步骤 2：即使只有一个敌人也要点击敌人确认）
	_enemy_hit_area = PanelContainer.new()
	_enemy_hit_area.position = Vector2(1280, 250)
	_enemy_hit_area.size = Vector2(300, 152)
	_enemy_hit_area.custom_minimum_size = Vector2(300, 152)
	_enemy_hit_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_enemy_hit_area.add_theme_stylebox_override("panel", Palette.box(Color(1, 1, 1, 0.03), 8, 1, Palette.BORDER))
	_enemy_hit_area.gui_input.connect(_on_enemy_gui_input)
	var fh = Label.new()
	fh.text = "魔像"
	fh.add_theme_font_size_override("font_size", 30)
	fh.add_theme_color_override("font_color", Palette.TEXT_DIM)
	fh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_hit_area.add_child(fh)
	add_child(_enemy_hit_area)


func _build_characters() -> void:
	# 角色站在场景里，而不是被塞进状态面板：这样环境、光影和角色才是一体的。
	# 位置与尺寸必须与 tools/verify_art_assets.py 的 PLACEMENT 保持一致。
	_char_player = TextureRect.new()
	_char_player.texture = load(Palette.ART_ADVENTURER)
	_char_player.position = Vector2(390, 190)
	_char_player.size = Vector2(300, 420)
	_char_player.stretch_mode = TextureRect.STRETCH_SCALE
	_char_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_char_player)

	_char_enemy = TextureRect.new()
	_char_enemy.texture = load(Palette.ART_GOLEM)
	_char_enemy.position = Vector2(890, 170)
	_char_enemy.size = Vector2(340, 440)
	_char_enemy.stretch_mode = TextureRect.STRETCH_SCALE
	_char_enemy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_char_enemy)


func _build_field() -> void:
	# 中央场地不再铺实心面板 —— 直接露出石室背景，角色站在其中。
	# 只保留场景牌区与图例这两块必要的信息载体。

	# 场景牌展示区（§4.2 中央场地区）
	var sp = _panel(Rect2(500, 82, 600, 104), Palette.PANEL, 10, 1, Palette.GOLD)
	var col = _content(sp, 10)
	_scene_name = _label("无场景牌", 16, Palette.SELECT)
	col.add_child(_scene_name)
	_scene_desc = _label("", 13, Palette.TEXT_DIM)
	_scene_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_scene_desc)
	_scene_triggers = _label("", 13, Palette.TEXT)
	col.add_child(_scene_triggers)

	var legend = _label(
		"卡牌类型：攻击·赭红   防御·石青   技能·紫藤   场景·金褐   随从·苔绿（同时显示类型文字）",
		13, Palette.TEXT_DIM)
	legend.position = Vector2(352, 588)
	legend.size = Vector2(900, 20)
	add_child(legend)


func _build_log_panel() -> void:
	var p = _panel(Rect2(1280, 412, 300, 196), Palette.PANEL, 10, 1)
	var col = _content(p, 10)
	var head = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var t = _label("结算日志", 15)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var fold = Button.new()
	fold.text = "折叠"
	fold.add_theme_font_size_override("font_size", 12)
	fold.custom_minimum_size = Vector2(56, 24)
	fold.pressed.connect(_on_log_fold)
	_style_button(fold, Palette.PANEL_HI, 12)
	head.add_child(fold)

	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_log_scroll)

	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_box)


func _build_bottom() -> void:
	# 左下角牌堆区（§4.2）
	var p = _panel(Rect2(20, 620, 160, 262), Palette.PANEL, 10, 1)
	var col = _content(p, 10)
	var draw_btn = _button("抽牌堆", Rect2(0, 0, 140, 40), Palette.PANEL_HI, 14)
	draw_btn.pressed.connect(_open_deck.bind("draw"))
	col.add_child(draw_btn)
	_draw_count = _label("15 张", 14, Palette.TEXT_DIM)
	col.add_child(_draw_count)
	var dis_btn = _button("弃牌堆", Rect2(0, 0, 140, 40), Palette.PANEL_HI, 14)
	dis_btn.pressed.connect(_open_deck.bind("discard"))
	col.add_child(dis_btn)
	_discard_count = _label("0 张", 14, Palette.TEXT_DIM)
	col.add_child(_discard_count)

	# 手牌区（§4.2）
	_hand_area = Control.new()
	_hand_area.position = Vector2(196, 620)
	_hand_area.size = Vector2(1188, 262)
	_hand_area.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_hand_area)

	# 右下角控制区（§4.2）
	var cp = _panel(Rect2(1400, 620, 180, 262), Palette.PANEL, 10, 1)
	var ccol = _content(cp, 10)
	_hint_label = _label("", 13, Palette.TEXT_DIM)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ccol.add_child(_hint_label)

	_confirm_btn = _button("确认使用", Rect2(0, 0, 158, 44), Color("#3b5a86"), 16)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	ccol.add_child(_confirm_btn)
	_confirm_btn.visible = false
	_end_turn_btn = _button("结束回合", Rect2(0, 0, 158, 56), Color("#3d6b46"), 18)
	_end_turn_btn.pressed.connect(_on_end_turn_pressed)
	ccol.add_child(_end_turn_btn)

	_restart_btn = _button("重开本局", Rect2(0, 0, 158, 34), Palette.PANEL_HI, 14)
	_restart_btn.pressed.connect(_on_restart_pressed)
	ccol.add_child(_restart_btn)


func _build_keep_bar() -> void:
	_keep_bar = HBoxContainer.new()
	_keep_bar.position = Vector2(500, 566)
	_keep_bar.size = Vector2(600, 40)
	_keep_bar.custom_minimum_size = Vector2(600, 40)
	_keep_bar.add_theme_constant_override("separation", 10)
	_keep_bar.visible = false
	add_child(_keep_bar)

	var lab = Label.new()
	lab.text = "保留一张牌，其余进入弃牌堆："
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Palette.SELECT)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_keep_bar.add_child(lab)

	_keep_confirm_btn = Button.new()
	_keep_confirm_btn.text = "保留并结束"
	_keep_confirm_btn.custom_minimum_size = Vector2(120, 36)
	_keep_confirm_btn.add_theme_font_size_override("font_size", 14)
	_keep_confirm_btn.pressed.connect(_on_keep_confirm)
	_style_button(_keep_confirm_btn, Palette.GOOD.darkened(0.35), 14)
	_keep_bar.add_child(_keep_confirm_btn)

	var nb = Button.new()
	nb.text = "不保留"
	nb.custom_minimum_size = Vector2(88, 36)
	nb.add_theme_font_size_override("font_size", 14)
	nb.pressed.connect(_on_keep_none)
	_style_button(nb, Palette.PANEL_HI, 14)
	_keep_bar.add_child(nb)

	var cb = Button.new()
	cb.text = "取消"
	cb.custom_minimum_size = Vector2(72, 36)
	cb.add_theme_font_size_override("font_size", 14)
	cb.pressed.connect(_on_keep_cancel)
	_style_button(cb, Palette.PANEL_HI, 14)
	_keep_bar.add_child(cb)


func _make_overlay() -> Dictionary:
	var ov = Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP   # 阻止背景操作
	ov.visible = false
	add_child(ov)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(dim)
	return {"overlay": ov}


func _centered_panel(ov: Control, w: float, h: float) -> PanelContainer:
	var p = PanelContainer.new()
	p.position = Vector2((VIEW.x - w) * 0.5, (VIEW.y - h) * 0.5)
	p.size = Vector2(w, h)
	p.custom_minimum_size = Vector2(w, h)
	p.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_HI, 12, 2, Palette.BORDER))
	ov.add_child(p)
	return p


func _build_help_overlay() -> void:
	var o = _make_overlay()
	_help_overlay = o["overlay"]
	var p = _centered_panel(_help_overlay, 760, 540)
	var col = _content(p, 20)
	col.add_child(_label("玩法说明", 22, Palette.SELECT))

	var text = """【抽牌】每个玩家回合开始时抽 5 张牌。保留的牌不会减少抽牌数量。手牌上限 10 张，超出的牌仍从牌库移出后进入弃牌堆。牌库不足时会把弃牌堆洗入牌库继续抽取。

【免费牌】普通攻击牌和防御牌费用为 0，可以任意张数连续使用，没有行动点，也没有每回合出牌次数上限。技能牌需要消耗能量。

【能量】回合开始 +1（上限 10，可跨回合保留）。成功使用一张普通攻击牌 +1，与被护盾挡下多少无关。敌人的一次行动造成玩家生命伤害时 +1（伤害被护盾完全吸收则不触发）。能量只由规则层结算，动画不影响数值。

【敌人意图】每回合开始时公开：攻击 N 表示本轮敌方阶段会对你造成 N 点伤害；防御 N 表示魔像会获得 N 点护盾且本轮不攻击。数值在展示后锁定，但如果你召唤了嘲讽随从，目标会立即改由该随从承受。

【保留一张牌】点击「结束回合」后，若有手牌会进入保留选择：选定一张保留，其余进入弃牌堆，然后结算随从自动攻击，再进入敌方阶段。也可以不保留，或取消返回行动阶段。

【护盾时机】你的护盾在下个玩家回合开始时清除；魔像的护盾在下个敌方阶段开始时清除，所以它的护盾会保护它度过你的下一整个回合。"""
	var l = _label(text, 14, Palette.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(l)

	var b = Button.new()
	b.text = "关闭"
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(_on_help_close)
	_style_button(b, Palette.PANEL_HI, 16)
	col.add_child(b)


func _build_result_overlay() -> void:
	var o = _make_overlay()
	_result_overlay = o["overlay"]
	var p = _centered_panel(_result_overlay, 560, 320)
	var col = _content(p, 24)
	_result_title = _label("战斗胜利", 30, Palette.SELECT)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result_title)
	_result_desc = _label("", 17)
	_result_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result_desc)
	_result_stats = _label("", 15, Palette.TEXT_DIM)
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_result_stats)
	_result_btn = Button.new()
	_result_btn.text = "再来一局"
	_result_btn.custom_minimum_size = Vector2(0, 52)
	_result_btn.add_theme_font_size_override("font_size", 19)
	_result_btn.pressed.connect(_on_restart_pressed)
	_style_button(_result_btn, Palette.GOLD, 19)
	col.add_child(_result_btn)


func _build_deck_overlay() -> void:
	var o = _make_overlay()
	_deck_overlay = o["overlay"]
	var p = _centered_panel(_deck_overlay, 620, 560)
	var col = _content(p, 18)
	_deck_title = _label("", 18, Palette.SELECT)
	_deck_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_deck_title)
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	_deck_list = VBoxContainer.new()
	_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_list.add_theme_constant_override("separation", 3)
	sc.add_child(_deck_list)
	var b = Button.new()
	b.text = "关闭"
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func(): _deck_overlay.visible = false)
	_style_button(b, Palette.PANEL_HI, 14)
	col.add_child(b)


# ══════════════════════════════════════════════════════════
#  开局 / 重开
# ══════════════════════════════════════════════════════════

func _start_new_battle(seed_value: int) -> void:
	# 重开时清空旧选择、日志、弹窗和未完成动画，防止旧回调修改新战斗（§9）
	_token += 1
	_busy = false
	_selected = -1
	_keep_mode = false
	_keep_choice = -1
	_restarting = false
	_result_btn.disabled = false
	_restart_btn.disabled = false
	_clear(_float_layer)
	_clear(_hand_area)
	_help_overlay.visible = false
	_result_overlay.visible = false
	_deck_overlay.visible = false
	if engine == null:
		engine = BattleEngine.new()
	engine.start_battle(seed_value)
	_refresh_all()


# ══════════════════════════════════════════════════════════
#  刷新界面
# ══════════════════════════════════════════════════════════

func _refresh_all() -> void:
	_refresh_top()
	_refresh_player()
	_refresh_enemy()
	_refresh_minions()
	_refresh_scene()
	_refresh_piles()
	_refresh_hand()
	_refresh_log()
	_refresh_controls()


func _refresh_top() -> void:
	_turn_label.text = "回合 %d" % engine.state.turn


func _refresh_player() -> void:
	var st = engine.state
	_player_hp_bar.max_value = maxf(1.0, float(st.player_max_hp))
	_player_hp_bar.value = float(st.player_hp)
	_player_hp_text.text = "%d / %d" % [st.player_hp, st.player_max_hp]
	_player_shield_label.text = "护盾 %d" % st.player_shield
	_energy_label.text = "能量 %d / %d" % [st.energy, st.max_energy]
	for i in range(_energy_pips.size()):
		var pip: ColorRect = _energy_pips[i]
		pip.color = Palette.ENERGY if i < st.energy else Color(1, 1, 1, 0.12)


func _refresh_enemy() -> void:
	var st = engine.state
	_enemy_name_label.text = st.enemy_name
	_enemy_hp_bar.max_value = maxf(1.0, float(st.enemy_max_hp))
	_enemy_hp_bar.value = float(st.enemy_hp)
	_enemy_hp_text.text = "%d / %d" % [st.enemy_hp, st.enemy_max_hp]
	_enemy_shield_label.text = "护盾 %d" % st.enemy_shield
	var view = engine.get_intent_view()
	if view.is_empty():
		_intent_label.text = "意图：—"
		_intent_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
		return
	var atk = int(view["kind"]) == T.IntentKind.ATTACK
	_intent_label.text = "意图：" + String(view["text"])
	var c = Color("#ff8a7a") if atk else Palette.SHIELD
	_intent_label.add_theme_color_override("font_color", c)
	_intent_box.add_theme_stylebox_override("panel",
		Palette.box(Color("#3a2020") if atk else Color("#1e2f42"), 8, 1, c))


func _refresh_minions() -> void:
	for s in range(T.MINION_SLOTS):
		var m = engine.state.minion_at_slot(s)
		var mv = _minion_views[s]
		if m.is_empty() or int(m["hp"]) <= 0:
			mv.show_minion({}, "", "")
		else:
			var def_id = engine.state.def_id_of(int(m["card_instance"]))
			mv.show_minion(m, def_id, CardDB.card_name(def_id))


func _refresh_scene() -> void:
	var st = engine.state
	if st.scene.is_empty():
		_scene_name.text = "无场景牌"
		_scene_desc.text = "场上仅能存在一张场景牌，新场景会立即替换旧场景。"
		_scene_triggers.text = ""
		return
	var def_id = st.def_id_of(int(st.scene["card_instance"]))
	_scene_name.text = "场景：" + CardDB.card_name(def_id)
	_scene_desc.text = String(CardDB.get_card(def_id).get("desc", ""))
	_scene_triggers.text = "剩余触发次数：%d" % int(st.scene["triggers"])


func _refresh_piles() -> void:
	_draw_count.text = "%d 张" % engine.state.draw_pile.size()
	_discard_count.text = "%d 张" % engine.state.discard_pile.size()


func _refresh_hand() -> void:
	_clear(_hand_area)
	var ids: Array = engine.state.hand.duplicate()
	var n = ids.size()
	if n == 0:
		return
	var card_w = CardView.CARD_SIZE.x
	var avail = _hand_area.size.x
	var step = card_w + 12.0
	if n > 1:
		step = minf(step, (avail - card_w) / float(n - 1))
	var total = card_w + step * (n - 1)
	var x0 = (_hand_area.size.x - total) * 0.5
	for i in range(n):
		var iid: int = int(ids[i])
		var def_id: String = engine.state.def_id_of(iid)
		var v = engine.can_play(iid)
		var cv = CardView.new()
		cv.setup(def_id, iid, bool(v["ok"]), String(v["reason"]))
		cv.position = Vector2(x0 + step * i, (_hand_area.size.y - CardView.CARD_SIZE.y) * 0.5)
		cv.card_clicked.connect(_on_card_clicked)
		_hand_area.add_child(cv)
		var active_sel = _keep_choice if _keep_mode else _selected
		cv.set_selected(iid == active_sel)


func _refresh_log() -> void:
	_clear(_log_box)
	var lines: Array = engine.state.log_lines
	var start = maxi(0, lines.size() - 80)
	for i in range(start, lines.size()):
		var l = _label(String(lines[i]), 12, Palette.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_log_box.add_child(l)
	_scroll_log_to_bottom()


func _scroll_log_to_bottom() -> void:
	await get_tree().process_frame
	if _log_scroll != null and is_instance_valid(_log_scroll):
		var bar = _log_scroll.get_v_scroll_bar()
		_log_scroll.scroll_vertical = int(bar.max_value)


func _refresh_controls() -> void:
	var st = engine.state
	var can_end = (not _busy) and (not _keep_mode) and (not st.battle_over()) \
		and st.phase == T.Phase.PLAYER_ACTION
	_end_turn_btn.disabled = not can_end
	_keep_bar.visible = _keep_mode
	_fast_btn.text = "快速：开" if _fast else "快速：关"
	_restart_btn.disabled = _restarting
	# 选中单体牌时高亮合法敌人；无目标牌提供「确认使用」（§5.1）
	var sel_tt = -1
	if _selected != -1:
		sel_tt = int(CardDB.get_card(st.def_id_of(_selected)).get("target", T.TargetType.NONE))
	_confirm_btn.visible = (_selected != -1 and not _keep_mode and not _busy and not st.battle_over())
	_confirm_btn.disabled = (sel_tt == T.TargetType.SINGLE_ENEMY)
	var hl = (sel_tt == T.TargetType.SINGLE_ENEMY)
	_enemy_hit_area.add_theme_stylebox_override("panel", Palette.box(Color(1, 1, 1, 0.03) if not hl else Color(0.95, 0.82, 0.42, 0.10), 8, 3 if hl else 1, Palette.SELECT if hl else Palette.BORDER))

	if _keep_confirm_btn != null:
		_keep_confirm_btn.disabled = (_keep_choice == -1)

	if st.battle_over():
		_hint_label.text = "战斗已结束。点击「再来一局」重新挑战。"
	elif _keep_mode:
		if _keep_choice == -1:
			_hint_label.text = "结束回合：请点击一张手牌作为要保留的牌，或点「不保留」。"
		else:
			_hint_label.text = "将保留「%s」，其余手牌进入弃牌堆。" % CardDB.card_name(st.def_id_of(_keep_choice))
	elif _busy:
		_hint_label.text = "结算中…（期间锁定输入）"
	elif _selected != -1:
		var def_id = st.def_id_of(_selected)
		var tt = int(CardDB.get_card(def_id).get("target", T.TargetType.NONE))
		if tt == T.TargetType.SINGLE_ENEMY:
			_hint_label.text = "已选中「%s」：点击魔像确认使用；右键 / Esc / 点击空白处取消。" % CardDB.card_name(def_id)
		elif tt == T.TargetType.MINION_SLOT:
			_hint_label.text = "已选中「%s」：再次点击卡牌或点「确认使用」召唤。" % CardDB.card_name(def_id)
		else:
			_hint_label.text = "已选中「%s」：再次点击卡牌或点「确认使用」。" % CardDB.card_name(def_id)
	elif st.turn == 1:
		_hint_label.text = String(EnemyDB.encounter()["first_turn_hint"])
	else:
		_hint_label.text = "点击手牌出牌，然后点「结束回合」。"


# ══════════════════════════════════════════════════════════
#  交互
# ══════════════════════════════════════════════════════════

func _on_card_clicked(instance_id: int) -> void:
	if _busy or engine.state.battle_over():
		return
	if _keep_mode:
		_keep_choice = instance_id
		_update_selection_visuals()
		_refresh_controls()
		return

	var v = engine.can_play(instance_id)
	if not v["ok"]:
		_float(String(v["reason"]), Vector2(VIEW.x * 0.5, 620), Palette.WARN, 19)
		return

	var def_id = engine.state.def_id_of(instance_id)
	var tt = int(CardDB.get_card(def_id).get("target", T.TargetType.NONE))

	if _selected == instance_id:
		# 再次点击：无目标牌直接生效；单体牌仍需点击敌人（§5.1）
		if tt != T.TargetType.SINGLE_ENEMY:
			_confirm_play(instance_id)
		else:
			_hint_label.text = "请点击魔像确认使用。"
		return

	_selected = instance_id
	_update_selection_visuals()
	_refresh_controls()


func _confirm_play(instance_id: int) -> void:
	var r = engine.play_card(instance_id)
	if not r["ok"]:
		_float(String(r["reason"]), Vector2(VIEW.x * 0.5, 620), Palette.WARN, 19)
		_refresh_all()
		return
	_selected = -1
	_refresh_all()
	await _play_events(r["events"])
	if _token == 0:
		return
	if engine.state.battle_over():
		_show_result()


func _on_enemy_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_enemy_clicked()
			accept_event()


func _on_enemy_clicked() -> void:
	if _busy or _selected == -1 or engine.state.battle_over():
		return
	var def_id = engine.state.def_id_of(_selected)
	var tt = int(CardDB.get_card(def_id).get("target", T.TargetType.NONE))
	if tt != T.TargetType.SINGLE_ENEMY:
		return
	_confirm_play(_selected)


## 只更新现有卡牌的选中外观，不重建节点（§5.1 出牌交互）。
## 重建会销毁正在处理点击事件的卡牌，导致 accept_event() 失效、事件继续冒泡到 _unhandled_input。
func _update_selection_visuals() -> void:
	var active = _keep_choice if _keep_mode else _selected
	for c in _hand_area.get_children():
		if c.has_method("set_selected"):
			c.set_selected(int(c.instance_id) == active)

func _cancel_selection() -> void:
	if _selected == -1:
		return
	_selected = -1
	_update_selection_visuals()
	_refresh_controls()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k = event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			_cancel_selection()


## 空白处点击：由最底层的 catcher 接收（卡牌与按钮在前，命中优先）。
func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			_cancel_selection()
			accept_event()


func _on_end_turn_pressed() -> void:
	if _busy or _keep_mode or engine.state.battle_over():
		return
	var r = engine.request_end_turn()
	if not r["ok"]:
		_float(String(r["reason"]), Vector2(VIEW.x * 0.5, 620), Palette.WARN, 19)
		return
	if not bool(r["needs_keep"]):
		_finish_end_turn(-1)
		return
	_keep_mode = true
	_keep_choice = -1
	_selected = -1
	_refresh_hand()
	_refresh_controls()


func _on_keep_confirm() -> void:
	if _keep_choice == -1:
		return
	_finish_end_turn(_keep_choice)


func _on_keep_none() -> void:
	_finish_end_turn(-1)


func _on_keep_cancel() -> void:
	var r = engine.cancel_end_turn()
	if not r["ok"]:
		_float(String(r["reason"]), Vector2(VIEW.x * 0.5, 620), Palette.WARN, 19)
		return
	_keep_mode = false
	_keep_choice = -1
	_refresh_all()


func _finish_end_turn(keep: int) -> void:
	var token = _token
	_busy = true
	_keep_mode = false
	_keep_choice = -1
	_refresh_controls()
	var r = engine.confirm_end_turn(keep)
	_refresh_all()
	if bool(r["ok"]):
		await _play_events(r["events"])
	if token != _token:
		return
	_busy = false
	_refresh_all()
	if engine.state.battle_over():
		_show_result()


func _on_fast_toggled() -> void:
	_fast = not _fast
	_refresh_controls()


func _on_log_fold() -> void:
	_log_scroll.visible = not _log_scroll.visible


func _on_help_pressed() -> void:
	# 玩法说明打开期间阻止背景操作，关闭后恢复原状态，不推进回合（§3）
	_help_overlay.visible = true


func _on_help_close() -> void:
	_help_overlay.visible = false


func _on_confirm_pressed() -> void:
	if _busy or _selected == -1 or engine.state.battle_over():
		return
	var def_id = engine.state.def_id_of(_selected)
	var tt = int(CardDB.get_card(def_id).get("target", T.TargetType.NONE))
	if tt == T.TargetType.SINGLE_ENEMY:
		_hint_label.text = "请点击魔像确认使用。"
		return
	_confirm_play(_selected)

func _on_restart_pressed() -> void:
	# §9：按钮执行初始化期间禁用，避免重复创建战斗
	if _restarting:
		return
	_restarting = true
	_result_btn.disabled = true
	_restart_btn.disabled = true
	await get_tree().process_frame
	_start_new_battle(_random_seed())


func _open_deck(kind: String) -> void:
	var st = engine.state
	_clear(_deck_list)
	if kind == "draw":
		_deck_title.text = "抽牌堆 · %d 张（只显示组成与数量，不暴露抽取顺序）" % st.draw_pile.size()
		var counts = {}
		for iid in st.draw_pile:
			var d: String = st.def_id_of(int(iid))
			counts[d] = int(counts.get(d, 0)) + 1
		var keys = counts.keys()
		keys.sort()
		for d in keys:
			_deck_list.add_child(_label("%s  ×%d" % [CardDB.card_name(String(d)), int(counts[d])], 14))
	else:
		_deck_title.text = "弃牌堆 · %d 张（显示实际内容）" % st.discard_pile.size()
		for iid in st.discard_pile:
			var d2: String = st.def_id_of(int(iid))
			var ctype = CardDB.card_type(d2)
			var l = _label("%s（%s）" % [CardDB.card_name(d2), String(T.CARD_TYPE_NAME.get(ctype, ""))], 14)
			l.add_theme_color_override("font_color", Palette.card_color(ctype).lightened(0.45))
			_deck_list.add_child(l)
	_deck_overlay.visible = true


func _show_result() -> void:
	var st = engine.state
	if st.result == T.Result.VICTORY:
		_result_title.text = "战斗胜利"
		_result_desc.text = "你击败了练习魔像"
	else:
		_result_title.text = "挑战失败"
		_result_desc.text = "调整出牌顺序，再试一次"
	_result_stats.text = "使用回合数：%d        玩家剩余生命：%d / %d" % [
		st.turn, st.player_hp, st.player_max_hp]
	_result_btn.disabled = false
	_result_overlay.visible = true


# ══════════════════════════════════════════════════════════
#  事件播放（只表现，不计算规则）
# ══════════════════════════════════════════════════════════

func _anchor_for_target(target: int, slot: int) -> Vector2:
	# 浮字锚点跟着场景里的角色走，而不是跟着状态面板走
	if target == T.Side.PLAYER:
		return Vector2(540, 300)
	if target == T.Side.ENEMY:
		return Vector2(1060, 300)
	if target == T.Side.MINION:
		var x = 97.0 if slot == 0 else 235.0
		return Vector2(x, 500)
	return Vector2(VIEW.x * 0.5, 400)


func _play_events(events: Array) -> void:
	var token = _token
	_busy = true
	_refresh_controls()
	for ev in events:
		if token != _token:
			return
		var etype = String(ev.get("type", ""))
		var paced = false

		if etype == T.EV_DAMAGE:
			var pos = _anchor_for_target(int(ev.get("target", -1)), int(ev.get("slot", -1)))
			var hp_loss = int(ev.get("hp_loss", 0))
			var absorbed = int(ev.get("absorbed", 0))
			if absorbed > 0:
				_float("护盾 -%d" % absorbed, pos + Vector2(0, 0), Palette.SHIELD, 20)
			if hp_loss > 0:
				_float("-%d" % hp_loss, pos + Vector2(0, -30), Color("#ff6b6b"), 30)
			_refresh_all()
			paced = true
		elif etype == T.EV_SHIELD_GAINED:
			var side = int(ev.get("side", -1))
			var pos2 = Vector2(170, 250) if side == T.Side.PLAYER else Vector2(1430, 250)
			_float("护盾 +%d" % int(ev.get("amount", 0)), pos2, Palette.SHIELD, 22)
			_refresh_all()
			paced = true
		elif etype == T.EV_ENERGY_CHANGED:
			var d = int(ev.get("delta", 0))
			if d != 0:
				_float(("能量 +%d" % d) if d > 0 else ("能量 %d" % d), Vector2(170, 330), Palette.ENERGY, 20)
				_refresh_all()
				paced = true
		elif etype == T.EV_CARDS_DRAWN:
			var cnt = int(ev.get("count", 0))
			if cnt > 0:
				_float("抽 %d 张" % cnt, Vector2(VIEW.x * 0.5, 470), Palette.TEXT, 20)
				_refresh_all()
				paced = true
		elif etype == T.EV_MINION_SUMMONED:
			_float("召唤「%s」" % String(ev.get("name", "")), Vector2(VIEW.x * 0.5, 470), Palette.GOOD, 22)
			_refresh_all()
			paced = true
		elif etype == T.EV_MINION_DIED:
			_float("「%s」死亡" % String(ev.get("name", "")), Vector2(VIEW.x * 0.5, 470), Color("#ff6b6b"), 20)
			_refresh_all()
			paced = true
		elif etype == T.EV_SCENE_TRIGGERED:
			_float("场景触发：能量 +1（剩余 %d 次）" % int(ev.get("triggers_left", 0)),
				Vector2(VIEW.x * 0.5, 200), Color("#e0c15a"), 20)
			_refresh_all()
			paced = true
		elif etype == T.EV_SCENE_EXPIRED:
			_float("场景到期，进入弃牌堆", Vector2(VIEW.x * 0.5, 200), Color("#e0c15a"), 18)
			_refresh_all()
			paced = true
		elif etype == T.EV_INTENT_TARGET_CHANGED:
			_float("意图目标更新：" + String(ev.get("text", "")), Vector2(1430, 330), Palette.WARN, 18)
			_refresh_all()
			paced = true
		elif etype == T.EV_ENEMY_ACTED:
			_refresh_all()
		elif etype == T.EV_SHIELD_CLEARED:
			var side3 = int(ev.get("side", -1))
			var pos3 = Vector2(170, 250) if side3 == T.Side.PLAYER else Vector2(1430, 250)
			_float("护盾清除 %d" % int(ev.get("amount", 0)), pos3, Palette.TEXT_DIM, 18)
			_refresh_all()
			paced = true

		if paced:
			await _delay(0.3)

	if token != _token:
		return
	_refresh_all()
	_busy = false
	_refresh_controls()


func _delay(sec: float) -> void:
	var t = sec * (0.25 if _fast else 1.0)
	if t <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(t).timeout


func _float(text: String, pos: Vector2, color: Color, font_size: int = 20) -> void:
	if _float_layer == null:
		return
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, 34)
	l.position = pos - Vector2(200, 17)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.add_child(l)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", l.position + Vector2(0, -58), 0.95)
	tw.tween_property(l, "modulate:a", 0.0, 0.95)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)