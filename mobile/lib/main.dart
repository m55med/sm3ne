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
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final localeProvider = StateProvider<Locale?>((ref) => null);
// Holds a shared file path when app is opened via share/open-with
final sharedFileProvider = StateProvider<String?>((ref) => null);

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
    // Handle shared files when app is already running
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _acceptSharedPath(files.first.path);
      }
    });

    // Handle shared files when app is opened via share
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _acceptSharedPath(files.first.path);
      }
    });

    // Handle "Open with" file URLs from iOS native
    const channel = MethodChannel('com.bisawtak/share');
    channel.setMethodCallHandler((call) async {
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
    if (path.isEmpty || path.contains('..')) {
      if (kDebugMode) debugPrint('share-receiver: rejected (empty/traversal): "$path"');
      return;
    }
    if (!hasAllowedAudioExtension(path)) {
      if (kDebugMode) debugPrint('share-receiver: rejected (unsupported extension): "$path"');
      return;
    }
    final allowed = await isPathInsideSandbox(path);
    if (!allowed) {
      if (kDebugMode) debugPrint('share-receiver: rejected (outside sandbox): "$path"');
      return;
    }
    if (!mounted) return;
    ref.read(sharedFileProvider.notifier).state = path;
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
          filePath: sharedFile,
          onDone: () {
            ref.read(sharedFileProvider.notifier).state = null;
          },
        ),
      );
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
