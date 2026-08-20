import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/core/auth/token_storage.dart';
import 'package:bisawtak/main.dart' show pendingShareRouteProvider;

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // No artificial delay — let the auth check drive when we navigate.
    final tokenStorage = ref.read(tokenStorageProvider);
    final isFirst = await tokenStorage.isFirstLaunch();
    if (!mounted) return;

    if (isFirst) {
      context.go('/onboarding');
      return;
    }

    ref.read(authProvider.notifier).checkAuth();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (_, state) {
      if (state.status == AuthStatus.authenticated) {
        // The Android floating share sheet can launch the app asking for a
        // specific screen ("فتح في بصوتك"). Consume it HERE: this listener runs
        // after main.dart's builder and would otherwise overwrite that
        // navigation with /home on the very next frame.
        final pending = ref.read(pendingShareRouteProvider);
        if (pending != null) {
          ref.read(pendingShareRouteProvider.notifier).state = null;
          context.go(pending);
        } else {
          context.go('/home');
        }
      } else if (state.status == AuthStatus.unauthenticated) {
        // Drop any staged route — it points at a signed-in screen the user
        // can't reach, and leaving it set would strand it until the next share.
        ref.read(pendingShareRouteProvider.notifier).state = null;
        context.go('/login');
      }
    });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic, size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'بصوتك',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'حوّل الصوت إلى نص',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
