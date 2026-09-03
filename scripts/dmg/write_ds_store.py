#!/usr/bin/env python3
"""把 DMG 那扇窗的样子直接写进 `.DS_Store`，不经过 Finder。

## 为什么不用 AppleScript

摆样子原来靠 `osascript` 驱动 Finder，而那需要 macOS 的「自动化」权限 ——
**一个需要人去点授权框的步骤，是一个会烂掉的步骤**：
CI 里跑不了，后台会话里跑不了（TCC 认 bundle 身份，实测 `-1743`），
换一台机器要重新点一次，而它失败的样子是"发出去的和以为发出去的不一样"。

`.DS_Store` 就是一个有格式的文件（B 树 + 伙伴分配器）。
`ds_store` + `mac_alias` 两个库把这层封好了，我们只需要写对那几格。

## 写哪几格

| 键 | 是什么 |
|---|---|
| `bwsp` | 窗口位置大小、工具栏/状态栏收起 |
| `icvp` | 图标视图：图标多大、字多大、背景图是哪张 |
| `Iloc` | 每个图标摆在哪（每个文件一条） |

背景图用 `mac_alias` 生成一条指向**挂载卷上那个文件**的别名 —— Finder 认这个。
"""
import os
import sys

import mac_alias
from ds_store import DSStore

# 660×370 内容区。这些数必须和 make-background.py 里的常量一致 ——
# 对不上就是图标压在箭头上，而那正是这一屏唯一要说的那句话。
WINDOW = (200, 160, 860, 559)  # left, top, right, bottom（含标题栏）
TITLEBAR = 29
ICON_SIZE = 128
TEXT_SIZE = 13
POSITIONS = {"METAG.app": (180, 171), "Applications": (480, 171)}
BACKGROUND = ".background/background.tiff"


def write(volume: str) -> None:
    left, top, right, bottom = WINDOW
    bg = os.path.join(volume, BACKGROUND)
    if not os.path.isfile(bg):
        sys.exit(f"error: 背景图不在挂载卷里：{bg}")
    alias = mac_alias.Alias.for_file(bg)

    with DSStore.open(os.path.join(volume, ".DS_Store"), "w+") as d:
        d["."]["bwsp"] = {
            "WindowBounds": f"{{{{{left}, {top}}}, {{{right - left}, {bottom - top}}}}}",
            "ShowStatusBar": False,
            "ShowToolbar": False,
            "ShowPathbar": False,
            "ShowSidebar": False,
        }
        d["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 2,          # 2 = 自定义图片
            "backgroundImageAlias": alias.to_bytes(),
            "iconSize": float(ICON_SIZE),
            "textSize": float(TEXT_SIZE),
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "labelOnBottom": True,
            "showIconPreview": True,
            "showItemInfo": False,
            "arrangeBy": "none",
        }
        d["."]["vSrn"] = ("long", 1)
        for name, (x, y) in POSITIONS.items():
            # Iloc 是 16 字节：x、y，其余留空。
            d[name]["Iloc"] = (x, y)


def verify(volume: str) -> None:
    """**自己验一遍自己的活。**

    量的是"这扇窗会不会按我们说的那样打开"，不是".DS_Store 有多少字节"。
    上一版验的是字节数 > 8000 —— 那是 Finder 那条路的经验值，
    换成自己写之后它既不准也说不清哪里不对。
    """
    with DSStore.open(os.path.join(volume, ".DS_Store"), "r") as d:
        icvp = d["."]["icvp"]
        if icvp.get("backgroundType") != 2 or not icvp.get("backgroundImageAlias"):
            sys.exit("error: 背景图没挂上 —— 打开是一片空白，箭头不见了")
        if float(icvp.get("iconSize", 0)) != float(ICON_SIZE):
            sys.exit(f"error: 图标大小是 {icvp.get('iconSize')}，不是 {ICON_SIZE}")
        for name, want in POSITIONS.items():
            got = d[name]["Iloc"]
            if tuple(got[:2]) != want:
                sys.exit(f"error: {name} 摆在 {got[:2]}，应该在 {want} —— 会压到箭头上")
    print(f"==> 窗样子写好并验过：{volume}/.DS_Store")


if __name__ == "__main__":
    args = sys.argv[1:]
    verify_only = "--verify-only" in args
    args = [a for a in args if a != "--verify-only"]
    if len(args) != 1:
        sys.exit("usage: write_ds_store.py [--verify-only] <mounted volume>")
    if not verify_only:
        write(args[0])
    verify(args[0])
