#!/usr/bin/env python3
"""界面文案的两条硬约束。

## 1. 源码里不许有裸的中文字符串

METAG 加进这个 app 的那些屏 —— 额度流水、我的作品、草案表、后端错误 ——
一度是**只有中文**的：英文和西语用户在「这笔钱花在哪」这一屏上看到的是中文。
2026-08-12 修掉之后，这条守卫防的是它再长回来：新写一句中文字符串很自然，
而它不会让任何测试变红。

## 2. `L("key")` 用到的每个 key，en / zh-Hans / es 三张表都必须有

漏一个的后果是**静默降级成英文**：中文用户在一句中文界面里看到一句英文，
没有任何报错。三张表是我们维护的三种语言（另外四份继承来的语言包按设计回落到英文，
不在这条约束里）。

判据落在**真表和真源码**上，不落在"我记得我加过"。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CJK = re.compile(r"[一-鿿]")
MAINTAINED = ("en", "zh-Hans", "es")

# 允许保留中文的地方，逐条写明理由。**空泛的通配不算例外，只能点名。**
ALLOW = {
    # 语言选择器要用各自的语言写自己的名字 —— 看不懂的选项对迷路的人没有用。
    "Sources/PalmierPro/Utilities/Localization.swift",
    # 音色名按语言分支返回，`case (..., "zh")` 那一支本来就该是中文。
    "Sources/PalmierPro/Metag/MetagNarrator.swift",
}

STRING = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')


def source_lines():
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        rel = str(path.relative_to(ROOT))
        for n, line in enumerate(path.read_text().splitlines(), 1):
            yield rel, n, line


def raw_chinese():
    out = []
    for rel, n, line in source_lines():
        if rel in ALLOW:
            continue
        stripped = line.strip()
        if stripped.startswith(("//", "///", "*")):
            continue
        for m in STRING.finditer(line):
            if CJK.search(m.group(1)):
                out.append((rel, n, stripped[:90]))
                break
    return out


def l_keys():
    """`L("key")` 和 `L10n.threadSafe("key")` 用到的 key。

    只认字面量。变量拼出来的 key 本来就查不出来，硬猜只会给出假的结论 ——
    这条限制写在这里，不藏着。
    """
    call = re.compile(r'(?:\bL|L10n\.threadSafe)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
    keys = {}
    for rel, n, line in source_lines():
        # 注释里的 `L("…")` 是在讲用法，不是调用。不跳过它，这份清单第一条就是假的。
        if line.strip().startswith(("//", "///", "*")):
            continue
        for m in call.finditer(line):
            keys.setdefault(m.group(1).replace('\\"', '"'), (rel, n))
    return keys


def table(lang):
    path = ROOT / f"Sources/PalmierPro/Resources/Localization/{lang}.lproj/Localizable.strings"
    entry = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', re.M)
    return {m.group(1).replace('\\"', '"') for m in entry.finditer(path.read_text())}


def main():
    failed = False

    raw = raw_chinese()
    if raw:
        failed = True
        print(f"FAIL 源码里有 {len(raw)} 处裸中文字符串（要走 L(…)）：")
        for rel, n, text in raw[:20]:
            print(f"       {rel}:{n}  {text}")
    else:
        print("OK   源码里没有裸中文字符串")

    keys = l_keys()
    for lang in MAINTAINED:
        have = table(lang)
        missing = sorted(k for k in keys if k not in have)
        if missing:
            failed = True
            print(f"FAIL {lang} 缺 {len(missing)} 个 key（界面会静默回落成英文）：")
            for k in missing[:15]:
                rel, n = keys[k]
                print(f'       "{k[:60]}"  ← {rel}:{n}')
        else:
            print(f"OK   {lang} 覆盖了全部 {len(keys)} 个 key")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
