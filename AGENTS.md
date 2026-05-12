# AGENTS.md — قواعد العمل لأي AI Agent على مشروع Bisawtak

> هذا الملف هو المرجع الإلزامي لأي وكيل (Claude / GPT / Cursor / Copilot / غيره) يعمل على هذا الـ repo. اقرأه بالكامل **قبل** أي edit. لو حصل تعارض بينه وبين CLAUDE.md أو AGENTS.md داخل مجلد فرعي → هذا الملف هو المصدر، إلا لو الفرعي أكثر تخصصاً.

---

## 1. عن المشروع — ما الذي تنظر إليه؟

**Bisawtak / بصوتك** — منصة SaaS لتحويل الصوت إلى نص باللغة العربية.

| المكوّن | التقنية | المسار |
|---|---|---|
| Backend API | Python 3.x + FastAPI + SQLAlchemy + PostgreSQL | `backend/` |
| Admin Dashboard | Next.js 16 (App Router) + React 19 + TS + Tailwind 4 + `@base-ui/react` | `admin/` |
| Mobile App | Flutter 3.x + Dart + Riverpod + Dio + sqflite | `mobile/` |
| Landing Page | Next.js (نفس مشروع الـ Admin، route group منفصل) | `admin/src/app/page.tsx` |

**الـ Providers الخارجية:**
- Speechmatics (default ASR)
- Gemini (fallback ASR)
- OpenAI Whisper (local fallback)
- Apple Sign-In + Google Sign-In (social auth)
- SMTP (forgot-password OTP)

**الـ Domains:**
- Backend + Admin: `https://voice.neojeen.com` (same-origin — راجع §6).
- Mobile API base: `https://voice.neojeen.com/api/v1`.

---

## 2. القواعد العامة (Non-negotiable)

### 2.1. لا تكسر اللي شغّال
- قبل أي edit في ملف، **اقرأه بالكامل**. ممنوع التخمين.
- لو لقيت كود غريب أو "TODO" تذكر إن في وكلاء آخرين شغّالين على نفس المشروع. ابحث في git history و log الـ commits.
- لو في شك، اسأل المستخدم. الـ scope creep ممنوع.

### 2.2. كل مكوّن له صاحبه — ممنوع التداخل
- لا تعدّل ملف في مكوّن لست متأكد من حالة باقي المكوّنات. مثلاً تغيير API endpoint في الـ Backend بدون تحديث Mobile و Admin = مرفوض.
- لو الـ change يلمس contract بين مكوّنين، **حدّث الاتجاهين**: route + schema في Backend، repository + screen في Mobile/Admin.

### 2.3. ممنوع كل ما يلي بدون إذن صريح من المستخدم:
- `git push` / `git push --force` / `git reset --hard` / `git checkout -- .` / `git clean -f`.
- حذف ملفات .env أو مفاتيح keystore.
- تعديل أي إعدادات production (`.env`, `key.properties`, `GoogleService-Info.plist`).
- إنشاء PR أو دفع commits لأي branch ما عدا المحلي.
- تشغيل migrations مباشرة على DB إنتاج.

### 2.4. ممنوع إضافة dependencies بدون تبرير
- قبل ما تضيف package جديد، تأكد إنه مش موجود.
- لو لازم تضيف، اذكر السبب في الـ commit message أو في تعليق.
- في Mobile: لا تضف packages بدون تشغيل `flutter pub get` (لا تفعل ذلك يدوياً — اطلب من المستخدم).

### 2.5. اللغة
- النصوص المعروضة للمستخدم: **عربية فصحى مع لمسة مصرية مقبولة** (مثل "بصوتك"). لا تكسر هذا.
- التعليقات في الكود: **إنجليزية**.
- أسماء المتغيرات/الـ functions: **إنجليزية**.
- رسائل الأخطاء التي تُعرض في UI: **عربية**.
- error codes في الـ JSON response: **إنجليزية snake_case** (مثل `daily_quota_exceeded`).

