import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bisawtak/config/constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _version = '1.0.0';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('عن التطبيق'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: Text('ب', style: TextStyle(fontSize: 64, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Center(
            child: Text(
              'الإصدار $_version',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: 'عن بصوتك'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'بصوتك تطبيق ذكي لتحويل الصوت إلى نص بدقة عالية وبدعم أكثر من 30 لغة. '
                'سواء كنت بتحتاج تدوّن محاضرة، تحول رسالة صوتية، أو تفرّغ اجتماع — '
                'بصوتك بيوفّر لك الأداة اللي محتاجها بسرعة وخصوصية.',
                style: TextStyle(height: 1.6, color: Colors.grey.shade800),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: 'المميزات'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  _FeatureRow(icon: Icons.mic, text: 'تحويل صوت لنص فوري'),
                  _FeatureRow(icon: Icons.language, text: 'دعم أكثر من 30 لغة'),
                  _FeatureRow(icon: Icons.cloud_off_outlined, text: 'حفظ التسجيلات محلياً'),
                  _FeatureRow(icon: Icons.share_outlined, text: 'مشاركة النص بسهولة'),
                  _FeatureRow(icon: Icons.security, text: 'الصوت يُحذف بعد المعالجة'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: 'روابط'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('الشروط والأحكام'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openUrl('https://voice.neojeen.com/terms'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('سياسة الخصوصية'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openUrl('https://voice.neojeen.com/privacy'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('الموقع الرسمي'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openUrl('https://voice.neojeen.com'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© ${DateTime.now().year} ${AppConstants.appName}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
