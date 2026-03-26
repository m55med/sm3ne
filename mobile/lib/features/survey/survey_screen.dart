import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/api/api_client.dart';

class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key});

  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  final _selected = <String>{};
  final _otherCtrl = TextEditingController();

  final _options = const [
    {'key': 'hearing_impaired', 'label': 'أعاني من ضعف السمع', 'icon': Icons.hearing_disabled},
    {'key': 'voice_messages', 'label': 'أريد قراءة الرسائل الصوتية', 'icon': Icons.message},
    {'key': 'lectures', 'label': 'أريد نسخ المحاضرات', 'icon': Icons.school},
    {'key': 'meetings', 'label': 'أريد نسخ الاجتماعات', 'icon': Icons.groups},
    {'key': 'accessibility', 'label': 'لأغراض إمكانية الوصول', 'icon': Icons.accessibility_new},
    {'key': 'other', 'label': 'أخرى', 'icon': Icons.more_horiz},
  ];

  Future<void> _submit() async {
    try {
      await ref.read(apiClientProvider).dio.post('/profile/survey', data: {
        'reasons': _selected.toList(),
        if (_selected.contains('other')) 'other_text': _otherCtrl.text,
      });
    } catch (_) {}
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: TextButton(onPressed: () => context.go('/home'), child: const Text('تخطي')),
              ),
              const SizedBox(height: 16),
              Text(
                'لماذا تريد استخدام بصوتك؟',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'اختر كل ما ينطبق عليك',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    ..._options.map((opt) {
                      final key = opt['key'] as String;
                      final selected = _selected.contains(key);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                        child: ListTile(
                          leading: Icon(opt['icon'] as IconData,
                            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
                          ),
                          title: Text(opt['label'] as String),
                          trailing: selected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
                          onTap: () => setState(() {
                            selected ? _selected.remove(key) : _selected.add(key);
                          }),
                        ),
                      );
                    }),
                    if (_selected.contains('other'))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: _otherCtrl,
                          decoration: const InputDecoration(labelText: 'حدد السبب...'),
                          maxLines: 2,
                        ),
                      ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _selected.isNotEmpty ? _submit : null,
                child: const Text('متابعة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
