import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = <_FaqItem>[
    _FaqItem(
      q: 'إزاي أحوّل ملف صوتي لنص؟',
      a: 'من الشاشة الرئيسية، اضغط على "رفع ملف صوتي" واختر الملف من جهازك. التطبيق هيعالجه ويرجّعلك النص فوراً.',
    ),
    _FaqItem(
      q: 'إيه الصيغ الصوتية المدعومة؟',
      a: 'بندعم MP3, M4A, WAV, OGG, FLAC, AAC, WMA و ملفات MP4 (بصوت فقط).',
    ),
    _FaqItem(
      q: 'ليه بيتقصّ الصوت الطويل؟',
      a: 'الباقة المجانية مسموح فيها بصوت لحد 30 ثانية. لو عايز ترفع ملفات أطول، ترقّى لباقة مدفوعة من تاب "الباقات".',
    ),
    _FaqItem(
      q: 'إزاي أغيّر الباقة بتاعتي؟',
      a: 'من تاب "الباقات" بتشوف الباقات المتاحة. اختر الباقة اللي تناسبك واضغط اشترك. لو عندك كوبون، تقدر تدخله وقت الاشتراك.',
    ),
    _FaqItem(
      q: 'هل تقدر النصوص تتحفظ عندي؟',
      a: 'آه، كل تحويل بيتحفظ محلياً في تاب "تسجيلاتي" وتقدر تشاركه أو تنسخه.',
    ),
    _FaqItem(
      q: 'إزيك تتواصل مع الدعم؟',
      a: 'روح لحسابي ← "اتصل بنا / اقتراحات" وابعت رسالتك. هنرد عليك في أقرب وقت.',
    ),
    _FaqItem(
      q: 'هل بيانات الصوت آمنة؟',
      a: 'الصوت بيتعالج على سيرفرنا بأمان وبيتحذف بعد المعالجة. النص بس هو اللي بيتحفظ.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المساعدة'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'هتلاقي هنا إجابات للأسئلة الشائعة. لو مالقيتش اللي بتدور عليه، تقدر تبعتلنا رسالة.',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._faqs.map((f) => _FaqCard(item: f)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/contact'),
            icon: const Icon(Icons.support_agent),
            label: const Text('اتصل بالدعم'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ),
    );
  }
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});
}

class _FaqCard extends StatelessWidget {
  final _FaqItem item;
  const _FaqCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(item.q, style: const TextStyle(fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(item.a, style: TextStyle(color: Colors.grey.shade700, height: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}
