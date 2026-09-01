# VaultCard

VaultCard is a privacy-first prepaid Visa/Mastercard gift card manager. The active iOS implementation is native SwiftUI in `ios-native/`; the earlier Flutter scaffold remains as a cross-platform reference.

## Current State

The native iOS app currently includes:

- adaptive light/midnight-blue SwiftUI design with iOS 26 Liquid Glass controls and iOS 17 material fallbacks
- camera scanning with explicit card number, expiration, and CVV confirmation
- Keychain-backed credentials with authenticated full-number and CVV reveal
- user-initiated GiftCardMall balance checks in a secure embedded browser
- WebKit capture of confirmed balances and transactions back into the local vault
- SwiftData metadata storage plus unit and Simulator UI coverage

## Required Local Setup

Before the app can be run or platform projects can be generated, install:

- Flutter 3.x
- Dart 3.x
- JDK 17
- Android Studio + Android SDK

The native app builds and runs locally with Xcode. Physical-device validation is still required for camera capture, Face ID, embedded GiftCardMall checks, and final signing behavior.

## Suggested Bootstrap Commands

Once Flutter is installed, run:

```powershell
flutter create . --platforms=android,ios --project-name vaultcard --org com.vaultcard.app
flutter pub get
flutter test
```

`flutter create .` should be run carefully so the generated platform files are added around the existing Dart code instead of replacing it.

## Architecture Notes

- Sensitive card credentials are modeled separately from card metadata.
- Parser config is local for MVP but accessed through an interface so it can move to remote config later.
- Telemetry is intentionally no-op by default.
- GiftCardMall checks are foreground-only: Check Balance opens the embedded site directly, autofills saved credentials, and persists confirmed balances and transactions immediately.
