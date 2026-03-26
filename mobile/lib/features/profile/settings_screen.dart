import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bisawtak/main.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          // Theme
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('المظهر'),
            subtitle: Text(_themeLabel(themeMode)),
            onTap: () => _showThemeDialog(context, ref, themeMode),
          ),
          const Divider(height: 1),
          // Language
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('اللغة'),
            subtitle: Text(locale?.languageCode == 'en' ? 'English' : locale?.languageCode == 'ar' ? 'العربية' : 'تلقائي (النظام)'),
            onTap: () => _showLanguageDialog(context, ref, locale),
          ),
          const Divider(height: 1),
          // App info
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('الإصدار'),
            subtitle: Text('1.0.0'),
          ),
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
