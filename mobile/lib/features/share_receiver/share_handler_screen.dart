import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/core/stt/stt_orchestrator.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/file_validation.dart';
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

class ShareHandlerScreen extends ConsumerStatefulWidget {
  final String filePath;
  final String? sourceApp;
  final VoidCallback? onDone;

  const ShareHandlerScreen({super.key, required this.filePath, this.sourceApp, this.onDone});

  @override
  ConsumerState<ShareHandlerScreen> createState() => _ShareHandlerScreenState();
}

class _ShareHandlerScreenState extends ConsumerState<ShareHandlerScreen> {
  Transcription? _result;
  String? _error;
  bool _processing = true;

  @override
  void initState() {
    super.initState();
    _process();
  }

  @override
  void didUpdateWidget(covariant ShareHandlerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fallback for the case where Flutter reuses this widget instance
    // because the parent didn't supply a Key on filePath (main.dart now
    // does, but defending here keeps the screen correct regardless of how
    // it's mounted in the future).
    if (oldWidget.filePath != widget.filePath) {
      setState(() {
        _result = null;
        _error = null;
        _processing = true;
      });
      _process();
    }
  }

  Future<void> _process() async {
    try {
      // Defense-in-depth: even though routes.dart hardens the deep-link path,
      // re-validate that the shared file lives inside the app sandbox and that
      // it's a supported audio format/size before sending it to the server.
      final insideSandbox = await isPathInsideSandbox(widget.filePath);
      if (!insideSandbox) {
        throw const TranscriptionUploadException(
          'لا يمكن قراءة الملف من هذا المسار.',
          code: 'outside_sandbox',
        );
      }
      validateAudioFileForUpload(widget.filePath);

      // Route through the orchestrator (not the repo directly) so the
      // on-device path is attempted first on iOS. The orchestrator falls
      // back to the server automatically if the recognizer can't handle
      // the file (locale unsupported, audio too long, low confidence, …).
      final uiLocale = Localizations.localeOf(context).languageCode;
      final result = await ref.read(sttOrchestratorProvider).transcribeFile(
        widget.filePath,
        source: 'shared',
        sourceApp: widget.sourceApp,
        uiLocale: uiLocale,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _processing = false;
      });
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _result!.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ النص!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _processing
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 24),
                      Text('جاري تحويل الصوت...', style: TextStyle(fontSize: 18)),
                      SizedBox(height: 8),
                      Text('بصوتك', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 16),
                          Text('فشل التحويل', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(onPressed: () => widget.onDone?.call(), child: const Text('إغلاق')),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('النتيجة', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                            IconButton(onPressed: () => widget.onDone?.call(), icon: const Icon(Icons.close)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(label: Text(_result!.languageName)),
                            Chip(label: Text('${_result!.duration.toStringAsFixed(1)}ث')),
                            Chip(label: Text('${_result!.wordCount} كلمة')),
                            if (!_result!.isClientSide && _result!.providerUsed != null)
                              const Chip(
                                avatar: Icon(Icons.cloud, size: 16),
                                label: Text('عبر الخادم'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                _result!.text,
                                style: const TextStyle(fontSize: 18, height: 1.8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _copy,
                                icon: const Icon(Icons.copy),
                                label: const Text('نسخ'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => widget.onDone?.call(),
                                icon: const Icon(Icons.check),
                                label: const Text('تم'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 52),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
