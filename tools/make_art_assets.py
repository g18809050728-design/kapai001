# -*- coding: utf-8 -*-
"""
生成「遗迹 · 自然」风格的美术资产。

美术方向：
    暖色石灰岩 + 羊皮纸 +土性颜料色；用环境与光影代替面板边框。
    所有形状在 2~4 倍分辨率下绘制再 LANCZOS 缩小，保证边缘柔和自然。

产出（assets/art/）：
    bg_ruins.png        1600×900   石室背景（拱门 / 石柱 / 地面 / 火光 / 颗粒）
    vignette.png        1600×900   暗角叠加（RGBA，中心透明）
    char_adventurer.png  300×420   冒险者（兜帽剪影 + 轮廓光）
    char_golem.png       340×440   练习魔像（石块躯干 + 余烬眼）

运行： python tools/make_art_assets.py
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "art")

# ── 与 src/ui/palette.gd 对应的色值 ─────────────────────────
SKY_TOP     = (0x17, 0x13, 0x10)
SKY_MID     = (0x24, 0x1d, 0x17)
STONE_WALL  = (0x32, 0x2a, 0x22)
STONE_LIT   = (0x45, 0x39, 0x2c)
STONE_DARK  = (0x1a, 0x15, 0x11)
FLOOR_NEAR  = (0x2e, 0x26, 0x1d)
FLOOR_FAR   = (0x22, 0x1c, 0x16)
TORCH       = (0xff, 0xa8, 0x4a)

CLOTH       = (0x4c, 0x5b, 0x46)
CLOTH_LIT   = (0x92, 0xa2, 0x78)
CLOTH_DARK  = (0x31, 0x3a, 0x2c)
GOLD        = (0xd9, 0xa4, 0x41)

G_STONE     = (0x5d, 0x59, 0x50)
G_STONE_HI  = (0x86, 0x81, 0x74)
G_STONE_LO  = (0x3a, 0x37, 0x31)
MOSS        = (0x4e, 0x6b, 0x3f)
EMBER       = (0xff, 0x8b, 0x3a)


# ══════════════════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════════════════

def linear_gradient(w, h, top, bottom):
    """竖直渐变，返回 float32 RGB 数组。"""
    t = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None, None]
    a = np.array(top, dtype=np.float32)[None, None, :]
    b = np.array(bottom, dtype=np.float32)[None, None, :]
    return np.repeat(a * (1 - t) + b * t, w, axis=1)


def radial_mask(w, h, cx, cy, radius, softness=2.0):
    """径向衰减遮罩（0~1），softness 越大边缘越柔。"""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / max(radius, 1e-6)
    m = np.clip(1.0 - d, 0.0, 1.0) ** softness
    return m


def add_glow(arr, w, h, cx, cy, radius, color, strength, softness=2.2):
    """叠加一团径向暖光。"""
    m = radial_mask(w, h, cx, cy, radius, softness)[:, :, None]
    col = np.array(color, dtype=np.float32)[None, None, :]
    return arr + m * col * strength


def vignette_mask(w, h, strength=0.55, power=1.7):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx - w / 2) / (w / 2)
    ny = (yy - h / 2) / (h / 2)
    r = np.sqrt(nx * nx + ny * ny) / 1.4142
    return np.clip(r, 0, 1) ** power * strength


def grain(w, h, amount=4.0, seed=7):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, amount, (h, w, 1)).astype(np.float32)
    return np.repeat(n, 3, axis=2)


def to_image(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def soft_shadow(size, draw_fn, blur=14, alpha=120):
    """把 draw_fn 画在一张透明层上，模糊后作为阴影返回。"""
    S = 2
    layer = Image.new("L", (size[0] * S, size[1] * S), 0)
    d = ImageDraw.Draw(layer)
    draw_fn(d, S)
    layer = layer.resize(size, Image.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    a = layer.point(lambda v: int(v * alpha / 255))
    out.putalpha(a)
    return out


# ══════════════════════════════════════════════════════════
#  背景：石室
# ══════════════════════════════════════════════════════════

def make_background():
    S = 2
    W, H = 1600 * S, 900 * S
    arr = linear_gradient(W, H, SKY_TOP, STONE_WALL)
    # 下半段更暖（地面反光）
    floor_y = int(H * 0.60)
    arr[floor_y:] = linear_gradient(W, H - floor_y, STONE_WALL, FLOOR_NEAR)

    img = to_image(arr)
    d = ImageDraw.Draw(img, "RGBA")

    def R(x, y, w, h, fill, radius=0):
        box = [x * S, y * S, (x + w) * S, (y + h) * S]
        if radius:
            d.rounded_rectangle(box, radius=radius * S, fill=fill)
        else:
            d.rectangle(box, fill=fill)

    def POLY(pts, fill):
        d.polygon([(px * S, py * S) for px, py in pts], fill=fill)

    # 后墙
    R(260, 110, 1080, 500, (*STONE_WALL, 255))
    # 中央拱门（更深的通道）
    R(690, 250, 220, 360, (*STONE_DARK, 255), radius=110)
    R(690, 250, 220, 120, (*STONE_DARK, 255))
    # 远柱
    for x in (430, 1130):
        R(x, 150, 42, 460, (*STONE_LIT, 190), radius=6)
        R(x + 34, 150, 8, 460, (0, 0, 0, 60))
    # 近柱（左右各一）
    for x, light in ((300, 210), (1240, 150)):
        R(x, 120, 78, 500, (*STONE_LIT, light), radius=8)
        R(x + 6, 130, 10, 480, (255, 240, 210, 26))   # 左缘轮廓光
        R(x + 66, 120, 12, 500, (0, 0, 0, 70))
    # 拱顶
    R(240, 96, 1120, 46, (0x1d, 0x18, 0x13, 255), radius=18)
    # 地面
    fh = H - floor_y
    floor = linear_gradient(W, fh, FLOOR_FAR, FLOOR_NEAR)
    img.paste(to_image(floor), (0, floor_y))
    d = ImageDraw.Draw(img, "RGBA")
    # 地面透视线（很淡）
    for i in range(-6, 7):
        x0 = W / 2 + i * 190 * S
        d.line([(x0, floor_y), (W / 2 + i * 90 * S, H)], fill=(255, 225, 190, 10), width=max(1, S))
    d.line([(0, floor_y), (W, floor_y)], fill=(255, 225, 190, 20), width=max(1, S))

    # 石缝
    for (x1, y1, x2, y2) in [(300, 300, 690, 420), (910, 380, 1240, 300),
                             (520, 180, 560, 560), (1050, 200, 1020, 560)]:
        d.line([(x1 * S, y1 * S), (x2 * S, y2 * S)], fill=(0, 0, 0, 46), width=max(1, 2 * S))

    arr = np.asarray(img).astype(np.float32)
    # 两团火把暖光
    arr = add_glow(arr, W, H, 470 * S, 300 * S, 360 * S, TORCH, 0.30)
    arr = add_glow(arr, W, H, 1130 * S, 290 * S, 330 * S, TORCH, 0.22)
    arr = add_glow(arr, W, H, W / 2, 150 * S, 620 * S, (0x6a, 0x7a, 0x90), 0.06)
    # 颗粒
    arr = arr + grain(W, H, 3.4)
    # 暗角
    arr = arr * (1.0 - vignette_mask(W, H, 0.62)[:, :, None])

    out = to_image(arr).resize((1600, 900), Image.LANCZOS)
    out.save(os.path.join(OUT_DIR, "bg_ruins.png"))
    return out


def make_vignette():
    W, H = 1600, 900
    m = vignette_mask(W, H, strength=1.0, power=2.1)
    m = np.clip(m * 1.15, 0, 1)
    # 底部再压一层，让手牌区更沉
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    m = np.clip(m + np.clip((yy - 0.68) / 0.32, 0, 1) ** 1.5 * 0.45, 0, 1)
    alpha = (m * 255 * 0.92).astype(np.uint8)
    img = Image.new("RGBA", (W, H), (0x0e, 0x0b, 0x08, 0))
    img.putalpha(Image.fromarray(alpha, "L"))
    img.save(os.path.join(OUT_DIR, "vignette.png"))
    return img


# ══════════════════════════════════════════════════════════
#  角色
# ══════════════════════════════════════════════════════════

def make_adventurer():
    W, H, S = 300, 420, 4
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")

    def P(pts, fill):
        d.polygon([(x * S, y * S) for x, y in pts], fill=fill)

    def E(box, fill):
        d.ellipse([box[0] * S, box[1] * S, box[2] * S, box[3] * S], fill=fill)

    # 斗篷主体
    P([(150, 128), (196, 168), (216, 268), (222, 372), (78, 372), (84, 268), (104, 168)], CLOTH_DARK)
    P([(150, 128), (196, 168), (216, 268), (222, 372), (150, 372), (150, 128)], CLOTH)
    # 下摆弧
    E((78, 344, 222, 396), CLOTH)
    E((78, 344, 150, 396), CLOTH_DARK)
    # 左侧轮廓光
    P([(150, 130), (104, 170), (86, 268), (80, 362), (92, 362), (100, 268), (116, 174), (150, 140)], CLOTH_LIT)
    # 兜帽
    E((104, 96, 196, 190), CLOTH)
    P([(108, 146), (192, 146), (176, 194), (124, 194)], CLOTH)
    E((104, 96, 196, 170), CLOTH)
    # 帽内阴影
    E((122, 118, 178, 172), (0x10, 0x0e, 0x0b, 255))
    # 眼部微光
    E((136, 138, 144, 146), (*GOLD, 210))
    E((158, 138, 166, 146), (*GOLD, 210))
    # 帽檐轮廓光
    P([(106, 128), (104, 156), (112, 156), (114, 130)], CLOTH_LIT)
    # 腰带
    P([(96, 258), (206, 258), (208, 274), (94, 274)], (0x5a, 0x45, 0x2c, 230))
    E((140, 254, 162, 278), (*GOLD, 235))
    # 木杖
    P([(224, 96), (232, 96), (240, 380), (232, 380)], (0x5b, 0x45, 0x30, 255))
    P([(224, 96), (228, 96), (234, 380), (230, 380)], (0x7a, 0x5e, 0x42, 255))
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([216 * S, 60 * S, 244 * S, 90 * S], fill=(*GOLD, 235))
    gd.ellipse([206 * S, 50 * S, 254 * S, 100 * S], fill=(*GOLD, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(6 * S))
    img = Image.alpha_composite(img, glow)

    # 暗色外描边：让剪影在任何背景上都能与背景分离（alpha 压在 0.6 以下，不影响主体测色）
    halo = img.split()[3].filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(9 * S))
    halo_layer = Image.new("RGBA", img.size, (0x0d, 0x0a, 0x07, 0))
    halo_layer.putalpha(halo.point(lambda v: int(v * 0.55)))
    img = Image.alpha_composite(halo_layer, img)

    sh = soft_shadow((W * S, H * S), lambda dd, s: dd.ellipse(
        [70 * s, 366 * s, 232 * s, 396 * s], fill=255), blur=10, alpha=150)
    out = Image.alpha_composite(sh, img).resize((W, H), Image.LANCZOS)
    out.save(os.path.join(OUT_DIR, "char_adventurer.png"))
    return out


def make_golem():
    W, H, S = 340, 440, 4
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")

    def B(box, fill, r=0):
        if r:
            d.rounded_rectangle([box[0] * S, box[1] * S, box[2] * S, box[3] * S], radius=r * S, fill=fill)
        else:
            d.rectangle([box[0] * S, box[1] * S, box[2] * S, box[3] * S], fill=fill)

    def P(pts, fill):
        d.polygon([(x * S, y * S) for x, y in pts], fill=fill)

    # 腿
    B((116, 330, 158, 400), G_STONE_LO, 10)
    B((182, 330, 224, 400), G_STONE_LO, 10)
    # 躯干
    P([(96, 150), (244, 150), (256, 340), (84, 340)], G_STONE)
    B((96, 150, 244, 340), G_STONE, 0)
    # 躯干左缘轮廓光
    P([(96, 152), (116, 152), (108, 338), (86, 338)], G_STONE_HI)
    # 胸口核心
    B((146, 214, 194, 262), (0x2c, 0x29, 0x24, 255), 12)
    d.ellipse([152 * S, 220 * S, 188 * S, 256 * S], fill=(*EMBER, 235))
    # 肩
    B((74, 132, 120, 186), G_STONE_LO, 12)
    B((220, 132, 266, 186), G_STONE_LO, 12)
    # 手臂
    B((62, 176, 104, 320), G_STONE_LO, 14)
    B((236, 176, 278, 320), G_STONE_LO, 14)
    # 头
    B((118, 76, 222, 152), G_STONE_HI, 14)
    P([(118, 120), (222, 120), (222, 152), (118, 152)], G_STONE_HI)
    # 眼部余烬
    d.ellipse([140 * S, 104 * S, 162 * S, 124 * S], fill=(*EMBER, 255))
    d.ellipse([178 * S, 104 * S, 200 * S, 124 * S], fill=(*EMBER, 255))
    # 嘴缝
    B((150, 132, 190, 138), (0x24, 0x21, 0x1d, 255), 3)
    # 裂纹
    for pts in ([(130, 170), (146, 210), (138, 250), (152, 292)],
                [(214, 166), (200, 206), (212, 242), (198, 286)]):
        d.line([(x * S, y * S) for x, y in pts], fill=(0x2f, 0x2c, 0x27, 220), width=2 * S)
    # 苔藓
    for (cx, cy, rx, ry) in [(86, 336, 22, 10), (250, 338, 20, 9), (110, 148, 16, 8),
                             (236, 196, 14, 7), (128, 396, 24, 10)]:
        d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S], fill=(*MOSS, 235))
    # 眼与核心外发光
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([130 * S, 94 * S, 210 * S, 134 * S], fill=(*EMBER, 90))
    gd.ellipse([140 * S, 206 * S, 200 * S, 270 * S], fill=(*EMBER, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(9 * S))
    img = Image.alpha_composite(glow, img)

    sh = soft_shadow((W * S, H * S), lambda dd, s: dd.ellipse(
        [56 * s, 384 * s, 284 * s, 416 * s], fill=255), blur=12, alpha=160)
    out = Image.alpha_composite(sh, img).resize((W, H), Image.LANCZOS)
    out.save(os.path.join(OUT_DIR, "char_golem.png"))
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in [("bg_ruins", make_background), ("vignette", make_vignette),
                     ("char_adventurer", make_adventurer), ("char_golem", make_golem)]:
        im = fn()
        p = os.path.join(OUT_DIR, name + ".png")
        print("  %-18s %-11s %6.1f KB" % (name, "%dx%d" % im.size, os.path.getsize(p) / 1024.0))
    print("→ %s" % OUT_DIR)


if __name__ == "__main__":
    main()
