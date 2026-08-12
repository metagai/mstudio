#!/bin/bash
set -euo pipefail

# Usage:
#   scripts/bundle.sh [release|debug]           # ad-hoc signed dev build
#   scripts/bundle.sh debug --fast              # fastest: skip dSYM + deep sign, just env+build
#   scripts/bundle.sh debug --speech             # include bundled speech and MLX
#   scripts/bundle.sh debug --all                # include all optional traits
#   scripts/bundle.sh release --sign            # build + Developer ID codesign
#   scripts/bundle.sh release --dist            # build + sign + notarize + staple + DMG
#   scripts/bundle.sh release --dmg             # build + ad-hoc sign + DMG (what we actually ship
#                                               #   until there is a Developer ID certificate)

CONFIG="release"
MODE="dev"
ENABLE_ALL_TRAITS=false
INCLUDE_BUNDLED_SPEECH=false
for arg in "$@"; do
  case "$arg" in
    release|debug) CONFIG="$arg" ;;
    --fast)        MODE="fast" ;;
    --sign)        MODE="sign" ;;
    --dist)        MODE="dist" ;;
    --dmg)         MODE="dmg" ;;
    # 开发构建默认不带打包语音与 MLX（上游 #440）—— 每次 debug 都编一遍
    # MLX 是纯浪费；release 仍然全带，见下面的 CONFIG 分支。
    --speech)      INCLUDE_BUNDLED_SPEECH=true ;;
    --all)
      ENABLE_ALL_TRAITS=true
      INCLUDE_BUNDLED_SPEECH=true
      ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

if [ "$CONFIG" = "release" ]; then
  # release 用 --enable-all-traits，行为与改动前一致（含 ProductionTelemetry：
  # Sentry + PostHog，我们本来就在发版里带它，隐私政策里已披露）。
  # 改的只有 debug：默认不再编 BundledSpeech / MLX —— 每次开发构建都编一遍是纯浪费。
  # 需要时 `--speech` 或 `--all` 显式打开。
  ENABLE_ALL_TRAITS=true
  INCLUDE_BUNDLED_SPEECH=true
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ENV_FILE=".env"
if [ "$CONFIG" = "release" ] && [ -f "$ROOT/.env.prod" ]; then
  ENV_FILE=".env.prod"
fi
if [ -f "$ROOT/$ENV_FILE" ]; then
  echo "==> Loading $ENV_FILE"
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/$ENV_FILE"
  set +a
fi

APPLE_TEAM_ID="${APPLE_TEAM_ID:-V969594VAF}"
# **Mac App 的 Bundle ID 是 `ai.metag.mac`，不是 `ai.metag`。**
# `ai.metag` 早已注册成 **Services ID**（网页版 Sign in with Apple 用），
# 而 Services ID 与 App ID **共用同一个标识符命名空间** —— 同一个字符串
# 不能既当网页登录身份、又当 App 身份。表现是建 App ID 时报
# "not available"，且 Developer ID profile 的下拉里根本看不到它。
# 这不是配置错了，是两种实体的命名冲突。
BUNDLE_ID="ai.metag.mac"
# No default identity: a wrong one silently produces an app nobody else can launch.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-metag-notary}"
SENTRY_DSN="${SENTRY_DSN:-}"
POSTHOG_PROJECT_TOKEN="${POSTHOG_PROJECT_TOKEN:-}"
POSTHOG_HOST="${POSTHOG_HOST:-https://us.i.posthog.com}"
PROVISION_PROFILE="${PROVISION_PROFILE:-$ROOT/scripts/METAGAI.provisionprofile}"
ENTITLEMENTS="$ROOT/scripts/METAG.entitlements"
KEYCHAIN_ACCESS_GROUP="${KEYCHAIN_ACCESS_GROUP:-$APPLE_TEAM_ID.$BUNDLE_ID}"
RESOURCES="$ROOT/Sources/PalmierPro/Resources"
APP="$ROOT/.build/METAG.app"
ZIP="$ROOT/.build/METAG.zip"
DMG="$ROOT/.build/METAG.dmg"

