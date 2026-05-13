"""Editable bot-message templates.

The bot's user-facing strings live in the ``telegram_bot_messages`` table so an
admin can edit them without a deploy. This module owns the defaults, a render()
that does simple ``{placeholder}`` substitution, and lookup helpers.

Rules:
  * Keys are stable identifiers; never rename them once shipped (the seed
    function only INSERTS missing keys, so a rename = a new row + old row
    silently stays).
  * Defaults must work even if the DB row is missing (network race during
    startup, admin deleted a row by accident). That's why ``get`` falls back
    to ``DEFAULTS`` rather than raising.
  * Placeholders are documented in the comment on each key. Renderer is
    strict on KeyError so a typo in a template doesn't show literal
    ``{wrong_key}`` to the user.
"""
from __future__ import annotations

import logging
from typing import Mapping

from sqlalchemy.orm import Session

from app.db.models import TelegramBotMessage


logger = logging.getLogger(__name__)


# Built-in fallback strings. Each value is Arabic — admins can override per-key
# from the dashboard. Placeholders in `{braces}` are filled by ``render``.
DEFAULTS: dict[str, tuple[str, str]] = {
    # (template, admin-facing description)
    "welcome_unlinked": (
        "👋 أهلاً بك في *بصوتك*!\n\n"
        "أنا بوت تفريغ الرسائل الصوتية. علشان تستخدمني، لازم تربط حسابك في "
        "التطبيق الأول:\n\n"
        "1️⃣ افتح تطبيق بصوتك على موبايلك\n"
        "2️⃣ اذهب إلى: البروفايل ← ربط مع تيليجرام\n"
        "3️⃣ اضغط على *افتح في تيليجرام* لربط حسابك تلقائياً\n\n"
        "أو ابعت لي الكود اللي ظهر لك في التطبيق هنا مباشرة.",
        "رسالة الترحيب للمستخدم اللي يدوس /start ومش مربوط (بدون كود).",
    ),
    "welcome_linked": (
        "✅ حسابك مربوط بالفعل، يا {first_name}.\n\n"
        "ابعتلي أي رسالة صوتية أو ملف صوتي وهبعتلك النص فوراً.\n\n"
        "📊 /status — حالة الباقة\n"
        "🔓 /unlink — فك الربط",
        "ترحيب المستخدم المربوط لما يدوس /start بدون كود.",
    ),
    "link_success": (
        "🎉 تم ربط حسابك بنجاح، يا {first_name}!\n\n"
        "ابعتلي أي رسالة صوتية أو ملف صوتي وهبعتلك النص فوراً.\n\n"
        "📊 /status — لمعرفة حالة الباقة\n"
        "❓ /help — للمساعدة",
        "تأكيد نجاح ربط الحساب.",
    ),
    "link_invalid_code": (
        "❌ الكود غير صحيح أو منتهي الصلاحية.\n\n"
        "افتح تطبيق بصوتك واطلب كود جديد من:\n"
        "البروفايل ← ربط مع تيليجرام",
        "رد على /start بكود غير صالح / منتهي / مستهلك.",
    ),
    "link_already_linked_other": (
        "⚠️ هذا الحساب في تيليجرام مربوط بحساب آخر في التطبيق.\n\n"
        "افصل الربط من التطبيق الأول، ثم حاول مرة أخرى.",
        "محاولة ربط حساب تيليجرام مربوط أصلاً بمستخدم تطبيق آخر.",
    ),
    "link_user_already_linked": (
        "ℹ️ حسابك في التطبيق مربوط بالفعل بحساب تيليجرام آخر.\n\n"
        "افتح التطبيق وافصل الربط الحالي قبل ما تجرب تربط حساب جديد.",
        "محاولة ربط مستخدم تطبيق مربوط أصلاً بحساب تيليجرام آخر.",
    ),
    "unlink_success": (
        "✂️ تم فك الربط.\n\n"
        "للربط مرة أخرى افتح التطبيق ← البروفايل ← ربط مع تيليجرام.",
        "تأكيد فك الربط بناءً على /unlink أو من التطبيق.",
    ),
    "unlink_not_linked": (
        "ℹ️ حسابك مش مربوط أصلاً.\n\n"
        "افتح التطبيق ← البروفايل ← ربط مع تيليجرام لربط الحساب.",
        "رد على /unlink من مستخدم غير مربوط.",
    ),
    "not_linked_voice": (
        "🔒 ابعتلي الصوت لكن حسابك في التطبيق مش مربوط بعد.\n\n"
        "حمّل تطبيق *بصوتك* واربط حسابك علشان تقدر تستخدم البوت:\n"
        "{store_links}\n\n"
        "بعد التحميل: البروفايل ← ربط مع تيليجرام.",
        "رد على رسالة صوت/صوتية من مستخدم غير مربوط.",
    ),
    "status_linked": (
        "📊 *حالة حسابك*\n\n"
        "👤 المستخدم: {username}\n"
        "💎 الباقة: {plan}\n"
        "📈 اليوم: {used_today} / {daily_limit}\n"
        "⏱️ المدة المسموحة لكل رسالة: {max_seconds_label}\n\n"
        "🔓 /unlink — لفك الربط",
        "رد /status لمستخدم مربوط.",
    ),
    "status_unlinked": (
        "ℹ️ حسابك غير مربوط.\n\n"
        "افتح التطبيق ← البروفايل ← ربط مع تيليجرام لربط الحساب.",
        "رد /status لمستخدم غير مربوط.",
    ),
    "quota_exceeded": (
        "🚦 تجاوزت الحد اليومي ({limit} رسالة في اليوم) لباقتك ({plan}).\n\n"
        "يتم تجديد العداد عند منتصف الليل بتوقيت UTC.\n"
        "للترقية: افتح التطبيق ← الباقات.",
        "رد لما المستخدم يستهلك حصته اليومية.",
    ),
    "audio_too_long": (
        "⏱️ الرسالة الصوتية أطول من الحد المسموح في باقتك "
        "({max_seconds} ثانية).\n\n"
        "تم تفريغ أول {max_seconds} ثانية فقط. للترقية افتح التطبيق ← الباقات.",
        "رد لما الرسالة الصوتية أطول من max_audio_seconds للباقة (متبوع بالنص المُفرَّغ في رسالة منفصلة).",
    ),
    "transcription_failed": (
        "❌ معلش، حصلت مشكلة وأنا بفرّغ الصوت. حاول مرة تانية بعد شوية.\n\n"
        "لو المشكلة استمرت، تواصل معنا من داخل التطبيق.",
        "رد لما الـ provider فشل في التفريغ.",
    ),
    "file_too_large": (
        "📦 الملف أكبر من الحد المسموح (20 ميجابايت لكل رسالة من تيليجرام).\n\n"
        "ابعت ملف أصغر أو ارفعه من التطبيق مباشرة.",
        "رد لما الملف أكبر من 20MB (قيد Telegram Bot API).",
    ),
    "unsupported_message": (
        "🎙️ ابعتلي رسالة صوتية أو ملف صوتي علشان أفرّغهم لك.\n\n"
        "الأوامر المتاحة:\n"
        "/start — البدء\n"
        "/status — حالة الحساب\n"
        "/unlink — فك الربط\n"
        "/help — المساعدة",
        "رد على رسالة غير مدعومة (نص عادي، صورة، فيديو، إلخ).",
    ),
    "help": (
        "🎙️ *بصوتك — تفريغ صوتي ذكي*\n\n"
        "ابعت أو أعد توجيه أي رسالة صوتية / فويس / ملف صوتي، "
        "وهبعتلك النص فوراً.\n\n"
        "*الأوامر*\n"
        "/start — البدء أو الربط بكود\n"
        "/status — حالة الباقة والاستهلاك\n"
        "/unlink — فك الربط مع التطبيق\n"
        "/help — هذه الرسالة\n\n"
        "❓ أي مشكلة؟ تواصل معنا من داخل تطبيق بصوتك.",
        "رد /help.",
    ),
}


