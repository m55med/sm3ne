import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
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
          // Logout
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('تسجيل الخروج', style: TextStyle(color: scheme.error)),
            onTap: () => _confirmLogout(context, ref),
          ),
          const Divider(height: 1),
          // Delete account (destructive)
          ListTile(
            leading: Icon(Icons.delete_forever, color: scheme.error),
            title: Text('حذف الحساب نهائياً', style: TextStyle(color: scheme.error)),
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
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
      // Soft-deletes the account server-side and clears local state via logout().
      await ref.read(profileRepositoryProvider).deleteAccount(confirmation: true);
      await ref.read(authProvider.notifier).logout();
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
