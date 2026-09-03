#!/usr/bin/env python3
"""最低系统版本：现在有**四处**写着同一个数，而它们谁也不认识谁。

| 谁 | 写在哪 |
|---|---|
| 构建 | `Package.swift` 的 `platforms: [.macOS(.vNN)]` |
| 启动 | `Sources/PalmierPro/Resources/Info.plist` 的 `LSMinimumSystemVersion` |
| 自动更新 | `appcast.xml` 每一条的 `sparkle:minimumSystemVersion` |
| 下载页 | `web/landing/src/lib/mac-fit.ts` 的 `MIN_MACOS`（+ 三语文案各一遍） |

**对不上的后果各不相同，而且都不报错：**

- `Info.plist` 比实际低 → 他装上了，双击闪退，我们收不到任何信号
- `appcast` 比实际低 → Sparkle 给他推一个装不上的更新（0.1.7/0.1.8 就是这样：
  声明 14.0 而 app 要 26.0，2026-09-03 订正）
- 下载页比实际高 → **当着一个装得上的人的面说"你装不了"**，比不提示更糟

这条只管我这侧的三处。落地页那一处在另一个仓库，
真源应该由网关 meta 吐出来（`min_macos`）—— 在那之前，
`release.sh` 每次发版会把这个数打印出来，人工跟。
"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    pkg = (ROOT / "Package.swift").read_text()
    m = re.search(r"platforms:\s*\[\.macOS\(\.v(\d+)\)\]", pkg)
    if not m:
        print("FAIL Package.swift 里找不到 platforms —— 判据够不着它了")
        return 1
    build = int(m.group(1))

    plist = plistlib.loads((ROOT / "Sources/PalmierPro/Resources/Info.plist").read_bytes())
    launch = plist.get("LSMinimumSystemVersion", "")
    feed = re.findall(r"<sparkle:minimumSystemVersion>([\d.]+)</sparkle:minimumSystemVersion>",
                      (ROOT / "appcast.xml").read_text())

    fails = []
    checks = 1 + len(feed)
    if not launch.startswith(f"{build}."):
        fails.append(f"Package.swift 要 macOS {build}，而 Info.plist 写着 {launch or '没写'}"
                     " —— 他装上了，双击闪退，我们收不到任何信号")
    for v in feed:
        if not v.startswith(f"{build}."):
            fails.append(f"appcast 里有一条写着 minimumSystemVersion {v}，而 app 要 {build}"
                         " —— Sparkle 会给他推一个装不上的更新，而且不报错")

    if fails:
        print(f"SCOPE {checks} 处最低系统版本")
        for f in fails:
            print(f"FAIL {f}")
        return 1
    print(f"SCOPE {checks} 处最低系统版本")
    print(f"OK   构建 / 启动 / 自动更新 三处都是 macOS {build}"
          f"（appcast {len(feed)} 条）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
