# Shipping METAG for macOS

Three tiers. Each one works on its own; you only need the next tier when you need what it buys.

| Tier | Command | Runs on your Mac | Runs on someone else's Mac | Auto-update |
| --- | --- | --- | --- | --- |
| Dev bundle | `scripts/bundle.sh debug` | yes | no (Gatekeeper blocks) | no |
| Signed | `scripts/bundle.sh release --sign` | yes | only after right-click → Open | no |
| Distributable | `scripts/bundle.sh release --dist` | yes | yes, double-click | yes |
| Released | `scripts/release.sh X.Y.Z` | yes | yes, from a download page | yes |

## Tier 1 — dev bundle (works today, no accounts needed)

```bash
scripts/bundle.sh debug          # → .build/METAG.app, ad-hoc signed
scripts/dev.sh                   # same, plus launch and stream OSLog
```

Ad-hoc signing means the app is valid only on the machine that built it. This is the
correct tier for development; do not send this build to anyone.

## Tier 2 and 3 — what the founder must provide

None of the following can be created, purchased, or worked around from inside this repo.
Each item is a one-time setup.

### A. Apple Developer Program membership — **BLOCKER**

- $99/year, https://developer.apple.com/programs/
- Must be the account that owns Team ID `V969594VAF` (already used by Sign in with Apple —
  see `APPLE_TEAM_ID` in `metag/.env`).
- Everything below depends on this.

### B. Developer ID Application certificate — **BLOCKER**

Only an Account Holder or Admin can create it.

1. Xcode → Settings → Accounts → your Apple ID → Manage Certificates → **+** →
   **Developer ID Application**.
2. Confirm it landed in the login keychain:
   ```bash
   security find-identity -v -p codesigning
   ```
   You want a line like `Developer ID Application: <Org Name> (V969594VAF)`.
3. Put the exact string in `metag/mac/.env`:
   ```
   SIGNING_IDENTITY="Developer ID Application: <Org Name> (V969594VAF)"
   ```
   `bundle.sh` refuses to start a signed build if this is unset or not in the keychain.

**Back this certificate up** (export the private key as a `.p12` and store it in the
password manager). Apple issues a limited number of Developer ID certificates per account
and cannot re-export the private key for you.

### C. Developer ID provisioning profile — **BLOCKER for `--sign` / `--dist`**

Needed because the app requests a keychain access group entitlement.

1. https://developer.apple.com/account/resources/profiles → **+** → **Developer ID** →
   pick App ID `V969594VAF.ai.metag`.
2. If that App ID does not exist yet, create it first under Identifiers, with the
   **Keychain Sharing** capability enabled.
3. Download and save as:
   ```
   metag/mac/scripts/METAG_Developer_ID.provisionprofile
   ```
   (git-ignored; it is not a secret but it is machine-specific paperwork.)

`scripts/METAG.entitlements` already declares `V969594VAF.ai.metag`, and `bundle.sh`
asserts it matches `APPLE_TEAM_ID` + `CFBundleIdentifier` before signing.

### D. notarytool keychain profile — **BLOCKER for `--dist`**

1. Create an app-specific password at https://account.apple.com → Sign-In and Security →
   App-Specific Passwords. Name it `metag-notary`.
2. Store it in the keychain once:
   ```bash
   xcrun notarytool store-credentials metag-notary \
     --apple-id <the Apple ID email> \
     --team-id V969594VAF \
     --password <app-specific-password>
   ```
   The password lives in the keychain from then on. **Never put it in `.env` or a script.**

### E. Sparkle EdDSA key pair — **BLOCKER for auto-update**

This section used to say `Info.plist` already points `SUFeedURL` at the metag-mac appcast.
**It does not.** `Sources/PalmierPro/Resources/Info.plist` contains neither `SUFeedURL` nor
`SUPublicEDKey` — verify with `grep SU Sources/PalmierPro/Resources/Info.plist`, which
prints nothing.

That makes the gap wider than a missing key. `Updater.swift` only constructs
`SPUStandardUpdaterController` when `SUFeedURL` is present, so today no shipped build ever
fetches an appcast; "Check for Updates" opens the download page instead. Publishing an
appcast entry therefore reaches nobody until **both** keys exist — and every copy already
installed without `SUFeedURL` can never be auto-updated at all, no matter what is added
later. Those users have to download a new build by hand once.

`appcast.xml` in this repo is still **upstream's Palmier Pro feed**: `<title>Palmier Pro</title>`,
enclosures pointing at `palmier-io/palmier-pro` releases, newest entry 0.6.15. No METAG
release has ever been added to it. It needs to be replaced, not appended to.

1. Generate the pair (the private key goes into the login keychain automatically):
   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
