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
    else:
        import struct
        head = png.read_bytes()[16:24]
        pw, ph = struct.unpack(">II", head)
        if (pw, ph) != (w, h):
            fails.append(f"background.png 是 {pw}×{ph}，排版按 {w}×{h} —— 图没重新生成")

    print(f"SCOPE {checks} 处 DMG 坐标耦合")
    if fails:
        for f in fails:
            print(f"FAIL {f}")
        return 1
    print(f"OK   DMG 窗口 {win_w}×{win_h}（内容区 {h}）和背景图、图标坐标全对得上")
    return 0


if __name__ == "__main__":
    sys.exit(main())
