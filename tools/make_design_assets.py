# -*- coding: utf-8 -*-
"""
生成《元素设计文档》的配图。

同一份绘制指令同时输出：
  docs/design/<name>.png   参考渲染（文档里嵌入的就是它）
  docs/design/<name>.svg   可编辑矢量源（给美术/设计接手用）

色值直接取自 src/ui/palette.gd，保证「设计图 = 实现」，不会各说各话。

运行： python tools/make_design_assets.py
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "docs", "design")

FONT_REG = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"
SVG_FONT = "Microsoft YaHei, Microsoft YaHei UI, SimHei, sans-serif"

# ── 与 src/ui/palette.gd 完全一致的色值（「遗迹 · 自然」）──────
C = {
    "BG_DEEP": "#171310", "BG_STONE": "#2a231c", "BG_FLOOR": "#241e18",
    "PANEL": "#332a22", "PANEL_HI": "#40352a",
    "BORDER": "#57493b", "BORDER_HI": "#7d6a53",
    "TEXT": "#ece3d4", "TEXT_DIM": "#a79883",
    "TEXT_INK": "#3b3024", "TEXT_INK_DIM": "#6b5b45",
    "GOLD": "#d9a441", "SELECT": "#f2dc9e",
    "HP": "#b0432f", "HP_BG": "#3a2620", "SHIELD": "#6f8fa8", "ENERGY": "#e0a94a",
    "GOOD": "#7a9a5a", "WARN": "#c98a4b", "TAUNT": "#c9924a",
    "PAPER": "#e9dcc3", "PAPER_EDGE": "#c9b691",
}
CARD_COLOR = {
    "攻击": "#a8442f", "防御": "#4a6f8f", "技能": "#7a5a8f",
    "场景": "#b08a3c", "随从": "#5f8a5a",
}


def darken(hexcolor, factor):
    h = hexcolor.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    r, g, b = (int(v * (1 - factor)) for v in (r, g, b))
    return "#%02x%02x%02x" % (r, g, b)


def lighten(hexcolor, factor):
    h = hexcolor.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    r, g, b = (min(255, int(v + (255 - v) * factor)) for v in (r, g, b))
    return "#%02x%02x%02x" % (r, g, b)


def alpha_hex(hexcolor, a):
    """PIL 不接受 8 位色值，这里把透明度混到背景色上，PNG/SVG 表现一致。"""
    h = hexcolor.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    br, bg_, bb = 0x17, 0x13, 0x10
    return "#%02x%02x%02x" % (
        int(r * a + br * (1 - a)), int(g * a + bg_ * (1 - a)), int(b * a + bb * (1 - a)))


class Canvas:
    """极简双后端画布：一份绘制指令 → PNG + SVG。"""

    def __init__(self, w, h, bg=None):
        self.w, self.h = w, h
        self.bg = bg or C["BG_DEEP"]
        self.img = Image.new("RGB", (w, h), self.bg)
        self.d = ImageDraw.Draw(self.img)
        self.svg = []
        self._fonts = {}

    # ── 度量 ──────────────────────────────────────────────
    def font(self, size, bold=False):
        key = (size, bold)
        if key not in self._fonts:
            self._fonts[key] = ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)
        return self._fonts[key]

    def tw(self, s, size, bold=False):
        b = self.font(size, bold).getbbox(s)
        return b[2] - b[0]

    def wrap(self, s, size, max_w, bold=False):
        """按字符断行（中文友好）。用 PIL 度量，保证 PNG 与 SVG 断行一致。"""
        lines, cur = [], ""
        for ch in s:
            if ch == "\n":
                lines.append(cur)
                cur = ""
                continue
            t = cur + ch
            if self.tw(t, size, bold) > max_w and cur:
                lines.append(cur)
                cur = ch
            else:
                cur = t
        if cur:
            lines.append(cur)
        return lines

    # ── 图元 ──────────────────────────────────────────────
    def rect(self, x, y, w, h, fill=None, stroke=None, sw=1, r=0, dash=None):
        if r > 0:
            self.d.rounded_rectangle([x, y, x + w, y + h], radius=r,
                                     fill=fill, outline=stroke, width=sw)
        else:
            self.d.rectangle([x, y, x + w, y + h], fill=fill, outline=stroke, width=sw)
        da = ' stroke-dasharray="%s"' % dash if dash else ""
        self.svg.append('<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s" stroke="%s" stroke-width="%g"%s/>'
                        % (x, y, w, h, r, fill or "none", stroke or "none", sw if stroke else 0, da))

    def circle(self, cx, cy, r, fill=None, stroke=None, sw=1):
        self.d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=stroke, width=sw)
        self.svg.append('<circle cx="%g" cy="%g" r="%g" fill="%s" stroke="%s" stroke-width="%g"/>'
                        % (cx, cy, r, fill or "none", stroke or "none", sw if stroke else 0))

    def line(self, x1, y1, x2, y2, color, sw=1, dash=None):
        self.d.line([x1, y1, x2, y2], fill=color, width=sw)
        da = ' stroke-dasharray="%s"' % dash if dash else ""
        self.svg.append('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="%g"%s/>'
                        % (x1, y1, x2, y2, color, sw, da))

    def poly(self, pts, fill=None, stroke=None, sw=1):
        self.d.polygon(pts, fill=fill, outline=stroke)
        p = " ".join("%g,%g" % (px, py) for px, py in pts)
        self.svg.append('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%g"/>'
                        % (p, fill or "none", stroke or "none", sw if stroke else 0))

    def text(self, x, y, s, size=16, color=None, bold=False, anchor="lt"):
        color = color or C["TEXT"]
        f = self.font(size, bold)
        pil_anchor = {"lt": "la", "ct": "ma", "rt": "ra",
                      "lm": "lm", "cm": "mm", "rm": "rm"}[anchor]
        self.d.text((x, y), s, font=f, fill=color, anchor=pil_anchor)
        svg_anchor = {"lt": "start", "ct": "middle", "rt": "end",
                      "lm": "start", "cm": "middle", "rm": "end"}[anchor]
        if anchor in ("lt", "ct", "rt"):
            baseline = y + size * 0.80
        else:
            baseline = y + size * 0.35
        esc = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        self.svg.append('<text x="%g" y="%g" font-family="%s" font-size="%g" font-weight="%s" '
                        'fill="%s" text-anchor="%s">%s</text>'
                        % (x, baseline, SVG_FONT, size, "bold" if bold else "normal", color, svg_anchor, esc))

    def save(self, name):
        os.makedirs(OUT_DIR, exist_ok=True)
        png = os.path.join(OUT_DIR, name + ".png")
        self.img.save(png)
        svg = os.path.join(OUT_DIR, name + ".svg")
        with open(svg, "w", encoding="utf-8") as f:
            f.write('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
                    'viewBox="0 0 %d %d">\n' % (self.w, self.h, self.w, self.h))
            f.write('<rect width="%d" height="%d" fill="%s"/>\n' % (self.w, self.h, self.bg))
            f.write("\n".join(self.svg))
            f.write("\n</svg>\n")
        return png, svg


# ══════════════════════════════════════════════════════════
#  通用组件
# ══════════════════════════════════════════════════════════

def draw_card(c, x, y, w, h, name, ctype, cost, desc, state="normal", hint="", scale=1.0):
    """羊皮纸卡面：纸色底 + 类型色卡头 + 墨色正文（与 src/ui/card_view.gd 一致）。"""
    tcol = CARD_COLOR[ctype]
    radius = int(w * 0.07)
    bw = max(1, int(w * 0.013))
    if state == "selected":
        bw = max(2, int(w * 0.020))
        border = C["SELECT"]
    elif state == "hover":
        border = lighten(tcol, 0.45)
    else:
        border = tcol
    if state == "disabled":
        tcol = darken(tcol, 0.45)
        border = darken(tcol, 0.2)

    paper = C["PAPER"] if state != "disabled" else darken(C["PAPER"], 0.24)
    ink = C["TEXT_INK"] if state != "disabled" else C["TEXT_INK_DIM"]
    ink_dim = C["TEXT_INK_DIM"] if state != "disabled" else "#8a7c66"

    # 纸面 + 类型色描边
    c.rect(x, y, w, h, fill=paper, stroke=border, sw=bw, r=radius)

    # 类型色卡头（上两角圆角，下两角抹平）
    hr = h * 0.21
    c.rect(x + bw, y + bw, w - bw * 2, hr, fill=tcol, r=radius)
    c.rect(x + bw, y + hr - radius + bw, w - bw * 2, radius, fill=tcol)

    pad = w * 0.068
    ns = int(w * 0.118)
    c.text(x + pad, y + h * 0.055, name, size=ns, color=C["TEXT"], bold=True)

    # 费用徽章：深色圆 + 金边 + 能量色数字（免费牌也显示 0）
    br = w * 0.098
    cx, cy = x + w - pad - br, y + h * 0.055 + br
    c.circle(cx, cy, br, fill="#17120c", stroke=C["GOLD"], sw=max(2, int(w * 0.015)))
    c.text(cx, cy, str(cost), size=int(ns * 0.92), color=C["ENERGY"], bold=True, anchor="cm")

    ts = int(ns * 0.70)
    c.text(x + pad, y + hr + h * 0.028, ctype, size=ts, color=ink_dim)

    ds = int(w * 0.090)
    ty = y + hr + h * 0.105
    for ln in c.wrap(desc, ds, w - pad * 2):
        c.text(x + pad, ty, ln, size=ds, color=ink)
        ty += ds * 1.45
    if hint:
        hs = int(w * 0.075)
        ty += ds * 0.25
        for ln in c.wrap(hint, hs, w - pad * 2):
            c.text(x + pad, ty, ln, size=hs, color=C["WARN"])
            ty += hs * 1.42
    return tcol


def title_block(c, title, sub=""):
    c.text(36, 24, title, size=27, color=C["TEXT"], bold=True)
    if sub:
        c.text(36, 58, sub, size=14, color=C["TEXT_DIM"])
    c.line(36, 82, c.w - 36, 82, C["BORDER"], 1)


def note(c, y, s, size=13, color=None, max_w=None):
    """说明文字。自动按画布宽度换行，避免横向溢出；返回下一行的 y。"""
    max_w = max_w or (c.w - 72)
    for ln in c.wrap(s, size, max_w):
        c.text(36, y, ln, size=size, color=color or C["TEXT_DIM"])
        y += size * 1.5
    return y


# ══════════════════════════════════════════════════════════
#  图 1：色彩系统
# ══════════════════════════════════════════════════════════

def fig_palette():
    c = Canvas(1100, 780)
    title_block(c, "色彩系统 · Color System",
                "与 src/ui/palette.gd 完全一致 —— 设计图即实现，不各自维护一套色值")

    groups = [
        ("界面底色：暖石灰岩，4 级明度", [("BG_DEEP", "最外层"), ("BG_STONE", "石墙"),
                                          ("BG_FLOOR", "地面"), ("PANEL", "面板"),
                                          ("PANEL_HI", "面板强调")]),
        ("描边与文字", [("BORDER", "描边"), ("BORDER_HI", "高光描边"),
                        ("TEXT", "主文字"), ("TEXT_DIM", "次要文字"),
                        ("TEXT_INK", "纸面墨色")]),
        ("状态与强调", [("HP", "生命"), ("SHIELD", "护盾"), ("ENERGY", "能量"),
                        ("GOLD", "金 / 描边"), ("SELECT", "选中 / 高亮"),
                        ("GOOD", "就绪"), ("WARN", "不可用原因")]),
        ("卡牌类型色（土性颜料）", [("__ATK", "攻击"), ("__DEF", "防御"), ("__SKL", "技能"),
                                   ("__SCN", "场景"), ("__MIN", "随从")]),
    ]
    type_map = {"__ATK": "攻击", "__DEF": "防御", "__SKL": "技能", "__SCN": "场景", "__MIN": "随从"}

    y = 104
    for gname, items in groups:
        c.text(36, y, gname, size=16, color=C["TEXT"], bold=True)
        y += 28
        x = 36
        for key, label in items:
            col = CARD_COLOR[type_map[key]] if key.startswith("__") else C[key]
            c.rect(x, y, 128, 62, fill=col, stroke=C["BORDER"], sw=1, r=8)
            c.text(x + 8, y + 68, label, size=12, color=C["TEXT"])
            c.text(x + 8, y + 84, col.upper(), size=11, color=C["TEXT_DIM"])
            x += 140
        y += 118

    note(c, y + 4, "界面底色用同一色系的 4 级明度拉开层级（而不是靠色相），卡牌类型是唯一允许"
                   "较高饱和的地方；类型识别始终同时给颜色与类型文字，不依赖颜色单独传达（规格 §4.1）。")
    return c


# ══════════════════════════════════════════════════════════
#  图 2：卡牌解剖
# ══════════════════════════════════════════════════════════

def fig_card_anatomy():
    c = Canvas(1100, 700)
    title_block(c, "卡牌元素解剖 · Card Anatomy",
                "手牌区单卡 148 × 208 px；下图放大 2.2 倍绘制，标注每个元素的字号与作用")

    cw, ch = 148 * 2.2, 208 * 2.2
    cx, cy = 110, 118
    draw_card(c, cx, cy, cw, ch, "能量冲击", "技能", 3,
              "造成 12 伤害", hint="")

    marks = [
        (cy + cw * 0.062 + 26, "① 卡牌名称", "17 px 粗体，左上角，单行"),
        (cy + cw * 0.098, "② 费用徽章", "免费牌也显示 0；能量不足时置灰并给出原因"),
        (cy + cw * 0.062 + 26 * 2.6, "③ 类型文字", "12 px，与类型色同现，不只靠颜色区分"),
        (cy + cw * 0.062 + 26 * 3.6, "④ 分隔线", "1 px，22% 白色，分隔头部与效果区"),
        (cy + ch * 0.40, "⑤ 完整效果描述", "13 px，自动换行，不截断、不用省略号"),
        (cy + ch * 0.78, "⑥ 不可用原因", "12 px 警告色；仅在该牌当前不可用时出现"),
    ]
    for ly, label, desc in marks:
        c.line(cx + cw + 14, ly, cx + cw + 74, ly, C["SELECT"], 1, dash="4 3")
        c.circle(cx + cw + 74, ly, 3, fill=C["SELECT"])
        c.text(cx + cw + 90, ly - 9, label, size=15, color=C["TEXT"], bold=True)
        c.text(cx + cw + 90, ly + 10, desc, size=12, color=C["TEXT_DIM"])

    note(c, cy + ch + 46, "交互尺寸（规格 §5.1）：整张卡为点击热区 148 × 208；悬停放大到 1.14 倍并提升 z 序；"
                          "相邻卡重叠时，悬停卡始终在最上层。")
    note(c, cy + ch + 68, "文字层级：名称 17px / 费用 15px / 类型 12px / 效果 13px / 原因 12px。", color=C["TEXT"])
    return c


# ══════════════════════════════════════════════════════════
#  图 3：五类卡牌
# ══════════════════════════════════════════════════════════

def fig_card_types():
    c = Canvas(1100, 420)
    title_block(c, "五类卡牌 · Card Types",
                "同一套版式，靠类型色 + 类型文字区分；下图取自卡表真实数值")
    cards = [
        ("斩击", "攻击", 0, "获得 1 能量，然后造成 5 伤害"),
        ("格挡", "防御", 0, "获得 6 护盾"),
        ("能量冲击", "技能", 3, "造成 12 伤害"),
        ("能量涌泉", "场景", 2, "接下来 3 个玩家回合开始时额外获得 1 能量"),
        ("守卫", "随从", 3, "召唤 2 攻击 / 7 生命嘲讽随从"),
    ]
    cw, ch = 184, 259
    gap = 26
    x = (c.w - (cw * 5 + gap * 4)) / 2
    for name, ctype, cost, desc in cards:
        draw_card(c, x, 110, cw, ch, name, ctype, cost, desc)
        c.rect(x + cw * 0.22, 380, cw * 0.56, 24, fill=CARD_COLOR[ctype], r=6)
        c.text(x + cw / 2, 380, ctype, size=14, color=C["TEXT"], bold=True, anchor="ct")
        x += cw + gap
    return c


# ══════════════════════════════════════════════════════════
#  图 4：卡牌四态
# ══════════════════════════════════════════════════════════

def fig_card_states():
    c = Canvas(1100, 470)
    title_block(c, "卡牌交互状态 · Card States",
                "四种状态对应四种玩家可感知的反馈（规格 §4.3 / §5.1）")
    states = [
        ("normal", "① 默认", "可出牌：类型色 + 正常亮度", ""),
        ("hover", "② 悬停", "放大 1.14 倍，展示完整描述", ""),
        ("selected", "③ 选中", "金色 3px 边框；单体牌提示点击敌人", ""),
        ("disabled", "④ 不可用", "整体置灰 + 底部显示具体原因", "需要 3 能量，当前 2"),
    ]
    cw, ch = 184, 259
    gap = 40
    x = (c.w - (cw * 4 + gap * 3)) / 2
    for state, label, desc, hint in states:
        yy = 118 if state != "hover" else 104
        xx = x if state != "hover" else x - cw * 0.07
        draw_card(c, xx, yy, cw * (1.14 if state == "hover" else 1.0),
                  ch * (1.14 if state == "hover" else 1.0),
                  "能量冲击", "技能", 3, "造成 12 伤害", state=state, hint=hint)
        c.text(x + cw / 2, 400, label, size=15, color=C["TEXT"], bold=True, anchor="ct")
        c.text(x + cw / 2, 418, desc, size=11, color=C["TEXT_DIM"], anchor="ct")
        x += cw + gap
    return c


# ══════════════════════════════════════════════════════════
#  图 5：战斗界面布局（真实坐标）
# ══════════════════════════════════════════════════════════

def fig_battle_layout():
    S = 0.72                        # 1600×900 → 1152×648
    LW, LH = int(1600 * S), int(900 * S)
    OX, OY = 36, 104
    c = Canvas(LW + OX * 2, OY + LH + 58)
    title_block(c, "战斗界面布局 · Battle Layout",
                "1600 × 900 设计空间等比缩放；每个区域的坐标都是实现中的真实值")

    def R(x, y, w, h, fill, stroke, label, sub="", lc=None, sw=2, dash=None):
        px, py = OX + x * S, OY + y * S
        c.rect(px, py, w * S, h * S, fill=fill, stroke=stroke, sw=sw, r=6, dash=dash)
        if label:
            c.text(px + 8, py + 8, label, size=13, color=lc or C["TEXT"], bold=True)
        if sub:
            c.text(px + 8, py + 27, sub, size=10, color=C["TEXT_DIM"])

    # 中央场地不再铺实心面板 —— 背景与角色直接露出，这里只用虚线标出范围
    R(336, 66, 928, 542, alpha_hex("#000000", 0.0), C["BORDER_HI"], "中央场地区（无实心面板）",
      "直接露出石室背景 · 角色站在其中 · 飘字在此", C["TEXT_DIM"], 2, "7 5")
    R(390, 190, 300, 420, alpha_hex("#8fa2c8", 0.10), "#9fb0d0", "玩家角色", "冒险者 300 × 420",
      C["TEXT"], 2, "4 4")
    R(890, 170, 340, 440, alpha_hex("#c8a98f", 0.10), "#d0b09f", "敌人角色", "练习魔像 340 × 440",
      C["TEXT"], 2, "4 4")
    R(0, 0, 1600, 54, C["PANEL"], C["BORDER"], "顶栏", "战斗名称 · 回合数 · 玩法说明 / 快速开关")
    R(20, 66, 300, 336, C["PANEL"], C["BORDER"], "左侧玩家区", "生命 · 护盾 · 能量 0~10")
    R(20, 412, 300, 196, C["PANEL"], C["BORDER"], "左下随从区", "两个固定槽位 · 攻击/生命 · 就绪 · 嘲讽")
    R(500, 82, 600, 104, C["PANEL"], C["GOLD"], "场景牌区", "名称 · 效果 · 剩余触发次数", C["SELECT"])
    R(1280, 66, 300, 336, C["PANEL"], C["BORDER"], "右侧敌人区", "名称 · 生命 · 护盾 · 当前意图")
    R(1280, 250, 300, 152, alpha_hex("#8f9bb0", 0.16), C["BORDER_HI"], "敌人点击热区",
      "单体牌需点击此处确认", C["TEXT_DIM"], 2, "5 4")
    R(1280, 412, 300, 196, C["PANEL"], C["BORDER"], "结算日志（可折叠）", "最近结算记录")
    R(20, 620, 160, 262, C["PANEL"], C["BORDER"], "牌堆区", "抽牌堆 / 弃牌堆")
    R(196, 620, 1188, 262, alpha_hex("#000000", 0.28), C["BORDER_HI"], "手牌区",
      "最多 10 张 · 重叠排列 · 悬停展开", C["TEXT"], 2, "6 4")
    R(1400, 620, 180, 262, C["PANEL"], C["BORDER"], "控制区", "提示 · 结束回合 · 重开")
    R(500, 566, 600, 40, alpha_hex("#5a5040", 0.6), C["SELECT"], "保留操作条",
      "保留并结束 / 不保留 / 取消　（仅保留阶段显示）", C["SELECT"])

    note(c, OY + LH + 18,
         "绘制顺序（从下到上）：1 石室背景 → 2 场景中的角色 → 3 暗角 → 4 全部 UI 面板 → 5 飘字。"
         "暗角夹在角色与 UI 之间，让四周沉下去但不压暗任何 UI。")
    note(c, OY + LH + 38,
         "卡牌 148 × 208；随从槽 130 × 146；敌人点击热区 300 × 152；手牌区 1188 × 262。"
         "全部坐标见 src/ui/battle_scene.gd 的 _build_ui()。")
    return c


# ══════════════════════════════════════════════════════════
#  图 6：手牌排布
# ══════════════════════════════════════════════════════════

def fig_hand_layout():
    c = Canvas(1100, 560)
    title_block(c, "手牌区排布规则 · Hand Layout",
                "手牌区宽 1188 px，单卡 148 px；卡片越多重叠越紧，始终居中且不溢出手牌区")

    cw, avail = 148, 1188
    scale = 0.42
    for idx, n in enumerate([1, 3, 6, 10]):
        y = 116 + idx * 108
        c.text(36, y + 6, "%2d 张" % n, size=15, color=C["TEXT"], bold=True)
        box_x, box_w = 120, avail * scale
        c.rect(box_x, y - 8, box_w, 208 * scale + 26, fill="#22242e", stroke="#5a6178", sw=1, r=5)
        step = cw + 12.0
        if n > 1:
            step = min(step, (avail - cw) / float(n - 1))
        total = cw + step * (n - 1)
        x0 = (avail - total) / 2.0
        overlap = "无重叠" if step >= cw else "重叠 %.0f px" % (cw - step)
        for i in range(n):
            xx = box_x + (x0 + step * i) * scale
            c.rect(xx, y, cw * scale, 208 * scale, fill=CARD_COLOR["攻击"] if i == 0 else "#3a4256",
                   stroke=C["BORDER"], sw=1, r=3)
        c.text(box_x + box_w + 14, y + 6, "步长 %.0f px　%s" % (step, overlap),
               size=12, color=C["TEXT_DIM"])
        c.text(box_x + box_w + 14, y + 24, "起始 x = %.0f（居中）" % x0, size=12, color=C["TEXT_DIM"])

    return c


# ══════════════════════════════════════════════════════════
#  图 7：Buff 图标集（为后续升级准备）
# ══════════════════════════════════════════════════════════

def fig_buff_icons():
    c = Canvas(1100, 430)
    title_block(c, "Buff / Debuff 图标集 · Status Icons",
                "与「升级路线图」第一步/第二步配套；图标用几何形表达，不依赖颜色单独辨识")

    icons = [
        ("力量", C["WARN"], "arrow_up", "攻击牌伤害 +X", "本场战斗"),
        ("蓄势", C["ENERGY"], "chevrons", "下一张伤害技能 +X", "触发后清除"),
        ("虚弱", "#7f8aa3", "arrow_down", "下一次攻击伤害 -25%", "之后移除"),
        ("中毒", C["GOOD"], "droplet", "敌方阶段开始损失生命", "每层每轮"),
        ("易伤", "#c0553b", "shield_crack", "下一次受伤 +50%", "触发后移除"),
        ("反击", "#5aa9c9", "retaliate", "每次被攻击反打 X", "全被挡也触发"),
    ]
    cell_w = 1000 / 6.0
    for i, (name, col, glyph, line1, line2) in enumerate(icons):
        cx = 46 + cell_w * i + cell_w / 2
        top = 108
        size = 108
        c.rect(cx - size / 2, top, size, size, fill=darken(col, 0.62), stroke=col, sw=2, r=14)

        gx, gy = cx, top + size / 2
        if glyph == "arrow_up":
            c.poly([(gx, gy - 30), (gx - 22, gy + 6), (gx - 8, gy + 6), (gx - 8, gy + 28),
                    (gx + 8, gy + 28), (gx + 8, gy + 6), (gx + 22, gy + 6)], fill=col)
        elif glyph == "arrow_down":
            c.poly([(gx, gy + 30), (gx - 22, gy - 6), (gx - 8, gy - 6), (gx - 8, gy - 28),
                    (gx + 8, gy - 28), (gx + 8, gy - 6), (gx + 22, gy - 6)], fill=col)
        elif glyph == "chevrons":
            for k in range(3):
                yy = gy - 20 + k * 18
                c.poly([(gx - 20, yy), (gx, yy - 13), (gx + 20, yy),
                        (gx + 20, yy + 8), (gx, yy - 5), (gx - 20, yy + 8)], fill=col)
        elif glyph == "droplet":
            c.poly([(gx, gy - 30), (gx + 20, gy + 6), (gx - 20, gy + 6)], fill=col)
            c.circle(gx, gy + 6, 20, fill=col)
        elif glyph == "shield_crack":
            c.poly([(gx, gy - 30), (gx + 24, gy - 16), (gx + 24, gy + 8),
                    (gx, gy + 30), (gx - 24, gy + 8), (gx - 24, gy - 16)], fill=darken(col, 0.25))
            c.line(gx - 4, gy - 26, gx + 6, gy - 4, C["BG_DEEP"], 3)
            c.line(gx + 6, gy - 4, gx - 6, gy + 10, C["BG_DEEP"], 3)
            c.line(gx - 6, gy + 10, gx + 4, gy + 28, C["BG_DEEP"], 3)
        elif glyph == "retaliate":
            c.line(gx - 20, gy - 14, gx + 20, gy + 14, col, 6)
            c.line(gx - 20, gy + 14, gx + 20, gy - 14, col, 6)
            c.poly([(gx + 22, gy + 18), (gx + 6, gy + 14), (gx + 16, gy + 4)], fill=col)
            c.poly([(gx - 22, gy - 18), (gx - 6, gy - 14), (gx - 16, gy - 4)], fill=col)

        c.text(cx, top + size + 12, name, size=17, color=C["TEXT"], bold=True, anchor="ct")
        c.text(cx, top + size + 36, line1, size=11, color=C["TEXT_DIM"], anchor="ct")
        c.text(cx, top + size + 53, line2, size=11, color=C["TEXT_DIM"], anchor="ct")

    note(c, 356, "设计约束：图标为 108 × 108 圆角方（内边距 14），几何形 + 字数 ≤ 3 的名称 + 两行规则摘要；")
    note(c, 376, "状态图标统一出现在：玩家/敌人血条下方、以及被作用目标的头顶飘字。", color=C["TEXT"])
    return c


# ══════════════════════════════════════════════════════════
#  图 8：敌人意图 + 玩家状态元素
# ══════════════════════════════════════════════════════════

def fig_intent_status():
    c = Canvas(1100, 560)
    title_block(c, "意图与状态元素 · Intent & Status",
                "意图显示「实际数值 + 目标」（规格 §4.2）；玩家状态含生命 / 护盾 / 能量")

    # ── 意图三种样式 ──
    c.text(36, 104, "敌人意图框（三种）", size=17, color=C["TEXT"], bold=True)
    intents = [
        ("攻击", "攻击玩家：6", "#ff8a7a", "#3a2020", "目标 = 玩家"),
        ("攻击", "攻击守卫：10", "#ff8a7a", "#3a2020", "有嘲讽随从时改指向它"),
        ("防御", "防御：获得 8 护盾", C["SHIELD"], "#1e2f42", "本轮不攻击"),
    ]
    x = 36
    for kind, text, col, bg, desc in intents:
        c.rect(x, 136, 320, 62, fill=bg, stroke=col, sw=2, r=8)
        c.text(x + 16, 152, "意图：" + text, size=17, color=col, bold=True)
        c.text(x + 16, 178, desc, size=12, color=C["TEXT_DIM"])
        x += 340

    note(c, 214, "数值在公开后锁定；玩家召唤嘲讽随从时目标立即更新，但数值不变（规格 §6.6、A18）。")

    # ── 玩家状态元素 ──
    c.text(36, 250, "玩家状态元素", size=17, color=C["TEXT"], bold=True)

    # 生命条
    c.text(36, 284, "生命", size=13, color=C["TEXT_DIM"])
    c.rect(36, 304, 300, 26, fill=C["HP_BG"], r=6)
    c.rect(36, 304, 300, 26, fill=C["HP"], r=6)
    c.text(186, 304, "60 / 60", size=15, color=C["TEXT"], bold=True, anchor="ct")

    # 受伤态
    c.text(380, 284, "受伤后（41 / 60）", size=13, color=C["TEXT_DIM"])
    c.rect(380, 304, 300, 26, fill=C["HP_BG"], r=6)
    c.rect(380, 304, 300 * 41 / 60.0, 26, fill=C["HP"], r=6)
    c.text(530, 304, "41 / 60", size=15, color=C["TEXT"], bold=True, anchor="ct")

    # 护盾
    c.text(724, 284, "护盾（与生命并列显示）", size=13, color=C["TEXT_DIM"])
    c.rect(724, 304, 340, 26, fill=darken(C["SHIELD"], 0.72), r=6)
    c.text(894, 304, "护盾 8", size=15, color=C["SHIELD"], bold=True, anchor="ct")

    # 能量
    c.text(36, 356, "能量 0 ~ 10（当前 3）", size=13, color=C["TEXT_DIM"])
    px = 36
    for i in range(10):
        col = C["ENERGY"] if i < 3 else "#2e3240"
        c.rect(px, 378, 22, 12, fill=col, r=3)
        px += 25
    c.text(px + 10, 378, "能量 3 / 10", size=15, color=C["ENERGY"], bold=True)

    # ── 飘字 ──
    c.text(36, 430, "飘字规范（伤害与效果反馈）", size=17, color=C["TEXT"], bold=True)
    floats = [
        ("-5", C["HP"], 30, "生命伤害，最大字号，向上飘 58px 并淡出"),
        ("护盾 -6", C["SHIELD"], 20, "护盾吸收量，叠在伤害上方"),
        ("能量 +1", C["ENERGY"], 20, "所有回能（回合开始 / 卡牌 / 承伤）"),
        ("护盾 +8", C["SHIELD"], 22, "获得护盾"),
    ]
    x = 36
    for text, col, size, desc in floats:
        c.text(x, 470, text, size=size, color=col, bold=True)
        c.text(x, 470 + size + 10, desc, size=10, color=C["TEXT_DIM"])
        x += 260
    return c


# ══════════════════════════════════════════════════════════
#  图 9：界面状态流转
# ══════════════════════════════════════════════════════════

def fig_flow():
    c = Canvas(1100, 540)
    title_block(c, "界面状态流转 · UI State Flow", "对应规格 §10.1 状态机；方块下标注该阶段输入是否可用")

    def box(x, y, w, h, text, sub, col):
        c.rect(x, y, w, h, fill=darken(col, 0.72), stroke=col, sw=2, r=8)
        c.text(x + w / 2, y + 10, text, size=15, color=C["TEXT"], bold=True, anchor="ct")
        c.text(x + w / 2, y + 32, sub, size=10, color=C["TEXT_DIM"], anchor="ct")

    def arrow(x1, y1, x2, y2, label="", col=None):
        col = col or C["BORDER"]
        c.line(x1, y1, x2, y2, col, 2)
        c.poly([(x2, y2), (x2 - 6, y2 - 9), (x2 + 6, y2 - 9)], fill=col)
        if label:
            c.text((x1 + x2) / 2, y1 - 20, label, size=11, color=C["TEXT_DIM"], anchor="ct")

    box(36, 112, 150, 56, "初始化", "无输入", "#6d7690")
    arrow(186, 140, 246, 140)
    box(252, 112, 170, 56, "玩家回合开始", "无输入（自动）", C["ENERGY"])
    arrow(422, 140, 482, 140)
    box(488, 112, 150, 56, "玩家行动", "可出牌 / 可结束", C["GOOD"])

    box(700, 108, 176, 64, "使用卡牌 → 效果结算", "输入锁定", CARD_COLOR["攻击"])
    arrow(638, 124, 700, 124, "出牌")
    arrow(700, 156, 638, 156, "回到行动")

    box(700, 218, 176, 64, "保留选择", "可保留 / 取消", C["SELECT"])
    arrow(563, 168, 640, 240, "结束回合且手牌非空")
    arrow(640, 250, 563, 176, "取消")

    box(700, 318, 176, 56, "随从自动攻击", "输入锁定", CARD_COLOR["随从"])
    arrow(788, 282, 788, 318)

    box(488, 318, 150, 56, "敌方阶段", "输入锁定", CARD_COLOR["防御"])
    arrow(700, 346, 638, 346)

    arrow(488, 346, 430, 346)
    c.line(430, 346, 430, 196, C["BORDER"], 2)
    c.poly([(430, 196), (424, 205), (436, 205)], fill=C["BORDER"])
    c.text(430, 268, "新回合", size=11, color=C["TEXT_DIM"], anchor="cm")

    box(908, 318, 160, 56, "终局", "锁定全部输入", C["HP"])
    c.text(908, 292, "任何生命变化后检查", size=10, color=C["TEXT_DIM"])

    c.rect(36, 420, 1032, 92, fill=C["PANEL"], stroke=C["BORDER"], sw=1, r=8)
    c.text(52, 434, "输入可用性约定", size=14, color=C["TEXT"], bold=True)
    c.text(52, 458, "· 仅「玩家行动」阶段接受出牌与结束回合；保留选择只接受保留操作，可取消返回。",
           size=12, color=C["TEXT_DIM"])
    c.text(52, 478, "· 效果结算、随从自动攻击、敌方阶段全程锁定输入；动画播放期间同样锁定（_busy）。",
           size=12, color=C["TEXT_DIM"])
    c.text(52, 498, "· 终局后禁止出牌与结束回合；玩法说明弹窗与结算弹窗期间，背景不可操作。",
           size=12, color=C["TEXT_DIM"])
    return c


FIGURES = [
    ("palette", fig_palette),
    ("card_anatomy", fig_card_anatomy),
    ("card_types", fig_card_types),
    ("card_states", fig_card_states),
    ("battle_layout", fig_battle_layout),
    ("hand_layout", fig_hand_layout),
    ("buff_icons", fig_buff_icons),
    ("intent_status", fig_intent_status),
    ("flow_states", fig_flow),
]


def main():
    total = 0
    for name, fn in FIGURES:
        c = fn()
        png, svg = c.save(name)
        png_kb = os.path.getsize(png) / 1024.0
        svg_kb = os.path.getsize(svg) / 1024.0
        total += 2
        print("  %-16s PNG %4dx%-4d %7.1f KB   SVG %6.1f KB" % (name, c.w, c.h, png_kb, svg_kb))
    print("共生成 %d 个文件 → %s" % (total, OUT_DIR))


if __name__ == "__main__":
    main()