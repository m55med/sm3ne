import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/features/auth/forgot_password_screen.dart';
import 'package:bisawtak/features/auth/login_screen.dart';
import 'package:bisawtak/features/auth/register_screen.dart';
import 'package:bisawtak/features/home/home_screen.dart';
import 'package:bisawtak/features/onboarding/onboarding_screen.dart';
import 'package:bisawtak/features/plans/plans_screen.dart';
import 'package:bisawtak/features/profile/about_screen.dart';
import 'package:bisawtak/features/profile/delete_account_screen.dart';
import 'package:bisawtak/features/profile/edit_profile_screen.dart';
import 'package:bisawtak/features/profile/help_screen.dart';
import 'package:bisawtak/features/profile/profile_screen.dart';
import 'package:bisawtak/features/profile/settings_screen.dart';
import 'package:bisawtak/features/splash/splash_screen.dart';
import 'package:bisawtak/features/support/contact_screen.dart';
import 'package:bisawtak/features/support/ticket_detail_screen.dart';
import 'package:bisawtak/features/survey/survey_screen.dart';
import 'package:bisawtak/features/transcription/transcription_list_screen.dart';
import 'package:bisawtak/features/transcription/transcription_result_screen.dart';
import 'package:bisawtak/main.dart';
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    // Unknown routes / shared file URLs are routed to /home. File paths
    // arriving via the URI are validated for sandbox containment before
    // we forward them to the shared-file provider.
    errorBuilder: (context, state) {
      _handleUnknownLocation(ref, state.uri.toString());
      return const _RedirectScreen(target: '/home');
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
        builder: (context, state, child) => _MainShell(state: state, child: child),
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
      GoRoute(path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/help', builder: (_, __) => const HelpScreen()),
      GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
      GoRoute(path: '/account/delete', builder: (_, __) => const DeleteAccountScreen()),
      GoRoute(path: '/contact', builder: (_, __) => const ContactScreen()),
      GoRoute(
        path: '/contact/:id',
        builder: (_, state) => TicketDetailScreen(publicId: state.pathParameters['id']!),
      ),
    ],
  );

  // Push users to /login whenever the API client signals a global 401.
  ref.listen(authInvalidationProvider, (_, __) {
    router.go('/login');
  });

  return router;
});

/// Strict scheme whitelist for "open with" intents.
const _kAllowedSchemes = <String>{'file', 'content', ''};

/// Inspects an unknown router location for a shared-file path. If the URI
/// looks like a file path with an allowed extension AND the resolved path
/// lives inside the app sandbox, forward it to [sharedFileProvider]. Any
/// path failing those checks is silently dropped — we never push raw user
/// input into the share handler.
void _handleUnknownLocation(Ref ref, String location) {
  String candidate = Uri.decodeComponent(location);
  Uri? parsed;
  try {
    parsed = Uri.parse(candidate);
  } catch (_) {
    return;
  }

  // Restrict to known schemes.
  if (!_kAllowedSchemes.contains(parsed.scheme.toLowerCase())) return;

  String path = parsed.scheme.isEmpty ? candidate : parsed.path;
  if (candidate.startsWith('file://')) path = candidate.substring(7);
  if (candidate.startsWith('/file://')) path = candidate.substring(8);

  // Reject path-traversal attempts up front.
  if (path.contains('..')) return;

  // Restrict by extension.
  if (!hasAllowedAudioExtension(path)) return;

  // Defer the async sandbox check; only set the provider if it resolves to a
  // path inside our sandbox.
  Future<void>(() async {
    final allowed = await isPathInsideSandbox(path);
    if (allowed) {
      ref.read(sharedFileProvider.notifier).state = path;
    }
  });
}

/// Tiny widget that immediately redirects when built. Used by the
/// `errorBuilder` while go_router unwinds the unknown-route state. We can't
/// use a top-level `redirect` here because errorBuilder always returns a
/// widget — but we still avoid `addPostFrameCallback` by using a builder
/// that issues `go()` synchronously after the first frame via a microtask.
class _RedirectScreen extends StatefulWidget {
  final String target;
  const _RedirectScreen({required this.target});

  @override
  State<_RedirectScreen> createState() => _RedirectScreenState();
}

class _RedirectScreenState extends State<_RedirectScreen> {
  @override
  void initState() {
    super.initState();
    // Schedule the redirect for after this frame; using a microtask is fine
    // because GoRouter's navigator is available immediately.
    scheduleMicrotask(() {
      if (!mounted) return;
      GoRouter.of(context).go(widget.target);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _MainShell extends StatelessWidget {
  final Widget child;
  final GoRouterState state;
  const _MainShell({required this.child, required this.state});

  static const _tabs = ['/home', '/transcriptions', '/plans', '/profile'];

  int _indexFor(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (location == _tabs[i] || location.startsWith('${_tabs[i]}/')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexFor(state.uri.path);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => context.go(_tabs[i]),
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
