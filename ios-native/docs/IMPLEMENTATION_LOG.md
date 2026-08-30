# Native iOS Implementation Log

## Phase 1-7 Baseline Pass

- Created separate native app scaffold under `ios-native/`.
- Added SwiftUI app shell, routing, dependency container, SwiftData `SchemaV1`, placeholder `VaultCardSchemaMigrationPlan`, and in-memory model container factory.
- Added manual vault, Keychain credential store, LocalAuthentication reveal/app lock, direct refresh shell, GiftCardMall WKWebView fallback, Vision/AVFoundation scan prefill, notification service, and BGTaskScheduler registration.
- Added unit/UI tests covering validation, OCR parsing, repository atomicity paths, transaction persistence, and GiftCardMall fixture parsing.

## Gate Status

- Attempted required gate:

```bash
xcodebuild \
  -project ios-native/VaultCard.xcodeproj \
  -scheme VaultCard \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  clean build test
```

- Result in this environment: `xcodebuild` is unavailable on Windows (`CommandNotFoundException`), so native compilation and simulator tests could not be executed here.
- XcodeBuildMCP validation was also attempted:
  - `session_show_defaults` succeeded but showed no configured project/scheme/simulator defaults.
  - `list_schemes` for `ios-native/VaultCard.xcodeproj` failed with `spawn xcodebuild ENOENT`.
  - `list_sims` failed with `spawn xcrun ENOENT`.
- Added `.github/workflows/native-ios.yml` so GitHub Actions can run the native iOS build/test gate on `macos-latest` using an available iPhone simulator.
- GitHub Actions run `27706449171` reached simulator testing but failed because `BGTaskScheduler` was registered from SwiftUI `.task` after app launch completed. Fixed by registering the launch handler from `VaultCardApp.init()` and leaving only best-effort scheduling in async app startup.
- GitHub Actions run `27706857825` passed app launch/UI testing and exposed a brittle rollback unit test. Fixed by adding a deterministic repository metadata-save failure hook and testing Keychain rollback through that path instead of depending on SwiftData unique-constraint timing.
- GitHub Actions run `27707134236` passed the native build/test gate. Added deterministic `--ui-testing` app environment and expanded UI tests for onboarding, manual add, reveal, delete, and validation failure paths.
- GitHub Actions run `27707380211` proved the manual add/reveal/delete path worked but failed on a brittle assertion that SwiftUI exposed the `Sensitive Details` section header as a static text. Updated the UI test to assert the reveal control and masked value instead.
- Static validation run locally against source/test directories:
  - `rg -n "TODO|fatalError|try!|print\(|debugPrint" ios-native/VaultCard ios-native/VaultCardTests ios-native/VaultCardUITests` returned no matches.
  - `rg -n "@Query|modelContext" ios-native/VaultCard ios-native/VaultCardTests ios-native/VaultCardUITests` returned no matches.
  - Keychain API references are isolated to `KeychainCredentialStore` in `VaultCardApp.swift`.
- No Flutter source files were modified.

## Appetize Deployment Gate

- Added `.github/workflows/native-ios-appetize.yml` as a deployment gate for the native iOS app.
- The workflow runs the native Xcode build/test gate, packages `VaultCard.app` as `VaultCard-ios-native-simulator.zip`, uploads the zip as a GitHub Actions artifact, and then uploads the same simulator artifact to Appetize.
- Appetize upload uses the official REST API with `X-API-KEY`, `platform=ios`, and `fileType=zip`. If `APPETIZE_IOS_PUBLIC_KEY` is configured as a GitHub Actions variable, the workflow updates that existing app; otherwise it creates a new Appetize app and reports the generated preview URL.
- Required GitHub Actions secret: `APPETIZE_API_TOKEN`.
- Optional GitHub Actions variable: `APPETIZE_IOS_PUBLIC_KEY`.
- GitHub Actions run `27726370417` passed the native build/test step, produced and uploaded the `VaultCard-ios-native-simulator` artifact, then failed at `Verify Appetize credentials` because `APPETIZE_API_TOKEN` was not configured in repository Actions secrets. `APPETIZE_APP_PUBLIC_KEY` was also empty.
- GitHub Actions run `27735285387` passed the full native Appetize gate: Xcode build/test, simulator app zip packaging, GitHub artifact upload, credential verification, and Appetize upload.
- Appetize iOS preview updated successfully at `https://appetize.io/app/menqwwjiw7wmvef57eeohiwrg4`.
- Appetize smoke test passed in browser on iPhone 14 Pro / iOS 17.2: launched the native app, dismissed the notification permission prompt, completed onboarding to the vault list, opened the add-card choice screen, and opened the manual card entry form.

## Local Mac Simulator Validation — 2026-08-30

- Host: macOS 15.6 (build 24G84).
- Toolchain: Xcode 26.3 (build 17C529), iOS 26.3.1 simulator runtime (build 23D8133).
- Simulator: iPhone 17 Pro, iOS 26.3, UDID `3C5A58FD-2450-45C0-A59C-D1450DFF2CDB`.
- XcodeBuildMCP was not installed, so validation used `xcodebuild` and `simctl` directly. The system-wide developer selection still pointed at Command Line Tools, so commands set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` explicitly.
- Installed and registered the simulator runtime with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -downloadPlatform iOS

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl runtime scan-and-mount
```

- Ran the complete native gate with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project ios-native/VaultCard.xcodeproj \
    -scheme VaultCard \
    -destination 'platform=iOS Simulator,id=3C5A58FD-2450-45C0-A59C-D1450DFF2CDB' \
    clean build test
```

- The first local run completed clean/build and all 9 unit tests, then exposed an iOS 26.3 UI-test selector ambiguity: SwiftUI published two nested elements labeled `Delete`, so the generic delete-confirmation query failed before it could perform the action.
- Updated `VaultCardUITests.testManualCardLifecycleHappyPath` to select the existing `detail.confirmDelete` accessibility identifier with `firstMatch`. This was a test compatibility correction; the app had presented the correct destructive confirmation dialog.
- Repeated the complete gate once after the correction. Result: `** TEST SUCCEEDED **`; 9 unit tests and 3 UI tests passed with zero failures.
- Direct simulator validation used a fresh install launched with `--ui-testing`, fixture card number `4111111111111111`, expiry `09/29`, CVV `123`, and nickname `Manual QA`. No real gift-card credentials were used. Verified:
  - all three fresh-install onboarding pages and completion
  - empty vault state
  - empty/invalid card submission displays `Enter a valid Visa or Mastercard number.`
  - manual entry detects `VISA`, saves the fixture, and displays expiry and nickname
  - saved card number is masked as `**** **** **** 1111`
  - test authentication path reveals the fixture number
  - Settings navigation and all expected settings/notification controls
  - GiftCardMall foreground screen, initial guidance, fixture-only secure-autofill status, and reload without a crash or live submission
  - destructive confirmation and deletion return to the empty vault state
- Still requires a signed physical iPhone and user interaction before release readiness can be claimed:
  - Face ID or passcode authentication
  - Keychain persistence across termination and relaunch
  - camera permission and OCR capture
  - local notification permission and delivery
  - background refresh behavior
  - app-switcher and screenshot privacy behavior
