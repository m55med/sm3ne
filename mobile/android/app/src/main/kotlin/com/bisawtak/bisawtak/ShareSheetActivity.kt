package com.bisawtak.bisawtak

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Transparent host for the share-result sheet.
 *
 * When a voice note is forwarded to Bisawtak (ACTION_SEND), Android delivers
 * the intent here instead of [MainActivity]. Because the window is translucent
 * and this activity keeps no task of its own, the sheet appears to float over
 * WhatsApp/Telegram — the full app never launches. This is the Android
 * counterpart of the iOS Share Extension.
 *
 * "Open with" (ACTION_VIEW) still targets [MainActivity]: there the user came
 * from a file manager expecting the app itself, not a floating sheet.
 *
 * Runs the [DART_ENTRYPOINT] Dart entrypoint, which builds only the sheet —
 * not the router, the splash, or the auth gate.
 */
class ShareSheetActivity : FlutterActivity() {

    /** Set once Dart has actually rendered — see [watchdog]. */
    private var dartReady = false
    private val handler = Handler(Looper.getMainLooper())

    /**
     * Kills a sheet that never drew.
     *
     * This window is transparent and sits on top of another app, so a Flutter
     * engine that fails to start does not look like a crash — it looks like the
     * *host app* froze, while an invisible layer swallows every touch. Rather
     * than trap the user there, finish and hand them back to WhatsApp.
     */
    private val watchdog = Runnable {
        if (!dartReady && !isFinishing) finish()
    }

    /** Transparent so whatever is behind this window keeps showing through. */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    /**
     * Resolved against the DEFAULT Dart library (lib/main.dart), which is where
     * `shareSheetMain` is declared — see the note on it. Pointing this at
     * lib/share_sheet_main.dart instead does not work: AOT never compiles a
     * library that nothing imports, so the function would not exist to resolve.
     */
    override fun getDartEntrypointFunctionName(): String = DART_ENTRYPOINT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handler.postDelayed(watchdog, WATCHDOG_MS)
    }

    override fun onDestroy() {
        handler.removeCallbacks(watchdog)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dart is alive and painting — stand the watchdog down.
                    "ready" -> {
                        dartReady = true
                        handler.removeCallbacks(watchdog)
                        result.success(true)
                    }
                    // "فتح في بصوتك" — hand the target route to the real app and
                    // close the sheet. FLAG_ACTIVITY_NEW_TASK is required because
                    // this activity has no task affinity of its own.
                    "openApp" -> {
                        val route = call.argument<String>("route")
                        val intent = Intent(this, MainActivity::class.java).apply {
                            addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                            )
                            if (route != null) putExtra(MainActivity.EXTRA_ROUTE, route)
                        }
                        startActivity(intent)
                        result.success(true)
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        const val CHANNEL = "com.bisawtak/share_sheet"
        const val DART_ENTRYPOINT = "shareSheetMain"

        /** Generous enough for a cold engine start on a slow device. */
        const val WATCHDOG_MS = 12_000L
    }
}
