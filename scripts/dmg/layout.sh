#!/bin/bash
# 造 DMG 并摆好那扇窗。**实现在 build_dmg.py**，这里只是 bundle.sh 的入口。
#
# 两条路走过：AppleScript 驱动 Finder（要人点授权框，于是 8/16 那版
# 发到线上时窗样子根本没进去），以及自己手写 `.DS_Store`（写漏了几格，
# Finder 把整块视图设置丢了，0.1.9 就是这么发出去的）。
# 现在用 dmgbuild —— 不再由我来"记得写全"哪几格。
set -euo pipefail

STAGING="$1"
OUT="$2"
VOL="${3:-METAG}"
HERE="$(cd "$(dirname "$0")" && pwd)"

python3 -c "import dmgbuild" 2>/dev/null || {
  echo "error: 缺 dmgbuild。装一次：" >&2
  echo "         uv pip install dmgbuild" >&2
  exit 1
}

python3 "$HERE/build_dmg.py" "$STAGING" "$OUT" "$VOL"