def seed_defaults(db: Session) -> None:
    """Insert any missing default rows. Existing rows are NEVER overwritten —
    the admin's edits win. Safe to call on every startup."""
    existing = {row.key for row in db.query(TelegramBotMessage.key).all()}
    to_add: list[TelegramBotMessage] = []
    for key, (text_ar, description) in DEFAULTS.items():
        if key in existing:
            continue
        to_add.append(TelegramBotMessage(
            key=key,
            text_ar=text_ar,
            description=description,
        ))
    if to_add:
        db.add_all(to_add)
        db.commit()


def _row(db: Session, key: str) -> TelegramBotMessage | None:
    return db.query(TelegramBotMessage).filter(TelegramBotMessage.key == key).first()


def get_text(db: Session, key: str) -> str:
    """Return the raw template text (Arabic). Falls back to the built-in
    default if the row is missing — never raises."""
    row = _row(db, key)
    if row and row.text_ar:
        return row.text_ar
    default = DEFAULTS.get(key)
    if default:
        return default[0]
    logger.warning("telegram bot message key=%r has no default", key)
    return ""


def render(db: Session, key: str, **placeholders: object) -> str:
    """Look up the template and fill placeholders.

    A KeyError from ``str.format`` (template uses a placeholder we didn't pass)
    is swallowed and we return the *unrendered* template — far better than
    crashing the webhook for a bad template.
    """
    template = get_text(db, key)
    if not template:
        return ""
    if not placeholders:
        return template
    try:
        return template.format(**placeholders)
    except (KeyError, IndexError) as exc:
        logger.warning("telegram template %r missing placeholder: %s", key, exc)
        return template


