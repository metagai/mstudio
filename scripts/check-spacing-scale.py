#!/usr/bin/env python3
"""刻度只许收窄，不许再长。**Apple HIG 的 4pt 网格。**

## 为什么要有这道棘轮

2026-09-03 量出来的现状：

    间距 13 档：0 2 4 6 8 10 12 14 16 20 24 28 44
                  ↑   ↑    ↑    ↑  不在 4pt 网格上
    字号 12 档：8 9 10 11 12 13 14 15 18 22 28 36
                └──── 7 档挤在 8–15，彼此差 1pt ────┘

**同时有 6 和 8、10 和 12、14 和 16 —— 差别肉眼看不出，而选择变多了三倍。**
字号 8→15 之间七档几乎无法分辨，然后一步跳到 18、22、28。
这不是设计出来的音阶，是**每一屏加了自己需要的那一号**留下的痕迹。

结果就是：节奏不匀、控件宽度参差、每一屏各定各的间距。
**干净不等于精致 —— 干净是没有错误，精致是有克制。**

## 这道门守什么

四个数，**每一个只许往下走**。要往下走就得改这个文件里的高水位，
而那一行提交正是"我确认这一档是我收掉的"。

它**不要求今天就收敛完** —— 一次性动 13 档会碰到几乎每个文件。
它只保证一件事：**从今天起不再变糟。**
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ── 高水位（2026-09-03 冻结）。**只许调小。** ──────────────────
MAX_SPACING_STEPS = 9    # 目标 ~7（收掉 lg=14、xxs=2、md=10、sm=6）
MAX_OFF_GRID = 0         # 到了：间距整档落在 4pt 网格上
MAX_FONT_STEPS = 12      # 目标 ~7
MAX_INDISTINCT_PAIRS = 7 # 相邻差 < 2pt 的对数，目标 0
GRID = 4                 # Apple HIG


def scale(source: str, name: str) -> list[float]:
    start = source.index(f"enum {name} {{")
    end = source.index("\n    }", start)
    body = source[start:end]
    return sorted({float(v) for _, v in
                   re.findall(r"static let (\w+): CGFloat = ([\d.]+)", body)})


def main() -> int:
    source = (ROOT / "Sources/PalmierPro/UI/AppTheme.swift").read_text()
    spacing = scale(source, "Spacing")
    fonts = scale(source, "FontSize")

    off_grid = [v for v in spacing if v % GRID]
    indistinct = [(fonts[i], fonts[i + 1]) for i in range(len(fonts) - 1)
                  if fonts[i + 1] - fonts[i] < 2]

    print(f"SCOPE {len(spacing)} 档间距 × {len(fonts)} 档字号")

    fails = []
    if len(spacing) > MAX_SPACING_STEPS:
        fails.append(f"间距涨到 {len(spacing)} 档（上限 {MAX_SPACING_STEPS}）"
                     f" —— 又加了一档，而肉眼分不出它和邻居的差别")
    if len(off_grid) > MAX_OFF_GRID:
        fails.append(f"离 {GRID}pt 网格的间距有 {len(off_grid)} 个"
                     f"（上限 {MAX_OFF_GRID}）：{off_grid}")
    if len(fonts) > MAX_FONT_STEPS:
        fails.append(f"字号涨到 {len(fonts)} 档（上限 {MAX_FONT_STEPS}）")
    if len(indistinct) > MAX_INDISTINCT_PAIRS:
        fails.append(f"相邻字号差不到 2pt 的有 {len(indistinct)} 对"
                     f"（上限 {MAX_INDISTINCT_PAIRS}）：{indistinct}")

    if fails:
        for f in fails:
            print(f"FAIL {f}")
        print("     **加一档之前先问：现有哪一档不够用？** 多半是够的。")
        print(f"     真要加，改 {Path(__file__).name} 里的高水位，"
              "那一行提交就是你确认这一档非加不可。")
        return 1

    # **收窄了就要求登记** —— 棘轮只有咬人才是棘轮。
    slack = [
        (len(spacing), MAX_SPACING_STEPS, "MAX_SPACING_STEPS"),
        (len(off_grid), MAX_OFF_GRID, "MAX_OFF_GRID"),
        (len(fonts), MAX_FONT_STEPS, "MAX_FONT_STEPS"),
        (len(indistinct), MAX_INDISTINCT_PAIRS, "MAX_INDISTINCT_PAIRS"),
    ]
    loose = [(now, cap, key) for now, cap, key in slack if now < cap]
    if loose:
        for now, cap, key in loose:
            print(f"FAIL 收到 {now} 了，而高水位还写着 {cap} —— 把 {key} 改成 {now}")
        print("     （**收窄不登记，下一次涨回去就没人拦得住。**）")
        return 1

    print(f"OK   间距 {len(spacing)} 档（离网格 {len(off_grid)}）、"
          f"字号 {len(fonts)} 档（分不清的 {len(indistinct)} 对）—— 都没再长")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
