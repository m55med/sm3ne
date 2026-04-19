const plans = [
  {
    name: "مجانية",
    price: "0",
    period: "",
    features: ["30 ثانية حد أقصى للصوت", "جميع اللغات المدعومة", "تحويل غير محدود", "يحتوي على إعلانات"],
    cta: "ابدأ مجاناً",
    popular: false,
  },
  {
    name: "شهرية",
    price: "27",
    period: "/شهرياً",
    features: ["بلا حدود في مدة الصوت", "جميع اللغات المدعومة", "تحويل غير محدود", "بدون إعلانات", "أولوية في المعالجة"],
    cta: "اشترك الآن",
    popular: true,
  },
  {
    name: "سنوية",
    price: "150",
    originalPrice: "325",
    period: "/سنوياً",
    discount: "54%",
    features: ["كل مميزات الشهرية", "خصم 54% على السعر", "بلا حدود في مدة الصوت", "بدون إعلانات", "أولوية في المعالجة"],
    cta: "وفّر الآن",
    popular: false,
  },
];

export function PlansSection() {
  return (
    <section id="plans" className="py-20 bg-white">
      <div className="max-w-6xl mx-auto px-6">
        <div className="text-center mb-16">
          <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">الباقات والأسعار</h2>
          <p className="text-gray-600 text-lg">اختر الباقة المناسبة لك</p>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-4xl mx-auto">
          {plans.map((plan, i) => (
            <div key={i} className={`relative rounded-2xl p-8 ${plan.popular ? "bg-blue-600 text-white shadow-xl shadow-blue-200 scale-105" : "bg-gray-50 text-gray-900"}`}>
              {plan.discount && (
                <div className="absolute -top-3 right-4 bg-red-500 text-white text-xs font-bold px-3 py-1 rounded-full">
                  خصم {plan.discount}
                </div>
              )}
              {plan.popular && (
                <div className="absolute -top-3 left-4 bg-yellow-400 text-gray-900 text-xs font-bold px-3 py-1 rounded-full">
                  الأكثر شعبية
                </div>
              )}
              <h3 className="text-xl font-bold mb-4">{plan.name}</h3>
              <div className="flex items-end gap-1 mb-6">
                {plan.originalPrice && (
                  <span className={`text-lg line-through ${plan.popular ? "text-blue-200" : "text-gray-400"}`}>{plan.originalPrice}</span>
                )}
                <span className="text-4xl font-bold">{plan.price}</span>
                <span className={`text-sm ${plan.popular ? "text-blue-200" : "text-gray-500"}`}>{plan.period}</span>
              </div>
              <ul className="space-y-3 mb-8">
                {plan.features.map((f, j) => (
                  <li key={j} className="flex items-center gap-2 text-sm">
                    <span>{plan.popular ? "✓" : "✓"}</span>
                    {f}
                  </li>
                ))}
              </ul>
              <button className={`w-full py-3 rounded-xl font-semibold transition ${plan.popular ? "bg-white text-blue-600 hover:bg-blue-50" : "bg-blue-600 text-white hover:bg-blue-700"}`}>
                {plan.cta}
              </button>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