# Signing preflight up front: fail before a 90-second build, not after.
if [ "$MODE" = "sign" ] || [ "$MODE" = "dist" ]; then
  if [ -z "$SIGNING_IDENTITY" ]; then
    echo "!! SIGNING_IDENTITY is not set." >&2
    echo "   Set it in $ENV_FILE, e.g." >&2
    echo "     SIGNING_IDENTITY=\"Developer ID Application: <Your Org> ($APPLE_TEAM_ID)\"" >&2
    echo "   List installed identities with: security find-identity -v -p codesigning" >&2
    exit 1
  fi
  if ! security find-identity -v -p codesigning | grep -qF "$SIGNING_IDENTITY"; then
    echo "!! codesigning identity not found in any keychain: $SIGNING_IDENTITY" >&2
    exit 1
  fi
fi

# Entitlements drift breaks signing in ways that only show up on another Mac.
if [ "$MODE" = "sign" ] || [ "$MODE" = "dist" ]; then
  ENT_APP_ID="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$ENTITLEMENTS")"
  PLIST_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$RESOURCES/Info.plist")"
  if [ "$ENT_APP_ID" != "$APPLE_TEAM_ID.$PLIST_BUNDLE_ID" ]; then
    echo "!! $ENTITLEMENTS declares application-identifier '$ENT_APP_ID'" >&2
    echo "   but the team + bundle id are '$APPLE_TEAM_ID.$PLIST_BUNDLE_ID'" >&2
    exit 1
  fi
fi

BUILD_ARGS=(-c "$CONFIG")
if $ENABLE_ALL_TRAITS; then
  TRAITS="all"
  BUILD_ARGS+=(--enable-all-traits)
else
  TRAITS=""
  if $INCLUDE_BUNDLED_SPEECH; then
    TRAITS="BundledSpeech"
  fi
  if [ -n "$TRAITS" ]; then
    BUILD_ARGS+=(--traits "$TRAITS")
  fi
fi

echo "==> Building ($CONFIG, traits: ${TRAITS:-none})"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/PalmierPro"
SPARKLE_FW="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
# The executable name stays PalmierPro: it is the SwiftPM product name and
# CFBundleExecutable / NSDocumentClass in Info.plist depend on it.
cp "$BIN" "$APP/Contents/MacOS/PalmierPro"
cp "$RESOURCES/Info.plist" "$APP/Contents/Info.plist"

if [ -n "$SENTRY_DSN" ]; then
  echo "==> Injecting SentryDSN into Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :SentryDSN" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :SentryDSN string $SENTRY_DSN" "$APP/Contents/Info.plist"
else
  echo "==> SENTRY_DSN not set — telemetry will be a no-op in this build"
fi

if [ -n "$POSTHOG_PROJECT_TOKEN" ]; then
  echo "==> Injecting PostHog analytics config into Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :PostHogProjectToken" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :PostHogProjectToken string $POSTHOG_PROJECT_TOKEN" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :PostHogHost" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :PostHogHost string $POSTHOG_HOST" "$APP/Contents/Info.plist"
else
  echo "==> POSTHOG_PROJECT_TOKEN not set — product analytics will be a no-op in this build"
fi

inject_plist() {
  local key="$1" value="$2"
  if [ -z "$value" ]; then
    echo "== $key not set in $ENV_FILE — the features reading it stay unavailable" >&2
    return
  fi
  /usr/libexec/PlistBuddy -c "Delete :$key" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$APP/Contents/Info.plist"
}

# Clerk/Convex only still drive the in-app Agent chat panel; generation and billing
# moved to the METAG gateway. Unset here means that panel is unavailable, nothing else.
echo "==> Injecting backend config into Info.plist"
inject_plist PalmierClerkPublishableKey "${CLERK_PUBLISHABLE_KEY:-}"
inject_plist PalmierConvexDeploymentURL "${CONVEX_DEPLOYMENT_URL:-}"
inject_plist PalmierConvexHttpURL "${CONVEX_HTTP_URL:-}"
cp "$RESOURCES/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

