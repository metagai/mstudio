#!/usr/bin/env python3
"""造 DMG 并摆好那扇窗（背景图、窗口大小、两个图标的位置）。

## 走过的两条弯路

**① AppleScript 驱动 Finder。** 那需要 macOS 的「自动化」权限 ——
**一个需要人去点授权框的步骤，是一个会烂掉的步骤**：CI 跑不了、
后台会话跑不了（TCC 认 bundle 身份，实测 `-1743`）、换台机器要重点一次。
它烂掉的结果是：8/16 发到线上的 0.1.8 里**根本没有窗样子**，
从那天起每个下载 METAG 的人看到的都是 Finder 默认的两个图标、零引导。

**② 自己手写 `.DS_Store`。** 方向对，但我写漏了几格
（`backgroundColorRed/Green/Blue`、`scrollPositionX/Y`），
于是 Finder 把整块视图设置丢掉了 —— 窗口大小和图标位置生效了，
**背景图没有**。0.1.9 就是这么发出去的。

而我的自检说"验过了" —— 它读回了我自己写的那几格，
**验的是"我写进去了什么"，不是"Finder 会怎么读"**。
判据和用户走的不是同一条路，今天这条错误我自己写进了 lessons，然后又犯了一次。

## 现在

用 `dmgbuild` —— 这类 DMG 的事实标准。它写出来的 `.DS_Store` 和
Docker 官方安装包里那份是同一套键（逐键比对过）。
不再由我来"记得写全"哪几格。
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BACKGROUND = os.path.join(HERE, "../../Resources/dmg/background.tiff")

# 660×370 内容区。这些数必须和 make-background.py 里的常量一致 ——
# 对不上就是图标压在箭头上，而那正是这一屏唯一要说的那句话。
WINDOW = (200, 160, 860, 559)   # left, top, right, bottom（含 29pt 标题栏）
ICON_SIZE = 128
TEXT_SIZE = 13
POSITIONS = {"METAG.app": (180, 171), "Applications": (480, 171)}

SETTINGS = '''\
files = {files!r}
symlinks = {{"Applications": "/Applications"}}
{icon_line}
background = {background!r}
window_rect = (({x}, {y}), ({w}, {h}))
icon_size = {icon_size}
text_size = {text_size}
icon_locations = {locations!r}
format = "UDZO"
'''


# **一个真正会渲染的 DMG，`icvp` 里必须有这些键。**
#
# 这张表是从两份**真的能画出背景图**的安装包里逐键比对出来的：
# Docker 官方的 DMG，和 dmgbuild 自己造的一份。
# 我手写那版少了 `backgroundColor*` 和 `scrollPosition*` —— Finder 就把
# 整块视图设置丢了。**少一格和写错一格是一样的后果，而它一声不响。**
REQUIRED_ICVP = {
    "viewOptionsVersion", "backgroundType", "backgroundImageAlias",
    "backgroundColorRed", "backgroundColorGreen", "backgroundColorBlue",
    "gridOffsetX", "gridOffsetY", "gridSpacing", "arrangeBy",
    "showIconPreview", "showItemInfo", "labelOnBottom",
    "textSize", "iconSize", "scrollPositionX", "scrollPositionY",
}


def verify(dmg: str) -> None:
    """挂开成品，问那扇窗会怎么打开。

    **不问"我写进去了什么"** —— 上一版就是那么"验过"的，
    而它验的是我自己刚写的那几格，Finder 读不读得懂完全没测到。
    """
    import re
    import mac_alias
    from ds_store import DSStore

    out = subprocess.run(
        ["hdiutil", "attach", "-readonly", "-noverify", "-noautoopen", dmg],
        capture_output=True, text=True, check=True).stdout
    mount = re.search(r"(/Volumes/.*)$", out, re.M).group(1).strip()
    try:
        with DSStore.open(os.path.join(mount, ".DS_Store"), "r") as d:
            icvp = dict(d["."]["icvp"])
            locs = {n: tuple(d[n]["Iloc"][:2]) for n in POSITIONS}
        missing = REQUIRED_ICVP - set(icvp)
        if missing:
            sys.exit(f"error: 视图设置少了 {sorted(missing)} —— Finder 会把整块丢掉，背景图不出现")
        if icvp["backgroundType"] != 2:
            sys.exit("error: 没设成自定义背景图")
        alias = mac_alias.Alias.from_bytes(icvp["backgroundImageAlias"])
        if alias.volume.name != os.path.basename(mount).split(" ")[0]:
            sys.exit(f"error: 背景图别名指向卷 {alias.volume.name!r}，而这个包挂出来叫 {mount!r}")
        if not any(os.path.exists(os.path.join(mount, p))
                   for p in (".background.tiff", ".background/background.tiff")):
            sys.exit("error: 背景图文件没进包")
        for name, want in POSITIONS.items():
            if locs[name] != want:
                sys.exit(f"error: {name} 摆在 {locs[name]}，应该在 {want} —— 会压到箭头上")
    finally:
        subprocess.run(["hdiutil", "detach", mount], capture_output=True)
    print(f"==> 窗样子验过：背景图挂上了、{len(REQUIRED_ICVP)} 格视图设置齐、图标没压到箭头")


def main() -> int:
    if len(sys.argv) != 4:
        sys.exit("usage: build_dmg.py <staging dir> <out.dmg> <volume name>")
    staging, out, volume = sys.argv[1:]
    background = os.path.abspath(BACKGROUND)
    if not os.path.isfile(background):
        sys.exit(f"error: 背景图不在：{background}（跑 scripts/dmg/make-background.py）")

    app = os.path.join(staging, "METAG.app")
    volume_icon = os.path.join(staging, ".VolumeIcon.icns")
    left, top, right, bottom = WINDOW

    with tempfile.TemporaryDirectory() as tmp:
        conf = os.path.join(tmp, "settings.py")
        with open(conf, "w") as f:
            f.write(SETTINGS.format(
                files=[app],
                icon_line=f"icon = {volume_icon!r}" if os.path.exists(volume_icon) else "",
                background=background,
                x=left, y=top, w=right - left, h=bottom - top,
                icon_size=ICON_SIZE, text_size=TEXT_SIZE,
                locations=POSITIONS,
            ))
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(
            [sys.executable, "-m", "dmgbuild", "-s", conf, volume, out],
            check=True,
        )
    print(f"==> DMG 造好了：{out}")
    verify(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
