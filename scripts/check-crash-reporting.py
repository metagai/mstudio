#!/usr/bin/env python3
"""崩了我们会不会知道。

## 为什么这条判据存在

A0 那张"实验开始前必须先修好"的清单上，唯一挂着 ❌ 的一条是
**「崩了我们不会知道」**。它的形状比缺功能更险：

    埋点断了   看到的是"没人在用"
    崩溃断了   看到的是"一条崩溃都没有"  ← **那正是我们希望看到的样子**

而它的每一环都能单独装好、然后在别处断掉：

    值填了            但填进了脚本不读的那个 .env（2026-09-07 实测撞到）
    值是真的          但 ORG/PROJECT 是 1 个字符的占位符（同上）
    token 认得过      但 DSN 指的是另一个项目 —— **崩溃报到一个没人看的地方**
    发出去 200        **摄取端点对垃圾 token 也返 200**，200 证明不了任何事

所以这条判据只认一件事：**发一条上去，再从 API 读回来。**

## 探针不许污染真实崩溃

发的那条带 `environment=probe` + `tags.probe=true`，报表按它滤得掉 ——
和 `workers/probe_metric.py` 同一个约定（"上新指标之前先跑一次"）。

## 用法

    check-crash-reporting.py            读回来才算通
    check-crash-reporting.py --config   只查配置，不发事件（离线也能跑）
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://sentry.io/api/0"


def env_value(key: str, minimum: int = 1) -> str:
    """两个 .env 都读，mac/ 优先 —— 和 `release.sh` 同一个规矩。

    **占位符等于没填**：1 个字符的 SENTRY_ORG 用 `if value` 判是真的，
    然后 sentry-cli 拿它去传符号表、失败，而我们以为传上去了。
    """
    for path in (ROOT / ".env", ROOT.parent / ".env"):
        if not path.exists():
            continue
        for line in path.read_text().splitlines():
            if line.startswith(f"{key}="):
                value = line.split("=", 1)[1].strip().strip("\"'")
                if len(value) >= minimum:
                    return value
    return ""


def api(path: str, token: str) -> tuple[int, object]:
    req = urllib.request.Request(f"{API}{path}", headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:  # noqa: BLE001
        return 0, str(e)


def main() -> int:
    config_only = "--config" in sys.argv
    failed = False

    dsn = env_value("SENTRY_DSN", 20)
    token = env_value("SENTRY_AUTH_TOKEN", 16)
    org = env_value("SENTRY_ORG", 2)
    project = env_value("SENTRY_PROJECT", 2)

    for name, value in (("SENTRY_DSN", dsn), ("SENTRY_AUTH_TOKEN", token),
                        ("SENTRY_ORG", org), ("SENTRY_PROJECT", project)):
        if not value:
            print(f"FAIL {name} 没填（或是占位符）—— 见 founder-todo §15")
            failed = True
    if failed:
        print("SCOPE 4 个凭据")
        return 1
    print(f"OK   四个值都在（DSN {len(dsn)} 字符，不打印内容）")

    # DSN 里的 project id
    dsn_project = dsn.rstrip("/").rsplit("/", 1)[-1]

    status, project_info = api(f"/projects/{org}/{project}/", token)
    if status != 200 or not isinstance(project_info, dict):
        print(f"FAIL 拿不到项目 {org}/{project}（HTTP {status}）—— token 或 slug 不对")
        print("SCOPE 4 个凭据")
        return 1

    # **这一条以前没人查过。** token 对、slug 对，而 DSN 指着另一个项目 ——
    # 崩溃会报到一个没人看的地方，而每一环单独看都是绿的。
    if str(project_info.get("id")) != dsn_project:
        print(f"FAIL DSN 指的项目（{dsn_project}）不是 {org}/{project}（{project_info.get('id')}）")
        print("     崩溃会报到一个没人看的项目里，而每一环单独看都是对的")
        print("SCOPE 4 个凭据 + 1 次项目比对")
        return 1
    print(f"OK   DSN 和 {org}/{project} 指的是同一个项目（{dsn_project}）")

    if config_only:
        print("SCOPE 4 个凭据 + 1 次项目比对（--config：没发事件）")
        return 0

    # ── 唯一算数的那一步：发一条，再读回来 ──────────────────────
    event_id = uuid.uuid4().hex
    key = dsn.split("//", 1)[1].split("@", 1)[0]
    host = dsn.split("@", 1)[1].split("/", 1)[0]
    body = json.dumps({
        "event_id": event_id,
        "platform": "cocoa",
        "level": "error",
        "environment": "probe",
        "release": "probe",
        "tags": {"probe": "true"},
        # ⚠ **这句话就是分组键，别改。**
        #
        # Sentry 按 message 分组，而这一组（MSTUDIO-2）已经被永久归档 ——
        # 于是探针每跑一次不再给创始人发一封邮件。
        # 2026-09-07 他收到过：10 封，全是这个探针。**十封"不是真崩溃"
        # 会教会人跳过 Sentry 的邮件，而下一封可能是真的。**
        # 改这句话等于开一个新分组，邮件立刻回来。
        "message": {"formatted": "METAG crash-reporting probe (not a real crash)"},
    }).encode()
    req = urllib.request.Request(
        f"https://{host}/api/{dsn_project}/store/", data=body,
        headers={
            "Content-Type": "application/json",
            "X-Sentry-Auth": f"Sentry sentry_version=7, sentry_key={key}, sentry_client=metag-probe/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            sent = r.status
    except Exception as e:  # noqa: BLE001
        print(f"FAIL 发不出去：{e}")
        print("SCOPE 4 个凭据 + 1 次项目比对 + 1 条探针事件")
        return 1
    # ⚠ **200 在这里什么都不证明** —— 摄取端点对垃圾 token 也返 200。
    print(f"OK   探针已发出（HTTP {sent}）—— 但这一行不算证据，下一行才算")

    for attempt in range(1, 21):
        status, event = api(f"/projects/{org}/{project}/events/{event_id}/", token)
        if status == 200 and isinstance(event, dict):
            tags = {t["key"]: t["value"] for t in event.get("tags", [])}
            print(f"OK   **读回来了**（第 {attempt} 次，environment={tags.get('environment')}，"
                  f"probe={tags.get('probe')}）—— 崩了我们会知道")
            print("SCOPE 4 个凭据 + 1 次项目比对 + 1 条探针事件（发+读回）")
            return 0
        time.sleep(3)

    print("FAIL 发出去了，20 次都读不回来 —— **发出去了不等于记下来了**")
    print("SCOPE 4 个凭据 + 1 次项目比对 + 1 条探针事件（发+读回）")
    return 1


if __name__ == "__main__":
    sys.exit(main())
