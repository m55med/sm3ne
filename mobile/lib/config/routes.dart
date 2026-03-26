import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/main.dart';
import 'package:bisawtak/features/splash/splash_screen.dart';
import 'package:bisawtak/features/onboarding/onboarding_screen.dart';
import 'package:bisawtak/features/auth/login_screen.dart';
import 'package:bisawtak/features/auth/register_screen.dart';
import 'package:bisawtak/features/auth/forgot_password_screen.dart';
import 'package:bisawtak/features/survey/survey_screen.dart';
import 'package:bisawtak/features/home/home_screen.dart';
import 'package:bisawtak/features/transcription/transcription_list_screen.dart';
import 'package:bisawtak/features/transcription/transcription_result_screen.dart';
import 'package:bisawtak/features/plans/plans_screen.dart';
import 'package:bisawtak/features/profile/profile_screen.dart';
import 'package:bisawtak/features/profile/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    // Catch ALL unknown routes and file URLs — redirect to /home
    errorBuilder: (context, state) {
      // If it's a file URL, capture it for processing
      final loc = state.uri.toString();
      if (loc.contains('.m4a') || loc.contains('.mp3') || loc.contains('.ogg') ||
          loc.contains('.wav') || loc.contains('.opus') || loc.startsWith('file')) {
        String filePath = Uri.decodeComponent(loc);
        if (filePath.startsWith('file://')) filePath = filePath.substring(7);
        if (filePath.startsWith('/file://')) filePath = filePath.substring(8);
        Future.microtask(() {
          ref.read(sharedFileProvider.notifier).state = filePath;
        });
      }
      // Show a simple redirect screen
      return const _RedirectToHome();
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/splash'),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/survey', builder: (_, __) => const SurveyScreen()),
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/transcriptions', builder: (_, __) => const TranscriptionListScreen()),
          GoRoute(path: '/plans', builder: (_, __) => const PlansScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/transcription/:id',
        builder: (_, state) => TranscriptionResultScreen(
          transcriptionId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
});

class _RedirectToHome extends StatelessWidget {
  const _RedirectToHome();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GoRouter.of(context).go('/home');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _MainShell extends StatefulWidget {
  final Widget child;
  const _MainShell({required this.child});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _currentIndex = 0;

  final _tabs = ['/home', '/transcriptions', '/plans', '/profile'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          context.go(_tabs[i]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.mic), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.history), label: 'تسجيلاتي'),
          NavigationDestination(icon: Icon(Icons.workspace_premium), label: 'الباقات'),
          NavigationDestination(icon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}
