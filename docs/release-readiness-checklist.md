# VaultCard Release Readiness Checklist

## Product and Policy

- finalize privacy policy copy for secure storage, biometrics, camera OCR, and notifications
- validate the browser-mediated GiftCardMall balance capture against real Visa and Mastercard prepaid cards
- document supported gift card issuers and unsupported cases inside onboarding/help copy

## Android

- verify camera capture on a physical Android device
- verify biometric unlock on at least one enrolled device
- verify local notification delivery after device reboot for configured expiry and low-balance alerts
- confirm secure display behavior in app switcher and screenshots

## iOS

- native SwiftUI clean simulator build/test verified on macOS 15.6 with Xcode 26.3 and iPhone 17 Pro / iOS 26.3
- build, sign, and launch on a physical iPhone
- verify Face ID or passcode unlock flow
- verify camera OCR permissions and capture flow
- verify local notifications and foreground balance-check failure handling on device
- verify the direct foreground GiftCardMall balance-check copy and embedded-page form positioning on a physical iPhone
- verify a confirmed GiftCardMall balance immediately updates the card detail and vault list

## Quality

- run `flutter analyze`
- run `flutter test --no-test-assets`
- add integration or device tests for camera capture and the foreground GiftCardMall browser flow where CI devices are available
- review crash reporting wiring before enabling distribution builds

## Distribution

- configure production app ids, signing, and store metadata
- confirm release icons, launch screens, and store screenshots
- decide whether analytics stays disabled in release or is replaced with an approved telemetry backend
