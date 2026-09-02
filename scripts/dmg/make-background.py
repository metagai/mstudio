#!/usr/bin/env python3
"""DMG 那扇窗的背景图。

## 为什么要有

之前 DMG 里 `/Applications` 软链**一直都在** —— 缺的只是"告诉他往哪拖"。
用户双击打开看到的是 Finder 默认视图里两个图标，没有任何引导：
装不装得上，全看他见没见过别的 Mac 软件。

## 为什么一个字都不写

产品支持中/英/西三种语言，而 DMG 背景**只有一张图**。
写英文，中文用户看到一句外语；三语并排，那一屏就不高级了。
一个箭头三种语言都读得懂 —— 这也是 Figma / Arc / Slack 的做法。

## 尺寸

窗口 660×420（内容区）。图标 128，两个中心分别在 x=180 / x=480，y=196。
`tiffutil` 把 1x 和 2x 合成一张 TIFF，Retina 上才不糊。
"""
from PIL import Image, ImageDraw

W, H = 660, 400
PAPER = (251, 250, 248)      # surface-base 亮 #FBFAF8，和 app 自己那一屏同一张纸
ARROW = (183, 179, 172)      # 安静的灰：它是路标，不是主角
# **配平的是"图标 + 文字标签"整组，不是图标本身。**
# 上一版按图标中心居中，于是标签把整组往下拽，底下空出一大片。
# 组高 = 图标 128 + 间距 ~12 + 标签 ~16 ≈ 156，组中心要落在 H/2。
LEFT_X, RIGHT_X, ICON_Y = 180, 480, 186


def render(scale: int) -> Image.Image:
    im = Image.new("RGB", (W * scale, H * scale), PAPER)
    d = ImageDraw.Draw(im)

    def s(v: float) -> float:
        return v * scale

    # 箭头：从 app 那一侧指向 Applications 那一侧，避开两个图标各自的地盘。
    #
    # **细、短、圆头。** 上一版又长又细、末端一个实心三角，
    # 像剪贴画；它是路标，不该比它指的两样东西还显眼。
    y = s(ICON_Y)
    x0, x1 = s(LEFT_X + 118), s(RIGHT_X - 112)
    w = max(1, round(s(3)))
    d.line([(x0, y), (x1, y)], fill=ARROW, width=w)
    # 圆头：两端各补一个圆点，缩回 1x 时不会露出方角。
    for x in (x0, x1):
        r = w / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=ARROW)
    # 箭头用两笔线画，和杆同一个粗细 —— 实心三角在这个尺寸上太重。
    # **头要撑得住杆**：上一版杆 104pt、头 15pt，比例失衡，像根拉长的线。
    head = s(19)
    for dy in (-1, 1):
        d.line([(x1 - head, y + dy * head * 0.62), (x1, y)], fill=ARROW, width=w)
        r = w / 2
        d.ellipse([x1 - head - r, y + dy * head * 0.62 - r,
                   x1 - head + r, y + dy * head * 0.62 + r], fill=ARROW)
    return im


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    for scale in (1, 2):
        suffix = "" if scale == 1 else "@2x"
        render(scale).save(f"{out}/background{suffix}.png")
    print(f"wrote {out}/background.png + background@2x.png")
