"""Static legal pages served from the same backend (HTML).

App stores (Apple App Store + Google Play) require a publicly accessible URL
for Privacy Policy / Terms of Service. We host them here so the URL lives on
the same domain as the API (voice.neojeen.com), no separate static host needed.

Content is Arabic-first with English fallback at /en/<page>.
"""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["legal"])


_BASE_CSS = """
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Cairo", sans-serif;
         max-width: 760px; margin: 2rem auto; padding: 0 1rem; line-height: 1.7;
         color: #1f2937; background: #f9fafb; }
  h1 { color: #4A90D9; border-bottom: 2px solid #4A90D9; padding-bottom: .4rem; }
  h2 { color: #1e3a8a; margin-top: 2rem; }
  p, li { color: #374151; }
  a { color: #4A90D9; }
  .meta { color: #6b7280; font-size: .875rem; }
  .lang-switch { text-align: end; margin-bottom: 1rem; }
  .container { background: white; padding: 2rem; border-radius: 12px;
               box-shadow: 0 1px 3px rgba(0,0,0,.04); }
</style>
"""


def _wrap(title: str, body: str, lang: str = "ar") -> str:
    dir_attr = "rtl" if lang == "ar" else "ltr"
    switch_text = "English" if lang == "ar" else "العربية"
    switch_href = "/en" if lang == "ar" else "/"
    return f"""<!DOCTYPE html>
<html lang="{lang}" dir="{dir_attr}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title} | بصوتك</title>
{_BASE_CSS}
</head>
<body>
<div class="container">
<div class="lang-switch"><a href="{switch_href}">{switch_text}</a></div>
{body}
</div>
</body>
</html>"""


@router.get("/privacy", response_class=HTMLResponse)
async def privacy_ar():
    body = """
<h1>سياسة الخصوصية</h1>
<p class="meta">آخر تحديث: 12 مايو 2026</p>

<p>نحن في تطبيق <strong>بصوتك</strong> نلتزم بحماية خصوصيتك. هذه السياسة توضح كيف نجمع ونستخدم ونحمي معلوماتك.</p>

<h2>1. البيانات التي نجمعها</h2>
<ul>
  <li><strong>بيانات الحساب:</strong> اسم المستخدم، البريد الإلكتروني، الاسم الكامل، طريقة تسجيل الدخول (Google/Apple/كلمة سر).</li>
  <li><strong>الملفات الصوتية:</strong> الملفات التي ترفعها أو تسجلها للتحويل لنص. تُعالج فوراً ويتم حذفها من سيرفرنا بعد المعالجة.</li>
  <li><strong>النص المُحوَّل:</strong> نحتفظ بالنص الناتج فقط مرتبطاً بحسابك للوصول له لاحقاً.</li>
  <li><strong>بيانات الاستخدام:</strong> عدد الطلبات، التواريخ، عنوان IP، نوع الجهاز ونظام التشغيل (للأمان والإحصاءات).</li>
</ul>

<h2>2. كيف نستخدم البيانات</h2>
<ul>
  <li>تقديم خدمة تحويل الصوت إلى نص.</li>
  <li>إدارة حسابك واشتراكاتك.</li>
  <li>تحسين الخدمة وتشخيص المشاكل.</li>
  <li>التواصل معك بخصوص الخدمة.</li>
</ul>

<h2>3. مشاركة البيانات</h2>
<p>لا نبيع ولا نؤجر بياناتك. نستخدم مقدمي خدمات تفريغ خارجيين مُعتمدين (Speechmatics و Google Gemini و Groq و AssemblyAI) لمعالجة الصوت. هؤلاء المقدمون ملزمون بسياسات صارمة.</p>

<h2>4. حقوقك</h2>
<ul>
  <li><strong>الوصول والتعديل:</strong> من شاشة الإعدادات تستطيع تعديل بياناتك.</li>
  <li><strong>حذف الحساب:</strong> تستطيع حذف حسابك نهائياً من داخل التطبيق (حسابي ← حذف الحساب). كل بياناتك تُحذف فوراً بشكل دائم.</li>
  <li><strong>طلب نسخة:</strong> راسلنا للحصول على نسخة من بياناتك.</li>
</ul>

<h2>5. الإعلانات</h2>
<p>قد نعرض إعلانات عبر Google AdMob. AdMob قد تجمع معرف الإعلان والموقع التقريبي لعرض إعلانات ملائمة. تستطيع تعطيل التتبع من إعدادات الجهاز.</p>

<h2>6. أمان البيانات</h2>
<p>نستخدم تشفير HTTPS لكل الاتصالات، وكلمات السر مشفّرة بـ bcrypt. لا نخزن أي ملف صوتي بعد المعالجة.</p>

<h2>7. الأطفال</h2>
<p>التطبيق غير مخصص للأطفال تحت 13 سنة. لا نجمع بيانات قاصرين عن قصد.</p>

<h2>8. التغييرات</h2>
<p>قد نُحدث هذه السياسة. التغييرات تظهر هنا مع تاريخ التحديث.</p>

<h2>9. التواصل</h2>
<p>لأي استفسار: <a href="/support">صفحة الدعم</a> أو من داخل التطبيق "حسابي ← اتصل بنا".</p>
"""
    return HTMLResponse(_wrap("سياسة الخصوصية", body, lang="ar"))


