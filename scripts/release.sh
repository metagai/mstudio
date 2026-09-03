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
#   7. gh release create with the DMG and notes
#   8. Update appcast.xml + commit + push
#
# Bails out before anything public-visible if a preflight check fails.

if [ $# -ne 1 ]; then
  echo "usage: $0 <version>  (e.g. 0.1.3)" >&2
  exit 1
fi

VERSION="$1"
TAG="v$VERSION"

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
  NEXT_FREE=""
  for n in $(seq 1 200); do
    cand="v0.1.$n"
    git rev-parse "$cand" >/dev/null 2>&1 || { NEXT_FREE="0.1.$n"; break; }
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
LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo '')"
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

echo "==> Creating GH release"
gh release create "$TAG" "$DMG" --title "$TAG" --notes-file "$NOTES_CLEAN"

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

item = f"""        <item>
            <title>Version {v}</title>
            <pubDate>{d}</pubDate>
            <sparkle:version>{b}</sparkle:version>
            <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="{url}"
                length="{l}"
                type="application/octet-stream"
                sparkle:edSignature="{s}"/>
        </item>"""

path = "appcast.xml"
with open(path) as f:
    content = f.read()
content = content.replace("    </channel>", item + "\n    </channel>")
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

echo ""
echo "==> Released $TAG"
echo "    下载：https://metag.ai/mac/$REMOTE_DMG"
echo "    自动更新：https://metag.ai/mac/appcast.xml（已实测能取到这一版）"
echo "    归档：$(git remote get-url origin | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##')/releases/tag/$TAG"
