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
# ## 失败就是失败
#
# 摆样子要用 AppleScript 驱动 Finder，需要"自动化"权限。
# 拿不到权限时**直接退出**，不悄悄回落成一个没背景的 DMG ——
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

# **卷图标要打标记才生效。** 光把 `.VolumeIcon.icns` 拷进去不够 ——
# 没有这一句，标题栏上是系统通用的磁盘映像图标，不是 METAG。
# （2026-09-02 真机截图照出来的：标题栏那个小灰图标。）
if [ -f "$MOUNT/.VolumeIcon.icns" ]; then
  SetFile -a C "$MOUNT"
fi

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
osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- **含标题栏。** 内容区 = 高度 - 29pt，背景图按 660×370 排的。
    set the bounds of container window to {200, 160, 860, 559}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "METAG.app" of container window to {180, 171}
    set position of item "Applications" of container window to {480, 171}
    update without registering applications
    close
  end tell
end tell
EOF

# Finder 把 .DS_Store 写回去需要一点时间；不等就可能压进一个还没落盘的版本。
sync; /bin/sleep 2

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
fail=""
[ -f "$CHECK/.background/background.tiff" ] || fail="$fail 背景图没进去"
# 卷图标的自定义标记 —— 没打的话标题栏是通用磁盘图标。
[ "$(GetFileInfo -a "$CHECK" 2>/dev/null | cut -c6)" = "C" ] || fail="$fail 卷图标没生效"
# 空 .DS_Store 约 6KB；带了视图设置和两个图标位置的会明显更大。
size=$(stat -f%z "$CHECK/.DS_Store" 2>/dev/null || echo 0)
[ "$size" -gt 8000 ] || fail="$fail .DS_Store 只有 ${size}B（样子没摆上）"
hdiutil detach "$CHECK" >/dev/null
if [ -n "$fail" ]; then
  rm -f "$OUT"
  echo "error:$fail" >&2
  echo "       —— 没有摆好样子的 DMG 不算成品，已删除。" >&2
  exit 1
fi
echo "==> DMG 摆好了并验过：$OUT"