@router.get("/terms", response_class=HTMLResponse)
async def terms_ar():
    body = """
<h1>الشروط والأحكام</h1>
<p class="meta">آخر تحديث: 12 مايو 2026</p>

<h2>1. القبول</h2>
<p>باستخدامك لتطبيق <strong>بصوتك</strong> فأنت توافق على هذه الشروط.</p>

<h2>2. الخدمة</h2>
<p>بصوتك يقدم خدمة تحويل الصوت إلى نص بالاعتماد على تقنيات الذكاء الاصطناعي. الدقة عالية لكنها ليست 100%.</p>

<h2>3. الحساب</h2>
<ul>
  <li>أنت مسؤول عن الحفاظ على سرية كلمة السر.</li>
  <li>المعلومات اللي بتدخلها لازم تكون صحيحة.</li>
  <li>نحتفظ بالحق في إيقاف أي حساب يخالف الشروط.</li>
</ul>

<h2>4. المحتوى</h2>
<ul>
  <li>أنت تملك الملفات الصوتية اللي بترفعها والنصوص الناتجة.</li>
  <li>ممنوع رفع محتوى مخالف للقانون أو ينتهك حقوق الآخرين.</li>
  <li>نحتفظ بالحق في رفض معالجة أي محتوى مشبوه.</li>
</ul>

<h2>5. الباقات والاشتراكات</h2>
<ul>
  <li>الباقة المجانية متاحة بحدود يومية محددة.</li>
  <li>الاشتراكات المدفوعة تُجدد تلقائياً (إلا لو ألغيتها).</li>
  <li>الإلغاء يُفعّل في نهاية فترة الاشتراك الحالية — مفيش استرداد جزئي.</li>
</ul>

<h2>6. المسؤولية</h2>
<p>الخدمة مقدمة "كما هي". لسنا مسؤولين عن أي ضرر ناتج عن استخدام التطبيق أو الاعتماد على دقة التحويل في قرارات حساسة.</p>

<h2>7. تغيير الشروط</h2>
<p>قد نُعدّل هذه الشروط. الاستمرار في الاستخدام بعد التعديل يعني الموافقة.</p>

<h2>8. القانون المُطبَّق</h2>
<p>هذه الشروط تخضع للقوانين المعمول بها في جمهورية مصر العربية.</p>

<h2>9. التواصل</h2>
<p>لأي استفسار قانوني: <a href="/support">صفحة الدعم</a>.</p>
"""
    return HTMLResponse(_wrap("الشروط والأحكام", body, lang="ar"))


@router.get("/support", response_class=HTMLResponse)
async def support_ar():
    body = """
<h1>الدعم الفني</h1>
<p>إحنا هنا عشان نساعدك. اختار الطريقة اللي تناسبك:</p>

<h2>📱 من داخل التطبيق</h2>
<p>افتح <strong>بصوتك</strong> → حسابي → <strong>اتصل بنا / اقتراحات</strong>. هتلاقي نموذج لإرسال رسالتك وستظهر الردود في نفس المكان.</p>

<h2>📧 البريد الإلكتروني</h2>
<p>راسلنا على: <a href="mailto:support@neojeen.com">support@neojeen.com</a></p>

<h2>📚 الأسئلة الشائعة</h2>
<ul>
  <li><strong>إزاي أحذف حسابي؟</strong> حسابي ← حذف الحساب نهائياً (هيطلب تأكيد هويتك).</li>
  <li><strong>إيه الصيغ المدعومة؟</strong> MP3, M4A, WAV, OGG, FLAC, AAC, WebM, MP4 (صوت).</li>
  <li><strong>ليه بيتقص الصوت؟</strong> الباقة المجانية محدودة بـ 30 ثانية لكل ملف. ترقّى للباقات المدفوعة لإزالة الحد.</li>
  <li><strong>هل بيانات الصوت آمنة؟</strong> آه، تُحذف من السيرفر بعد المعالجة مباشرة. النص فقط هو اللي بيتحفظ في حسابك.</li>
</ul>

<h2>⏱️ مواعيد الرد</h2>
<p>هنرد على رسالتك خلال 24-48 ساعة في أيام العمل.</p>
"""
    return HTMLResponse(_wrap("الدعم", body, lang="ar"))


