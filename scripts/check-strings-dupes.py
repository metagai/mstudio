#!/usr/bin/env python3
"""同一个键在词条表里出现两次，而两次的值不一样。

## 咬过一次

2026-09-03：`zh-Hans` 和 `es` 各有 **87 个重复键**，其中值不同的
36 / 39 个 —— 而 `.strings` 的语义是**后一条覆盖前一条**。

我做了一次"清理"，去重时保留了**第一条**，于是 75 处翻译被悄悄退回旧版本；
西语那边尤其糟，第一条多半是**没翻译的英文原文**
（`"AI transcription" = "AI transcription"`），第二条才是真翻译。

**门当时没抓到**：覆盖率检查只问"这个键有没有翻译"，
而两条都在，覆盖率是满的。

重复本身就该红：留着它，下一个人做同样的"清理"还会踩。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINE = re.compile(r'^("(?:[^"\\]|\\.)*") = (.*);$')


def main() -> int:
    catalogs = sorted((ROOT / "Sources/PalmierPro/Resources/Localization").glob("*.lproj/Localizable.strings"))
    fails, keys = [], 0
    for path in catalogs:
        seen: dict[str, str] = {}
        dupes: list[str] = []
        for line in path.read_text().split("\n"):
            m = LINE.match(line)
            if not m:
                continue
            key, value = m.groups()
            keys += 1
            if key in seen:
                dupes.append(f"{key} → {seen[key]} / {value}"
                             if seen[key] != value else key)
            seen[key] = value
        if dupes:
            name = path.parent.name
            conflicting = [d for d in dupes if "→" in d]
            fails.append(f"{name}：{len(dupes)} 个键写了两遍"
                         + (f"，其中 {len(conflicting)} 个两次的值不一样" if conflicting else ""))
            for d in conflicting[:3]:
                fails.append(f"    {d}")

    print(f"SCOPE {keys} 条词条 × {len(catalogs)} 张表")
    if fails:
        for f in fails:
            print(f"FAIL {f}" if not f.startswith("    ") else f)
        print("     生效的是**后一条**。去重时留错那一条，会把翻译悄悄退回旧版本。")
        return 1
    print(f"OK   {len(catalogs)} 张词条表里没有一个键写了两遍")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
