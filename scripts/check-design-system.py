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

## 手搓卡片：棘轮，不是到期日

我原来打算"只报数不判红，三周后降不到 100 就判红"。合伙人指出那不成立：
**一个需要人再决定一次的触发条件，等于没有触发条件** —— 三周后数字是 118，
判不判？大概率有人说"这周太忙"，把日期往后挪一次，而挪过一次的期限
就再也不是期限了。

改成棘轮：把当前值写死在 `HIGH_WATER` 里。**多一处就红**（新债当天被抓住），
少一处就提醒把这行改小（存量自己往下走）。降到 0 那天它自动变成一道闸，
不需要谁记得、不需要再改一次代码形态。

## 顺带更正一个我数错的数

我原来数 `RoundedRectangle(cornerRadius` 的出现次数（133），然后管它叫
"手搓卡片"。逐个分类之后：37 处是 `clipShape`（裁图，本来就不是卡片）、
39 处是选中环/焦点圈、26 处是悬停填充和代码块底色 —— **真正 fill+描边的
容器只有 3 处**，而且已经换完了。

**数一个东西然后管它叫另一个名字**，和"判据看了 0 个 key 还报绿"是同一族。
所以这里数的是那个真签名，不是那个大数。
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
# 真正的"手搓卡片"签名：`.background(RoundedRectangle…fill)` 紧跟
# `.overlay(RoundedRectangle…strokeBorder)` —— 那正是 `cardSurface` 做的事。
# `clipShape` / 选中环 / 悬停填充都不算：它们本来就不是卡片。
# **用户写的东西长度不可控，是常态不是异常。**
#
# 2026-09-01：创始人在 web 端粘了两千字 prompt 点生成，片子被挤成顶上一条，
# 整屏是他自己刚粘进去的那段字 —— **prompt 变成了页面本身**。
# Mac 上同一个形状在检视器里（`Text(verbatim: prompt)`，没有行数上限，
# 在一条窄侧栏里就是一根一里长的柱子）。
#
# 凡是把**用户提供的文字**显示回去的地方，都要有上限：`lineLimit`、
# `CollapsingProse`、或者截断。app 自己的标题不在此列 —— 它们的长度我们说了算。
USER_TEXT = re.compile(r"Text\(\s*verbatim:\s*[^)\n]*\b(prompt|narration|userText|caption)\b", re.I)
BOUNDED = re.compile(r"lineLimit|CollapsingProse|truncationMode|prefix\(")

HANDROLLED_CARD = re.compile(
    r"\.background\(\s*\n\s*RoundedRectangle\(cornerRadius[^\n]*\n\s*\.fill\([^\n]*\n\s*\)"
    r"\s*\n\s*\.overlay\(\s*\n\s*RoundedRectangle\(cornerRadius[^\n]*\n\s*\.strokeBorder\(",
    re.M,
)

# 棘轮的当前刻度。**只能往下调。** 判据会告诉你该调成多少。
HIGH_WATER = 0


def unbounded_user_text():
    """把用户文字原样铺出来、又不给上限的地方。"""
    out = []
    for path in sorted(SOURCES.rglob("*.swift")):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            if line.strip().startswith(("//", "///")):
                continue
            if not USER_TEXT.search(line):
                continue
            # 上限可能写在后面几个修饰符上
            window = "\n".join(lines[i : i + 8])
            if not BOUNDED.search(window):
                out.append((str(path.relative_to(SOURCES)), i + 1, line.strip()[:70]))
    return out


def handrolled_cards():
    """整文件扫（这个签名跨行），返回 [(文件, 行号)]。"""
    out = []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name == "Card.swift":
            continue
        text = path.read_text()
        for m in HANDROLLED_CARD.finditer(text):
            out.append((str(path.relative_to(SOURCES)), text[: m.start()].count("\n") + 1))
    return out


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

    for rel, n, line in code_lines():
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

    walls = unbounded_user_text()
    if walls:
        failed = True
        print(f"FAIL 用户文字没有上限 {len(walls)} 处（长 prompt 会把这一屏挤爆）：")
        for rel, n, line in walls:
            print(f"       {rel}:{n}  {line}")
    else:
        print("OK   用户文字都有上限")

    cards = handrolled_cards()
    if len(cards) > HIGH_WATER:
        failed = True
        print(f"FAIL 手搓卡片 {len(cards)} 处 > 棘轮 {HIGH_WATER} —— 新写的这几处要用 `cardSurface`：")
        for rel, n in cards[:10]:
            print(f"       {rel}:{n}")
    elif len(cards) < HIGH_WATER:
        print(f"OK   手搓卡片降到 {len(cards)} 处 —— **把 HIGH_WATER 改成 {len(cards)}**（棘轮只能往下）")
    else:
        print(f"OK   手搓卡片 {len(cards)} 处，和棘轮持平")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
