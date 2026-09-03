#!/bin/bash
# 给 DMG 那扇窗摆好样子：背景图、窗口大小、两个图标的位置。
#
# ## 之前是什么样
#
# `/Applications` 软链**一直都在** —— 缺的只是"告诉他往哪拖"。
# 用户双击打开，看到的是 Finder 默认视图里两个图标，没有任何引导：
# 装不装得上，全看他见没见过别的 Mac 软件。
#
# ## 为什么单独一个脚本
#
# bundle.sh 里有两条造 DMG 的路（`--dmg` 本地、`--dist` 发布）。
# 各写一遍的话，迟早只有一条是好看的 —— 而好看的那条不一定是发出去的那条。
#
# ## 为什么不再用 Finder（2026-09-03）
#
# 摆样子原来靠 AppleScript 驱动 Finder，那需要 macOS 的「自动化」权限。
# **一个需要人去点授权框的步骤，是一个会烂掉的步骤**：CI 跑不了、
# 后台会话跑不了（TCC 认 bundle 身份，实测 -1743）、换台机器要重点一次。
# 于是这一步长期只能由创始人本人跑，而发版被这一件事卡了很久。
#
# `.DS_Store` 就是个有格式的文件。`write_ds_store.py` 直接写它。
#
# ## 失败就是失败
#
# 写不成就**直接退出**，不悄悄回落成一个没背景的 DMG ——
# 那样发出去的东西和我们以为发出去的东西是两回事，而没有一处会红。
set -euo pipefail

STAGING="$1"       # 里面已经有 METAG.app 和 Applications 软链
OUT="$2"           # 最终 .dmg
VOL="${3:-METAG}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BG="$HERE/../../Resources/dmg/background.tiff"

[ -f "$BG" ] || { echo "error: 背景图不在：$BG（跑 scripts/dmg/make-background.py）" >&2; exit 1; }

RW="$(mktemp -u -t metag-dmg-rw).dmg"
trap 'rm -f "$RW"' EXIT

# 先造一个可写的，摆完样子再压。**压过的动不了。**
hdiutil create -volname "$VOL" -srcfolder "$STAGING" -ov \
  -format UDRW -fs HFS+ "$RW" >/dev/null

MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | \
  grep -o '/Volumes/.*$' | head -1)"
[ -n "$MOUNT" ] || { echo "error: 挂不上刚造的 DMG" >&2; exit 1; }

mkdir -p "$MOUNT/.background"
cp "$BG" "$MOUNT/.background/background.tiff"

# **替身角标留着。** `/Applications` 是符号链接，Finder 会在左下角盖一个
# 黑箭头角标 —— 那一屏上唯一一处系统杂音。
#
# 试过给它一个自定义图标把角标顶掉（`Rez` + `SetFile -a C`）：
# **不成立** —— Rez 跟着符号链接走，拒绝写资源分支（`fnfErr -43`），
# 而真跟过去就是往系统的 `/Applications` 里写东西。
# 大多数发行版的 DMG 也带这个角标；为它冒那个险不值。
#
# 660×370 内容区。位置和 make-background.py 里的常量**必须一致** ——
# 对不上就是图标压在箭头上，而那正是这一屏唯一要说的那句话。
# **不经过 Finder。** 见 write_ds_store.py 开头那段。
# 缺库时说清装什么 —— 不然报错是一行 ModuleNotFoundError，
# 而这一步失败的后果是"发出去的和以为发出去的不一样"。
python3 -c "import ds_store, mac_alias" 2>/dev/null || {
  echo "error: 缺 ds-store / mac-alias。装一次：" >&2
  echo "         uv pip install ds-store mac-alias" >&2
  exit 1
}
python3 "$HERE/write_ds_store.py" "$MOUNT"

sync

# **卷图标的标记要打在写完窗样子之后。**
#
# 光把 `.VolumeIcon.icns` 拷进去不够，得给卷打上"我有自定义图标"的标志位；
# 否则标题栏上是系统通用的磁盘映像图标，不是 METAG。
#
# 而它必须排在写窗样子那一段**后面** —— 那一步会重写卷的 Finder info，
# 把先打的标记冲掉。第一版打在前面，于是自检报"卷图标没生效"，
# 而那条自检当时还会**把成品删掉**：一个装饰细节，把"你根本没法测"塞给了创始人。
if [ -f "$MOUNT/.VolumeIcon.icns" ]; then
  SetFile -a C "$MOUNT" || echo "warn: 卷图标标记没打上，标题栏会是通用磁盘图标" >&2
fi
sync

hdiutil detach "$MOUNT" >/dev/null
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

# **自己验一遍自己的活。**
#
# AppleScript 那一段可能"跑完了但什么都没生效"（权限被撤、Finder 卡住、
# .DS_Store 还没落盘就被压进去）。不验的话，我们发出去的
# 和我们以为发出去的是两回事，而没有任何一处会红 ——
# 这个项目在这个形状上栽过太多次。
CHECK="$(hdiutil attach -readonly -noverify -noautoopen "$OUT" | grep -o '/Volumes/.*$' | head -1)"
[ -n "$CHECK" ] || { echo "error: 成品 DMG 挂不上" >&2; exit 1; }
# **分两档：能不能装 vs 好不好看。**
#
# 第一版把两档混在一起，而且验不过就 `rm -f "$OUT"` —— 于是卷图标
# （纯装饰）没生效时，创始人拿到的是"没有成品，你没法测"。
# **一个装饰细节不该有权力把交付物删掉。**
fatal=""
cosmetic=""
[ -f "$CHECK/.background/background.tiff" ] || fatal="$fatal 背景图没进去；"
# **问那扇窗会怎么打开，不问 .DS_Store 有多少字节。**
# 字节数是 Finder 那条路留下的经验值，既不准也说不清哪里不对。
python3 "$HERE/write_ds_store.py" --verify-only "$CHECK" >/dev/null 2>&1 || \
  fatal="$fatal 窗样子没进成品（背景图/图标位置对不上）；"
# 卷图标：标题栏上那个小图标。没有也照样能装。
[ "$(GetFileInfo -a "$CHECK" 2>/dev/null | cut -c6)" = "C" ] || cosmetic="标题栏是通用磁盘图标"
hdiutil detach "$CHECK" >/dev/null

if [ -n "$fatal" ]; then
  # **不删。** 留着让人能打开看看到底哪里不对 —— 退出码已经拦住了发布。
  echo "error: DMG 的样子没摆上：$fatal" >&2
  echo "       成品留在 $OUT，打开看一眼。" >&2
  exit 1
fi
[ -n "$cosmetic" ] && echo "warn: $cosmetic（不影响安装）" >&2
echo "==> DMG 摆好了并验过：$OUT"
