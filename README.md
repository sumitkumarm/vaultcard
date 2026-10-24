# VaultCard

VaultCard is a privacy-first prepaid Visa/Mastercard gift card manager. The active iOS implementation is native SwiftUI in `ios-native/`; the earlier Flutter scaffold remains as a cross-platform reference.

## Current State

The native iOS app currently includes:

- adaptive light/midnight-blue SwiftUI design with iOS 26 Liquid Glass controls and iOS 17 material fallbacks
- camera scanning with explicit card number, expiration, and CVV confirmation
- bulk card capture from grid photos, uploaded images, CSV/TSV files, or pasted rows, with editable review and one-tap saving
- Keychain-backed credentials with authenticated full-number and CVV reveal
- home-screen unused funds total across active cards, with unknown and stale balance indicators
- user-initiated Visa/MyGift and Mastercard balance checks on the current MyCardWallet portals
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

## Bulk card capture

Choose **Add Multiple Cards** from the add-card flow. Photograph a grid, select photos,
import an image or delimited text file, or paste spreadsheet rows. Columns should be
card number, expiry (one column or separate month and year), then optional CVV/PIN.
Table headings are used to locate credentials and ignore extra columns such as balance
and last-updated dates. English month names and abbreviations are case insensitive; numeric months and
2- or 4-digit years (including apostrophe-prefixed years) are supported. A PIN header
selects PIN automatically; each reviewed row can also switch its code to PIN.

Review and correct every captured row, remove unwanted rows, then tap **Confirm & Add**.
Missing CVVs do not prevent saving. Open the saved card and choose **Add CVV** before
managing its balance. Recognition runs locally; credentials use the existing secure store.