### 2.6. ممنوع الـ secrets
- لا تطبع SECRET_KEY أو tokens أو OTP في logs (أي مستوى).
- لا تكتب مفاتيح في الكود — استخدم env vars.
- لا تـ commit ملف `.env` أو `key.properties` (موجودة في .gitignore — تأكد).
- لا تخزن tokens في `localStorage` على الـ Admin (راجع §6.2).

---

## 3. هيكل الـ Backend (FastAPI)

```
backend/
├── main.py                        # FastAPI app + CORS + security headers + routers
├── .env                            # ⚠️ لا تـ commit، يحتوي أسرار
├── .env.example                    # template للـ deployers — حدّثه كل مرة تضيف env var
├── requirements.txt
├── Dockerfile + docker-compose.yml
├── app/
│   ├── core/
│   │   ├── config.py              # كل env var. ⚠️ يرفع RuntimeError على startup لو متغيّر ناقص
│   │   ├── lifespan.py            # startup hooks + idempotent DDL (بدلاً من Alembic حالياً)
│   │   ├── security_headers.py    # CSP / HSTS / X-Frame-Options middleware
│   │   ├── time_utils.py          # utc_now, start_of_today_utc, إلخ
│   │   └── client_info.py         # extracts IP/UA/device metadata for login_events
│   ├── auth/
│   │   ├── jwt.py                 # JWT يحتوي iss/aud/iat — راجع §3.4
│   │   ├── deps.py                # quota + RPM enforcement + auth dependency injectors
│   │   ├── api_key.py             # HMAC-SHA256 with pepper for API keys
│   │   ├── social.py              # Google/Apple verify (nonce mandatory for Apple)
│   │   └── password.py            # bcrypt(rounds=12)
│   ├── db/
│   │   ├── database.py            # SQLAlchemy session
│   │   └── models.py              # كل الـ models. ⚠️ DateTime(timezone=True) دايماً
│   ├── routes/                    # كل route ملف خاص
│   ├── schemas/                   # Pydantic input/output schemas
│   └── services/                  # business logic — مش في routes!
└── scripts/
```

### 3.1. القاعدة الذهبية للـ Backend
**الـ routes رفيعة — كل الـ logic في `services/`.**

### 3.2. Idempotent DDL في `lifespan.py`
حالياً لا يوجد Alembic. كل column أو table جديد يضاف عبر `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...` داخل `lifespan.py`. **لو أضفت column في `models.py`، لازم تضيف DDL مقابل في `lifespan.py`.**

### 3.3. Rate Limiting
- كل auth endpoint عليه `@limiter.limit(...)` — راجع `routes/auth.py`.
- `slowapi` بـ in-memory backend في dev، وعلى prod يُفضّل `RATE_LIMIT_STORAGE_URI=redis://...`.
- bucket على `auth_principal` لو موجود (راجع `core/config._rate_limit_key`)، وإلا IP.
- **لا تضف endpoint جديد بدون rate limit مناسب.**

### 3.4. JWT
- `HS256`، يحوي: `sub, username, role, iss="bisawtak", aud="bisawtak-app", iat, exp`.
- التحقق صارم — أي token بدون `iss/aud/iat/exp` يُرفض.
- لو `user.password_changed_at > iat` يُرفض (يبطل tokens بعد change-password).
- مدة الـ token: `TOKEN_EXPIRE_MINUTES` (افتراضي 1440 = 24h).
- **لا يوجد JWT blocklist** — `/auth/logout` no-op على الـ server (راجع limitation في الكود).

### 3.5. الـ Quota و Plans
- كل خطة في جدول `plans`. القيم في الـ DB، **لا تجعلها hardcoded في الكود**.
- `is_live_recording=true` **لا يتخطى الـ quota** — له quota منفصلة (20 free / 200 paid).
- API keys بحساب موحّد عبر كل مفاتيح المستخدم — لا تستطيع تجاوز الحد بإنشاء مفاتيح متعددة.
- Coupon redemption **atomic** عبر `validate_and_consume_coupon` — لا تستخدم read-modify-write.

