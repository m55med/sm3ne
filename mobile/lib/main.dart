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
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/features/share_receiver/share_handler_screen.dart';
import 'package:bisawtak/share_sheet_main.dart' show runShareSheet;
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

/// Set when the user taps "فتح في بصوتك" on the share sheet. The sheet is an
/// overlay in the router app's `builder` and doesn't hold a router ref, so it
/// stashes the target route here and dismisses; the root widget then drives the
/// MaterialApp.router to that route once it rebuilds.
///
/// Two producers now write to it, and they are drained by DIFFERENT widgets:
///  - the in-app overlay (iOS / "Open with") — app already past the splash, so
///    [_BisawtakAppState.build] drains it immediately;
///  - the Android [ShareSheetActivity], which launches this app with a route
///    extra. That arrives while the splash is still resolving auth, and any
///    navigation from here would be overwritten by the splash's own auth
///    listener — so `SplashScreen` drains it instead once auth settles.
/// The `authenticated` check in the builder is what keeps the two apart.
final pendingShareRouteProvider = StateProvider<String?>((ref) => null);

/// Channel to the Android host activity, used to collect a route handed over by
/// the floating share sheet. iOS has no counterpart — its Share Extension does
/// not deep-link back into the app.
const _appRouteChannel = MethodChannel('com.bisawtak/app_route');

/// Entrypoint for `ShareSheetActivity`'s engine — the floating share sheet.
///
/// It lives HERE, in the default library, on purpose. Flutter's AOT build walks
/// the import graph out of lib/main.dart; a library nothing imports is never
/// compiled, so an entrypoint declared in share_sheet_main.dart was absent from
/// the release binary and the engine died with "Could not resolve main
/// entrypoint function" — leaving an invisible window over the sending app.
/// Declaring it here also pulls share_sheet_main.dart into the build.
@pragma('vm:entry-point')
void shareSheetMain() {
  runShareSheet();
}

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
    _handleShareSheetRoute();
  }

  /// Collects the route the Android floating share sheet asked us to open.
  ///
  /// Cold start (app was not running): the launching intent carried the extra
  /// before Dart existed, so we PULL it. Warm start: the host activity PUSHes
  /// it through `onNewIntent`. Both land in [pendingShareRouteProvider].
  void _handleShareSheetRoute() {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    _appRouteChannel.setMethodCallHandler((call) async {
      if (call.method == 'route') {
        final route = call.arguments as String?;
        RemoteLogger.log('share', 'route pushed from sheet: ${route ?? "nil"}');
        if (route != null && route.isNotEmpty && mounted) {
          ref.read(pendingShareRouteProvider.notifier).state = route;
        }
      }
    });

    _appRouteChannel.invokeMethod<String>('getPendingRoute').then((route) {
      RemoteLogger.log('share', 'route pulled from sheet: ${route ?? "nil"}');
      if (route != null && route.isNotEmpty && mounted) {
        ref.read(pendingShareRouteProvider.notifier).state = route;
      }
    }).catchError((Object e) {
      RemoteLogger.log('share', 'getPendingRoute failed: $e');
    });
  }

  void _handleIncomingShares() {
    RemoteLogger.log('share', '_handleIncomingShares registered');

    // Handle shared files when app is already running (Android warm start via
    // singleTop onNewIntent). reset() after handling clears the plugin's stored
    // intent so the NEXT forward fires cleanly — without it, a forward made
    // while the app is backgrounded can be swallowed and the user has to share
    // twice (the Android side of the double-forward bug).
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      RemoteLogger.log('share', 'rsi-stream fired (${files.length} files)');
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _acceptSharedPath(files.first.path);
        ReceiveSharingIntent.instance.reset();
      }
    });

    // Handle shared files when app is opened via share (Android cold start).
    // reset() stops a rebuild from re-delivering the same initial file.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      RemoteLogger.log('share', 'rsi-initial fired (${files.length} files)');
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _acceptSharedPath(files.first.path);
        ReceiveSharingIntent.instance.reset();
      }
    });

    // Handle "Open with" file URLs from iOS native (our SceneDelegate) — the
    // native side PUSHes shared voice notes here.
    const channel = MethodChannel('com.bisawtak/share');
    channel.setMethodCallHandler((call) async {
      RemoteLogger.log('share', 'channel called: ${call.method}');
      if (call.method == 'sharedFile') {
        final path = call.arguments as String;
        _acceptSharedPath(path);
      }
    });

    // Double-forward fix (iOS): the native push races against this Dart handler
    // on a cold launch and the FIRST forward used to be dropped. Now that our
    // handler is registered, immediately PULL any file the native side stashed
    // before we were listening. accept() dedupes by path, and the native slot
    // is read-and-cleared, so this never double-processes what the push already
    // delivered. iOS-only: Android delivery goes through receive_sharing_intent.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      channel.invokeMethod<String>('getPendingSharedFile').then((path) {
        RemoteLogger.log('share', 'pull getPendingSharedFile → ${path ?? "nil"}');
        if (path != null && path.isNotEmpty) {
          _acceptSharedPath(path);
        }
      }).catchError((Object e) {
        RemoteLogger.log('share', 'pull failed: $e');
      });
    }
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

    // Drain a pending "فتح في بصوتك" navigation once the router app is back.
    //
    // Only while the session is already settled: a route arriving during a cold
    // start (Android share sheet → launch app) would be pushed here and then
    // immediately overwritten by SplashScreen's auth listener sending the user
    // to /home. In that window we leave the route staged and let the splash
    // deliver it. `read` — not `watch` — so an auth change alone never triggers
    // this drain; it runs only when a route is actually staged.
    final pendingRoute = ref.watch(pendingShareRouteProvider);
    final settled = ref.read(authProvider).status == AuthStatus.authenticated;
    if (pendingRoute != null && settled) {
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
      // The shared-result sheet floats OVER the running app — the home screen
      // dims behind it via the sheet's own translucent scrim — instead of
      // replacing the whole app with a black screen. (iOS still can't show
      // ANOTHER app behind a foreground app; the native Share Extension covers
      // the float-over-host-app case.)
      builder: (context, child) {
        return Stack(
          children: [
            ?child,
            if (sharedFile != null)
              Positioned.fill(
                child: ShareHandlerScreen(
                  // Fresh instance whenever a NEW file arrives so a second
                  // forward re-runs initState instead of showing the stale one.
                  key: ValueKey(sharedFile),
                  filePath: sharedFile,
                  onDone: () => ref.read(sharedFileProvider.notifier).dismiss(),
                  onOpenRoute: (route) {
                    ref.read(pendingShareRouteProvider.notifier).state = route;
                    ref.read(sharedFileProvider.notifier).dismiss();
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
