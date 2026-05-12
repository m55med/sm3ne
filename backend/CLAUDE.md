# Backend — Claude/Agent notes

Quick reference. الـ full rules في [`../AGENTS.md`](../AGENTS.md) §3.

## Quick rules
- **Routes thin, services fat.** أي logic > 5 سطور في route → انقله إلى `services/`.
- **`@limiter.limit("X/...")` على كل endpoint جديد** (راجع `routes/auth.py` للأمثلة).
- **`@router.get` etc. لازم يأخذ `request: Request`** لو فيه decorator limiter.
- **DateTime columns:** `Column(DateTime(timezone=True), ...)` دائماً.
- **Coupon redemption:** استخدم `subscription_service.validate_and_consume_coupon(db, code, plan_id)` — atomic.
- **Audit log:** بعد admin actions، استدع `audit_service.record(...)` (يبتلع الأخطاء — آمن).
- **OTP:** `secrets.choice` لا `random`. لا تطبع OTP في prod.
- **File upload:** `services/file_validation.validate_audio_upload` للـ magic bytes.
- **JWT validation:** الـ `get_current_user` يفحص iss/aud/iat — لا تكسر.
- **idempotent DDL** في `core/lifespan.py` لأي column/table جديد.

## env vars جديدة
- ضع في `core/config.py` مع validation.
- حدّث `.env.example` مع تعليق.

## Testing
- `python3 -c "import ast; ast.parse(open('FILE').read())"` للـ syntax check.
- لا تشغّل الـ server.

## Critical files
- `core/config.py` — يرفع RuntimeError على startup لو env var ناقصة.
- `core/lifespan.py` — DDL migrations idempotent.
- `auth/deps.py` — quota + RPM enforcement.
- `services/subscription_service.py` — atomic coupon redemption.
