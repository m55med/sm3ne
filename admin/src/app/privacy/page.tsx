import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "سياسة الخصوصية — بصوتك",
  description:
    "كيف نتعامل مع بياناتك في تطبيق بصوتك: تسجيلات الصوت، معلومات الحساب، الإحصائيات، والخدمات الخارجية المستخدمة.",
};

// Last updated when the policy changed materially. Bump this whenever you add
// a new data type collected or a new third-party processor.
const LAST_UPDATED = "16 مايو 2026";
const SUPPORT_EMAIL = "support@neojeen.com";

export default function PrivacyPolicyAr() {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            بصوتك
          </Link>
          <Link
            href="/privacy/en"
            className="text-sm text-blue-600 hover:underline"
          >
            English
          </Link>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-6 py-10">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">
          سياسة الخصوصية
        </h1>
        <p className="text-sm text-gray-500 mb-8">
          آخر تحديث: {LAST_UPDATED}
        </p>

        <Section title="مقدمة">
          <p>
            تطبيق <b>بصوتك</b> (Bisawtak) هو خدمة لتحويل الصوت إلى نص باللغة
            العربية وأكثر من 30 لغة أخرى. صُمّم في الأصل لخدمة الأشخاص الصُّم
            وضعاف السمع، ونحرص على حماية خصوصيتك في كل خطوة.
          </p>
          <p>
            هذه السياسة توضح أنواع البيانات التي نجمعها، أسباب جمعها، طريقة
            استخدامها، ومن يصل إليها. باستخدامك التطبيق فإنك توافق على ما
            ورد فيها.
          </p>
        </Section>

        <Section title="١. البيانات التي نجمعها">
          <h3 className="font-semibold text-gray-800 mt-3 mb-1">
            (أ) بيانات الحساب
          </h3>
          <ul className="list-disc pe-6 space-y-1">
            <li>الاسم الكامل، اسم المستخدم، والبريد الإلكتروني (إذا سجّلت).</li>
            <li>
              معرّف مزود الهوية لو سجّلت بحساب Google أو Apple (لا نخزّن كلمة
              السر الخاصة بهم).
            </li>
            <li>كلمة السر مُشفَّرة (hashed) إن سجّلت بريد إلكتروني عادي.</li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (ب) الملفات الصوتية
          </h3>
          <ul className="list-disc pe-6 space-y-1">
            <li>
              التسجيلات التي ترفعها أو تسجّلها داخل التطبيق تُرسَل لمزوّد
              التفريغ النصي ثم يُحذف الملف الصوتي من خوادمنا فور انتهاء
              المعالجة.
            </li>
            <li>
              لا نحتفظ بنسخة من الصوت بعد التفريغ. النصّ الناتج يُحفظ
              محلياً على جهازك (داخل قاعدة بيانات SQLite الخاصة بالتطبيق).
            </li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (ج) سجل الاستخدام
          </h3>
          <ul className="list-disc pe-6 space-y-1">
            <li>
              عدد ومدة الطلبات، اللغة المُكتشفة، عدد الكلمات، المزوّد المستخدم
              — لاحتساب الحصة اليومية/الشهرية وحالة الباقة.
            </li>
            <li>
              لا نحتفظ بنصّ التفريغ نفسه على خوادمنا — فقط الإحصائيات الرقمية.
            </li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (د) بيانات الجهاز والجلسة
          </h3>
          <ul className="list-disc pe-6 space-y-1">
            <li>
              نظام التشغيل، موديل الجهاز، إصدار التطبيق، عنوان IP، وقت تسجيل
              الدخول — لأغراض الأمان وكشف الاستخدام المشبوه.
            </li>
            <li>
              إحصاءات الأعطال (Crash reports) عبر Firebase Crashlytics.
            </li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (هـ) مرفقات الدعم الفنّي
          </h3>
          <ul className="list-disc pe-6 space-y-1">
            <li>
              لو رفعت سكرين شوت داخل تذكرة دعم، يُخزَّن على خوادمنا حتى تُحلّ
              المشكلة، ثم يمكن حذفه بطلب منك.
            </li>
          </ul>
        </Section>

        <Section title="٢. أُذونات التطبيق على الجهاز">
          <ul className="list-disc pe-6 space-y-1">
            <li>
              <b>الميكروفون</b>: للتسجيل المباشر داخل التطبيق. لا نسجّل في
              الخلفية أبداً.
            </li>
            <li>
              <b>التخزين/الملفات</b>: لاختيار ملف صوتي أو سكرين شوت من جهازك.
            </li>
            <li>
              <b>الإشعارات</b>: لإعلامك بانتهاء التفريغ ولو غادرت التطبيق.
            </li>
            <li>
              <b>الإنترنت</b>: لإرسال الصوت لخدمات التفريغ النصي واستلام النص.
            </li>
          </ul>
        </Section>

        <Section title="٣. الخدمات الخارجية التي نستخدمها">
          <p>
            عند تفريغ ملف صوتي، يُرسَل الصوت إلى واحد من المزوّدين الآتيين
            (نختار حسب الباقة والإعدادات وقت الطلب):
          </p>
          <ul className="list-disc pe-6 space-y-1">
            <li>
              <b>OpenAI Whisper</b> (يعمل على خوادمنا الخاصة — الصوت لا يخرج
              منها).
            </li>
            <li>
              <b>Speechmatics</b> · <b>Google Gemini</b> · <b>Groq</b> ·{" "}
              <b>AssemblyAI</b> — لكل واحد منهم سياسة خصوصية خاصة. الصوت
              يُحذف من خوادمهم بعد التفريغ وفق سياساتهم المعلنة.
            </li>
            <li>
              <b>Firebase</b> (Google): تحليلات وأعطال — لا يُرسَل الصوت ولا
              النصّ المُفرَّغ.
            </li>
            <li>
              <b>Google Sign-In / Apple Sign-In</b>: للمصادقة فقط — نستلم
              معرّف المستخدم والبريد فقط.
            </li>
            <li>
              <b>Telegram Bot API</b>: لمستخدمي البوت الرسمي{" "}
              <span dir="ltr">@bisawtikbot</span> — نستلم معرّف Telegram
              والرسالة الصوتية المُرسَلة.
            </li>
          </ul>
        </Section>

        <Section title="٤. حذف الحساب والبيانات">
          <p>
            تستطيع حذف حسابك بالكامل من داخل التطبيق:{" "}
            <b>الملف الشخصي → حذف الحساب</b>. عند الحذف:
          </p>
          <ul className="list-disc pe-6 space-y-1">
            <li>
              يُلغَى حسابك ويُستبدل بريدك واسم المستخدم بنصّ مُجهَّل
              (anonymized).
            </li>
            <li>
              نحتفظ بسجلّ مُجهَّل لأغراض المراجعة المالية ومنع إساءة الاستخدام
              المتكرّر.
            </li>
            <li>تُلغَى كل الجلسات النشطة وتُحذف الـ tokens فوراً.</li>
          </ul>
          <p className="mt-2">
            أو راسلنا على {" "}
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="text-blue-600 hover:underline"
              dir="ltr"
            >
              {SUPPORT_EMAIL}
            </a>{" "}
            لطلب حذف كامل بدون أي سجلّ متبقّي.
          </p>
        </Section>

        <Section title="٥. الأطفال">
          <p>
            التطبيق غير موجَّه للأطفال دون ١٣ عاماً، ولا نجمع بياناتهم عمداً.
            لو علمت أن طفلاً أنشأ حساباً، راسلنا فوراً وسنحذف الحساب.
          </p>
        </Section>

        <Section title="٦. أمان البيانات">
          <ul className="list-disc pe-6 space-y-1">
            <li>كل الاتصالات مع خوادمنا عبر HTTPS / TLS.</li>
            <li>
              التوكنات (tokens) مُخزَّنة بأمان في{" "}
              <span dir="ltr">Keychain</span> على iOS و{" "}
              <span dir="ltr">EncryptedSharedPreferences</span> على Android.
            </li>
            <li>كلمات السر مُشفَّرة بـ bcrypt — لا نستطيع رؤيتها أبداً.</li>
            <li>
              مفاتيح JWT تنتهي صلاحيتها تلقائياً، ويمكنك إنهاء كل الجلسات من
              التطبيق.
            </li>
          </ul>
        </Section>

        <Section title="٧. تغييرات على هذه السياسة">
          <p>
            قد نُحدّث هذه السياسة من حين لآخر. التغييرات الجوهرية سنُبلغك بها
            داخل التطبيق. التاريخ في أعلى الصفحة يعكس آخر تحديث.
          </p>
        </Section>

        <Section title="٨. تواصل معنا">
          <p>
            لأي سؤال أو طلب يتعلق بهذه السياسة:{" "}
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="text-blue-600 hover:underline"
              dir="ltr"
            >
              {SUPPORT_EMAIL}
            </a>
          </p>
        </Section>

        <div className="mt-10 pt-6 border-t border-gray-200 text-sm text-gray-500 flex justify-between">
          <Link href="/" className="text-blue-600 hover:underline">
            ← الصفحة الرئيسية
          </Link>
          <Link href="/privacy/en" className="text-blue-600 hover:underline">
            English version →
          </Link>
        </div>
      </main>
    </div>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-8">
      <h2 className="text-xl font-bold text-gray-900 mb-3">{title}</h2>
      <div className="text-gray-700 leading-relaxed space-y-2">{children}</div>
    </section>
  );
}
