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

# **内容区，不是窗口。** AppleScript 的 `bounds` 含标题栏（实测 29pt），
# 上一版按 660×400 排版，而真正能画的只有 660×370 —— 背景底下 30pt 被切掉，
# 整组版心往下坠了半格。这个数是从真机截图上量出来的。
W, H = 660, 370
PAPER = (251, 250, 248)      # surface-base 亮 #FBFAF8，和 app 自己那一屏同一张纸
# 片基：**中性暖灰，不是近黑**。
# 近黑那一版和 app 图标在抢注意力 —— 它是路标，不该比它指的两样东西更响。
FILM = (150, 146, 138)
# **配平的是"图标 + 文字标签"整组，不是图标本身。**
# 上一版按图标中心居中，于是标签把整组往下拽，底下空出一大片。
# 组高 = 图标 128 + 间距 ~12 + 标签 ~16 ≈ 156，组中心要落在 H/2。
# 组高 = 图标 128 + 间距 ~12 + 标签 ~16 ≈ 156，组中心落在 H/2=185 →
# 图标中心 = 185 - 156/2 + 64 = 171。
LEFT_X, RIGHT_X, ICON_Y = 180, 480, 171


def film_strip(d: ImageDraw.ImageDraw, s, y: float, x0: float, x1: float) -> None:
    """两个图标之间那一段胶片，外加一个指方向的角标。

    ## 为什么是两件东西

    一开始把片基右端收成一个尖当箭头用 —— 放大看像支铅笔：
    **真胶片不会收成尖**，那一下同时毁了"像胶片"和"像箭头"两件事。

    拆开之后各做一件事：**胶片说"这是片子"，角标说"往这边"**。
    角标是两笔线，比实心三角轻得多 —— 它是路标，不该比它指的两样东西更响。

    ## 齿孔和画格

    真胶片一格对四个齿孔，孔是方的、贴着边，格线横贯整条、齿孔压在它上面。
    尺寸按画格来定，不是随手排 —— 随手排出来是打孔纸带，不是胶片。
    """
    half = s(14)
    chevron_room = s(24)
    body_right = x1 - chevron_room

    # 片基整段用整数格，末尾不留一条切剩的窄条。
    frame_w = s(30)
    frames = max(2, round((body_right - x0) / frame_w))
    frame_w = (body_right - x0) / frames

    d.rectangle([x0, y - half, body_right, y + half], fill=FILM)

    hole_w, hole_h, r = s(4.5), s(3.4), s(1)
    pitch = frame_w / 4                # 一格四孔
    inset = s(3.2)
    x = x0 + pitch / 2
    while x + hole_w < body_right:
        for cy in (y - half + inset + hole_h / 2, y + half - inset - hole_h / 2):
            d.rounded_rectangle(
                [x, cy - hole_h / 2, x + hole_w, cy + hole_h / 2], radius=r, fill=PAPER)
        x += pitch

    # 格线横贯整条，齿孔压在它上面 —— 这是它读起来像胶片的关键一笔。
    for k in range(1, frames):
        gx = x0 + frame_w * k
        d.line([(gx, y - half), (gx, y + half)], fill=PAPER, width=max(1, round(s(1))))

    # 角标：两笔线，和格线同一个粗细族。
    w = max(1, round(s(2.5)))
    tipx, arm = x1, s(11)
    for dy in (-1, 1):
        d.line([(tipx - arm, y + dy * arm), (tipx, y)], fill=FILM, width=w)
    for dy in (-1, 1):   # 端点补圆，缩回 1x 不露方角
        for px, py in ((tipx - arm, y + dy * arm), (tipx, y)):
            rr = w / 2
            d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=FILM)


def render(scale: int) -> Image.Image:
    im = Image.new("RGB", (W * scale, H * scale), PAPER)
    d = ImageDraw.Draw(im)

    def s(v: float) -> float:
        return v * scale

    # **一段胶片，不是一根箭头。**
    #
    # 这个产品讲的就是"一句话变成一条片子"，而安装那一屏是他和它的第一次照面。
    # 一根通用箭头谁家都能用；一段带齿孔的胶片只有我们能用。
    #
    # 它仍然要**说清方向**，所以右端收成一个尖 —— 像片头的引带。
    # 而且要**安静**：它是路标，不该比它指的那两样东西更响。
    film_strip(d, s, y=s(ICON_Y), x0=s(LEFT_X + 86), x1=s(RIGHT_X - 86))
    return im


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    for scale in (1, 2):
        suffix = "" if scale == 1 else "@2x"
        render(scale).save(f"{out}/background{suffix}.png")
    print(f"wrote {out}/background.png + background@2x.png")
