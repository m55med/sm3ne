export function Footer() {
  return (
    <footer className="bg-gray-900 text-gray-400 py-12">
      <div className="max-w-6xl mx-auto px-6">
        <div className="flex flex-col md:flex-row justify-between items-center gap-6">
          <div>
            <span className="text-2xl font-bold text-white">بصوتك</span>
            <p className="text-sm mt-1">حوّل الصوت إلى نص بالذكاء الاصطناعي</p>
          </div>
          <div className="flex gap-6 text-sm">
            <a href="#features" className="hover:text-white transition">المميزات</a>
            <a href="#plans" className="hover:text-white transition">الباقات</a>
            <a href="#faq" className="hover:text-white transition">الأسئلة</a>
            <a href="mailto:m55med@icloud.com" className="hover:text-white transition">تواصل معنا</a>
          </div>
        </div>
        <div className="border-t border-gray-800 mt-8 pt-8 text-center text-sm">
          &copy; {new Date().getFullYear()} بصوتك — جميع الحقوق محفوظة
        </div>
      </div>
    </footer>
  );
}
