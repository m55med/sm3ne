import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/core/stt/on_device_stt.dart';
import 'package:bisawtak/core/stt/on_device_stt_pref.dart';
import 'package:bisawtak/data/repositories/profile_repository.dart';
import 'package:bisawtak/main.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/widgets/confirm_dialog.dart';

final _appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } catch (_) {
    return '—';
  }
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final versionAsync = ref.watch(_appVersionProvider);
    final scheme = Theme.of(context).colorScheme;
    final chevron = Icon(forwardChevron(context));

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          // Theme
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('المظهر'),
            subtitle: Text(_themeLabel(themeMode)),
            trailing: chevron,
            onTap: () => _showThemeDialog(context, ref, themeMode),
          ),
          const Divider(height: 1),
          // Language
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('اللغة'),
            subtitle: Text(_languageLabel(locale)),
            trailing: chevron,
            onTap: () => _showLanguageDialog(context, ref, locale),
          ),
          const Divider(height: 1),
          // On-device speech recognition — defaults to ON. Turning it off
          // routes every recording through the backend (uses daily quota).
          const _OnDeviceSttTile(),
          const Divider(height: 1),
          // Change password
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('تغيير كلمة السر'),
            trailing: chevron,
            onTap: () => context.push('/forgot-password'),
          ),
          const Divider(height: 1),
          // Telegram link
          ListTile(
            leading: const Icon(Icons.telegram, color: Color(0xFF229ED9)),
            title: const Text('ربط مع تيليجرام'),
            subtitle: const Text('استقبل تفريغ الفويس على تيليجرام'),
            trailing: chevron,
            onTap: () => context.push('/telegram'),
          ),
          const Divider(height: 1),
          // About
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن التطبيق'),
            trailing: chevron,
            onTap: () => context.push('/about'),
          ),
          const Divider(height: 1),
          // App version
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('الإصدار'),
            subtitle: versionAsync.when(
              data: (v) => Text(v),
              loading: () => const Text('...'),
              error: (_, __) => const Text('—'),
            ),
          ),
          const Divider(height: 1),
          // Logout — the everyday "sign me out" action.
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('تسجيل الخروج', style: TextStyle(color: scheme.error)),
            onTap: () => _confirmLogout(context, ref),
          ),

          // Visually separated "Danger zone". Delete-account used to sit
          // right under Logout — UX-wise that read as "next natural step",
          // which led users to delete their account by mistake. We now
          // segregate it: extra spacing, a bold header, an "advanced" gate.
          const SizedBox(height: AppSpacing.xxl),
          _DangerZone(onDelete: () => _confirmDeleteAccount(context, ref)),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark: return 'مظلم';
      case ThemeMode.light: return 'فاتح';
      default: return 'تلقائي (النظام)';
    }
  }

  String _languageLabel(Locale? locale) {
    if (locale == null) return 'تلقائي (النظام)';
    return locale.languageCode == 'en' ? 'English' : 'العربية';
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref, ThemeMode current) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('المظهر'),
        children: [
          _ThemeOption('تلقائي (النظام)', ThemeMode.system, current, ref),
          _ThemeOption('فاتح', ThemeMode.light, current, ref),
          _ThemeOption('مظلم', ThemeMode.dark, current, ref),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref, Locale? current) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('اللغة'),
        children: [
          _LangOption('تلقائي (النظام)', null, current, ref),
          _LangOption('العربية', const Locale('ar'), current, ref),
          _LangOption('English', const Locale('en'), current, ref),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'تسجيل الخروج',
      message: 'هل تريد تسجيل الخروج من حسابك؟',
      confirmLabel: 'تسجيل الخروج',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'حذف الحساب نهائياً',
      message: 'سيتم حذف حسابك وجميع بياناتك بشكل دائم ولا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف الحساب',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    try {
      // Soft-deletes the account server-side, then wipes local state WITHOUT
      // calling /auth/logout. Hitting /auth/logout for a just-deleted account
      // would 401 → trip the global auth-invalidation listener → mis-show
      // "session expired" on the login screen the user lands on next.
      await ref.read(profileRepositoryProvider).deleteAccount(confirmation: true);
      await ref.read(authProvider.notifier).logoutLocalOnly();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('expired_session_pending');
      } catch (_) {/* best effort */}
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

class _ThemeOption extends ConsumerWidget {
  final String label;
  final ThemeMode mode;
  final ThemeMode current;
  final WidgetRef parentRef;

  const _ThemeOption(this.label, this.mode, this.current, this.parentRef);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RadioListTile<ThemeMode>(
      title: Text(label),
      value: mode,
      groupValue: current,
      onChanged: (val) async {
        parentRef.read(themeModeProvider.notifier).state = val!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('theme_mode', val == ThemeMode.dark ? 'dark' : val == ThemeMode.light ? 'light' : 'system');
        if (context.mounted) Navigator.pop(context);
      },
    );
  }
}

