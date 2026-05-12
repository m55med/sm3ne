import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:bisawtak/config/l10n/app_localizations.dart';
import 'package:bisawtak/config/theme.dart';
import 'package:bisawtak/config/routes.dart';
import 'package:bisawtak/features/share_receiver/share_handler_screen.dart';
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final localeProvider = StateProvider<Locale?>((ref) => null);
// Holds a shared file path when app is opened via share/open-with
final sharedFileProvider = StateProvider<String?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  /// silently to defuse path-traversal vectors.
  Future<void> _acceptSharedPath(String path) async {
    if (path.isEmpty || path.contains('..')) return;
    if (!hasAllowedAudioExtension(path)) return;
    final allowed = await isPathInsideSandbox(path);
    if (!allowed) return;
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
