#!/usr/bin/env python3
"""守卫自己也要被守。

## 一天之内六条"看不见"

2026-09-01 我和产品技术负责人一共翻出六件事，**每一件都是一个我们以为
在量、其实没在量的东西**：

| 判据 | 它说的 | 实际 |
|---|---|---|
| `check-l10n` | 「覆盖了全部 1121 个 key」 | 迁移之后一个 key 都没扫到 |
| verify「登录可发起」 | 绿了两个月 | 微信那条路一直是死的，它只看 30x |
| `ops_daily` HUMAN | 「29 人里剩 11 人」 | 真人只有 1 个，其余是我们自己的探针 |
| 国内网关健康 | 全绿 | 网关挂了，nginx 静默兜到海外，判据被兜住了 |
| 「133 处手搓卡片」 | 一个真数字 | 真正是卡片的只有 11 处，名字是假的 |
| 三个团队目标 | 要去优化 | 其中两个 Mac 根本量不到 |

它们不是六个 bug。**是同一个动作犯了六次：写了一把尺子，然后再没量过这把尺子。**

## 两种形状

- **A 类：它什么都没看见，然后报了绿。** 沉默被当成了通过。
- **B 类：它看见的是真的，但名字是假的。** 数字对，声称错 —— 更隐蔽，
  因为没有任何东西会跟它矛盾。

## 这条判据管 A 类

**每一把尺子都必须说出自己量了多少个东西**，并且那个数不能是 0。
契约是一行：

    SCOPE <个数> <量的是什么>

「量的是什么」不是装饰 —— 它是 B 类唯一的解药：**把声称和数字写在一起**，
下一个人才看得出"133 个 RoundedRectangle"和"133 个手搓卡片"不是一回事。

## 别人仓里那 7 把尺子

主仓的 `scripts/check-*.py` 是产品技术负责人的。**我不给别人的代码上闸** ——
这里只数一个棘轮：现在有几把没声明 scope。**新增的那把必须声明**，
存量归零由他决定要不要跟。
"""
import re
import subprocess
import sys
from pathlib import Path

MAC = Path(__file__).resolve().parent
PARENT = MAC.parent.parent / "scripts"

SCOPE = re.compile(r"^SCOPE\s+(\d+)\s+(\S.*)$", re.M)

# 主仓那 7 把还没声明 scope 的尺子。**只能往下调。**
# 它不判红是因为那是别人的代码；它是棘轮是因为"整类放过"等于没有判据。
FOREIGN_UNDECLARED_HIGH_WATER = 7


def declares_scope(script: Path) -> tuple[bool, str]:
    """跑一遍，看它有没有说出自己量了多少。"""
    try:
        out = subprocess.run(
            [sys.executable, str(script)],
            capture_output=True, text=True, timeout=120, cwd=script.parent.parent,
        )
    except Exception as e:  # noqa: BLE001 - 跑不起来也是一种"没声明"
        return False, f"跑不起来：{e}"
    text = out.stdout + out.stderr
    m = SCOPE.search(text)
    if not m:
        return False, "没有 SCOPE 行 —— 它没说自己量了多少个东西"
    n, unit = int(m.group(1)), m.group(2)
    if n == 0:
        return False, f"SCOPE 是 0（{unit}）—— 一把什么都没量到的尺子，比没有尺子更糟"
    return True, f"{n} {unit}"


def main() -> int:
    failed = False

    mine = sorted(p for p in MAC.glob("check-*.py") if p.name != Path(__file__).name)
    for script in mine:
        ok, why = declares_scope(script)
        if ok:
            print(f"OK   {script.name} 量了 {why}")
        else:
            failed = True
            print(f"FAIL {script.name}：{why}")

    if PARENT.is_dir():
        foreign = sorted(PARENT.glob("check-*.py"))
        undeclared = [s.name for s in foreign if not declares_scope(s)[0]]
        if len(undeclared) > FOREIGN_UNDECLARED_HIGH_WATER:
            failed = True
            print(f"FAIL 主仓没声明 scope 的判据 {len(undeclared)} 把 > 棘轮 "
                  f"{FOREIGN_UNDECLARED_HIGH_WATER} —— 新加的那把要声明：")
            for name in undeclared[FOREIGN_UNDECLARED_HIGH_WATER:]:
                print(f"       {name}")
        elif len(undeclared) < FOREIGN_UNDECLARED_HIGH_WATER:
            print(f"OK   主仓没声明的降到 {len(undeclared)} 把 —— "
                  f"**把 FOREIGN_UNDECLARED_HIGH_WATER 改成 {len(undeclared)}**")
        else:
            print(f"OK   主仓 {len(undeclared)} 把没声明 scope（棘轮持平，存量由那侧决定）")

    # 这把尺子自己也要说话 —— 否则它就是第七条"看不见"。
    print(f"SCOPE {len(mine)} 把本仓判据")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
