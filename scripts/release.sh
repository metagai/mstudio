#!/bin/bash
set -euo pipefail

# Usage: scripts/release.sh <version>       e.g. scripts/release.sh 0.1.3
#
# Full release pipeline:
#   1. Preflight (on main, tree clean, tag free, in sync with origin)
#   2. Bump CFBundleShortVersionString + auto-increment CFBundleVersion
#   3. Prompt for release notes in $EDITOR (prefilled with recent commits)
#   4. Run bundle.sh release --dist
#   5. Commit + push version bump
#   6. Tag + push tag
#   7. Update appcast.xml + commit + push
#   8. Upload DMG then appcast to metag.ai, verify both from the public net
#   9. Archive to GitHub (backup; a failure here does not undo the release)
#
# Bails out before anything public-visible if a preflight check fails.

if [ $# -ne 1 ]; then
  echo "usage: $0 <version>  (e.g. 0.1.3)" >&2
  exit 1
fi

VERSION="$1"
# **我们的 tag 带 `metag-` 前缀。**
#
# 这个仓库从 palmier-io/palmier-pro fork 出来，继承了它 fork 之前的全部 tag：
# `v0.1.2 … v0.1.29`、一直到 `v0.8.1`。而 METAG 自己的版本号走的也是 0.1.x ——
# **整个命名空间被占着**，挑一个"还没被用的号"是打地鼠，而且以后每跟一次上游
# 都可能再撞。
#
# 加前缀比换号好：用户看到的版本号（关于面板、appcast、下载文件名）**保持连续**，
# 0.1.8 之后就是 0.1.9；而 tag 永远不会再和上游撞。
TAG="metag-v$VERSION"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be X.Y.Z (got: $VERSION)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Sources/PalmierPro/Resources/Info.plist"
APPCAST="$ROOT/appcast.xml"
DMG="$ROOT/.build/METAG.dmg"
cd "$ROOT"

echo "==> Preflight"

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "error: no 'origin' remote. Create the release repo and add it:" >&2
  echo "  git remote add origin git@github.com:metag-ai/metag-mac.git" >&2
  echo "  (must match SUFeedURL in Sources/PalmierPro/Resources/Info.plist)" >&2
  exit 1
fi

# 默认分支**问 origin，不写死**。
#
# 这里原来写死 `main`，而这个仓库的默认分支是 `master`（而且不打算改名）——
# 也就是说**发版脚本的第一道门就永远关着**，谁都跑不到打包那一步。
# 写死一个名字，等于把"我这台机器上叫什么"钉进了交付流程。
DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "$DEFAULT_BRANCH" ]; then
  echo "error: must be on $DEFAULT_BRANCH (got: $BRANCH)" >&2
  exit 1
fi

if ! git diff-index --quiet HEAD --; then
  echo "error: working tree has uncommitted changes:" >&2
  git status --short >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists locally" >&2
  # 这个仓库是从 palmier-io/palmier-pro fork 出来的，**继承了它 fork 之前的 tag**
  # （v0.1.0 … v0.1.9，build 8/9/10，离现在 1000 多个提交）。而 METAG 自己的
  # 版本号又走到了 0.1.x —— 于是名字撞上，脚本第一道门就关着。
  # 光说"已存在"没用：他不知道是自己发过，还是撞了别人的。
  if [ "$(git rev-list --count "$TAG"..HEAD 2>/dev/null || echo 0)" -gt 500 ]; then
    echo "       这是 fork 之前上游留下的旧 tag（离 HEAD $(git rev-list --count "$TAG"..HEAD) 个提交），不是我们发过的版本。" >&2
  fi
  # **从当前发布的版本往上找**，不是从 1 开始 ——
  # 上游的 tag 有空档（0.1.24、0.1.26 没有），从头找会建议一个
  # 比线上已发布的还低的号，Sparkle 那侧等于降级。
  CUR="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo 0.0.0)"
  CUR_MAJOR="${CUR%%.*}"; CUR_REST="${CUR#*.}"
  CUR_MINOR="${CUR_REST%%.*}"; CUR_PATCH="${CUR_REST#*.}"
  NEXT_FREE=""
  for n in $(seq $((CUR_PATCH + 1)) $((CUR_PATCH + 200))); do
    cand="$CUR_MAJOR.$CUR_MINOR.$n"
    git rev-parse "metag-v$cand" >/dev/null 2>&1 || { NEXT_FREE="$cand"; break; }
  done
  [ -n "$NEXT_FREE" ] && echo "       下一个不冲突的版本号：$NEXT_FREE" >&2
  exit 1