### 3.6. الـ /plans/subscribe gate
- الـ free plan: مفتوح بدون coupon.
- الـ paid plans: تتطلب `coupon_code` صالح وإلا `402 Payment Required`.
- لا يوجد payment gateway مدمج بعد — لما تتدمج، حدّث الـ gate. **لا تشيل الفحص الحالي قبل ما تربط gateway فعلي.**

### 3.7. File Upload
- استخدم `services/file_validation.py:validate_audio_upload` لكل upload.
- يفحص magic bytes + extension.
- حد أقصى `MAX_UPLOAD_BYTES` (افتراضي 200 MB).
- `ffmpeg/ffprobe` بـ `-protocol_whitelist file,pipe` دائماً.

### 3.8. Logging
- لا تطبع OTP أو tokens.
- استخدم `logging.exception(...)` لإلتقاط stack trace في الـ server دون تسريبها للمستخدم.
- رسائل الـ HTTPException للمستخدم النهائي يجب أن تكون عامة ("Transcription failed") لا تفاصيل تقنية.

### 3.9. Audit Log
- استخدم `services/audit_service.record(...)` بعد كل admin action حساس.
- الـ `record` يبتلع الأخطاء بـ try/except — لا تتركها تكسر الـ action.
- DB column اسمه `metadata` لكن في الـ ORM `metadata_json` (محجوزة في SQLAlchemy).

---

## 4. هيكل الـ Admin (Next.js)

```
admin/
├── next.config.ts                  # security headers + CSP
├── package.json
├── .env.local                      # NEXT_PUBLIC_API_URL لو محتاج override
├── src/
│   ├── app/
│   │   ├── page.tsx               # Landing page (public)
│   │   ├── login/                 # Admin login
│   │   ├── (admin)/               # كل صفحات الـ admin، محمية بـ useAuth
│   │   │   ├── layout.tsx         # sidebar + Toaster + ConfirmDialog هنا
│   │   │   └── ...
│   ├── components/
│   │   ├── ui/                    # @base-ui/react primitives (dialog, popover, etc.)
│   │   ├── landing/               # landing page components
│   │   ├── confirm-dialog.tsx     # ⭐ استخدمه دائماً بدلاً من window.confirm
│   │   ├── toaster.tsx            # ⭐ استخدمه دائماً بدلاً من alert
│   │   ├── empty-state.tsx
│   │   ├── error-boundary.tsx
│   │   └── skeleton-table.tsx
│   ├── lib/
│   │   ├── api.ts                 # fetch wrapper مع 401 handling
│   │   ├── auth.ts                # useAuth + JWT decode + role check
│   │   ├── labels.ts              # ⭐ كل الـ labels العربية موحّدة هنا
│   │   ├── format.ts              # formatNumber, formatDate (Intl.ar-EG, gregory)
│   │   └── types.ts
│   └── hooks/
│       └── use-debounced-value.ts
```

### 4.1. القواعد الذهبية للـ Admin

| ممنوع | بديل |
|---|---|
| `window.confirm`, `confirm()` | `<ConfirmDialog>` من `components/confirm-dialog.tsx` |
| `alert()` | `toast.error()` / `toast.success()` من `components/toaster.tsx` |
| `dangerouslySetInnerHTML` | استخدم نصاً عادياً — React يهرّب تلقائياً |
| `localStorage.getItem("token")` بدون decode | استخدم `useAuth()` و `getDecodedToken()` |
| `<a href="#">` | `<button disabled>` لو الميزة قريباً، أو route فعلي |
| `border-l/r`, `mr-/ml-`, `left-/right-` | logical CSS: `border-s/e`, `me-/ms-`, `start-/end-` |
| `toLocaleDateString("ar")` | `formatDateTime()` من `lib/format.ts` (يستخدم gregorian) |
| Hardcoded plan/ticket labels | استورد من `lib/labels.ts` |

### 4.2. الـ JWT validation
- `useAuth` يفحص: token موجود، `payload.role === "admin"`، `exp * 1000 > Date.now()`.
- لو أي فحص فشل ← clear token + redirect to `/login`.
- التوكن في `localStorage` للآن (مرحلة انتقالية — راجع §6.2). أي ميزة جديدة، لا تضع secrets في localStorage.