/// Collapsed "danger zone" with the irreversible account-deletion action.
/// Hidden behind an explicit toggle so it can't be tapped by reflex —
/// previously the delete tile lived right under Logout and users hit it
/// thinking it was a logout follow-up.
class _DangerZone extends StatefulWidget {
  final VoidCallback onDelete;
  const _DangerZone({required this.onDelete});

  @override
  State<_DangerZone> createState() => _DangerZoneState();
}

class _DangerZoneState extends State<_DangerZone> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: scheme.error),
            title: Text(
              'منطقة خطرة',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              _expanded
                  ? 'إجراءات لا يمكن التراجع عنها.'
                  : 'اضغط لإظهار خيارات حذف الحساب.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_forever, color: scheme.error),
              title: Text(
                'حذف الحساب نهائياً',
                style: TextStyle(color: scheme.error),
              ),
              subtitle: const Text(
                'سيتم حذف حسابك وجميع بياناتك بشكل دائم.',
                style: TextStyle(fontSize: 12),
              ),
              onTap: widget.onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _LangOption extends ConsumerWidget {
  final String label;
  final Locale? locale;
  final Locale? current;
  final WidgetRef parentRef;

  const _LangOption(this.label, this.locale, this.current, this.parentRef);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RadioListTile<Locale?>(
      title: Text(label),
      value: locale,
      groupValue: current,
      onChanged: (val) async {
        parentRef.read(localeProvider.notifier).state = val;
        final prefs = await SharedPreferences.getInstance();
        if (val != null) {
          await prefs.setString('locale', val.languageCode);
        } else {
          await prefs.remove('locale');
        }
        if (context.mounted) Navigator.pop(context);
      },
    );
  }
}

/// Settings tile for the on-device STT toggle. Carries its own state because
/// we need to (a) probe Apple's Speech framework for current capability and
/// (b) request authorization when the user enables the switch — both async.
class _OnDeviceSttTile extends ConsumerStatefulWidget {
  const _OnDeviceSttTile();

  @override
  ConsumerState<_OnDeviceSttTile> createState() => _OnDeviceSttTileState();
}