# ---- English versions ----

@router.get("/en/privacy", response_class=HTMLResponse)
async def privacy_en():
    body = """
<h1>Privacy Policy</h1>
<p class="meta">Last updated: May 12, 2026</p>

<p>At <strong>Bisawtak</strong> we are committed to protecting your privacy. This policy explains how we collect, use, and protect your information.</p>

<h2>1. Data We Collect</h2>
<ul>
  <li><strong>Account data:</strong> email, full name (optional), sign-in method (Google/Apple/password).</li>
  <li><strong>Audio files:</strong> files you upload or record for transcription. Processed immediately and deleted from our server.</li>
  <li><strong>Transcribed text:</strong> only the resulting text is kept, linked to your account for later access.</li>
  <li><strong>Usage data:</strong> request counts, timestamps, IP, device type and OS (for security and analytics).</li>
</ul>

<h2>2. How We Use Data</h2>
<ul>
  <li>Provide the speech-to-text service.</li>
  <li>Manage your account and subscriptions.</li>
  <li>Improve the service and diagnose issues.</li>
  <li>Communicate with you about the service.</li>
</ul>

<h2>3. Data Sharing</h2>
<p>We do not sell or rent your data. We use approved external transcription providers (Speechmatics, Google Gemini, Groq, and AssemblyAI) for audio processing. These providers are bound by strict policies.</p>

<h2>4. Your Rights</h2>
<ul>
  <li><strong>Access &amp; edit:</strong> from the in-app settings.</li>
  <li><strong>Account deletion:</strong> permanently delete your account from the app (Account → Delete Account). All your data is removed immediately and permanently.</li>
  <li><strong>Data copy:</strong> contact us to request a copy of your data.</li>
</ul>

<h2>5. Ads</h2>
<p>We may show ads via Google AdMob. AdMob may collect ad ID and approximate location to serve relevant ads. You can disable tracking from your device settings.</p>

<h2>6. Security</h2>
<p>All communications use HTTPS. Passwords are hashed with bcrypt. No audio file is stored after processing.</p>

<h2>7. Children</h2>
<p>The app is not for children under 13. We do not knowingly collect data from minors.</p>

<h2>8. Changes</h2>
<p>We may update this policy. Changes appear here with the update date.</p>

<h2>9. Contact</h2>
<p>For any question: <a href="/en/support">support page</a> or in-app "Account → Contact us".</p>
"""
    return HTMLResponse(_wrap("Privacy Policy", body, lang="en"))


@router.get("/en/terms", response_class=HTMLResponse)
async def terms_en():
    body = """
<h1>Terms of Service</h1>
<p class="meta">Last updated: May 12, 2026</p>

<h2>1. Acceptance</h2>
<p>By using <strong>Bisawtak</strong> you agree to these terms.</p>

<h2>2. Service</h2>
<p>Bisawtak provides speech-to-text conversion using AI. Accuracy is high but not 100%.</p>

<h2>3. Account</h2>
<p>You are responsible for keeping your password secure and for the accuracy of information you provide.</p>

<h2>4. Content</h2>
<p>You own the audio you upload and the resulting text. Uploading unlawful content is prohibited.</p>

<h2>5. Plans &amp; Subscriptions</h2>
<p>Free plan has daily limits. Paid subscriptions auto-renew until cancelled.</p>

<h2>6. Liability</h2>
<p>Service is provided "as is". We are not liable for damages from reliance on transcription accuracy in sensitive decisions.</p>

<h2>7. Governing Law</h2>
<p>Governed by the laws of the Arab Republic of Egypt.</p>

<h2>8. Contact</h2>
<p>For legal questions: <a href="/en/support">support page</a>.</p>
"""
    return HTMLResponse(_wrap("Terms of Service", body, lang="en"))


@router.get("/en/support", response_class=HTMLResponse)
async def support_en():
    body = """
<h1>Support</h1>
<p>We're here to help.</p>

<h2>📱 In-App</h2>
<p>Open <strong>Bisawtak</strong> → Account → <strong>Contact us</strong>.</p>

<h2>📧 Email</h2>
<p><a href="mailto:support@neojeen.com">support@neojeen.com</a></p>

<h2>⏱️ Response Time</h2>
<p>We reply within 24-48 hours on business days.</p>
"""
    return HTMLResponse(_wrap("Support", body, lang="en"))