### 4.3. Security Headers
- محدّدة في `next.config.ts` async headers(). إذا أضفت endpoint جديد يحتاج CSP إضافي، حدّث `connect-src`.

### 4.4. RTL
- الـ root `<html lang="ar" dir="rtl">`.
- استخدم logical CSS لا physical.
- أرقام بالـ `Intl.NumberFormat("ar-EG")` (راجع `lib/format.ts`).
- نص لاتيني داخل عربي: لفّه في `<span dir="ltr">`.

---

## 5. هيكل الـ Mobile (Flutter)

```
mobile/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md                       # build/run/release instructions
├── android/
│   ├── key.properties.example      # template — actual key.properties ليس في git
│   └── app/
│       ├── build.gradle.kts        # signing config مع debug fallback
│       └── src/main/AndroidManifest.xml  # ⚠️ INTERNET + RECORD_AUDIO + allowBackup=false
├── ios/
│   └── Runner/
│       ├── Info.plist              # ATS lockdown
│       └── Runner.entitlements
├── lib/
│   ├── main.dart                   # MaterialApp + Localizations + share intent handlers
│   ├── config/
│   │   ├── constants.dart          # apiBaseUrl via String.fromEnvironment('API_URL', ...)
│   │   └── routes.dart             # GoRouter — deep links مع sandbox checks
│   ├── core/
│   │   ├── api/api_client.dart     # Dio + 401 refresh + auth invalidation stream
│   │   └── auth/
│   │       ├── token_storage.dart  # FlutterSecureStorage مع encryptedSharedPrefs
│   │       └── auth_provider.dart  # Riverpod StateNotifier
│   ├── data/
│   │   ├── models/                 # plain Dart classes (لا json_serializable حالياً)
│   │   ├── local/                  # sqflite — transcriptions cache
│   │   └── repositories/           # ⭐ كل HTTP يمر هنا، مش في widgets
│   ├── shared/
│   │   ├── utils/
│   │   │   ├── error_messages.dart # friendlyErrorMessage() — استخدمه دائماً
│   │   │   ├── file_validation.dart
│   │   │   └── sandbox_paths.dart
│   │   └── widgets/
│   │       ├── confirm_dialog.dart # ⭐ showConfirmDialog()
│   │       ├── empty_state.dart
│   │       ├── error_view.dart
│   │       └── connectivity_banner.dart
│   └── features/                   # واحدة لكل feature، screens فقط هنا
└── test/                           # ⚠️ فاضي حالياً — أضف tests للـ business logic الجديد
```

### 5.1. القواعد الذهبية للـ Mobile

| ممنوع | بديل |
|---|---|
| HTTP مباشر من widget (`dio.post`) | استخدم repository من `data/repositories/` |
| نصوص خطأ خام (`'فشل: $e'`) | `friendlyErrorMessage(e)` من `shared/utils/error_messages.dart` |
| `print(...)` على بيانات حساسة | `debugPrint` فقط لا غير، ولا بيانات حساسة |
| `flutter_secure_storage()` بدون options | استخدم `aOptions: AndroidOptions(encryptedSharedPreferences: true)` |
| `Future.delayed(2s)` فقط للـ UX | تخلص — السبب الحقيقي للانتظار يجب أن يكون async work |
| `permission_handler` بدون `openAppSettings` fallback | لما يكون `permanentlyDenied`، أعرض dialog مع زر إعدادات |
| Hardcoded plan names (`if plan.name == 'annual'`) | استخدم signals من الـ backend (`is_recommended`, price diff) |
| Hardcoded API URL | استخدم `AppConstants.apiBaseUrl` (يقرأ من `--dart-define API_URL=...`) |
| ضغط مزدوج على submit | احفظ `_loading/_saving` flag وعطّل الزر |

### 5.2. Deep Links — حماية إلزامية
أي path يأتي من deep link / share intent **لازم** يمر بـ:
1. `isPathInsideSandbox(path)` من `shared/utils/sandbox_paths.dart`
2. `hasAllowedAudioExtension(path)`
3. `validateAudioFileForUpload(path)` من `file_validation.dart`

