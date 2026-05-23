const features = [
  {
    icon: "🎯",
    title: "دقة عالية",
    description: "مدعوم بنموذج Whisper Large من OpenAI لأعلى دقة في تحويل الصوت إلى نص",
  },
  {
    icon: "🌍",
    title: "أكثر من 30 لغة",
    description: "يدعم العربية والإنجليزية والفرنسية والتركية وعشرات اللغات الأخرى تلقائياً",
  },
  {
    icon: "📤",
    title: "شارك من أي تطبيق",
    description: "شارك الرسائل الصوتية مباشرة من واتساب أو تيليجرام أو أي تطبيق آخر",
  },
  {
    icon: "🔒",
    title: "خصوصيتك أولاً",
    description: "لا نخزن أي ملفات صوتية على سيرفراتنا — المعالجة فقط ثم الحذف فوراً",
  },
];

export function Features() {
  return (
    <section id="features" className="py-20 bg-white dark:bg-background">
      <div className="max-w-6xl mx-auto px-6">
        <div className="text-center mb-16">
          <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 dark:text-foreground mb-4">لماذا بصوتك؟</h2>
          <p className="text-gray-600 dark:text-muted-foreground text-lg max-w-xl mx-auto">أدوات ذكية تجعل تحويل الصوت لنص أسهل وأسرع</p>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {features.map((f, i) => (
            <div key={i} className="bg-gray-50 dark:bg-card border border-transparent dark:border-border rounded-2xl p-6 hover:shadow-lg dark:hover:border-blue-500/30 dark:hover:shadow-blue-500/10 hover:-translate-y-1 transition-all duration-300">
              <div className="text-4xl mb-4">{f.icon}</div>
              <h3 className="text-lg font-bold text-gray-900 dark:text-foreground mb-2">{f.title}</h3>
              <p className="text-gray-600 dark:text-muted-foreground text-sm leading-relaxed">{f.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