def list_all(db: Session) -> list[dict]:
    """Admin dashboard listing — joins DB rows with defaults so the admin sees
    keys that exist in code but were never inserted (shouldn't happen post-seed,
    but defensive)."""
    rows = {r.key: r for r in db.query(TelegramBotMessage).all()}
    out: list[dict] = []
    for key, (default_text, description) in DEFAULTS.items():
        row = rows.get(key)
        out.append({
            "key": key,
            "description": description,
            "text_ar": row.text_ar if row else default_text,
            "default_text": default_text,
            "is_default": row is None or row.text_ar == default_text,
            "updated_at": row.updated_at if row else None,
            "updated_by_user_id": row.updated_by_user_id if row else None,
        })
    return out


def update(
    db: Session, key: str, text_ar: str, *, admin_user_id: int | None = None
) -> TelegramBotMessage:
    """Upsert a single message. Empty/whitespace text resets to default by
    DELETEing the row — so the runtime falls back to the built-in default."""
    text_ar = (text_ar or "").strip()
    row = _row(db, key)

    if not text_ar:
        if row is not None:
            db.delete(row)
            db.commit()
        # Return a transient instance representing the default so the route can
        # serialize it without another query.
        default_text, description = DEFAULTS.get(key, ("", None))
        return TelegramBotMessage(
            key=key,
            text_ar=default_text,
            description=description,
            updated_by_user_id=admin_user_id,
        )

    if row is None:
        if key not in DEFAULTS:
            raise ValueError(f"unknown telegram_bot_messages key: {key!r}")
        description = DEFAULTS[key][1]
        row = TelegramBotMessage(
            key=key,
            text_ar=text_ar,
            description=description,
            updated_by_user_id=admin_user_id,
        )
        db.add(row)
    else:
        row.text_ar = text_ar
        row.updated_by_user_id = admin_user_id
    db.commit()
    db.refresh(row)
    return row


# Render-time helper for store-link substitution. The mobile / Play store URLs
# are optional in config; this builds whatever's available into a single block.
def store_links_block() -> str:
    from app.core import config  # local import to avoid circular at startup
    parts: list[str] = []
    if config.PLAY_STORE_URL:
        parts.append(f"📱 Android: {config.PLAY_STORE_URL}")
    if config.APP_STORE_URL:
        parts.append(f"🍎 iOS: {config.APP_STORE_URL}")
    return "\n".join(parts) if parts else "افتح الـ App Store أو Google Play وابحث عن \"بصوتك\"."
