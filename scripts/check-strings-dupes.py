#!/usr/bin/env python3
"""词条表上的两族错：同一个键写两遍，和多参数翻译静悄悄跟着英文的语序走。

## 第二族：语序（2026-09-04 咬的）

`"%@ of %@ shots are in"` 在中文里翻成了 `"%@ 镜里到了 %@"` ——
参数按顺序填进去，用户看见的是 **"0 镜里到了 5"**。意思正好反过来：
在说"总共 0 镜，到了 5 镜"。

**两个 `%@` 的键，翻译只要不写 `%1$@`/`%2$@`，就只能跟着英文的语序。**
而语序恰恰是各语言最不一样的地方。所以：**一个键有两个以上占位符时，
每一种译文都必须用位置化参数** —— 除非它跟英文语序真的一致，
那也得显式写出来，让下一个人知道这是想过的，不是漏掉的。

门抓不到它，因为编译和渲染都成立：`%@` 填得进去，那一屏画得出来。
只有人读那句中文才看得出来它是反的。而 25 个语言里没人读过。

## 第一族：重复键

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
BASELINE = ROOT / "scripts/strings-argorder-baseline.txt"
LINE = re.compile(r'^("(?:[^"\\]|\\.)*") = (.*);$')


PLACEHOLDER = re.compile(r"%(\d+\$)?[@dfs]")
WORD = re.compile(r"[^\W\d_]", re.UNICODE)


def reorderable(key: str) -> bool:
    """两个占位符**中间夹着实词**时，各语言才会调换它们的顺序。

    `"%@ · %@"`、`"%@: %@."` 中间只有分隔符，顺序由分隔符的含义定死，
    要求它们写 %1$@ 是纯噪音 —— 而被无视的守卫等于没有。
    `"%@ of %@ shots are in"` 中间有 "of"，那是语序真会变的地方。
    """
    parts = PLACEHOLDER.split(key)
    # split 会把捕获组也带出来，只看占位符**之间**的那些片段
    between = [s for s in parts[1:-1] if s and not s.endswith("$")]
    return len(PLACEHOLDER.findall(key)) >= 2 and any(WORD.search(s) for s in between)


def check_argument_order(catalogs: list[Path]) -> list[str]:
    """多参数的键，译文必须用位置化参数说清它想要哪个顺序。

    只查**译文**：英文那张表就是参数顺序的定义，它自己不需要位置化。
    """
    english = {}
    for path in catalogs:
        if path.parent.name == "en.lproj":
            for line in path.read_text().split("\n"):
                m = LINE.match(line)
                if m and reorderable(m.group(1)):
                    english[m.group(1)] = True

    baseline = {l for l in (BASELINE.read_text().split("\n") if BASELINE.exists() else [])
                if l and not l.startswith("#")}
    current, fails = set(), []
    for path in catalogs:
        if path.parent.name == "en.lproj":
            continue
        for line in path.read_text().split("\n"):
            m = LINE.match(line)
            if not m or m.group(1) not in english:
                continue
            marks = PLACEHOLDER.findall(m.group(2))
            if len(marks) >= 2 and not all(marks):
                current.add(f"{path.parent.name}\t{m.group(1)}")

    added = sorted(current - baseline)
    if added:
        fails.append(f"{len(added)} 条**新**的多参数译文没写 %1$@ —— "
                     f"它们只能跟着英文的语序走，而那多半不是你想要的")
        for a in added[:6]:
            fails.append(f"    {a.replace(chr(9), '  ')}")
        fails.append("    要么写成 %1$@ / %2$@，要么读一遍确认同序后登记进 "
                     f"{BASELINE.name}")
    gone = len(baseline - current)
    print(f"SCOPE 多参数译文：{len(current)} 条在基线里（没人读过语序）"
          + (f"，比基线少了 {gone} 条" if gone else ""))
    return fails


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

    fails += check_argument_order(catalogs)

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
