import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isRecording = false;
  bool _isProcessing = false;

  Future<void> _toggleRecording() async {
    // TODO: Recording will be re-added with record package fix
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('التسجيل قيد التطوير - استخدم رفع ملف حالياً')),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      _processFile(result.files.single.path!, source: 'uploaded');
    }
  }

  Future<void> _processFile(String path, {String source = 'uploaded'}) async {
    setState(() => _isProcessing = true);
    try {
      final transcription = await ref.read(transcriptionRepoProvider).transcribeFile(path, source: source);
      if (mounted) {
        _showResult(transcription);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التحويل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showResult(Transcription t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Chip(label: Text(t.languageName)),
                  const SizedBox(width: 8),
                  Chip(label: Text('${t.duration.toStringAsFixed(1)}ث')),
                  const SizedBox(width: 8),
                  Chip(label: Text('${t.wordCount} كلمة')),
                ],
              ),
              if (t.wasTrimmed)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text('تم قص الصوت إلى 30 ثانية (باقة مجانية)', style: TextStyle(color: Colors.orange))),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              SelectableText(
                t.text,
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(height: 1.8, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Copy to clipboard
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Share
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بصوتك'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 24),
                  Text('جاري تحويل الصوت إلى نص...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _toggleRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _isRecording ? 140 : 120,
                      height: _isRecording ? 140 : 120,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : Theme.of(context).colorScheme.primary).withValues(alpha: 0.3),
                            blurRadius: _isRecording ? 30 : 20,
                            spreadRadius: _isRecording ? 10 : 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isRecording ? 'اضغط للإيقاف' : 'اضغط للتسجيل',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 48),
                  OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('رفع ملف صوتي'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
