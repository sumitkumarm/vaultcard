# VaultCard

VaultCard is a privacy-first prepaid Visa/Mastercard gift card manager built as a Flutter mobile app for iOS and Android.

## Current State

This repository was scaffolded manually because the local machine does not currently have `flutter`, `dart`, or `java` installed. The codebase includes:

- app shell, navigation, theming, and Riverpod wiring
- core domain models, repositories, and local service abstractions
- manual card management flows
- security/reveal flows with injectable biometric abstractions
- balance-refresh orchestration, parser config abstraction, and GiftCardMall parsing fixtures
- tests for core business rules and repository/service behavior

## Required Local Setup

Before the app can be run or platform projects can be generated, install:

- Flutter 3.x
- Dart 3.x
- JDK 17
- Android Studio + Android SDK

Windows cannot complete iOS build validation. A macOS environment with Xcode is still required for iOS signing, biometric checks, background task verification, and App Store packaging.

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
- The direct HTTP GiftCardMall flow is implemented behind abstractions and still requires live validation before production use.