fi

git fetch origin "$DEFAULT_BRANCH" --quiet
git fetch origin --tags --quiet
if git rev-parse "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists on origin" >&2
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/$DEFAULT_BRANCH)" ]; then
  echo "error: local main differs from origin/$DEFAULT_BRANCH. Push or pull first." >&2
  exit 1
fi

echo "==> Generating release notes from commit log"
NOTES_CLEAN="$(mktemp -t metag-release.XXXXXX).md"
trap 'rm -f "$NOTES_CLEAN"' EXIT
# **只认我们自己的 tag。** 不加 --match 的话它会挑到上游那些（离这里一千多个
# 提交），于是 release notes 从 fork 之前开始列，一千条。
LAST_TAG="$(git describe --tags --abbrev=0 --match 'metag-v*' 2>/dev/null || echo '')"
{
  echo "## What's new"
  echo ""
  if [ -n "$LAST_TAG" ]; then
    git log --pretty=format:"- %s" "$LAST_TAG..HEAD"
    echo ""
  else
    echo "First release."
  fi
} >"$NOTES_CLEAN"
echo "    (edit on GitHub later if you want to polish)"

echo "==> Bumping version"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
NEW_BUILD=$((CURRENT_BUILD + 1))

MAX_PUBLISHED="$(grep -oE '<sparkle:version>[0-9]+</sparkle:version>' "$APPCAST" \
  | grep -oE '[0-9]+' | sort -n | tail -1)"
if [ -n "$MAX_PUBLISHED" ] && [ "$NEW_BUILD" -le "$MAX_PUBLISHED" ]; then
  echo "error: NEW_BUILD=$NEW_BUILD is not greater than max published sparkle:version=$MAX_PUBLISHED" >&2
  echo "       Info.plist CFBundleVersion ($CURRENT_BUILD) was likely rolled back by an unrelated commit." >&2
  echo "       Set CFBundleVersion to $MAX_PUBLISHED in $PLIST and retry." >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"
echo "    $VERSION (build $NEW_BUILD)"

# 埋点 token 从仓库根的 .env 里取（gitignored，永不进脚本或日志）。
#
# **`bundle.sh` 一直会读 `POSTHOG_PROJECT_TOKEN`，而这里从来没设过它** ——
# 于是 `Analytics.swift`（12.6KB，事件铺满全 app）每一次上报都落进虚空。
# `founder-todo` §15 写着「等你去开通 PostHog」，而它 2026-09-04 查实早就
# 开通了：50 字符的真 token 一直躺在 .env 里，只差这三行。
#
# **取不到就发不出去。** 埋点静悄悄是空的，正是我们连瞎四个版本的那个形状
# （0.1.9–0.1.12 发出去打不开，靠创始人截图才发现）。要故意发一个瞎的包，
# 就显式写出来 —— 让它是一个决定，不是一次遗忘。
ENV_FILE="$(dirname "$0")/../../.env"
if [ -f "$ENV_FILE" ]; then
  POSTHOG_PROJECT_TOKEN="$(grep -m1 '^POSTHOG_PROJECT_TOKEN=' "$ENV_FILE" | cut -d= -f2- | tr -d '"'"'"' \r')"
  export POSTHOG_PROJECT_TOKEN
fi
if [ -z "${POSTHOG_PROJECT_TOKEN:-}" ] && [ "${ALLOW_BLIND_RELEASE:-}" != "1" ]; then
  echo "!! 拿不到 POSTHOG_PROJECT_TOKEN —— 这一版发出去我们看不见任何人在用它。" >&2
  echo "   token 在仓库根的 .env 里。真要发一个瞎的包：ALLOW_BLIND_RELEASE=1" >&2
  exit 1