2. Add **both** keys to `Sources/PalmierPro/Resources/Info.plist`:
   ```xml
   <key>SUFeedURL</key>
   <string>https://raw.githubusercontent.com/metag-ai/metag-mac/main/appcast.xml</string>
   <key>SUPublicEDKey</key>
   <string><the printed public key></string>
   ```
3. Export and back up the private key — losing it means no existing install can ever be
   updated again:
   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key.txt
   ```

### F. Release repository — **BLOCKER for `scripts/release.sh`**

The only git remote in this repo today is `upstream` (palmier-io). `release.sh` pushes
tags and creates GitHub releases on `origin`, and the download URL it writes into
`appcast.xml` must match `SUFeedURL`.

1. Create `github.com/metag-ai/metag-mac`.
2. ```bash
   git remote add origin git@github.com:metag-ai/metag-mac.git
   git push -u origin main
   ```
3. `gh auth login` so `gh release create` works.

`release.sh` now fails fast with this instruction if `origin` is missing.

### G. Optional, not blockers

- `SENTRY_DSN`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` — crash reports and
  dSYM upload. Unset means telemetry is a no-op.
- `POSTHOG_PROJECT_TOKEN` — product analytics. Unset means a no-op.
- `CLERK_PUBLISHABLE_KEY`, `CONVEX_DEPLOYMENT_URL`, `CONVEX_HTTP_URL` — these are
  upstream's backend and now drive **only** the in-app Agent chat panel. Generation,
  billing, and accounts run through the METAG gateway and do not need them. Leaving them
  unset ships an app whose Agent chat panel does not work; see "Known gaps".

## 本机需要的那份配置：`mac/.env`（2026-08-16 补）

A–F 都办妥之后，构建仍然需要**这台机器上**的一个 gitignored 文件：

```
mac/.env
  SIGNING_IDENTITY="Developer ID Application: <Org> (V969594VAF)"
```

不写它，`bundle.sh release --dist` 会停在
`!! SIGNING_IDENTITY is not set.` —— 证书明明在钥匙串里，脚本却读不到。

**为什么专门记这一条：** 2026-08-16 要发 0.1.8 时，这台机器上的 `mac/.env`
已经不见了（它是 gitignored 的，谁也没备份）。而 `d6d6adac` 那次提交的标题
恰恰是「把 0.1.7 真正发版时用的签名配置提交上」—— 当时补的是能提交的那几个
文件，**不能提交的那一份没有留下任何指引**，于是同一个坑又踩了一次。

怎么取（不含任何密钥）：

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
# 把引号里那串完整名字填进 mac/.env
```

`NOTARY_PROFILE` 默认 `metag-notary`，验证它还通：

```bash
xcrun notarytool history --keychain-profile metag-notary | head -3
```

**私钥不在这份文件里**，也不该在任何文件里：Developer ID 私钥和 Sparkle 的
EdDSA 私钥都在钥匙串，`.env` 里只有那串**公开的证书名**。

### `--dist` 还要 ~700MB 二进制依赖

`release` 一律走 `--enable-all-traits`（含 ProductionTelemetry），
于是要拉 7 个 Sentry xcframework + SpeechCore，约 700MB。
慢链路上 SwiftPM 并行下载会集体超时，报
`downloadError("The request timed out.")`。

**已下好的会留在 `.build/artifacts/`，所以重试是累积的** —— 重试就行，
但必须带上同一组特性：

```bash
swift package resolve --enable-all-traits    # 反复跑直到成功
```

⚠ 不带 `--enable-all-traits` 的 `swift package resolve` **会把已经下好的
那部分清掉**（它认为用不上）。我 2026-08-16 就这么把 199MB 白扔了一次。

## Release flow, once B–F are in place

```bash
scripts/bundle.sh release --dist   # sign → notarize → staple → DMG → notarize DMG
scripts/release.sh 0.7.0           # version bump, tag, GitHub release, appcast entry
```

Verify a distributable build the way a user's Mac will:

```bash
spctl -a -vvv -t install .build/METAG.dmg     # expect: accepted, source=Notarized Developer ID
xcrun stapler validate .build/METAG.app
```

## Known gaps

- **Agent chat panel is dead in METAG builds.** `Sources/PalmierPro/Agent/Clients/PalmierClient.swift`
  still streams through Convex + Clerk, which are no longer configured. The MCP server and
  every timeline tool work; only the in-app chat does not. Porting it to the gateway is a
  separate piece of work.
- **Sparkle auto-update is entirely off** (item E). Neither `SUFeedURL` nor `SUPublicEDKey`
  is in `Info.plist`, so the updater is never even started and `appcast.xml` is still
  upstream's feed. Updating the appcast today changes nothing for anyone.
- **Translated READMEs still show the pre-token MCP setup.** `docs/readme/README.*.md` hand out a
  config with no access token, which the server now refuses. The refusal message points at
  `Help` -> `MCP Instructions`, so it is not silent, but the translations need updating.
