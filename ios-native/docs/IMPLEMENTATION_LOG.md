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
