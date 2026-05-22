import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key});

  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  final _selected = <String>{};
  final _otherCtrl = TextEditingController();
  bool _saving = false;

  final _options = const [
    {'key': 'hearing_impaired', 'label': 'أعاني من ضعف السمع', 'icon': Icons.hearing_disabled},
    {'key': 'voice_messages', 'label': 'أريد قراءة الرسائل الصوتية', 'icon': Icons.message},
    {'key': 'lectures', 'label': 'أريد نسخ المحاضرات', 'icon': Icons.school},
    {'key': 'meetings', 'label': 'أريد نسخ الاجتماعات', 'icon': Icons.groups},
    {'key': 'accessibility', 'label': 'لأغراض إمكانية الوصول', 'icon': Icons.accessibility_new},
    {'key': 'other', 'label': 'أخرى', 'icon': Icons.more_horiz},
  ];

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || _selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.post('/profile/survey', data: {
        'reasons': _selected.toList(),
        if (_selected.contains('other')) 'other_text': _otherCtrl.text.trim(),
      });
      // Pull fresh user (survey_response now set).
      await ref.read(authProvider.notifier).checkAuth();
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(
            label: 'إعادة',
            textColor: Colors.white,
            onPressed: _submit,
          ),
        ),
      );
    }
  }

  /// Sends an empty survey so the user.survey_response field gets populated
  /// (with `{"reasons":[]}`) — that's how login_screen knows this user has
  /// already been shown the survey and shouldn't be re-prompted on next
  /// sign-in. We tolerate network failures here: worst case the user sees
  /// the survey one more time on their next login.
  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.post('/profile/survey', data: {
        'reasons': <String>[],
      });
      await ref.read(authProvider.notifier).checkAuth();
    } catch (_) {
      // Best-effort — silently move on so the user can keep using the app.
    }
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
                child: TextButton(
                  onPressed: _saving ? null : _skip,
                  child: const Text('تخطي'),
                ),
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
                          onTap: _saving
                              ? null
                              : () => setState(() {
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
                          enabled: !_saving,
                        ),
                      ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: (_selected.isEmpty || _saving) ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('متابعة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
