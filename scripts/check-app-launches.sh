#!/bin/bash
# **造完就把它启一次。起不来就不发。**
#
# 2026-09-03：0.1.10 / 0.1.11 / 0.1.12 三版发出去都起不来，而每一版
# 都走完了整条流水线：签名通过、两次苹果公证 Accepted、`spctl` 判
# `accepted / Notarized Developer ID`、appcast 字节数对得上、
# 窗样子 17 格齐、从公网下回来挂开验过。
#
# **唯独没有人双击一次。**
#
# 真因是描述文件里那张证书和签名用的不是同一张，AMFI 在 exec 时 SIGKILL。
# 这个错**没有任何一条既有判据能看见**：它们全都在问"这个包对不对"，
# 而这一条问的是"它跑不跑得起来"。
#
# 用法：check-app-launches.sh <app 路径>
set -euo pipefail

APP="${1:?usage: check-app-launches.sh <app>}"
EXEC="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
[ -x "$EXEC" ] || { echo "FAIL 可执行文件不在：$EXEC"; exit 1; }

# **在一个干净的副本上跑**，不动交付物本身，也不碰用户已经装好的那份。
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ditto "$APP" "$TMP/$(basename "$APP")"
RUN="$TMP/$(basename "$APP")/Contents/MacOS/$(basename "$EXEC")"

# **这一发起的是 release 构建，而 release 构建会往生产漏斗发事件。**
#
# 2026-09-04：`exported` 那一格 1072 次是判据打进去的（那一批是单测，
# 已经改成跑在判据里一条都不发）。**而这里是另一条路** ——
# 它起的是真正的 .app，`isRunningTests` 认不出它，`#if DEBUG` 也不成立。
# 每发一次版就往生产漏斗灌一条 `landed`，而它长得和真人一模一样。
#
# `METAG_INTERNAL=1` 让 `MetagFunnel.isOurs` 认出自己，事件带 `probe` 标，
# 报表按 `NOT_OURS` 滤得掉。**不是不发** —— 发但认得出，
# 因为"启动之后活过 8 秒"这件事本身也值得留一条记录。
METAG_INTERNAL=1 "$RUN" >"$TMP/out.txt" 2>&1 &
PID=$!
sleep 8

if kill -0 "$PID" 2>/dev/null; then
  kill -9 "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  echo "SCOPE 1 个 app：启动一次"
  echo "OK   $(basename "$APP") 启动之后活过了 8 秒"
  exit 0
fi

wait "$PID" 2>/dev/null || CODE=$?
CODE="${CODE:-0}"
echo "SCOPE 1 个 app：启动一次"
echo "FAIL $(basename "$APP") 起来就死了（退出码 ${CODE}）"
if [ "$CODE" = 137 ]; then
  echo "     137 = SIGKILL：多半是签名/授权被 AMFI 拒了 ——"
  echo "     **公证通过和 spctl accepted 都看不见这一种**。"
  echo "     先比一下描述文件里那张证书和签名用的是不是同一张："
  echo "       security cms -D -i scripts/METAGAI.provisionprofile | plutil -extract DeveloperCertificates raw -o - -"
fi
head -5 "$TMP/out.txt" 2>/dev/null | sed 's/^/     /'
exit 1
