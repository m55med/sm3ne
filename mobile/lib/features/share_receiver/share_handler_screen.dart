import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:flutter/services.dart';

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

  Future<void> _process() async {
    try {
      final result = await ref.read(transcriptionRepoProvider).transcribeFile(
        widget.filePath,
        source: 'shared',
        sourceApp: widget.sourceApp,
      );
      setState(() {
        _result = result;
        _processing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _processing = false;
      });
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
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text('فشل التحويل', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(_error!, style: const TextStyle(color: Colors.grey)),
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
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _result!.text));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ النص!')));
                                },
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
