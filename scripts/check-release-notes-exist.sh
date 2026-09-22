#!/bin/bash
# **这一版有没有自己的更新说明 —— 问造好的那个包，不问源码。**
#
# 2026-09-13 发了 0.1.19。自动更新把它推给了每一个人，而**用户点开更新说明
# 看到的是空白**：`changelog.json` 里根本没有 0.1.19 这一条。
# 整条流水线全绿 —— 签名、公证、appcast、启动检查 —— **没有一处在问
# 「这一版有没有话对用户说」。**
#
# `ChangelogStore` 是精确匹配：`entries.first { $0.version == current }`，
# 其中 current 来自 `CFBundleShortVersionString`。对不上就是 nil，就是空白。
#
# ⚠ **读的是包里那两个文件，不是仓库里的。** 版本号是 release.sh 在构建
# 之前才 +1 的，源码那份在构建时已经过期；而真正发出去的是这个 .app。
# ⚠ **变量一律写 `${VAR}`。** 这个仓库里提示语全是中文，而 `$VERSION：`
# 会把那个全角冒号吞进变量名 —— bash 报 `VERSION：: unbound variable`。
# 2026-09-22 一晚上两处同一个原因（另一处在 deploy.sh 的走查分类里），
# 两处都是**写完读过、语法检查过、而那几行从来没被执行过**。
set -euo pipefail

APP="${1:?usage: check-release-notes-exist.sh <app>}"
PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")

# 资源可能在两处（`swift run` 与打包后的布局不同）——和 Changelog.swift 同一份清单。
RES="$APP/Contents/Resources"
JSON=""
for c in "$RES/Changelog/changelog.json" \
         "$RES/PalmierPro_PalmierPro.bundle/Contents/Resources/Changelog/changelog.json" \
         "$RES/PalmierPro_PalmierPro.bundle/Changelog/changelog.json"; do
  [ -f "$c" ] && { JSON="$c"; break; }
done
if [ -z "$JSON" ]; then
  echo "✗ 包里找不到 changelog.json —— 更新说明这一栏对每个用户都是空白" >&2
  exit 1
fi

# **反例长什么样**：版本号在 plist 里，而 entries 里没有同名的一条。
FOUND=$(/usr/bin/python3 - "$JSON" "$VERSION" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8")).get("entries") or []
hit = next((e for e in entries if e.get("version") == sys.argv[2]), None)
if not hit:
    print("MISSING " + ",".join(e.get("version", "?") for e in entries[:4]))
else:
    n = sum(len(s.get("items") or []) for s in (hit.get("sections") or []))
    print(("EMPTY " if n == 0 else "OK ") + str(n))
PY
)
case "$FOUND" in
  OK*)      echo "  ✓ 更新说明有这一版：${VERSION}（${FOUND#OK } 条）" ;;
  EMPTY*)   echo "✗ ${VERSION} 这一条在，但一句话都没有 —— 和空白没区别" >&2; exit 1 ;;
  MISSING*) echo "✗ 包里是 ${VERSION}，而 changelog.json 里最新的几条是 ${FOUND#MISSING } —— 用户点开会是空白" >&2; exit 1 ;;
esac
