# -*- coding: utf-8 -*-
"""
校验设计配图是否真的可用（而不是「文件存在」就算过）。

检查项：
  1. PNG 能解码，尺寸符合预期
  2. 墨迹占比在合理区间（不是空白，也不是糊成一片）
  3. 内容边界留有余量 —— 若内容贴到画布边缘，说明有元素被裁切
  4. SVG 是合法 XML，且元素数量与 PNG 复杂度相称
  5. 中文字形确实渲染出来了（与「缺字回退」的渲染做对比）

运行： python tools/verify_design_assets.py
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIG_DIR = os.path.join(ROOT, "docs", "design")

EXPECTED = {
    "palette": (1100, 780),
    "card_anatomy": (1100, 700),
    "card_types": (1100, 420),
    "card_states": (1100, 470),
    "battle_layout": (1224, 810),
    "hand_layout": (1100, 560),
    "buff_icons": (1100, 430),
    "intent_status": (1100, 560),
    "flow_states": (1100, 540),
}

BG = (0x14, 0x15, 0x18)   # 画布背景色
problems = []
checks = 0


def ok(msg):
    global checks
    checks += 1
    print("  [OK]   " + msg)


def bad(msg):
    global checks
    checks += 1
    problems.append(msg)
    print("  [FAIL] " + msg)


# ── 1~3. PNG 内容检查 ─────────────────────────────────────
print("1. PNG 内容与边界")
for name, (ew, eh) in EXPECTED.items():
    path = os.path.join(FIG_DIR, name + ".png")
    if not os.path.exists(path):
        bad("%s.png 不存在" % name)
        continue
    img = Image.open(path).convert("RGB")
    if img.size != (ew, eh):
        bad("%s.png 尺寸 %s，期望 %s" % (name, img.size, (ew, eh)))
        continue
    a = np.asarray(img).astype(int)
    diff = np.abs(a - np.array(BG)).sum(axis=2)
    mask = diff > 14
    ratio = mask.mean()
    if ratio < 0.01:
        bad("%s.png 墨迹占比仅 %.3f，疑似空白" % (name, ratio))
        continue
    # 布局类图本来就大片铺满，用「唯一色数」判断是否退化成糊成一片更准确
    colors = len(np.unique(a.reshape(-1, 3), axis=0))
    if colors < 12:
        bad("%s.png 只有 %d 种颜色，疑似内容缺失" % (name, colors))
        continue
    ys, xs = np.where(mask)
    left, top = int(xs.min()), int(ys.min())
    right, bottom = ew - 1 - int(xs.max()), eh - 1 - int(ys.max())
    margin = min(left, top, right, bottom)
    if margin < 3:
        bad("%s.png 内容贴边（边距 L%d T%d R%d B%d），可能有元素被裁切"
            % (name, left, top, right, bottom))
    else:
        ok("%-15s %dx%d  墨迹 %.1f%%  色数 %4d  最小边距 %dpx"
           % (name, ew, eh, ratio * 100, colors, margin))

# ── 4. SVG 合法性 ─────────────────────────────────────────
print("2. SVG 合法性与元素数量")
for name in EXPECTED:
    path = os.path.join(FIG_DIR, name + ".svg")
    if not os.path.exists(path):
        bad("%s.svg 不存在" % name)
        continue
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        bad("%s.svg XML 非法：%s" % (name, e))
        continue
    root = tree.getroot()
    n = len(list(root.iter()))
    texts = len([e for e in root.iter() if e.tag.endswith("text")])
    if n < 20:
        bad("%s.svg 元素过少（%d），疑似内容缺失" % (name, n))
    elif texts < 4:
        bad("%s.svg 文本元素过少（%d）" % (name, texts))
    else:
        ok("%-15s 元素 %4d 个，其中文本 %3d 条" % (name, n, texts))

# ── 5. 中文字形是否真的画出来了 ───────────────────────────
print("3. 中文字形渲染检查")
SAMPLE = "力量中毒蓄势"
msyh = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 48)
try:
    latin = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 48)
    have_latin = True
except Exception:
    have_latin = False


def render(font):
    im = Image.new("L", (400, 80), 0)
    d = ImageDraw.Draw(im)
    d.text((6, 10), SAMPLE, font=font, fill=255)
    return np.asarray(im).astype(int)


a = render(msyh)
if a.max() == 0:
    bad("微软雅黑渲染中文得到全黑图像 —— 字体加载失败")
else:
    ok("微软雅黑渲染「%s」有墨迹（最大灰度 %d）" % (SAMPLE, a.max()))

if have_latin:
    b = render(latin)
    # 缺字回退通常画成空心方框或干脆不画，与真字形差异明显
    diff_ratio = (np.abs(a - b) > 60).mean()
    if diff_ratio < 0.02:
        bad("中文字形与拉丁字体的缺字渲染过于接近（差异 %.3f），疑似渲染成占位方框" % diff_ratio)
    else:
        ok("中文字形与缺字渲染差异 %.1f%%，确认是真实字形" % (diff_ratio * 100))
else:
    ok("未找到 arial.ttf，跳过缺字对比")

# ── 4. 布局图坐标 vs 真实实现 ─────────────────────────────
print("4. 布局图坐标是否等于实现中的坐标")
scene = os.path.join(ROOT, "src", "ui", "battle_scene.gd")
gen = os.path.join(ROOT, "tools", "make_design_assets.py")
if os.path.exists(scene):
    src = open(scene, encoding="utf-8").read()
    rects = set()
    for m in re.finditer(r'Rect2\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\)', src):
        rects.add(tuple(int(float(g)) for g in m.groups()))
    for m in re.finditer(r'Rect2\(\s*0\s*,\s*0\s*,\s*VIEW\.x\s*,\s*([\d.]+)\s*\)', src):
        rects.add((0, 0, 1600, int(float(m.group(1)))))
    vecs = set()
    for m in re.finditer(r'Vector2\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)', src):
        vecs.add(tuple(int(float(g)) for g in m.groups()))

    fig_src = open(gen, encoding="utf-8").read()
    block = fig_src.split("def fig_battle_layout()")[1].split("\ndef ")[0]
    fig_rects = []
    for m in re.finditer(r'R\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,', block):
        fig_rects.append(tuple(int(float(g)) for g in m.groups()))

    if not fig_rects:
        bad("未能从布局图代码解析出任何矩形")
    else:
        miss = []
        for x, y, w, h in fig_rects:
            if (x, y, w, h) in rects:
                continue
            if (x, y) in vecs and (w, h) in vecs:
                continue
            miss.append((x, y, w, h))
        if miss:
            for r in miss:
                bad("布局图中的 %s 在 battle_scene.gd 中找不到对应坐标" % (r,))
        else:
            ok("布局图 %d 个区域的坐标全部能在 battle_scene.gd 中找到对应" % len(fig_rects))

# ── 汇总 ──────────────────────────────────────────────────
print()
print("=" * 62)
print("检查项 %d，失败 %d" % (checks, len(problems)))
for p in problems:
    print("  - " + p)
sys.exit(1 if problems else 0)