# Flatten SwiftPM's resource bundle into the app's Resources tree.
RES_BUNDLE="$(dirname "$BIN")/PalmierPro_PalmierPro.bundle"
if [ -d "$RES_BUNDLE/Fonts" ]; then
  cp -R "$RES_BUNDLE/Fonts" "$APP/Contents/Resources/"
else
  echo "!! missing Fonts/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi

# Ensure the shipped Claude Desktop connector is always up to date with mcpb/ sources.
MCPB_SRC="$ROOT/mcpb"
MCPB_CHECKED_IN="$ROOT/Sources/PalmierPro/Resources/MCPB/metag.mcpb"
MCPB_FRESH="$(mktemp -d)/metag.mcpb"
(cd "$MCPB_SRC" && zip -q -X -r "$MCPB_FRESH" manifest.json icon.png server/index.js server/package.json)
if ! unzip -p "$MCPB_CHECKED_IN" server/index.js 2>/dev/null | diff -q - <(unzip -p "$MCPB_FRESH" server/index.js) >/dev/null 2>&1 \
  || ! unzip -p "$MCPB_CHECKED_IN" manifest.json 2>/dev/null | diff -q - <(unzip -p "$MCPB_FRESH" manifest.json) >/dev/null 2>&1; then
  echo "==> refreshing checked-in metag.mcpb from mcpb/ sources"
  cp "$MCPB_FRESH" "$MCPB_CHECKED_IN"
fi
cp "$MCPB_FRESH" "$APP/Contents/Resources/metag.mcpb"
rm -rf "$(dirname "$MCPB_FRESH")"
if [ -d "$RES_BUNDLE/Images" ]; then
  cp -R "$RES_BUNDLE/Images" "$APP/Contents/Resources/"
