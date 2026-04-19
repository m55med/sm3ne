"use client";
import { useState } from "react";

const faqs = [
  { q: "هل التطبيق يدعم اللغة العربية؟", a: "نعم! بصوتك يدعم العربية بدقة عالية بالإضافة لأكثر من 30 لغة أخرى. يتم اكتشاف اللغة تلقائياً." },
  { q: "هل ملفاتي الصوتية محفوظة على السيرفر؟", a: "لا. نحن لا نخزن أي ملفات صوتية. يتم معالجة الصوت وتحويله لنص ثم حذف الملف فوراً." },
  { q: "ما الفرق بين الباقة المجانية والمدفوعة؟", a: "الباقة المجانية تقتصر على 30 ثانية كحد أقصى للملف الصوتي وتحتوي على إعلانات. الباقة المدفوعة بلا حدود في مدة الصوت وبدون إعلانات." },
  { q: "كيف أشارك فويس من واتساب؟", a: "اضغط مطولاً على الرسالة الصوتية في واتساب، ثم اختر 'مشاركة' أو 'إعادة توجيه'، وحدد تطبيق بصوتك من القائمة." },
  { q: "هل يعمل التطبيق بدون إنترنت؟", a: "لا. التطبيق يحتاج اتصال بالإنترنت لإرسال الملف الصوتي للسيرفر ومعالجته بالذكاء الاصطناعي." },
  { q: "لديّ ضعف سمع، هل هناك خصم؟", a: "نعم! نوفر كوبونات خاصة لذوي الاحتياجات السمعية. تواصل معنا للحصول على كوبون مجاني." },
];

export function FAQ() {
  const [open, setOpen] = useState<number | null>(null);

  return (
    <section id="faq" className="py-20 bg-gray-50">
      <div className="max-w-3xl mx-auto px-6">
        <div className="text-center mb-16">
          <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">أسئلة شائعة</h2>
        </div>
        <div className="space-y-3">
          {faqs.map((faq, i) => (
            <div key={i} className="bg-white rounded-xl overflow-hidden">
              <button
                onClick={() => setOpen(open === i ? null : i)}
                className="w-full flex items-center justify-between p-5 text-right hover:bg-gray-50 transition"
              >
                <span className="font-semibold text-gray-900">{faq.q}</span>
                <span className={`text-gray-400 transition-transform duration-200 ${open === i ? "rotate-180" : ""}`}>
                  ▼
                </span>
              </button>
              {open === i && (
                <div className="px-5 pb-5 text-gray-600 leading-relaxed">
                  {faq.a}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
