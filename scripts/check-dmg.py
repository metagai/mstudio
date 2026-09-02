#!/usr/bin/env python3
"""DMG 那扇窗：两个文件里的坐标必须对得上。

## 咬过一次的那个耦合

排版在 `scripts/dmg/make-background.py`（画背景图），
摆位在 `scripts/dmg/layout.sh`（AppleScript 告诉 Finder 图标放哪）。
**两边各写一份数字，对不上就是图标压在箭头上** ——
而那一屏总共只说一句话。

2026-09-02 真机截图照出来的第一版就错了：AppleScript 的 `bounds`
**含标题栏**（实测 29pt），我按 660×400 排的版，而真正能画的只有
660×370 —— 背景底下 30pt 被切掉，整组版心往下坠了半格。

**这个数不是能记住的，是要被算出来的。**
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BG_PY = ROOT / "scripts/dmg/make-background.py"
LAYOUT = ROOT / "scripts/dmg/layout.sh"
TITLE_BAR = 29          # 实测：真机截图上标题栏 29pt


def main() -> int:
    py, sh = BG_PY.read_text(), LAYOUT.read_text()
    checks = 0
    fails = []

    w, h = (int(v) for v in re.search(r"^W, H = (\d+), (\d+)", py, re.M).groups())
    left, right, icon_y = (int(v) for v in re.search(
        r"^LEFT_X, RIGHT_X, ICON_Y = (\d+), (\d+), (\d+)", py, re.M).groups())

    b = [int(v) for v in re.search(
        r"set the bounds of container window to \{(\d+), (\d+), (\d+), (\d+)\}", sh).groups()]
    win_w, win_h = b[2] - b[0], b[3] - b[1]

    checks += 1
    if win_w != w:
        fails.append(f"窗口宽 {win_w} ≠ 背景图宽 {w}")

    checks += 1
    if win_h - TITLE_BAR != h:
        fails.append(
            f"窗口高 {win_h} - 标题栏 {TITLE_BAR} = {win_h - TITLE_BAR}，"
            f"而背景图高 {h} —— 底下那截会被切掉，版心坠半格")

    for name, x in (("METAG.app", left), ("Applications", right)):
        checks += 1
        m = re.search(
            r'set position of item "%s" of container window to \{(\d+), (\d+)\}' % re.escape(name), sh)
        if not m:
            fails.append(f"layout.sh 里找不到 {name} 的位置")
            continue
        if (int(m.group(1)), int(m.group(2))) != (x, icon_y):
            fails.append(f"{name} 摆在 {m.group(1)},{m.group(2)}，"
                         f"背景图按 {x},{icon_y} 画的 —— 图标会压在箭头上")

    # 背景图真的在，而且尺寸和排版一致 —— 光有数字对不算，图得是那张图。
    checks += 1
    png = ROOT / "Resources/dmg/background.png"
    if not png.exists():
        fails.append("background.png 不在（跑 scripts/dmg/make-background.py）")
        return report(checks, fails, win_w, win_h, h)

    import struct
    pw, ph = struct.unpack(">II", png.read_bytes()[16:24])
    if (pw, ph) != (w, h):
        fails.append(f"background.png 是 {pw}×{ph}，排版按 {w}×{h} —— 图没重新生成")

    # **那段胶片不许压到图标上。**
    #
    # 这张图唯一会出的错就是它：Finder 把两个 128pt 的图标画在背景**上面**，
    # 胶片一旦伸进它们的地盘，就变成图标底下露出来的一截脏东西 ——
    # 而那正是"布局错位"看起来的样子。
    #
    # 量的是图上真实的墨迹范围，不是源码里那几个常量。
    checks += 2
    ink = ink_extent(png)
    if ink is None:
        fails.append("背景图上一点东西都没画 —— 那一屏只剩两个图标和一片空白")
    else:
        ink_x0, ink_x1 = ink
        left_edge, right_edge = left + 64, right - 64      # 图标各占 128pt
        if ink_x0 <= left_edge:
            fails.append(f"胶片左端到了 {ink_x0}，压进了 METAG 图标（它右边缘在 {left_edge}）")
        if ink_x1 >= right_edge:
            fails.append(f"胶片右端到了 {ink_x1}，压进了 Applications（它左边缘在 {right_edge}）")

    # **DMG 装的是 tiff，而上面那几条查的是 png。**
    #
    # 谁重新生成了 png 却忘了跑 `tiffutil`，上面全绿，
    # 而发出去的 DMG 里还是旧图 —— 判据看着一个文件，用户拿到另一个。
    #
    # 比的是**解出来的像素**，不是文件字节：`tiffutil` 的输出在不同
    # macOS 版本上不保证逐字节一致，比字节会变成假红。
    checks += 2
    fails += tiff_matches_png(ROOT / "Resources/dmg")

    return report(checks, fails, win_w, win_h, h)


def tiff_matches_png(folder: Path) -> list:
    from PIL import Image, ImageChops
    tiff = folder / "background.tiff"
    if not tiff.exists():
        return ["background.tiff 不在 —— DMG 摆样子那一步会直接退出"]
    out = []
    try:
        im = Image.open(tiff)
        for index, name in enumerate(["background.png", "background@2x.png"]):
            im.seek(index)
            a = im.convert("RGB")
            b = Image.open(folder / name).convert("RGB")
            if a.size != b.size:
                out.append(f"tiff 第 {index + 1} 帧是 {a.size}，{name} 是 {b.size} —— tiff 没重新生成")
            elif ImageChops.difference(a, b).getbbox() is not None:
                out.append(f"tiff 第 {index + 1} 帧和 {name} 画的不是一张图 —— 忘了跑 tiffutil")
    except EOFError:
        out.append("background.tiff 只有一帧 —— Retina 上会糊（要 1x + 2x 两张）")
    return out


def ink_extent(png: Path):
    """图上"画了东西"的那一段横向范围。纸底之外的一切都算墨迹。"""
    from PIL import Image
    im = Image.open(png).convert("RGB")
    w, h = im.size
    px = im.load()
    paper = px[2, 2]
    xs = [x for x in range(w)
          if any(sum(abs(a - b) for a, b in zip(px[x, y], paper)) > 24 for y in range(h))]
    return (xs[0], xs[-1]) if xs else None


def report(checks, fails, win_w, win_h, h) -> int:
    print(f"SCOPE {checks} 处 DMG 坐标耦合")
    if fails:
        for f in fails:
            print(f"FAIL {f}")
        return 1
    print(f"OK   DMG 窗口 {win_w}×{win_h}（内容区 {h}）、背景图、图标坐标全对得上，胶片没压到图标")
    return 0


if __name__ == "__main__":
    sys.exit(main())