fi
# .lproj folders must live at the bundle root for macOS to resolve them —
# flatten out of Resources/Localization/ even though that's just an org folder.
if [ -d "$RES_BUNDLE/Localization" ]; then
  for locale_dir in "$RES_BUNDLE/Localization"/*.lproj; do
    [ -d "$locale_dir" ] && cp -R "$locale_dir" "$APP/Contents/Resources/"
  done
else
  echo "!! missing Localization/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi
if [ -d "$RES_BUNDLE/Changelog" ]; then
  cp -R "$RES_BUNDLE/Changelog" "$APP/Contents/Resources/"
else
  echo "!! missing Changelog/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi
if [ -d "$RES_BUNDLE/Models" ]; then
  cp -R "$RES_BUNDLE/Models" "$APP/Contents/Resources/"
else
  echo "!! missing Models/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi

if ! ls "$RES_BUNDLE"/*.metallib >/dev/null 2>&1; then
  echo "!! no .metallib in SwiftPM resource bundle at $RES_BUNDLE — Metal effects would be missing" >&2
  exit 1
fi
cp "$RES_BUNDLE"/*.metallib "$APP/Contents/Resources/"

if $INCLUDE_BUNDLED_SPEECH; then
  MLX_METALLIB="$ROOT/.build/$CONFIG/mlx.metallib"
  if [ ! -f "$MLX_METALLIB" ]; then
    echo "==> Building MLX metallib ($CONFIG)"
    BUILD_DIR="$ROOT/.build" "$ROOT/.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh" "$CONFIG"
  fi
  if [ ! -f "$MLX_METALLIB" ]; then
    echo "!! missing $MLX_METALLIB — on-device speech features (VAD, speaker ID) would die silently" >&2
    exit 1
  fi
  mkdir -p "$APP/Contents/Resources/mlx-swift_Cmlx.bundle"
  cp "$MLX_METALLIB" "$APP/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/PalmierPro"
touch "$APP"

if [ "$MODE" = "fast" ]; then
  # A stable identity keeps Keychain items and TCC grants across dev rebuilds;
  # ad-hoc is the fallback so the dev loop works without a certificate.
  FAST_IDENTITY="${SIGNING_IDENTITY:--}"
  echo "==> Codesigning main app with ${FAST_IDENTITY} (no timestamp, no helpers)"
  codesign --force --sign "$FAST_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  echo "==> Done: $APP (fast mode — no dSYM)"
  exit 0
fi

DSYM="$ROOT/.build/PalmierPro.dSYM"
echo "==> Generating dSYM"
rm -rf "$DSYM"
dsymutil "$APP/Contents/MacOS/PalmierPro" -o "$DSYM"

upload_dsyms() {
  if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
    echo "==> Sentry creds not set — skipping dSYM upload"
    return
  fi
  if ! command -v sentry-cli >/dev/null 2>&1; then
    echo "!! sentry-cli not found in PATH — skipping dSYM upload"
    return
  fi
  echo "==> Uploading dSYM to Sentry"
  sentry-cli debug-files upload --include-sources "$DSYM" || echo "!! sentry-cli upload failed (continuing)"
}

if [ "$MODE" = "dev" ] || [ "$MODE" = "dmg" ]; then
  echo "==> Ad-hoc signing dev app"
  codesign --force --deep --sign - "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  upload_dsyms
  if [ "$MODE" = "dmg" ]; then
    # 我们发的就是这个未公证的包（没有 Developer ID 证书）。
    # 以前这几步是每次发版手敲的 —— 手敲的步骤一定会漂，而漂掉的那一次
    # 用户拿到的是一个装不上或版本号不对的 DMG。
    VER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
    DMG="$ROOT/.build/METAG-$VER-mac.dmg"
    echo "==> Building DMG $DMG"
    rm -f "$DMG"
    STAGING="$(mktemp -d)"
    cp -R "$APP" "$STAGING/METAG.app"
    ln -s /Applications "$STAGING/Applications"
    cp "$RESOURCES/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
    hdiutil create -volname "METAG" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
    rm -rf "$STAGING"
    echo "==> Done: $DMG (ad-hoc signed, NOT notarised —"
    echo "    first launch needs Privacy & Security -> Open Anyway)"
    exit 0
  fi
  echo "==> Done: $APP (ad-hoc signed)"
  exit 0
fi

echo "==> Codesigning nested Sparkle helpers"
SPARKLE_CURRENT="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
for helper in \
    "$SPARKLE_CURRENT/Autoupdate" \
    "$SPARKLE_CURRENT/Updater.app/Contents/MacOS/Updater" \
    "$SPARKLE_CURRENT/Updater.app" \
    "$SPARKLE_CURRENT/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$SPARKLE_CURRENT/XPCServices/Downloader.xpc" \
    "$SPARKLE_CURRENT/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$SPARKLE_CURRENT/XPCServices/Installer.xpc"; do
  [ -e "$helper" ] && codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$helper"
done

echo "==> Codesigning Sparkle framework"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework"

echo "==> Embedding provisioning profile + keychain access group"
if [ ! -f "$PROVISION_PROFILE" ]; then
  echo "!! provisioning profile not found at $PROVISION_PROFILE" >&2
  exit 1
fi
cp "$PROVISION_PROFILE" "$APP/Contents/embedded.provisionprofile"
inject_plist PalmierClerkKeychainAccessGroup "$KEYCHAIN_ACCESS_GROUP"

echo "==> Codesigning main app"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ "$MODE" = "sign" ]; then
  echo "==> Done: $APP (signed, not notarized)"
  exit 0
fi

echo "==> Zipping .app for notarization"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary (this can take several minutes)"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling ticket to .app"
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "==> Building DMG"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/METAG.app"
ln -s /Applications "$STAGING/Applications"
cp "$RESOURCES/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
hdiutil create \
  -volname "METAG" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"
rm -rf "$STAGING"

echo "==> Codesigning DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

echo "==> Submitting DMG to notary"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling DMG"
xcrun stapler staple "$DMG"

upload_dsyms

echo "==> Signing DMG with Sparkle EdDSA key"
SPARKLE_SIG="$("$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update" "$DMG")"

echo ""
echo "==> Done"
echo "   App: $APP"
echo "   DMG: $DMG"
echo ""
echo "Sparkle signature for appcast entry:"
echo "  $SPARKLE_SIG"
echo ""
echo "Add an <item> to appcast.xml with:"
echo "  - version, shortVersionString from Info.plist"
echo "  - url pointing at the GitHub Release download"
echo "  - length=$(stat -f%z "$DMG")"
echo "  - the sparkle:edSignature from above"
