#!/usr/bin/env python3
"""把品牌 mark 放进 macOS 的图标形状里，生成 AppIcon.icns。

## 之前是什么样

`AppIcon.icns` 里每一档都是**直角方块**：没有圆角、没有内缩、没有阴影
（1024 那张四个角是 `(11,18,16,255)` —— 不透明的黑）。

macOS 上所有图标都是圆角超椭圆，在画布里内缩一圈、下方压一层阴影。
一个直角方块摆在 Dock 里，是"这个 app 没做完"最早也最显眼的信号 ——
用户在打开产品之前就看见了。

## 形状不是拍的，是量的

拿系统自带 app 的图标，只认完全不透明的像素（避开阴影）量出来：

    本体 814×814 / 1024 画布（四周各内缩 105）
    超椭圆指数 n ≈ 5.1–5.3

所以这里 `BODY = 814`、`N = 5.2`。**不是"看起来差不多"，是对齐平台。**

## 为什么不是纯透明底

合伙人做过一套 `icon-transparent-*.png`（干净的 mark，没有烘死的方块）——
这里用的就是它。但 macOS 的 app 图标不是自由浮动的图形：
纯透明底在 16px（菜单栏、访达列表）上会瘦成一根认不出的细线，
而且和 Dock 里每一个图标都不是一套剪影。

**mark 用合伙人的，容器按平台的。** 两件事各自归位。
"""
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1024
BODY = 814                 # 实测：系统图标本体占 1024 画布的 814
N = 5.2                    # 实测：超椭圆指数
GROUND_TOP = (24, 34, 30)  # 容器底：**极轻的竖向渐变**，平涂看着像贴纸
GROUND_BOTTOM = (9, 15, 13)
MARK_RATIO = 0.62          # mark 占容器的比例，四周留呼吸


def squircle_mask(size: int, supersample: int = 4) -> Image.Image:
    """超椭圆遮罩。超采样再缩回来，边缘才不锯齿。"""
    s = size * supersample
    mask = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(mask)
    r = s / 2
    for y in range(s):
        ny = abs((y + 0.5 - r) / r)
        if ny >= 1:
            continue
        half = (1 - ny ** N) ** (1 / N) * r
        draw.line([(r - half, y), (r + half, y)], fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def plate(size: int) -> Image.Image:
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel((0, y), tuple(
            round(a + (b - a) * t) for a, b in zip(GROUND_TOP, GROUND_BOTTOM)))
    return grad.resize((size, size)).convert("RGBA")


def build(mark_path: Path, out_png: Path) -> None:
    mark = Image.open(mark_path).convert("RGBA")
    # 素材四周自带留白，先裁到真实内容再按容器比例摆 —— 否则 mark 会小一圈。
    box = mark.split()[-1].getbbox()
    if box:
        mark = mark.crop(box)

    mask = squircle_mask(BODY)
    body = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 0))
    body.paste(plate(BODY), (0, 0), mask)

    w = round(BODY * MARK_RATIO)
    h = round(w * mark.height / mark.width)
    body.alpha_composite(mark.resize((w, h), Image.LANCZOS),
                         ((BODY - w) // 2, (BODY - h) // 2))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    inset = (CANVAS - BODY) // 2
    # 阴影只往下 —— 图标浮在桌面上，不是印在上面。和系统一致。
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 82), (inset, inset + 13), mask)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(17)))
    canvas.alpha_composite(body, (inset, inset))
    canvas.save(out_png)


def build_icns(png: Path, icns: Path) -> None:
    """每一档单独缩 —— 让 `iconutil` 从一张图自己降采样，小尺寸会糊。"""
    iconset = icns.with_suffix(".iconset")
    subprocess.run(["rm", "-rf", str(iconset)], check=True)
    iconset.mkdir(parents=True)
    src = Image.open(png).convert("RGBA")
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'' if scale == 1 else '@2x'}.png"
            src.resize((px, px), Image.LANCZOS).save(iconset / name)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
    subprocess.run(["rm", "-rf", str(iconset)], check=True)


if __name__ == "__main__":
    mark, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    png = out_dir / "AppIcon.png"
    build(mark, png)
    build_icns(png, out_dir / "AppIcon.icns")
    print(f"wrote {png} + {out_dir / 'AppIcon.icns'}")