لا تـ upload أي ملف لم يجتز الفحوص الثلاثة.

### 5.3. Authentication
- التوكنات في `FlutterSecureStorage` مع options صحيحة.
- `isFirstLaunch` في `SharedPreferences` (مش secure storage — هذا متعمد عشان iOS keychain يبقى بعد uninstall).
- `appleSignIn(token, {nonce})` يبعث الـ raw nonce؛ الـ Backend يحسب `sha256` ويقارن.
- 401 يبدأ refresh attempt مرة واحدة؛ لو فشل، يمسح كل التوكنات ويبعث event على `authInvalidationProvider`.
- `logout()` يستدعي backend (best-effort) + يمسح كل التوكنات + يمسح DB المحلية.

### 5.4. Release Build
- Android signing عبر `android/key.properties` (مش في git). لو غير موجود، الـ release يستخدم debug keystore (للتطوير فقط).
- يجب `flutter build apk --release --obfuscate --split-debug-info=build/symbols`.
- iOS: راجع `IOS_SETUP_GUIDE.md`.

### 5.5. Localization
- الـ ARB files في `lib/l10n/`. `AppLocalizations.delegate` متصل في `main.dart`.
- **استخدم `AppLocalizations.of(context)!.xxx` للنصوص الجديدة، لا تكتب hardcoded** (إلا للنصوص الدلائلية الطويلة كـ FAQ، حالياً معفاة).

### 5.6. Permissions على Android
ملف `AndroidManifest.xml` الـ MAIN يجب أن يحتوي:
- `INTERNET` (حرجة — بدونها التطبيق لا يعمل في release)
- `RECORD_AUDIO`
- `WAKE_LOCK`
- `ACCESS_NETWORK_STATE`
- `<application android:allowBackup="false">`

---

## 6. قواعد أمنية حرجة (Don't break)

### 6.1. CORS
- `backend/main.py` يقرأ `CORS_ALLOWED_ORIGINS` من env. **لا ترجع لـ `["*"]`**.

### 6.2. JWT Storage في الـ Admin
- حالياً في `localStorage` لمشكلة جذرية (راجع §6 من تقرير الفحص الأمني).
- خطة الانتقال: `HttpOnly Secure SameSite=Strict cookie`. لا تضف ميزات جديدة تعتمد على localStorage لتوكنات.

### 6.3. Coupon Race
- استخدم `validate_and_consume_coupon` دائماً — atomic UPDATE...RETURNING.
- لا تستخدم `coupon.times_used += 1` يدوياً — race condition.

### 6.4. Admin Mutation Protection
- لا يستطيع admin تعطيل admin آخر (`update_user` يتحقق).
- لا يستطيع admin تخفيض رتبته (`update_user` يتحقق).
- كل admin action مهم يكتب audit log.

### 6.5. Password Reset (OTP)
- OTP بـ `secrets.choice` (لا `random`).
- 5 محاولات قصوى ثم OTP يموت.
- توليد OTP جديد يبطل القديم.
- لا تطبع الـ OTP أبداً في prod. `EMAIL_DEV_PRINT_OTP=true` للـ dev فقط.

### 6.6. Social Auth
- `GOOGLE_CLIENT_ID` mandatory — يرفع 503 لو فاضي.
- `APPLE_CLIENT_ID` mandatory.
- لا تربط social account بـ local account تلقائياً (الكود يرفع 409 `account_exists_local`).
- nonce حماية إلزامية لـ Apple (مبيث من الموبايل، يحقق على الـ backend).

### 6.7. File Upload
- magic bytes + extension + size + ffmpeg protocol whitelist — لا تتجاوز أيها.

