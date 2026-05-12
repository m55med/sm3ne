# Mobile — Claude/Agent notes

Quick reference. القواعد الكاملة في [`../AGENTS.md`](../AGENTS.md) §5.

## Quick rules
- **HTTP من widget = ممنوع.** كل request عبر repository من `lib/data/repositories/`:
  - `auth_repository.dart`
  - `plans_repository.dart`
  - `profile_repository.dart`
  - `support_repository.dart`
  - `transcription_repository.dart`
- **رسائل خطأ:** استخدم `friendlyErrorMessage(e)` من `lib/shared/utils/error_messages.dart` — يحوّل DioException إلى رسالة عربية مفهومة.
- **Confirm dialogs:** `showConfirmDialog(context, ...)` من `lib/shared/widgets/confirm_dialog.dart`. Destructive (حذف، logout): `destructive: true`.
- **Empty/Error/Connectivity:** widgets جاهزة في `lib/shared/widgets/`.
- **Deep links / share intents:** **لا ترفع ملف** قبل `isPathInsideSandbox()` + `hasAllowedAudioExtension()` + `validateAudioFileForUpload()`.
- **Secure storage:** `FlutterSecureStorage` بـ `aOptions: AndroidOptions(encryptedSharedPreferences: true)` + `iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`.
- **`isFirstLaunch` → SharedPreferences** (لا secure storage — متعمد بسبب iOS keychain persisting بعد uninstall).
- **API URL:** `AppConstants.apiBaseUrl` يقرأ من `String.fromEnvironment('API_URL', ...)`.
- **Plans:** لا تـ hardcode `if plan.name == 'annual'`. استخدم signals من الـ backend (سعر، خصم، `is_recommended`).
- **AppLocalizations:** متصلة في `main.dart`. استخدم `AppLocalizations.of(context)!.xxx` للنصوص الجديدة (إلا للنصوص الدلائلية الطويلة كـ FAQ).

## Permissions
- AndroidManifest الـ MAIN يحتوي:
  - `INTERNET`, `RECORD_AUDIO`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`
  - `<application android:allowBackup="false">`
- لو طلبت permission جديد، أضف intent-filter أو UsageDescription في iOS Info.plist.

## Apple Sign-In Nonce
- الـ client يولّد `Random.secure()` raw nonce → `sha256(rawNonce)` → يبعث للـ Apple.
- ثم يبعث الـ **raw** nonce للـ backend مع identity token.
- Backend يحسب `sha256(rawNonce)` ويقارن بـ payload.nonce.
- **لا تكسر هذا الـ flow** — هو حماية ضد replay attacks.

## Release Build
```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```
يحتاج `android/key.properties` (مش في git).

## Testing
- `flutter analyze` (لا تشغّل `flutter build`).
- `test/` فاضي حالياً — أضف tests للـ business logic الجديد قدر الإمكان.

## Critical files
- `lib/core/api/api_client.dart` — Dio interceptor + 401 refresh + auth invalidation stream.
- `lib/core/auth/auth_provider.dart` — Riverpod StateNotifier.
- `lib/config/routes.dart` — GoRouter + deep link sandbox validation.
- `lib/data/local/database.dart` — sqflite singleton مع Completer lock.
