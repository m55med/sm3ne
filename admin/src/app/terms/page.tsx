import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "الشروط والأحكام — بصوتك",
  description:
    "شروط استخدام تطبيق بصوتك: الخدمة، الحساب، المحتوى، الباقات والاشتراكات، والمسؤولية.",
};

const LAST_UPDATED = "12 مايو 2026";

export default function TermsAr() {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            بصوتك
          </Link>
          <Link href="/terms/en" className="text-sm text-blue-600 hover:underline">
            English
          </Link>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-6 py-10">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">الشروط والأحكام</h1>
        <p className="text-sm text-gray-500 mb-8">آخر تحديث: {LAST_UPDATED}</p>

        <Section title="١. القبول">
          <p>
            باستخدامك لتطبيق <b>بصوتك</b> فأنت توافق على هذه الشروط.
          </p>
        </Section>

        <Section title="٢. الخدمة">
          <p>
            بصوتك يقدّم خدمة تحويل الصوت إلى نص بالاعتماد على تقنيات الذكاء
            الاصطناعي. الدقة عالية لكنها ليست 100%.
          </p>
        </Section>

        <Section title="٣. الحساب">
          <ul className="list-disc pe-6 space-y-1">
            <li>أنت مسؤول عن الحفاظ على سرية كلمة السر.</li>
            <li>المعلومات اللي بتدخلها لازم تكون صحيحة.</li>
            <li>نحتفظ بالحق في إيقاف أي حساب يخالف الشروط.</li>
          </ul>
        </Section>

        <Section title="٤. المحتوى">
          <ul className="list-disc pe-6 space-y-1">
            <li>أنت تملك الملفات الصوتية اللي بترفعها والنصوص الناتجة.</li>
            <li>ممنوع رفع محتوى مخالف للقانون أو ينتهك حقوق الآخرين.</li>
            <li>نحتفظ بالحق في رفض معالجة أي محتوى مشبوه.</li>
          </ul>
        </Section>

        <Section title="٥. الباقات والاشتراكات">
          <ul className="list-disc pe-6 space-y-1">
            <li>الباقة المجانية متاحة بحدود يومية محددة.</li>
            <li>الاشتراكات المدفوعة تُجدَّد تلقائياً (إلا لو ألغيتها).</li>
            <li>الإلغاء يُفعَّل في نهاية فترة الاشتراك الحالية — مفيش استرداد جزئي.</li>
          </ul>
        </Section>

        <Section title="٦. المسؤولية">
          <p>
            الخدمة مقدّمة &quot;كما هي&quot;. لسنا مسؤولين عن أي ضرر ناتج عن
            استخدام التطبيق أو الاعتماد على دقة التحويل في قرارات حسّاسة.
          </p>
        </Section>

        <Section title="٧. تغيير الشروط">
          <p>
            قد نُعدّل هذه الشروط. الاستمرار في الاستخدام بعد التعديل يعني الموافقة.
          </p>
        </Section>

        <Section title="٨. القانون المُطبَّق">
          <p>هذه الشروط تخضع للقوانين المعمول بها في جمهورية مصر العربية.</p>
        </Section>

        <Section title="٩. التواصل">
          <p>
            لأي استفسار قانوني:{" "}
            <Link href="/support" className="text-blue-600 hover:underline">
              صفحة الدعم
            </Link>
            .
          </p>
        </Section>

        <div className="mt-10 pt-6 border-t border-gray-200 text-sm text-gray-500 flex justify-between">
          <Link href="/" className="text-blue-600 hover:underline">
            ← الصفحة الرئيسية
          </Link>
          <Link href="/terms/en" className="text-blue-600 hover:underline">
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
