#!/usr/bin/env python3
"""从 app_icon.svg 的几何参数生成 Android 图标与开屏图。

本机无 SVG 栅格化器（rsvg/inkscape/cairosvg 均缺），图案又是简单的
圆弧+圆点，故按 SVG 中的精确数值用 PIL 4x 超采样栅格化。
改设计时同步修改本文件的常量（数值须与 app_icon.svg 一致）。

产物（写入 ../android/app/src/main/res/）：
- mipmap-<d>/ic_launcher.png            legacy 启动器图标（白底圆角+涟漪）
- mipmap-<d>/ic_launcher_foreground.png 自适应图标前景（涟漪缩入安全区）
- drawable-<d>/splash_logo.png          开屏居中 logo（透明底）
"""
import math
import os
from PIL import Image, ImageDraw

# ---- app_icon.svg 几何（viewBox 1024x1024）----
CANVAS = 1024
CX = CY = 512
INK = (76, 65, 230, 255)  # #4C41E6
CORNER = 230
DOT_R = 90
# (半径, 线宽, 起点角°, 终点角°)；sweep-flag=1 即角度顺时针增大
ARCS = [
    (190, 60, 15.0, 255.0),
    (310, 44, 45.0, 285.0),
    (412, 32, 75.0, 315.0),
]

# 自适应前景缩放：108dp 画布经系统遮罩后只显示中央 72dp。
# 设计涟漪直径占画布 856/1024=0.836；scale=0.52 时涟漪在最终图标中
# 约占 0.836*0.52*108/72 = 65%（与主流图标留白观感一致；0.73 会到 92%
# 顶边——108 画布里的"安全圆"映射到成品图标本身就是 92%，不能当留白用）。
FG_SCALE = 0.52
# legacy 位图不经遮罩、整张即成品图标：scale=0.78 时涟漪约占 65%。
LEGACY_SCALE = 0.78

SS = 4  # 超采样倍数
HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "android", "app", "src", "main", "res")

DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}
LEGACY_DP = 48      # legacy 启动器图标 48dp
FOREGROUND_DP = 108  # 自适应图标 108dp
SPLASH_DP = 160     # 开屏 logo 宽 160dp
SPLASH_INK = (255, 255, 255, 255)  # 开屏 logo 白色（App 为深色专用，背景 #0B0E12）


def draw_logo(img, scale=1.0, ink=INK):
    """在给定（透明）画布上绘制涟漪+圆点，scale 相对 1024 设计坐标。

    不用 PIL 自带 arc(width=)：它对弧的折线采样很粗，粗线下末端会短一截，
    自绘圆头补点会与弧身脱节（看起来像一串孤立圆点）。改为手工构造
    等宽弧面多边形（外弧→内弧闭合填充）+ 两端圆头，0.25° 密采样。
    """
    d = ImageDraw.Draw(img)
    size = img.size[0]
    s = size / CANVAS
    cx = cy = CX * s

    def polar(r, deg):
        rad = math.radians(deg)
        return cx + r * math.cos(rad), cy + r * math.sin(rad)

    for r_design, w_design, a0, a1 in ARCS:
        r = r_design * scale * s
        w = w_design * scale * s
        steps = max(2, int(round((a1 - a0) / 0.25)))
        outer = [polar(r + w / 2, a0 + (a1 - a0) * i / steps)
                 for i in range(steps + 1)]
        inner = [polar(r - w / 2, a1 - (a1 - a0) * i / steps)
                 for i in range(steps + 1)]
        d.polygon(outer + inner, fill=ink)
        # SVG stroke-linecap=round：弧两端补圆头
        cap = w / 2
        for deg in (a0, a1):
            ex, ey = polar(r, deg)
            d.ellipse((ex - cap, ey - cap, ex + cap, ey + cap), fill=ink)

    dot = DOT_R * scale * s
    d.ellipse((cx - dot, cy - dot, cx + dot, cy + dot), fill=ink)


def render_master(size, with_plate, fg_scale=1.0, ink=INK):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if with_plate:
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((0, 0, size - 1, size - 1), radius=CORNER / CANVAS * size,
                            fill=(255, 255, 255, 255))
    draw_logo(img, fg_scale, ink)
    return img


def save_scaled(master, px, path):
    out = master.resize((px, px), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)


def main():
    full = render_master(CANVAS * SS, with_plate=True, fg_scale=LEGACY_SCALE)
    logo = render_master(CANVAS * SS, with_plate=False, ink=SPLASH_INK)
    fg = render_master(CANVAS * SS, with_plate=False, fg_scale=FG_SCALE)

    for name, mult in DENSITIES.items():
        save_scaled(full, round(LEGACY_DP * mult),
                    os.path.join(RES, f"mipmap-{name}", "ic_launcher.png"))
        save_scaled(fg, round(FOREGROUND_DP * mult),
                    os.path.join(RES, f"mipmap-{name}", "ic_launcher_foreground.png"))
        save_scaled(logo, round(SPLASH_DP * mult),
                    os.path.join(RES, f"drawable-{name}", "splash_logo.png"))
    print("icons generated")


if __name__ == "__main__":
    main()
