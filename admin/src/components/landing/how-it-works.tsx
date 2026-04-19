const steps = [
  { number: "١", title: "شارك الصوت", description: "اضغط مشاركة على أي رسالة صوتية واختر بصوتك", icon: "📱" },
  { number: "٢", title: "بصوتك يحوّله", description: "الذكاء الاصطناعي يحلل الصوت ويحوّله لنص مكتوب", icon: "⚡" },
  { number: "٣", title: "انسخ وشارك", description: "النص جاهز! انسخه أو شاركه أو احفظه للرجوع لاحقاً", icon: "✨" },
];

export function HowItWorks() {
  return (
    <section className="py-20 bg-gray-50">
      <div className="max-w-6xl mx-auto px-6">
        <div className="text-center mb-16">
          <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">كيف يعمل؟</h2>
          <p className="text-gray-600 text-lg">ثلاث خطوات بسيطة</p>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {steps.map((s, i) => (
            <div key={i} className="text-center">
              <div className="w-20 h-20 bg-blue-100 rounded-2xl flex items-center justify-center text-4xl mx-auto mb-6">
                {s.icon}
              </div>
              <div className="inline-flex items-center justify-center w-8 h-8 bg-blue-600 text-white rounded-full text-sm font-bold mb-4">
                {s.number}
              </div>
              <h3 className="text-xl font-bold text-gray-900 mb-2">{s.title}</h3>
              <p className="text-gray-600 leading-relaxed">{s.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
