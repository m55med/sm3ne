export function Footer() {
  // TODO: replace with a real, monitored support inbox once one is provisioned.
  // The domain in use is voice.neojeen.com, so we route to neojeen for now.
  const SUPPORT_EMAIL = "support@neojeen.com";
  return (
    <footer className="bg-gray-900 text-gray-400 py-12">
      <div className="max-w-6xl mx-auto px-6">
        <div className="flex flex-col md:flex-row justify-between items-center gap-6">
          <div>
            <span className="text-2xl font-bold text-white">بصوتك</span>
            <p className="text-sm mt-1">حوّل الصوت إلى نص بالذكاء الاصطناعي</p>
          </div>
          <div className="flex gap-6 text-sm flex-wrap justify-center">
            <a href="#features" className="hover:text-white transition">المميزات</a>
            <a href="#plans" className="hover:text-white transition">الباقات</a>
            <a href="#faq" className="hover:text-white transition">الأسئلة</a>
            <a href="/privacy" className="hover:text-white transition">سياسة الخصوصية</a>
            <a href="/terms" className="hover:text-white transition">الشروط والأحكام</a>
            <a href="/support" className="hover:text-white transition">الدعم</a>
            <a href={`mailto:${SUPPORT_EMAIL}`} className="hover:text-white transition">تواصل معنا</a>
          </div>
        </div>
        <div className="border-t border-gray-800 mt-8 pt-8 text-center text-sm">
          &copy; <span dir="ltr">{new Date().getFullYear()}</span> بصوتك — جميع الحقوق محفوظة
        </div>
      </div>
    </footer>
  );
}
