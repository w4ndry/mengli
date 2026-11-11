# mengli QA reference — staging release build + Maestro flow library

QA always runs against a **staging release** build of the current branch (JS bundle baked in, no Metro). Navigation is discovered **once** with mobile-mcp, saved as Maestro flows, then replayed deterministically.

Always export before running maestro (quiet output):
```bash
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
```

## 1. Device pre-flight
| | iOS (default) | Android |
|---|---|---|
| find device | `xcrun simctl list devices booted -j` → first `udid` | `adb devices` → first `emulator-*` in `device` state |
| none running | `xcrun simctl boot <config.qa.ios.device or first available iPhone from xcrun simctl list devices available -j>` then `open -a Simulator` | `emulator -avd <config.qa.android.avd or first of emulator -list-avds> -no-snapshot-save &` then poll `adb -s <serial> shell getprop sys.boot_completed` = 1 (max 180s) |
| maestro | `maestro --version` must succeed | same |

Device missing after that → **environment STOP** (not a QA attempt).

## 2. Build & install (staging release)
Skip when `state.json.lastBuild` == `{platform, sha: git rev-parse HEAD, diffHash: git diff HEAD | shasum}` and the app is installed.

**iOS** (run in background, log to `<workdir>/qa/build-ios.log`):
```bash
xcodebuild -workspace ios/FlipApp.xcworkspace -scheme FlipAppStaging -configuration Staging \
  -sdk iphonesimulator -destination "id=<udid>" \
  -derivedDataPath ~/.claude/mengli/build/ios build > <workdir>/qa/build-ios.log 2>&1
xcrun simctl install <udid> ~/.claude/mengli/build/ios/Build/Products/Staging-iphonesimulator/Flip.app
```
If pods are out of date (`The sandbox is not in sync with the Podfile.lock`): `cd ios && bundle exec pod install && cd ..`, then retry once.

**Android** (background, log to `<workdir>/qa/build-android.log`):
```bash
yarn build_android_staging_release > <workdir>/qa/build-android.log 2>&1
APK=$(ls -t android/app/build/outputs/apk/staging/release/*.apk | head -1)
adb -s <serial> install -r "$APK"
```
The build is `arm64-v8a` only (fits Apple Silicon emulators).

Scheme / configuration / build script / appId come from `config.json.qa.<platform>` (override for stream schemes, e.g. `FlipDPStaging`). Build failure → **environment STOP** with the last 50 lines of the log.

## 3. Flow library (`~/.claude/mengli/maestro/`, shared by every task)
```
index.json                    # screen → subflow registry
subflows/launch.yaml          # launch app, wait for home
subflows/enter-pin.yaml       # optional PIN entry from ${MENGLI_QA_PIN}
subflows/nav-to-<screen>.yaml # discovered paths, one per destination screen
```
`index.json` schema:
```json
{
  "screens": {
    "payment-option": {
      "route": "PaymentOptionScene",
      "file": "subflows/nav-to-payment-option.yaml",
      "from": "home",
      "destinationAssert": "id: payment_option_header",
      "verifiedOn": { "ios": "2026-10-16", "android": null },
      "healedAt": []
    }
  }
}
```
Flows are cross-platform: RN `testID` maps to the iOS accessibilityIdentifier and the Android resource-id, so `id:` selectors work on both. A flow not yet verified on the current platform is run once to verify it (and healed if needed) before it is trusted.

## 4. Flow conventions
Subflow (`nav-to-<screen>.yaml`):
```yaml
appId: ${APP_ID}
---
- runFlow: /Users/FLP9EriWandri/.claude/mengli/maestro/subflows/launch.yaml
- tapOn:
    id: "home_menu_transfer"          # testID first
- tapOn: "Transfer ke Bank"           # exact text only when no testID
- extendedWaitUntil:
    visible:
      id: "payment_option_header"
    timeout: 15000
- assertVisible:
    id: "payment_option_header"       # unique to the destination
```
Per-task AC flow (`<workdir>/maestro/ac-<n>.yaml`):
```yaml
appId: ${APP_ID}
name: "AC-2 voucher chip hidden under 10k"
---
- runFlow: /Users/FLP9EriWandri/.claude/mengli/maestro/subflows/nav-to-payment-option.yaml
- inputText: "9000"
- assertNotVisible:
    id: "voucher_chip"
- takeScreenshot: ac-2
```
Rules:
- **Absolute paths** in `runFlow` (per-task flows live outside the library).
- Selectors: `id:` → exact `text:` → never `point:`. If an element has no testID and no stable text, note it; the plan should add a testID.
- No `- waitForAnimationToEnd` chains or sleeps; use `extendedWaitUntil` with a timeout.
- `launchApp: { clearState: false }` inside `launch.yaml` — keep the logged-in session.
- Validate syntax before running: `maestro check-syntax <file>`.

`launch.yaml` waits for a home-screen element; if instead a PIN screen appears and `MENGLI_QA_PIN` is set, it runs `enter-pin.yaml`. Login/OTP screens → `ENV_BLOCKED` (never store credentials).

## 5. Running
Run from the attempt dir so screenshots land there:
```bash
mkdir -p <workdir>/qa/attempt-<n> && cd <workdir>/qa/attempt-<n> && \
maestro --device <udid|serial> test -e APP_ID=<appId> \
  ${MENGLI_QA_PIN:+-e MENGLI_QA_PIN="$MENGLI_QA_PIN"} \
  --format junit --output report.xml --test-output-dir . \
  <workdir>/maestro/
```
(`cd` back to the repo root afterwards.) Confirm the `ac-*.png` screenshots exist; if maestro wrote them elsewhere, move them into the attempt dir.

## 6. Reading results (orchestrator, attempts 2–5)
Parse `report.xml` (`<testcase name=...>` with `<failure>`), and the maestro stdout:
- Failure inside a step that belongs to a **nav subflow** (message names a selector from `subflows/…` or occurs before the AC's own steps) → **stale flow** → `mengli-qa-simulator` in `heal` mode (≤ `qaMaxHeals`, not counted as an attempt).
- Failure on an **AC assertion** (`assertVisible`/`assertNotVisible`/text check in `ac-<n>.yaml`) → **app bug** → fix code, rebuild, replay (counts as an attempt).
- App crash / not launching → app bug; collect `xcrun simctl spawn <udid> log show --last 2m --predicate 'process == "Flip"'` or `adb logcat -d -t 500` into the attempt dir.

## 7. Recording the demo (step 8)
`<workdir>/maestro/demo.yaml` = `runFlow` of every `ac-*.yaml` in order.
- iOS:
  ```bash
  xcrun simctl io <udid> recordVideo --codec=h264 --force <workdir>/demo.mp4 &  REC=$!
  sleep 2; maestro --device <udid> test -e APP_ID=<appId> <workdir>/maestro/demo.yaml
  kill -INT $REC; wait $REC
  ```
- Android (180 s cap per file):
  ```bash
  adb -s <serial> shell screenrecord --bit-rate 4000000 /sdcard/mengli-demo.mp4 &  REC=$!
  sleep 2; maestro --device <serial> test -e APP_ID=<appId> <workdir>/maestro/demo.yaml
  kill -INT $REC; sleep 2; adb -s <serial> pull /sdcard/mengli-demo.mp4 <workdir>/demo.mp4
  ```
If `demo.mp4` > 50 MB and `ffmpeg` exists: `ffmpeg -i demo.mp4 -vcodec libx264 -crf 30 -vf scale=-2:1280 demo-small.mp4` and upload the small one.
