# CLAUDE.md

> هذا الملف هو نقطة الدخول لـ Claude Code. القواعد الكاملة في [`AGENTS.md`](./AGENTS.md) — اقرأها قبل أي تعديل.

## TL;DR للوكلاء

1. **اقرأ `AGENTS.md` كاملاً قبل أي edit** — يحتوي على قواعد الأمن وأسلوب التطوير في المشروع.
2. **المشروع 3 مكوّنات منفصلة** ولكل مكوّن قواعد:
   - `backend/` — FastAPI (راجع AGENTS.md §3)
   - `admin/` — Next.js 16 (راجع AGENTS.md §4)
   - `mobile/` — Flutter (راجع AGENTS.md §5)
3. **القواعد الذهبية** (مختصر):
   - لا `dangerouslySetInnerHTML` في الـ Admin، لا `window.confirm`/`alert` — استخدم `<ConfirmDialog>` و `toast`.
   - الـ HTTP من الـ Mobile **دائماً** عبر `data/repositories/` — مش من widgets.
   - الـ Backend: `services/` تحتوي الـ logic، الـ `routes/` رفيعة، كل auth endpoint عليه `@limiter.limit`.
   - JWT يحتوي `iss="bisawtak"`, `aud="bisawtak-app"`, `iat` — لا تكسر هذا.
   - الـ DateTime في DB كله `timezone=True`.
   - Coupons تستخدم `validate_and_consume_coupon` — atomic.
   - لا تطبع أسرار/OTP/tokens في logs.
4. **اللغة:** نصوص المستخدم عربية، التعليقات إنجليزية، أسماء الـ identifiers إنجليزية.
5. **عند إضافة env var جديد** ← حدّث `backend/.env.example`.
6. **عند إضافة column جديد** ← حدّث `models.py` + DDL في `lifespan.py`.
7. **عند الشك** ← اسأل المستخدم. لا تتخذ قرارات صامتة في architecture أو security.

## ملفات يجب أن لا تـ commit

- `backend/.env`
- `mobile/android/key.properties`
- `mobile/android/app/google-services.json`
- `mobile/ios/Runner/GoogleService-Info.plist`

(كلها في `.gitignore` — تأكد قبل أي `git add -A`.)

## تواصل

لو الـ task تخصصي جداً (مثلاً مراجعة أمنية كاملة، rewrite كبير، release planning)، استدعِ AGENTS فرعيين متخصصين بدلاً من تنفيذ كل شيء في الـ main thread.
