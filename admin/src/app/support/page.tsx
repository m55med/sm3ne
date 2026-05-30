import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "الدعم الفني — بصوتك",
  description:
    "تواصل مع فريق بصوتك: من داخل التطبيق أو عبر البريد الإلكتروني، مع إجابات الأسئلة الشائعة ومواعيد الرد.",
};

const SUPPORT_EMAIL = "support@neojeen.com";

export default function SupportAr() {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            بصوتك
          </Link>
          <Link href="/support/en" className="text-sm text-blue-600 hover:underline">
            English
          </Link>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-6 py-10">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">الدعم الفني</h1>
        <p className="text-gray-700 mb-8">
          إحنا هنا عشان نساعدك. اختار الطريقة اللي تناسبك:
        </p>

        <Section title="📱 من داخل التطبيق">
          <p>
            افتح <b>بصوتك</b> ← حسابي ← <b>اتصل بنا / اقتراحات</b>. هتلاقي نموذج
            لإرسال رسالتك، وهتظهر الردود في نفس المكان.
          </p>
        </Section>

        <Section title="📧 البريد الإلكتروني">
          <p>
            راسلنا على:{" "}
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="text-blue-600 hover:underline"
              dir="ltr"
            >
              {SUPPORT_EMAIL}
            </a>
          </p>
        </Section>

        <Section title="📚 الأسئلة الشائعة">
          <ul className="list-disc pe-6 space-y-2">
            <li>
              <b>إزاي أحذف حسابي؟</b> حسابي ← حذف الحساب نهائياً (هيطلب تأكيد
              هويتك).
            </li>
            <li>
              <b>إيه الصيغ المدعومة؟</b>{" "}
              <span dir="ltr">MP3, M4A, WAV, OGG, FLAC, AAC, WebM, MP4</span>{" "}
              (صوت).
            </li>
            <li>
              <b>ليه بيتقص الصوت؟</b> الباقة المجانية محدودة بـ 30 ثانية لكل ملف.
              ترقَّ للباقات المدفوعة لإزالة الحد.
            </li>
            <li>
              <b>هل بيانات الصوت آمنة؟</b> آه، تُحذف من السيرفر بعد المعالجة
              مباشرة. النص فقط هو اللي بيتحفظ في حسابك.
            </li>
          </ul>
        </Section>

        <Section title="⏱️ مواعيد الرد">
          <p>هنرد على رسالتك خلال 24-48 ساعة في أيام العمل.</p>
        </Section>

        <div className="mt-10 pt-6 border-t border-gray-200 text-sm text-gray-500 flex justify-between">
          <Link href="/" className="text-blue-600 hover:underline">
            ← الصفحة الرئيسية
          </Link>
          <Link href="/support/en" className="text-blue-600 hover:underline">
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
