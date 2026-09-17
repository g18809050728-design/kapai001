# -*- coding: utf-8 -*-
"""
校验美术资产是否真的可用。

重点不是「文件在不在」，而是：
  1. 背景亮度与层次是否合理（不是一团黑，也不是一片灰）
  2. 暗角是否真的从中心向外渐变
  3. 角色剪影是否有内容（不是空白，也不是一块纯色）
  4. **角色在实际摆放位置上是否看得清**（与背景的亮度差）
  5. 场景中角色之间、角色与 UI 面板是否互相遮挡

运行： python tools/verify_art_assets.py
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")

# 角色在场景中的实际摆放（与 battle_scene.gd 保持一致）
PLACEMENT = {
    "char_adventurer": (390, 190, 300, 420),
    "char_golem": (890, 170, 340, 440),
}

problems = []
checks = 0


def ok(m):
    global checks
    checks += 1
    print("  [OK]   " + m)


def bad(m):
    global checks
    checks += 1
    problems.append(m)
    print("  [FAIL] " + m)


def lum(img):
    return np.asarray(img.convert("L")).astype(np.float32)


# ── 1. 背景 ───────────────────────────────────────────────
print("1. 背景 bg_ruins.png")
bg_path = os.path.join(ART, "bg_ruins.png")
bg = None
if not os.path.exists(bg_path):
    bad("bg_ruins.png 不存在")
else:
    bg = Image.open(bg_path).convert("RGB")
    if bg.size != (1600, 900):
        bad("尺寸 %s，期望 (1600, 900)" % (bg.size,))
    else:
        L = lum(bg)
        mean, std = float(L.mean()), float(L.std())
        if mean < 22:
            bad("背景平均亮度 %.1f 过暗，看不清场景内容" % mean)
        elif mean > 150:
            bad("背景平均亮度 %.1f 过亮，会压制前景 UI" % mean)
        elif std < 10:
            bad("背景亮度标准差 %.1f 过低，缺少层次" % std)
        else:
            ok("尺寸 1600x900，平均亮度 %.1f，层次标准差 %.1f" % (mean, std))
        center = float(L[300:600, 600:1000].mean())
        corner = float(np.mean([L[0:120, 0:120].mean(), L[0:120, 1400:].mean(),
                                L[-120:, 0:120].mean(), L[-120:, 1400:].mean()]))
        if corner >= center:
            bad("四角亮度 %.1f 未低于中心 %.1f，暗角没生效" % (corner, center))
        else:
            ok("暗角生效：四角 %.1f < 中心 %.1f" % (corner, center))

# ── 2. 暗角叠加层 ─────────────────────────────────────────
print("2. 暗角层 vignette.png")
vg_path = os.path.join(ART, "vignette.png")
if not os.path.exists(vg_path):
    bad("vignette.png 不存在")
else:
    vg = Image.open(vg_path)
    if vg.size != (1600, 900) or vg.mode != "RGBA":
        bad("尺寸/通道不符：%s %s（期望 1600x900 RGBA）" % (vg.size, vg.mode))
    else:
        a = np.asarray(vg.split()[3]).astype(np.float32)
        c = float(a[400:500, 760:840].mean())
        e = float(np.mean([a[0:60, 0:60].mean(), a[0:60, -60:].mean(),
                           a[-60:, 0:60].mean(), a[-60:, -60:].mean()]))
        if c > 40:
            bad("中心 alpha %.0f 过高，会把画面压暗" % c)
        elif e < 170:
            bad("边缘 alpha %.0f 过低，暗角几乎不可见" % e)
        else:
            ok("中心 alpha %.0f → 边缘 %.0f，渐变正确" % (c, e))

# ── 3. 角色剪影 ───────────────────────────────────────────
print("3. 角色剪影内容")
chars = {}
for name, (px, py, pw, ph) in PLACEMENT.items():
    p = os.path.join(ART, name + ".png")
    if not os.path.exists(p):
        bad("%s.png 不存在" % name)
        continue
    im = Image.open(p).convert("RGBA")
    if im.size != (pw, ph):
        bad("%s 尺寸 %s，与摆放尺寸 %s 不一致" % (name, im.size, (pw, ph)))
        continue
    a = np.asarray(im.split()[3]).astype(np.float32) / 255.0
    cover = float((a > 0.35).mean())
    if cover < 0.05:
        bad("%s 不透明像素仅 %.1f%%，图形可能是空的" % (name, cover * 100))
        continue
    if cover > 0.80:
        bad("%s 不透明像素 %.1f%%，几乎是一块实心色块" % (name, cover * 100))
        continue
    rgb = np.asarray(im.convert("RGB")).astype(np.float32)
    m = a > 0.6
    L = rgb.mean(axis=2)
    if float(L[m].std()) < 6:
        bad("%s 主体亮度标准差 %.1f 过低，缺少体积感" % (name, float(L[m].std())))
    else:
        ok("%-16s %dx%d  覆盖 %.1f%%  主体亮度 %.1f±%.1f"
           % (name, pw, ph, cover * 100, float(L[m].mean()), float(L[m].std())))
    chars[name] = (im, (px, py, pw, ph))

# ── 4. 角色在背景上是否看得清 ─────────────────────────────
print("4. 角色与背景的可辨识度")
if bg is not None:
    Lb = lum(bg)
    for name, (im, (px, py, pw, ph)) in chars.items():
        patch = Lb[py:py + ph, px:px + pw]
        a = np.asarray(im.split()[3]).astype(np.float32) / 255.0
        m = a > 0.6
        cl = float((np.asarray(im.convert("L")).astype(np.float32))[m].mean())
        bl = float(patch[m].mean())
        d = abs(cl - bl)
        if d < 18:
            bad("%s 与背景亮度差仅 %.1f，会糊在一起" % (name, d))
        else:
            ok("%-16s 主体亮度 %.1f vs 背景 %.1f，差 %.1f" % (name, cl, bl, d))
else:
    bad("背景缺失，跳过可辨识度检查")

# ── 5. 角色之间是否重叠 ───────────────────────────────────
print("5. 场景占位冲突")
boxes = [(n, PLACEMENT[n]) for n in PLACEMENT if n in chars]
for i in range(len(boxes)):
    for j in range(i + 1, len(boxes)):
        n1, (x1, y1, w1, h1) = boxes[i]
        n2, (x2, y2, w2, h2) = boxes[j]
        if x1 < x2 + w2 and x2 < x1 + w1 and y1 < y2 + h2 and y2 < y1 + h1:
            bad("%s 与 %s 的占位矩形重叠" % (n1, n2))
if not problems or all("重叠" not in p for p in problems):
    ok("两个角色占位互不重叠")

# 角色不得压到左右两侧的状态面板（x 20..320 与 1280..1580）
for name, (px, py, pw, ph) in PLACEMENT.items():
    if px < 320:
        bad("%s 左边界 %d 压到左侧玩家面板（x<320）" % (name, px))
    if px + pw > 1280:
        bad("%s 右边界 %d 压到右侧敌人面板（x>1280）" % (name, px + pw))
if all(PLACEMENT[n][0] >= 320 and PLACEMENT[n][0] + PLACEMENT[n][2] <= 1280 for n in PLACEMENT
       if n in chars):
    ok("两个角色均落在中央场地内，不遮挡两侧状态面板")

print()
print("=" * 62)
print("检查项 %d，失败 %d" % (checks, len(problems)))
for p in problems:
    print("  - " + p)
sys.exit(1 if problems else 0)
