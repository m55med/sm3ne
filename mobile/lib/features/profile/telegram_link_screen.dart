import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bisawtak/data/repositories/telegram_repository.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/widgets/confirm_dialog.dart';

class TelegramLinkScreen extends ConsumerStatefulWidget {
  const TelegramLinkScreen({super.key});

  @override
  ConsumerState<TelegramLinkScreen> createState() => _TelegramLinkScreenState();
}

class _TelegramLinkScreenState extends ConsumerState<TelegramLinkScreen> {
  TelegramStatus? _status;
  TelegramLinkStart? _activeCode;
  String? _loadError;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final s = await ref.read(telegramRepositoryProvider).status();
      if (!mounted) return;
      setState(() {
        _status = s;
        // Linking just succeeded? Discard any in-flight code on display.
        if (s.linked) _activeCode = null;
      });
    } on TelegramException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.isDisabled
            ? 'الربط مع تيليجرام غير مفعّل على هذا الخادم حالياً.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateCode() async {
    setState(() => _busy = true);
    try {
      final c = await ref.read(telegramRepositoryProvider).startLink();
      if (!mounted) return;
      setState(() => _activeCode = c);
    } on TelegramException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack(friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTelegram(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack('الرابط غير صالح');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showSnack('تعذّر فتح تيليجرام. هل التطبيق مثبت؟');
    } catch (_) {
      _showSnack('تعذّر فتح تيليجرام. هل التطبيق مثبت؟');
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _showSnack('تم نسخ الكود');
  }

  Future<void> _unlink() async {
    final ok = await showConfirmDialog(
      context,
      title: 'فك الربط مع تيليجرام',
      message:
          'هل تريد فعلاً فك الربط؟ لن يتمكن البوت من معرفتك بعد ذلك ولن يفرّغ الرسائل اللي تبعتها له حتى تعيد الربط.',
      confirmLabel: 'فك الربط',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(telegramRepositoryProvider).unlink();
      _showSnack('تم فك الربط');
      await _refresh();
    } on TelegramException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack(friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ربط مع تيليجرام')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                _ErrorBlock(message: _loadError!, onRetry: _refresh)
              else if (_status?.enabled == false)
                _DisabledBlock()
              else if (_status?.linked == true)
                _LinkedBlock(
                  status: _status!,
                  busy: _busy,
                  onUnlink: _unlink,
                  onRefresh: _refresh,
                )
              else
                _UnlinkedBlock(
                  scheme: scheme,
                  busy: _busy,
                  activeCode: _activeCode,
                  botUsername: _status?.botUsername,
                  onGenerate: _generateCode,
                  onCopy: _copyCode,
                  onOpenTelegram: _openTelegram,
                  onCheckAgain: _refresh,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisabledBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const _HeroCard(
      icon: Icons.cancel_outlined,
      iconColor: Colors.grey,
      title: 'الربط مع تيليجرام غير مفعّل',
      body: 'هذه الميزة غير متاحة على الخادم الحالي. تواصل مع الدعم لمزيد من المعلومات.',
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(
          icon: Icons.error_outline,
          iconColor: Colors.red,
          title: 'حدث خطأ',
          body: message,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => onRetry(),
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    );
  }
}

class _LinkedBlock extends StatelessWidget {
  final TelegramStatus status;
  final bool busy;
  final VoidCallback onUnlink;
  final Future<void> Function() onRefresh;
  const _LinkedBlock({
    required this.status,
    required this.busy,
    required this.onUnlink,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(
          icon: Icons.check_circle,
          iconColor: Colors.green,
          title: 'تم ربط حسابك بنجاح',
          body:
              'تقدر دلوقتي تبعت أي رسالة صوتية أو ملف صوتي للبوت @${status.botUsername ?? 'bot'} على تيليجرام، وهيرد عليك بالنص المُفرَّغ. الاستهلاك بيتحسب من باقتك العادية.',
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الحساب المربوط',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'الاسم',
                  value: status.telegramFirstName ?? '—',
                ),
                if (status.telegramUsername != null)
                  _InfoRow(
                    label: 'اسم المستخدم',
                    value: '@${status.telegramUsername}',
                    ltr: true,
                  ),
                if (status.telegramId != null)
                  _InfoRow(
                    label: 'Telegram ID',
                    value: status.telegramId.toString(),
                    ltr: true,
                  ),
                if (status.linkedAt != null)
                  _InfoRow(
                    label: 'تاريخ الربط',
                    value: _formatDate(status.linkedAt!),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: busy ? null : onUnlink,
          icon: const Icon(Icons.link_off),
          label: const Text('فك الربط'),
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}'
        ' ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _UnlinkedBlock extends StatelessWidget {
  final ColorScheme scheme;
  final bool busy;
  final TelegramLinkStart? activeCode;
  final String? botUsername;
  final Future<void> Function() onGenerate;
  final Future<void> Function(String code) onCopy;
  final Future<void> Function(String url) onOpenTelegram;
  final Future<void> Function() onCheckAgain;

  const _UnlinkedBlock({
    required this.scheme,
    required this.busy,
    required this.activeCode,
    required this.botUsername,
    required this.onGenerate,
    required this.onCopy,
    required this.onOpenTelegram,
    required this.onCheckAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HeroCard(
          icon: Icons.telegram,
          iconColor: Color(0xFF229ED9),
          title: 'حوّل أي فويس على تيليجرام لنص',
          body:
              'لما تربط حسابك، أي رسالة صوتية أو ملف صوتي تبعته لبوتنا على تيليجرام هيتحول لنص ويرجعلك على طول. كل التفريغات بتنحفظ في حسابك زي العادي.',
        ),
        const SizedBox(height: 24),
        if (activeCode == null)
          ElevatedButton.icon(
            onPressed: busy ? null : onGenerate,
            icon: busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_link),
            label: const Text('بدء الربط'),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          )
        else
          _ActiveCodeCard(
            scheme: scheme,
            code: activeCode!,
            busy: busy,
            botUsername: botUsername,
            onCopy: () => onCopy(activeCode!.code),
            onOpenTelegram: () {
              final url = activeCode!.deepLink;
              if (url != null && url.isNotEmpty) onOpenTelegram(url);
            },
            onCheckAgain: onCheckAgain,
            onRegenerate: onGenerate,
          ),
        const SizedBox(height: 24),
        Text(
          'كيف تربط حسابك',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        const _StepRow(number: 1, text: 'اضغط "بدء الربط" لتوليد كود مؤقت.'),
        const _StepRow(
          number: 2,
          text: 'اضغط "افتح في تيليجرام" — البوت يستقبل الكود تلقائياً.',
        ),
        const _StepRow(
          number: 3,
          text: 'البوت يرسل رسالة "تم الربط ✅" — وانتهينا.',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تقدر تربط حساب تيليجرام واحد فقط لكل حساب في التطبيق. الكود صالح لمدة 10 دقائق.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveCodeCard extends StatelessWidget {
  final ColorScheme scheme;
  final TelegramLinkStart code;
  final bool busy;
  final String? botUsername;
  final VoidCallback onCopy;
  final VoidCallback onOpenTelegram;
  final Future<void> Function() onCheckAgain;
  final Future<void> Function() onRegenerate;

  const _ActiveCodeCard({
    required this.scheme,
    required this.code,
    required this.busy,
    required this.botUsername,
    required this.onCopy,
    required this.onOpenTelegram,
    required this.onCheckAgain,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final canOpen = (code.deepLink ?? '').isNotEmpty;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الكود الخاص بك',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            // Big monospace code, tappable to copy.
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  code.code,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'صالح لمدة 10 دقائق · اضغط للنسخ',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            if (canOpen)
              ElevatedButton.icon(
                onPressed: busy ? null : onOpenTelegram,
                icon: const Icon(Icons.send),
                label: const Text('افتح في تيليجرام (الأسهل)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFF229ED9),
                  foregroundColor: Colors.white,
                ),
              )
            else if (botUsername != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'افتح @${botUsername!} في تيليجرام والصق الكود ك /start بعدها مسافة ثم الكود.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => onCheckAgain(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('فحص الحالة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: busy ? null : () => onRegenerate(),
                    icon: const Icon(Icons.autorenew, size: 18),
                    label: const Text('كود جديد'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  const _HeroCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.6,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final String text;
  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ltr;
  const _InfoRow({required this.label, required this.value, this.ltr = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            textDirection: ltr ? TextDirection.ltr : null,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
