# Flutter Web QA Mode

Use web QA mode for fast browser testing of shared VaultCard behavior without rebuilding Android or iOS.

Build:

```powershell
flutter build web --debug --dart-define VAULTCARD_QA=true
```

Serve the built app:

```powershell
cd build\web
python -m http.server 53621 --bind 127.0.0.1
```

Open:

```text
http://127.0.0.1:53621
```

QA mode behavior:

- Skips onboarding.
- Uses in-memory card metadata, preferences, and credentials.
- Keeps the real card-entry, validation, network detection, save, detail, and reveal flows.
- Replaces camera OCR with a text-parser screen.
- Replaces the native GiftCardMall WebView with a placeholder explaining that WebView/autofill still needs Android/iOS/Appetize testing.
- Disables background refresh, notifications, and biometric prompts.

Validation run:

```powershell
flutter analyze
flutter test
flutter build web --debug --dart-define VAULTCARD_QA=true
```

Known limitation:

Flutter's normal JavaScript web build works. The current dependency set still emits wasm dry-run warnings because `flutter_secure_storage_web` depends on browser libraries that are not wasm-compatible.
