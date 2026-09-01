#!/usr/bin/env python3
"""界面是不是**一套东西**。

## 为什么需要一条判据

"高级感"听起来像品味问题，于是它永远排在功能后面，也永远没人能说清它好没好。
但它有一半是可以数出来的：**同一件事有几种画法。**

2026-09-01 数了一遍：`RoundedRectangle(cornerRadius:` 在 57 个文件里出现
**133 次** —— 每一屏都在手搓自己的卡片，圆角、描边、底色、阴影各挑各的。
单独看每一处都合理，合起来就是"这些屏不像同一个产品"。

**这就是"乐高感"的反面。** 乐高像乐高不是因为积木好看，
是因为**每一块的接口都一样**。一个到处手搓卡片的界面，
是 133 种互不兼容的积木。

## 这条判据管两件事

1. **不许用系统语义字号和系统按钮样式**（`.font(.headline)` / `.borderedProminent`）——
   它们是"这一屏没设计过"的最明显特征。实测：40 处里 35 处在 METAG 自己那几屏上，
   也就是**我们后加的屏才是没走设计系统的那一批**。
2. **不许用裸的系统色**（`.foregroundStyle(.orange)`）—— `systemOrange`
   在我们的纸底上只有 2.11:1，过不了 AA。AppTheme 里为此专门收敛过一版。

手搓卡片的那 133 处**只报数不判红**：一次全改完的风险比它本身大。
数字会随着一处处换成 `Card` 往下走 —— 它是进度条，不是闸。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources/PalmierPro"

# 允许保留的地方，逐条写明理由。**空泛的通配不算例外，只能点名。**
ALLOW = {
    # Markdown 渲染要按语义层级映射字号，那本来就是它的工作。
    "Agent/Panel/MarkdownText.swift",
}

SEMANTIC_FONT = re.compile(r"\.font\(\.(?:headline|subheadline|caption2?|title\d?|body|footnote)\)")
SYSTEM_BUTTON = re.compile(r"\.buttonStyle\(\.bordered(?:Prominent)?\)")
RAW_COLOR = re.compile(r"\.foregroundStyle\(\.(?:orange|green|red|blue|yellow|gray|secondary|tertiary|quaternary)\)")
HANDROLLED_CARD = re.compile(r"RoundedRectangle\(cornerRadius")


def code_lines():
    for path in sorted(SOURCES.rglob("*.swift")):
        rel = str(path.relative_to(SOURCES))
        for n, line in enumerate(path.read_text().splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith(("//", "///", "*")):
                continue
            yield rel, n, stripped


def main():
    failed = False
    findings = {"系统语义字号": [], "系统按钮样式": [], "裸系统色": []}
    cards = 0

    for rel, n, line in code_lines():
        cards += len(HANDROLLED_CARD.findall(line))
        if rel in ALLOW:
            continue
        for label, rx in (
            ("系统语义字号", SEMANTIC_FONT),
            ("系统按钮样式", SYSTEM_BUTTON),
            ("裸系统色", RAW_COLOR),
        ):
            if rx.search(line):
                findings[label].append((rel, n, line[:80]))

    for label, hits in findings.items():
        if hits:
            failed = True
            print(f"FAIL {label} {len(hits)} 处（设计系统里有对应的 token）：")
            for rel, n, line in hits[:12]:
                print(f"       {rel}:{n}  {line}")
        else:
            print(f"OK   没有{label}")

    # **进度条，不是闸。** 一次把 133 处全换掉的风险比它本身大；
    # 这个数字随着一处处换成 `Card` 往下走，走到 0 就把它改成判红。
    print(f"NOTE 手搓卡片还有 {cards} 处 —— 换成 `Card` 的进度条（不判红）")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
