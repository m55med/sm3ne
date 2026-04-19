export function Hero() {
  return (
    <section className="relative overflow-hidden bg-gradient-to-b from-blue-50 to-white py-20 sm:py-32">
      <div className="max-w-6xl mx-auto px-6 text-center">
        <div className="inline-flex items-center gap-2 bg-blue-100 text-blue-700 rounded-full px-4 py-1.5 text-sm font-medium mb-8">
          <span className="w-2 h-2 bg-blue-500 rounded-full animate-pulse" />
          مدعوم بالذكاء الاصطناعي
        </div>
        <h1 className="text-4xl sm:text-6xl font-bold text-gray-900 leading-tight mb-6">
          حوّل الصوت إلى نص
          <br />
          <span className="text-blue-600">بلمسة واحدة</span>
        </h1>
        <p className="text-lg sm:text-xl text-gray-600 max-w-2xl mx-auto mb-10 leading-relaxed">
          شارك أي رسالة صوتية من واتساب أو تيليجرام أو أي تطبيق، وبصوتك يحوّلها لنص مكتوب بدقة عالية مع دعم أكثر من 30 لغة
        </p>
        <div className="flex flex-col sm:flex-row gap-4 justify-center mb-16">
          <a href="#" className="inline-flex items-center gap-3 bg-black text-white px-6 py-3.5 rounded-xl hover:bg-gray-800 transition">
            <svg className="w-7 h-7" viewBox="0 0 24 24" fill="currentColor"><path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 21.99 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.1 21.99C7.79 22.03 6.8 20.68 5.96 19.47C4.25 16.97 2.94 12.45 4.7 9.39C5.57 7.87 7.13 6.91 8.82 6.88C10.1 6.86 11.32 7.75 12.11 7.75C12.89 7.75 14.37 6.68 15.92 6.84C16.57 6.87 18.39 7.1 19.56 8.82C19.47 8.88 17.39 10.1 17.41 12.63C17.44 15.65 20.06 16.66 20.09 16.67C20.06 16.74 19.67 18.11 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.6 4.35 14.9 5.19C14.21 6.04 13.07 6.7 11.95 6.61C11.8 5.46 12.36 4.26 13 3.5Z"/></svg>
            <div className="text-start">
              <div className="text-[10px] opacity-80">حمّل من</div>
              <div className="text-base font-semibold leading-tight">App Store</div>
            </div>
          </a>
          <a href="#" className="inline-flex items-center gap-3 bg-black text-white px-6 py-3.5 rounded-xl hover:bg-gray-800 transition">
            <svg className="w-7 h-7" viewBox="0 0 24 24" fill="currentColor"><path d="M3,20.5V3.5C3,2.91 3.34,2.39 3.84,2.15L13.69,12L3.84,21.85C3.34,21.6 3,21.09 3,20.5M16.81,15.12L6.05,21.34L14.54,12.85L16.81,15.12M20.16,10.81C20.5,11.08 20.75,11.5 20.75,12C20.75,12.5 20.53,12.9 20.18,13.18L17.89,14.5L15.39,12L17.89,9.5L20.16,10.81M6.05,2.66L16.81,8.88L14.54,11.15L6.05,2.66Z"/></svg>
            <div className="text-start">
              <div className="text-[10px] opacity-80">حمّل من</div>
              <div className="text-base font-semibold leading-tight">Google Play</div>
            </div>
          </a>
        </div>
        <div className="relative mx-auto max-w-sm">
          <div className="bg-gradient-to-b from-blue-100 to-blue-50 rounded-3xl p-8 shadow-2xl shadow-blue-200/50">
            <div className="bg-white rounded-2xl p-6 shadow-sm space-y-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center text-blue-600 text-lg">🎙️</div>
                <div className="text-right">
                  <div className="font-bold text-gray-900">بصوتك</div>
                  <div className="text-xs text-gray-400">حوّل الصوت إلى نص</div>
                </div>
              </div>
              <div className="bg-gray-50 rounded-xl p-4 text-sm text-gray-700 leading-relaxed">
                &ldquo;مرحباً، أريد تأكيد الحجز ليوم الخميس الساعة العاشرة صباحاً...&rdquo;
              </div>
              <div className="flex gap-2 text-xs">
                <span className="bg-blue-50 text-blue-600 px-2 py-1 rounded-full">عربي</span>
                <span className="bg-gray-100 text-gray-600 px-2 py-1 rounded-full">8.5 ثانية</span>
                <span className="bg-gray-100 text-gray-600 px-2 py-1 rounded-full">12 كلمة</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