class _OnDeviceSttTileState extends ConsumerState<_OnDeviceSttTile> {
  Map<String, dynamic>? _probe;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refreshProbe();
  }

  Future<void> _refreshProbe() async {
    if (!Platform.isIOS) return;
    final p = await SpeechToTextOnDeviceStt.probeAvailability();
    if (!mounted) return;
    setState(() => _probe = p);
  }

  Future<void> _onToggle(bool value) async {
    // Persist the preference first so the orchestrator picks it up even if
    // the permission request lags behind.
    await ref.read(onDeviceSttPrefProvider.notifier).setEnabled(value);

    if (!value || !Platform.isIOS) return;

    // Re-probe before deciding what to do — the user may have changed
    // permission state under the Settings app since last probe.
    setState(() => _requesting = true);
    final pre = await SpeechToTextOnDeviceStt.probeAvailability();
    final auth = pre['auth_status'] as String? ?? 'unknown';

    // Trigger Apple's authorization dialog for `notDetermined`. We also
    // request on `unknown` as a defensive fallback: if the probe channel
    // somehow doesn't respond, requestPermission still calls native
    // `SFSpeechRecognizer.requestAuthorization` which is the source of truth
    // and surfaces the system dialog if the user hasn't decided yet.
    if (auth == 'notDetermined' || auth == 'unknown') {
      await SpeechToTextOnDeviceStt.requestPermission();
    } else if (auth == 'denied' || auth == 'restricted') {
      // We can't re-prompt — Apple only shows the dialog once. Send the user
      // to the system Settings page where they can re-enable it.
      if (mounted) await _openSpeechSettings();
    }

    await _refreshProbe();
    if (mounted) setState(() => _requesting = false);
  }

  Future<void> _openSpeechSettings() async {
    final ok = await openAppSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الإعدادات تلقائياً، افتحها يدوياً.')),
      );
    }
  }

  String _arabicAuthLabel(String auth) {
    switch (auth) {
      case 'authorized':
        return 'الصلاحية مفعّلة';
      case 'denied':
        return 'الصلاحية مرفوضة — افتح الإعدادات';
      case 'restricted':
        return 'الصلاحية مقيّدة بسياسات الجهاز';
      case 'notDetermined':
        return 'اضغط على المفتاح أعلاه لطلب الصلاحية';
      case 'not_applicable':
        return 'غير متاح على هذه المنصّة';
      case 'unknown':
        return 'تعذّر التواصل مع نظام التعرف — أعد فتح التطبيق';
      default:
        return 'حالة الصلاحية غير معروفة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final onDeviceStt = ref.watch(onDeviceSttPrefProvider);
    final scheme = Theme.of(context).colorScheme;

    // The status row is only meaningful on iOS — Android falls back to the
    // server pipeline regardless of this toggle, so we don't surface a
    // "permission" line that would only confuse users.
    Widget? status;
    if (Platform.isIOS && onDeviceStt) {
      final probe = _probe;
      if (probe == null) {
        status = const Padding(
          padding: EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Row(
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('جاري التحقق من الإعدادات...', style: TextStyle(fontSize: 12)),
            ],
          ),
        );
      } else {
        final auth = probe['auth_status'] as String? ?? 'unknown';
        final supportsOnDevice = probe['supports_on_device'] == true;
        final issues = <String>[];
        if (auth != 'authorized') issues.add(_arabicAuthLabel(auth));
        if (auth == 'authorized' && !supportsOnDevice) {
          issues.add('اللغة العربية غير مثبتة للتعرف داخل الجهاز — '
              'افتح الإعدادات > عام > لوحة المفاتيح > إملاء، وثبّت العربية.');
        }
        final allOk = auth == 'authorized' && supportsOnDevice;
        status = Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                allOk ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: allOk ? Colors.green : scheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allOk ? 'جاهز — التعرف داخل الجهاز مفعّل' : issues.join('\n'),
                      style: TextStyle(
                        fontSize: 12,
                        color: allOk ? Colors.green : scheme.error,
                      ),
                    ),
                    if (!allOk && (auth == 'denied' || auth == 'restricted')) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _openSpeechSettings,
                        child: Text(
                          'افتح الإعدادات',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }
    }

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.phonelink_ring),
          title: const Text('التعرّف على الصوت داخل الجهاز'),
          subtitle: const Text(
            'أسرع وأكثر خصوصية ولا يُخصم من باقتك. عند تعذّره يتم استخدام الخادم تلقائياً.',
          ),
          value: onDeviceStt,
          onChanged: _requesting ? null : _onToggle,
        ),
        if (status != null) status,
      ],
    );
  }
}