fi
if [ -n "${POSTHOG_PROJECT_TOKEN:-}" ]; then
  echo "==> 埋点 token 已就位（${#POSTHOG_PROJECT_TOKEN} 字符，不打印内容）"
fi

echo "==> Building signed + notarized DMG"
BUILD_LOG="$(mktemp -t metag-build.XXXXXX).log"
trap 'rm -f "$NOTES_CLEAN" "$BUILD_LOG"' EXIT
./scripts/bundle.sh release --dist 2>&1 | tee "$BUILD_LOG"

# Only match the real signature line (which has length="<digits>"), not the
# instruction hint text that bundle.sh also prints.
SIG_LINE="$(grep -E 'edSignature="[^"]+".*length="[0-9]+"' "$BUILD_LOG" | tail -1)"
SIGNATURE="$(echo "$SIG_LINE" | sed -E 's/.*edSignature="([^"]+)".*/\1/')"
LENGTH="$(echo "$SIG_LINE" | sed -E 's/.*length="([0-9]+)".*/\1/')"
if [ -z "$SIGNATURE" ] || ! [[ "$LENGTH" =~ ^[0-9]+$ ]]; then
  echo "error: couldn't extract Sparkle signature or numeric length from build output" >&2
  echo "  got SIGNATURE=$SIGNATURE" >&2
  echo "  got LENGTH=$LENGTH" >&2
  exit 1
fi

echo "==> Committing + pushing version bump"
git add "$PLIST"
git commit -m "Bump to $VERSION"
git push origin "$DEFAULT_BRANCH"

echo "==> Tagging $TAG"
git tag "$TAG"
git push origin "$TAG"

echo "==> Updating appcast.xml"
PUBDATE="$(date -R)"
export VERSION NEW_BUILD PUBDATE LENGTH SIGNATURE
python3 <<'PYEOF'
import os
v = os.environ["VERSION"]
b = os.environ["NEW_BUILD"]
d = os.environ["PUBDATE"]
l = os.environ["LENGTH"]
s = os.environ["SIGNATURE"]
# 下载地址是 **metag.ai**，不是 GitHub。
# 上一版写的是 https://github.com/metag-ai/metag-mac/releases/... ——
# 那个仓库不存在（2026-09-03 实测 404），而 origin 是 metagai/mstudio。
# 也就是说这一行会把一个死链写进 appcast，**每个用户的自动更新当场坏掉**，
# 而在此之前没人跑完过这个脚本，所以没人撞见。
# 线上已发布的两条（0.1.7 / 0.1.8）用的都是 metag.ai，跟着它。
url = f"https://metag.ai/mac/METAG-{v}.dmg"

# **版本号在 `<item>` 里和 `<enclosure>` 上各写一遍。**
#
# 看着冗余，但已发布的两条都是这个形状，而 `verify.sh` 的
# 「已装好的那台 Mac 收得到下一版」读的正是 enclosure 上那个属性。
# 2026-09-03 发完 0.1.9，只写了元素形式 —— 门读到的还是上一版的 0.1.8，
# 判据对着一条**已经不是最新的**记录说"三处对不上"。
# Sparkle 两种都认；不一致的是我们自己。
item = f"""        <item>
            <title>Version {v}</title>
            <pubDate>{d}</pubDate>
            <sparkle:version>{b}</sparkle:version>
            <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure url="{url}"
                       sparkle:version="{b}"
                       sparkle:shortVersionString="{v}"
                       length="{l}"
                       type="application/octet-stream"
                       sparkle:edSignature="{s}" />
        </item>"""

# **新的放最前面。**
#
# 上一版是 `content.replace("    </channel>", item + ...)` —— 追加到末尾。
# Sparkle 自己取版本号最大的那条，所以它不会挑错；
# 但这个文件的既有约定是新的在前（0.1.8、0.1.7），而
# `verify.sh` 的「已装好的那台 Mac 收得到下一版」读的正是**第一条**。
# 于是 2026-09-03 发完 0.1.9，门当场红：「appcast 0.1.8 · Info.plist 0.1.9」。
#
# 两个读法不一致，本身就是隐患 —— 统一成「最新的在最前」。
path = "appcast.xml"
with open(path) as f:
    content = f.read()
first = content.index("        <item>")
content = content[:first] + item + "\n" + content[first:]
with open(path, "w") as f:
    f.write(content)
PYEOF

git add "$APPCAST"
git commit -m "Add $TAG to appcast"
git push origin "$DEFAULT_BRANCH"

# ==> 真正的发布
#
# **提交到仓库不等于发布。** Sparkle 读的是 `SUFeedURL`，也就是
# https://metag.ai/mac/appcast.xml —— 那是这台机器上的一个文件，
# 和仓库里那份是两回事（只是长期靠人手工同步，才看起来一样）。
# 上一版脚本到上面那行就结束了，于是**每一次"发版"都不会有任何用户收到更新**。
PUBLISH_HOST="${PUBLISH_HOST:-yons@47.252.113.151}"
PUBLISH_DIR="${PUBLISH_DIR:-/home/yons/metag/mac}"
REMOTE_DMG="METAG-$VERSION.dmg"

# **先传 DMG，后传 appcast。** 反过来的话，中间那几十秒里 appcast 已经在
# 告诉所有人有新版了，而那个包还没上去 —— 他们点更新，拿到 404。
echo "==> Uploading DMG to $PUBLISH_HOST:$PUBLISH_DIR/$REMOTE_DMG"
scp "$DMG" "$PUBLISH_HOST:$PUBLISH_DIR/$REMOTE_DMG"
echo "==> Uploading appcast"
scp "$APPCAST" "$PUBLISH_HOST:$PUBLISH_DIR/appcast.xml"

# **判据落在用户走的那条路上**：不问"scp 退出码是 0 吗"，
# 问"从公网取那两个文件，拿到的是不是这一版"。
echo "==> Verifying what a user's updater would actually see"
LIVE_LEN="$(curl -sSI --max-time 30 "https://metag.ai/mac/$REMOTE_DMG" \
  | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)"
if [ "$LIVE_LEN" != "$LENGTH" ]; then
  echo "error: https://metag.ai/mac/$REMOTE_DMG 的大小是 ${LIVE_LEN:-取不到}，appcast 里写的是 $LENGTH" >&2
  echo "       用户点更新会拿到一个对不上签名的包。发布没有完成。" >&2
  exit 1
fi
if ! curl -sS --max-time 30 https://metag.ai/mac/appcast.xml | grep -q "$REMOTE_DMG"; then
  echo "error: 线上的 appcast 里没有 $REMOTE_DMG —— 没有人会收到这次更新" >&2
  exit 1
fi

# **归档放最后，而且不许它挡路。**
#
# 上一版把 `gh release create` 排在 appcast 和上传**之前**：GitHub 抖一下
# （或者 77MB 传到一半断了），脚本就在 tag 已经推上去、而用户什么都没收到的
# 状态下退出 —— 而重跑会撞"tag 已存在"，人被卡在中间。
#
# 用户拿片子靠 metag.ai，GitHub 这份只是异地备份。**备份失败不该拦住交付。**
echo "==> Archiving to GitHub (备份，失败不影响已完成的发布)"
# **`--repo` 不能省。** `gh` 自己挑远端，而这个仓库还留着 `upstream`
# （palmier-io/palmier-pro）—— 2026-09-03 它就挑了那个，报
# 「tag exists locally but has not been pushed to palmier-io/palmier-pro」。
# 幸好这一步排在交付之后，只是没归档成。
GH_REPO_SLUG="$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
if ! gh release create "$TAG" "$DMG" --repo "$GH_REPO_SLUG" --title "$TAG" --notes-file "$NOTES_CLEAN"; then
  echo "!! GitHub 归档没成功 —— **发布本身已经完成**（上面那两条公网校验是绿的）。" >&2
  echo "   补一次：gh release create $TAG $DMG --repo $GH_REPO_SLUG --title $TAG" >&2
fi

# **发完把网关要的那几个数打印出来。**
#
# 落地页现在会在他点下载之前判断这台装不装得上，而那条判断依赖两个事实：
# 最低系统版本、安装后体积。前端把它们写死在自己那侧 ——
# 「两处要一起改」的东西，迟早只有一处改了，而那时页面会
# **当着一个装得上的人的面说"你装不了"**，比不提示更糟。
#
# 真源在这里：`Info.plist` 的 `LSMinimumSystemVersion` 和刚构建出来的 `.app`。
# 网关把它们吐进 `/api/v1/download/mac/meta`，前端就能把写死的那几行删掉。
MIN_MACOS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST")"
APP_BYTES="$(du -sk "$ROOT/.build/METAG.app" | awk '{print $1 * 1024}')"
echo ""
# ==> 网站那条下载路，这个脚本既没填也没验
#
# **发版有两条互不相干的路，文件名都不一样：**
#
#   Sparkle 自动更新   metag.ai/mac/METAG-{v}.dmg          ← 上面刚传的、刚验的
#   网站点"下载"       两个桶/METAG-{v}-mac.dmg            ← 这个脚本碰都没碰
#
# 2026-09-03：我核完上面那条就说"完整核实通过"，而网站那条的两个桶里
# 当时只有到 0.1.10。网关常量一改成 0.1.11，**下载按钮在两个区同时坏了
# （海外 404、国内 403），页面照常渲染、一处不报错。**
#
# 这正是 `docs/lessons.md` 第四十条：**我修的、我验的，都是我最熟的那条路。**
# 所以这里主动去探一下另一条 —— 探不到不算发版失败（Sparkle 那条是真的成了），
# 但**必须挡住"让网关声称这一版"那一步**：素材永远先于声明它的页面。
probe_bucket() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 25 -r 0-0 "$1" 2>/dev/null || echo 000
}
R2_URL="https://s3.metag.ai/metag/metag/releases/METAG-$VERSION-mac.dmg"
OSS_URL="https://metagai.oss-cn-beijing.aliyuncs.com/metag/releases/METAG-$VERSION-mac.dmg"
R2_CODE="$(probe_bucket "$R2_URL")"
OSS_CODE="$(probe_bucket "$OSS_URL")"
echo ""
if [[ "$R2_CODE" =~ ^20[06]$ && "$OSS_CODE" =~ ^20[06]$ ]]; then
  echo "==> 网站下载路也就位了（R2 $R2_CODE · OSS $OSS_CODE）"
else
  echo "⚠️  网站那条下载路还没就位 —— R2 $R2_CODE · OSS $OSS_CODE" >&2
  echo "    这两个桶要的是 METAG-$VERSION-mac.dmg（注意文件名和上面那条不一样）" >&2
  echo "    **在它们能取到之前，别让网关 meta 声称 $VERSION** —— " >&2
  echo "    网关按版本号拼下载地址，声称早一步 = 下载按钮两个区同时 404/403，而页面不报错。" >&2
fi

# ⚠ **这是数，不是契约。** 形状由网关那侧定，别照着这里的引号写解析。
#
# 2026-09-03：我这份样例把 `min_macos` 写成 `"26.0"`（那是 `Info.plist` 里
# `LSMinimumSystemVersion` 的原文），网关实现发的是整数 `26`，
# 而落地页照着我的样例写了 `(x ?? '').split('.')` —— 对整数调 `.split` 直接抛，
# **两个站首页白屏**。三方都没写错，是三方对同一个字段的形状各自假设了一次。
#
# 契约已定死在整数那一侧（比大小是这个数唯一的用途，整数是它的自然形状）。
# 这里继续吐原文，网关取整。
echo "==> 网关 meta 要的数（partner：照抄数值，形状以网关文档为准）"
cat <<META
{
  "version":        "$VERSION",
  "bytes":          $LENGTH,
  "released":       "$(date +%Y-%m-%d)",
  "min_macos":      "$MIN_MACOS",
  "installed_bytes": $APP_BYTES
}
META

echo ""
echo "==> Released $TAG"
echo "    下载：https://metag.ai/mac/$REMOTE_DMG"
echo "    自动更新：https://metag.ai/mac/appcast.xml（已实测能取到这一版）"
echo "    归档：$(git remote get-url origin | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##')/releases/tag/$TAG"
