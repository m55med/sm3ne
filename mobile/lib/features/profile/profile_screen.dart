import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

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
                      (user?.fullName ?? user?.username ?? '?')[0].toUpperCase(),
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
          _MenuItem(icon: Icons.workspace_premium, title: 'الباقة الحالية', subtitle: 'مجانية', onTap: () => context.go('/plans')),
          _MenuItem(icon: Icons.settings, title: 'الإعدادات', onTap: () => context.push('/settings')),
          _MenuItem(icon: Icons.help_outline, title: 'المساعدة', onTap: () {}),
          _MenuItem(icon: Icons.info_outline, title: 'عن التطبيق', onTap: () {}),
          const SizedBox(height: 16),
          _MenuItem(
            icon: Icons.logout,
            title: 'تسجيل الخروج',
            color: Colors.red,
            onTap: () {
              ref.read(authProvider.notifier).logout();
              context.go('/login');
            },
          ),
        ],
      ),
    );
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
