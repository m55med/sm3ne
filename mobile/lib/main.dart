import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:bisawtak/config/l10n/app_localizations.dart';
import 'package:bisawtak/config/theme.dart';
import 'package:bisawtak/config/routes.dart';
import 'package:bisawtak/core/analytics/analytics_service.dart';
import 'package:bisawtak/features/share_receiver/share_handler_screen.dart';
import 'package:bisawtak/shared/utils/remote_logger.dart';
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final localeProvider = StateProvider<Locale?>((ref) => null);

/// Holds the path of a file shared into the app (WhatsApp voice note, "Open
/// with…", etc.). Implemented as a Notifier — NOT a plain `StateProvider` —
/// so the only way to clear it is via the explicit [SharedFileNotifier.dismiss]
/// method (called from the share-handler's "done/close" buttons). This guards
/// against accidental resets from unrelated code paths that would make the
/// share screen flicker and vanish.
class SharedFileNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Stage a file for the share handler. Idempotent on the same path.
  void accept(String path) {
    if (state == path) {
      RemoteLogger.log('share', 'accept-skip (same path): $path');
      return;
    }
    RemoteLogger.log('share', 'accept: $path (was: $state)');
    state = path;
  }

  /// Tear down the share handler. The ONLY way to clear the state — called
  /// exclusively from the share-handler's user-initiated "تم/إغلاق" actions.
  void dismiss() {
    RemoteLogger.log('share', 'dismiss (was: $state)');
    state = null;
  }
}

final sharedFileProvider =
    NotifierProvider<SharedFileNotifier, String?>(SharedFileNotifier.new);

/// Set when the user taps "فتح في بصوتك" on the share sheet. The share overlay
/// lives in a plain MaterialApp (no GoRouter), so it can't navigate directly.
/// Instead it stashes the target route here and dismisses; the root widget
/// then drives the MaterialApp.router to that route once it rebuilds.
final pendingShareRouteProvider = StateProvider<String?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — Analytics + Crashlytics. Wrapped in try/catch so a Firebase
  // hiccup (e.g. missing config in a misbuilt flavour) can never block app
  // startup; analytics is best-effort, the app must still run without it.
  AnalyticsService? analytics;
  try {
    await Firebase.initializeApp();
    // Route uncaught Flutter + platform errors to Crashlytics.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    analytics = AnalyticsService(FirebaseAnalytics.instance);
    await analytics.appOpened();
  } catch (e) {
    if (kDebugMode) debugPrint('Firebase init failed (continuing without it): $e');
  }

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode');
  final savedLocale = prefs.getString('locale');

  runApp(ProviderScope(
    overrides: [
      themeModeProvider.overrideWith((ref) {
        if (savedTheme == 'dark') return ThemeMode.dark;
        if (savedTheme == 'light') return ThemeMode.light;
        return ThemeMode.system;
      }),
      if (savedLocale != null)
        localeProvider.overrideWith((ref) => Locale(savedLocale)),
      if (analytics != null)
        analyticsProvider.overrideWithValue(analytics),
    ],
    child: const BisawtakApp(),
  ));
}

class BisawtakApp extends ConsumerStatefulWidget {
  const BisawtakApp({super.key});

  @override
  ConsumerState<BisawtakApp> createState() => _BisawtakAppState();
}

class _BisawtakAppState extends ConsumerState<BisawtakApp> {
  @override
  void initState() {
    super.initState();
    _handleIncomingShares();
  }

  void _handleIncomingShares() {
    RemoteLogger.log('share', '_handleIncomingShares registered');

    // Handle shared files when app is already running
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      RemoteLogger.log('share', 'rsi-stream fired (${files.length} files)');
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _acceptSharedPath(files.first.path);
      }
    });

    // Handle shared files when app is opened via share
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      RemoteLogger.log('share', 'rsi-initial fired (${files.length} files)');
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _acceptSharedPath(files.first.path);
      }
    });

    // Handle "Open with" file URLs from iOS native (our SceneDelegate).
    const channel = MethodChannel('com.bisawtak/share');
    channel.setMethodCallHandler((call) async {
      RemoteLogger.log('share', 'channel called: ${call.method}');
      if (call.method == 'sharedFile') {
        final path = call.arguments as String;
        _acceptSharedPath(path);
      }
    });
  }

  /// Validates an incoming shared-file path against the app sandbox + allowed
  /// extensions before pushing it into [sharedFileProvider]. Untrusted paths
  /// — anything containing `..` or pointing outside the sandbox — are dropped
  /// silently to defuse path-traversal vectors. Failures are logged in debug
  /// builds so we can diagnose why a share from a new platform was rejected.
  Future<void> _acceptSharedPath(String path) async {
    RemoteLogger.log('share', '_acceptSharedPath entry: "$path"');
    if (path.isEmpty || path.contains('..')) {
      RemoteLogger.log('share', 'REJECTED (empty/traversal): "$path"');
      return;
    }
    if (!hasAllowedAudioExtension(path)) {
      RemoteLogger.log('share', 'REJECTED (bad extension): "$path"');
      return;
    }
    final allowed = await isPathInsideSandbox(path);
    if (!allowed) {
      RemoteLogger.log('share', 'REJECTED (outside sandbox): "$path"');
      return;
    }
    if (!mounted) {
      RemoteLogger.log('share', 'REJECTED (widget unmounted): "$path"');
      return;
    }
    ref.read(sharedFileProvider.notifier).accept(path);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    final sharedFile = ref.watch(sharedFileProvider);

    // If a file was shared, show the share handler overlay
    if (sharedFile != null) {
      return MaterialApp(
        title: 'بصوتك',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ShareHandlerScreen(
          // The Key ensures Flutter unmounts the previous instance and
          // creates a fresh one whenever a NEW shared file arrives — i.e.
          // when the user shares another WhatsApp voice while the previous
          // result is still on screen. Without this, the old transcription
          // would stay visible because initState only runs on the first
          // mount.
          key: ValueKey(sharedFile),
          filePath: sharedFile,
          onDone: () => ref.read(sharedFileProvider.notifier).dismiss(),
          onOpenRoute: (route) {
            ref.read(pendingShareRouteProvider.notifier).state = route;
            ref.read(sharedFileProvider.notifier).dismiss();
          },
        ),
      );
    }

    // Drain a pending "فتح في بصوتك" navigation once the router app is back.
    final pendingRoute = ref.watch(pendingShareRouteProvider);
    if (pendingRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(pendingShareRouteProvider) == pendingRoute) {
          ref.read(pendingShareRouteProvider.notifier).state = null;
          router.go(pendingRoute);
        }
      });
    }

    return MaterialApp.router(
      title: 'بصوتك',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    );
  }
}
