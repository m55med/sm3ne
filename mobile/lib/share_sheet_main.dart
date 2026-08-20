import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bisawtak/config/l10n/app_localizations.dart';
import 'package:bisawtak/config/theme.dart';
import 'package:bisawtak/core/analytics/analytics_service.dart';
import 'package:bisawtak/features/share_receiver/share_handler_screen.dart';
import 'package:bisawtak/main.dart' show localeProvider, themeModeProvider;
import 'package:bisawtak/shared/utils/remote_logger.dart';
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

/// Talks to `ShareSheetActivity` (Android). Only `openApp` is exposed; closing
/// the sheet goes through [SystemNavigator.pop], which finishes the activity.
const _sheetChannel = MethodChannel('com.bisawtak/share_sheet');

/// How long to wait for the shared file before giving up. The intent that
/// launched us already carries it, so this only ever trips when a share is
/// malformed or the plugin never delivers — without it the user would stare at
/// a spinner over WhatsApp forever.
const _deliveryTimeout = Duration(seconds: 8);

/// Boots the floating share sheet — the Android counterpart of the iOS Share
/// Extension. Runs in `ShareSheetActivity`'s own engine, NOT the launcher's.
///
/// Deliberately does not build the router, the splash, or the auth gate: this
/// engine renders one sheet over the app the voice note came from and then goes
/// away. Tapping "فتح في بصوتك" is what hands control to the real app.
///
/// The `@pragma('vm:entry-point')` marker sits on `shareSheetMain()` in
/// main.dart, not here. AOT compilation walks imports out of lib/main.dart and
/// silently omits any library it can't reach — a standalone entrypoint in this
/// file never made it into the release binary at all, and the engine failed
/// with "Could not resolve main entrypoint function" over a transparent window.
Future<void> runShareSheet() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mirrors main(): best-effort, never fatal. Analytics is created but no
  // `appOpened` event is sent — a share is not an app open.
  AnalyticsService? analytics;
  try {
    await Firebase.initializeApp();
    analytics = AnalyticsService(FirebaseAnalytics.instance);
  } catch (e) {
    if (kDebugMode) debugPrint('Firebase init failed in share sheet: $e');
  }

  // Same persisted appearance as the app, so the sheet doesn't flash a light
  // card at a user running the app in dark mode.
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
      if (analytics != null) analyticsProvider.overrideWithValue(analytics),
    ],
    child: const ShareSheetApp(),
  ));
}

class ShareSheetApp extends ConsumerStatefulWidget {
  const ShareSheetApp({super.key});

  @override
  ConsumerState<ShareSheetApp> createState() => _ShareSheetAppState();
}

class _ShareSheetAppState extends ConsumerState<ShareSheetApp> {
  String? _path;
  bool _failed = false;
  StreamSubscription<List<SharedMediaFile>>? _sub;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    // Stand down the host activity's watchdog: it finishes a sheet that never
    // drew, so that a dead engine can't leave an invisible touch-eating layer
    // sitting on top of WhatsApp.
    _sheetChannel.invokeMethod('ready').catchError((Object e) {
      RemoteLogger.log('share_sheet', 'ready ping failed: $e');
      return null;
    });
    _listenForSharedFile();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  void _listenForSharedFile() {
    RemoteLogger.log('share_sheet', 'listening');

    // Cold start — the intent that launched this activity.
    //
    // catchError is load-bearing: an ACTION_SEND carrying no usable stream makes
    // the plugin's SharedMediaFile.fromMap throw ("type 'Null' is not a subtype
    // of type 'String'"). Unhandled, that leaves this transparent window on
    // screen with nothing in it — the exact blank-overlay failure the watchdog
    // exists to catch. Surface it as the error sheet instead.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      RemoteLogger.log('share_sheet', 'initial fired (${files.length} files)');
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _accept(files.first.path);
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((Object e) {
      RemoteLogger.log('share_sheet', 'initial media failed: $e');
      _reject();
    });

    // A second forward while the sheet is still open: the activity is
    // singleTop, so it is re-delivered through onNewIntent rather than
    // stacking another sheet.
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        RemoteLogger.log('share_sheet', 'stream fired (${files.length} files)');
        if (files.isNotEmpty && files.first.path.isNotEmpty) {
          _accept(files.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
      // Same guard as the cold-start path above: never let a malformed share
      // take down the isolate and strand an empty window over the host app.
      onError: (Object e) {
        RemoteLogger.log('share_sheet', 'media stream failed: $e');
        _reject();
      },
    );

    _timeout = Timer(_deliveryTimeout, () {
      if (_path == null && mounted) {
        RemoteLogger.log('share_sheet', 'timeout — no file delivered');
        setState(() => _failed = true);
      }
    });
  }

  /// Same three gates the in-app handler applies (AGENTS.md §5.2): no
  /// traversal, allowed audio extension, inside the sandbox. A path failing any
  /// of them never reaches the transcription pipeline.
  Future<void> _accept(String path) async {
    RemoteLogger.log('share_sheet', 'accept entry: "$path"');
    if (path.isEmpty || path.contains('..')) {
      RemoteLogger.log('share_sheet', 'REJECTED (empty/traversal)');
      _reject();
      return;
    }
    if (!hasAllowedAudioExtension(path)) {
      RemoteLogger.log('share_sheet', 'REJECTED (bad extension): "$path"');
      _reject();
      return;
    }
    if (!await isPathInsideSandbox(path)) {
      RemoteLogger.log('share_sheet', 'REJECTED (outside sandbox): "$path"');
      _reject();
      return;
    }
    if (!mounted || _path == path) return;
    _timeout?.cancel();
    setState(() {
      _path = path;
      _failed = false;
    });
  }

  void _reject() {
    if (!mounted || _path != null) return;
    _timeout?.cancel();
    setState(() => _failed = true);
  }

  /// Finishes the activity, returning the user to the app they shared from.
  void _close() => SystemNavigator.pop();

  /// Hands the target screen to the real app and closes the sheet.
  Future<void> _openApp(String route) async {
    try {
      await _sheetChannel.invokeMethod('openApp', {'route': route});
    } catch (e) {
      RemoteLogger.log('share_sheet', 'openApp failed: $e');
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'بصوتك',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: _body(),
    );
  }

  Widget _body() {
    final path = _path;
    if (path != null) {
      return ShareHandlerScreen(
        key: ValueKey(path),
        filePath: path,
        onDone: _close,
        onOpenRoute: _openApp,
      );
    }
    // Both waiting and failure keep the window see-through, so the host app
    // stays visible behind the sheet exactly as it does once the result lands.
    return _failed ? _FailedSheet(onClose: _close) : const _WaitingSheet();
  }
}

class _WaitingSheet extends StatelessWidget {
  const _WaitingSheet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _FailedSheet extends StatelessWidget {
  final VoidCallback onClose;
  const _FailedSheet({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      body: GestureDetector(
        onTap: onClose,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Material(
              color: scheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: scheme.error),
                      const SizedBox(height: 12),
                      Text(
                        'تعذّر قراءة الملف الصوتي المشارَك',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onClose,
                          child: const Text('إغلاق'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