### 6.8. Rate Limiting على Endpoints الحساسة
| Endpoint | Limit |
|---|---|
| `/auth/login` | 5/min |
| `/auth/register` | 3/min |
| `/auth/forgot-password` | 3/hour |
| `/auth/reset-password` | 5/min |
| `/auth/google`, `/auth/apple` | 10/min |
| `/plans/subscribe`, `/plans/coupon` | 5/min |
| `/keys` (POST) | 5/hour |
| `/support/tickets` (POST) | 5/hour |
| `/transcribe` | per-plan RPM via `check_rpm_limit` |

---

## 7. سير العمل (Workflow) المتوقع

### 7.1. قبل أي edit
1. اقرأ `AGENTS.md` (هذا الملف).
2. اقرأ `CLAUDE.md` لو موجود.
3. اقرأ الملف الذي ستعدله بالكامل.
4. لو الـ feature تلمس أكثر من مكوّن، رتّب الـ changes بحيث contract calls لا تنكسر.

### 7.2. عند إضافة env var جديد
1. أضفه في `backend/app/core/config.py` (مع validation لو لازم).
2. حدّث `backend/.env.example` مع تعليق توضيحي.
3. لو variable حساس، تأكد من غيابه عن git history و logs.

### 7.3. عند إضافة column/table جديد
1. عدّل `backend/app/db/models.py` (مع `DateTime(timezone=True)`).
2. أضف DDL idempotent في `backend/app/core/lifespan.py`.
3. تأكد من index لو حقل بحثي.

### 7.4. عند إضافة endpoint جديد
1. Schema في `backend/app/schemas/`.
2. Route رفيع في `backend/app/routes/`.
3. Logic في `backend/app/services/`.
4. Rate limit decorator (`@limiter.limit("X/...")`).
5. Audit log call لو admin action.
6. لو endpoint مستخدم من Mobile: أضف method في الـ repository المناسب.
7. لو endpoint مستخدم من Admin: أضف function call في الـ page المناسبة + types في `lib/types.ts`.

### 7.5. قبل ما تقول "خلصت"
- Backend: `python3 -c "import ast; ast.parse(open('FILE').read())"` لكل ملف معدّل.
- Admin: راجع imports + tsconfig errors.
- Mobile: `flutter analyze` لو متاح (لا تشغل `flutter build`).
- وثّق أي behavioral change في تعليق على الكود.

### 7.6. ممنوع كتابة tests وهمية
- لا تكتب test يـ assert على شيء واضح فقط للوصول لـ coverage.
- لو ما تستطيع تكتب test حقيقي، اترك TODO واضح.

---

## 8. اللي قابل للنقاش — لا تعدّله بدون مناقشة

- اختيار default transcription provider (`speechmatics > gemini > whisper`).
- مدة JWT (`TOKEN_EXPIRE_MINUTES=1440`).
- صلاحية OTP و duration.
- حدود الـ plans (موجودة في DB، لكن defaults في `PLAN_DEFAULTS` بـ `lifespan.py`).
- الـ AdMob test IDs (يجب استبدالها قبل release لكن استشر المستخدم).

---

## 9. عند الشك → اسأل المستخدم

أمثلة على ما يستوجب السؤال قبل التنفيذ:
- إضافة dependency جديد كبير (`@tanstack/react-query`, `freezed`, إلخ).
- تغيير schema يكسر backward compatibility (إعادة تسمية حقل).
- migration ضخم على DB.
- إعادة تنظيم architecture كاملة (مثلاً تحويل الـ admin لـ React Query).
- تشغيل أي حاجة على بيئة الإنتاج.
- إصدار release جديد للموبايل.

---

## 10. تاريخ التعديل

- **2026-05-12** — إصدار أول. صدر بعد audit شامل وتطبيق 100+ إصلاح أمني وUX على Backend/Admin/Mobile. راجع الـ git log من تاريخ هذا الـ commit للحصول على قائمة الإصلاحات.

---

> **آخر تذكير:** هذا المشروع تجاري وسيستخدمه مستخدمون حقيقيون. الـ shortcut اليوم = ثغرة بكرة. لا تعمل دش الخطوات الأمنية بحجة "السرعة". لو السرعة هي الأولوية، استشر المستخدم بصراحة بدلاً من اتخاذ قرار صامت.
