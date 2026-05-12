import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/shared/widgets/confirm_dialog.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    // Safe initial — never crash on an empty username/full name.
    final initial =
        (user?.fullName ?? user?.username ?? '?').characters.firstOrNull?.toUpperCase() ?? '?';

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      initial,
                      style: TextStyle(fontSize: 32, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.fullName ?? user?.username ?? '',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (user?.email != null)
                    Text(user!.email!, style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _MenuItem(icon: Icons.edit_outlined, title: 'تعديل البروفايل', onTap: () => context.push('/profile/edit')),
          _MenuItem(
            icon: Icons.workspace_premium,
            title: 'الباقة الحالية',
            subtitle: _planLabel(_readCurrentPlan(user)),
            onTap: () => context.go('/plans'),
          ),
          _MenuItem(icon: Icons.settings, title: 'الإعدادات', onTap: () => context.push('/settings')),
          _MenuItem(icon: Icons.support_agent, title: 'اتصل بنا / اقتراحات', onTap: () => context.push('/contact')),
          _MenuItem(icon: Icons.help_outline, title: 'المساعدة', onTap: () => context.push('/help')),
          _MenuItem(icon: Icons.info_outline, title: 'عن التطبيق', onTap: () => context.push('/about')),
          const SizedBox(height: 16),
          _MenuItem(
            icon: Icons.logout,
            title: 'تسجيل الخروج',
            color: Colors.red,
            onTap: () async {
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
            },
          ),
          _MenuItem(
            icon: Icons.delete_forever,
            title: 'حذف الحساب نهائياً',
            color: Colors.red,
            onTap: () => context.push('/account/delete'),
          ),
        ],
      ),
    );
  }

  /// Best-effort access to the new `currentPlanName` field on User. Mobile-2
  /// will add it to the model; until then we fall back to dynamic dispatch
  /// so this code keeps compiling whether the field exists or not.
  String? _readCurrentPlan(dynamic user) {
    if (user == null) return null;
    try {
      final dyn = user as dynamic;
      final value = dyn.currentPlanName;
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {
      // Field not present yet — Mobile-2 will add it.
    }
    return null;
  }

  String _planLabel(String? name) {
    switch (name) {
      case 'free':
        return 'مجانية';
      case 'monthly':
        return 'شهرية';
      case 'annual':
        return 'سنوية';
      case null:
        return '—';
      default:
        return name;
    }
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  const _MenuItem({required this.icon, required this.title, this.subtitle, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color)),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
