# bisawtak (بصوتك)

Flutter mobile client for the Bisawtak speech-to-text platform. Talks to the
FastAPI backend at `voice.neojeen.com`.

## Prerequisites

- Flutter **3.x** (channel `stable`)
- Dart **3.x** (ships with Flutter)
- Xcode 15+ and CocoaPods (for iOS builds)
- Android Studio / Android SDK with platform-tools (for Android builds)
- A configured device or emulator/simulator

Verify your toolchain with `flutter doctor` before going further.

## Required configuration files

These are **not** checked into git. Obtain them from the team lead and place
them at the listed paths:

| File                                      | Purpose                              |
| ----------------------------------------- | ------------------------------------ |
| `android/key.properties`                  | Android release signing (see example below) |
| `android/app/google-services.json`        | Android Google sign-in / Firebase    |
| `ios/Runner/GoogleService-Info.plist`     | iOS Google sign-in / Firebase        |

For the Android signing config, copy `android/key.properties.example` to
`android/key.properties` and fill in real values. The `storeFile` path is
resolved relative to `mobile/android/`. Without `key.properties`, the build
falls back to the debug keystore and prints a warning — never ship that to
the store.

## Install dependencies

```bash
flutter pub get
```

iOS additionally needs CocoaPods:

```bash
cd ios && pod install && cd ..
```

## Run in development

```bash
flutter run --dart-define=API_URL=https://voice.neojeen.com/api/v1
```

Point `API_URL` at a local backend (e.g. `http://10.0.2.2:8000/api/v1` on the
Android emulator) when iterating against an unreleased backend.

## Release builds

### Android (obfuscated APK / AAB)

```bash
flutter build apk     --release --obfuscate --split-debug-info=build/symbols
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

The `--obfuscate` + `--split-debug-info` pair is required so stack traces can
be symbolicated later via `flutter symbolize`.

### iOS

See [`IOS_SETUP_GUIDE.md`](./IOS_SETUP_GUIDE.md) for the full provisioning,
entitlement, and App Store Connect walkthrough.

## Project layout (high level)

- `lib/` — Dart source (owned by mobile-app feature teams).
- `android/` — Android Gradle project, manifests, and signing config.
- `ios/` — Xcode project, Info.plist, and the share extension.
- `assets/` — Images, icons, Lottie animations.
- `test/` — Widget and unit tests.

## Troubleshooting

- `record_platform_interface` is pinned in `dependency_overrides` because the
  Linux flavour lags behind. Remove the override once `record_linux` catches
  up.
- If the iOS build complains about `aps-environment`, leave it removed —
  the app does not use push notifications. Re-add it only when push is
  actually wired up, otherwise Apple will reject the binary.
