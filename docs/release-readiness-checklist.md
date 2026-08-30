# VaultCard Release Readiness Checklist

## Product and Policy

- finalize privacy policy copy for secure storage, biometrics, camera OCR, and notifications
- confirm whether live balance refresh remains disabled for GiftCardMall until a browser-mediated flow exists
- document supported gift card issuers and unsupported cases inside onboarding/help copy

## Android

- verify camera capture on a physical Android device
- verify biometric unlock on at least one enrolled device
- verify background refresh scheduling, retry behavior, and notification delivery after device reboot
- confirm secure display behavior in app switcher and screenshots

## iOS

- native SwiftUI clean simulator build/test verified on macOS 15.6 with Xcode 26.3 and iPhone 17 Pro / iOS 26.3
- build, sign, and launch on a physical iPhone
- verify Face ID or passcode unlock flow
- verify camera OCR permissions and capture flow
- verify local notifications and background refresh constraints on device

## Quality

- run `flutter analyze`
- run `flutter test --no-test-assets`
- add integration or device tests for camera capture and background work where CI devices are available
- review crash reporting wiring before enabling distribution builds

## Distribution

- configure production app ids, signing, and store metadata
- confirm release icons, launch screens, and store screenshots
- decide whether analytics stays disabled in release or is replaced with an approved telemetry backend
