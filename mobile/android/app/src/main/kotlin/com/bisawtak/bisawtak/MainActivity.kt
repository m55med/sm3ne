package com.bisawtak.bisawtak

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app proper.
 *
 * Beyond hosting Flutter it carries one extra job: when the user taps
 * "فتح في بصوتك" on the floating [ShareSheetActivity], that sheet launches this
 * activity with an [EXTRA_ROUTE] telling it which screen to land on. Two
 * delivery paths, because the app may or may not already be running:
 *
 *  - cold start → Dart pulls it via `getPendingRoute` once its handler is up.
 *  - warm start → `onNewIntent` pushes it straight down the channel.
 *
 * Both funnel into `pendingShareRouteProvider` on the Dart side.
 */
class MainActivity : FlutterActivity() {

    /** Route captured before Dart was listening; read once, then cleared. */
    private var pendingRoute: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingRoute = intent?.getStringExtra(EXTRA_ROUTE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = intent.getStringExtra(EXTRA_ROUTE) ?: return
        val live = channel
        if (live != null) live.invokeMethod("route", route) else pendingRoute = route
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingRoute" -> {
                        result.success(pendingRoute)
                        pendingRoute = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    companion object {
        const val EXTRA_ROUTE = "com.bisawtak.route"
        const val CHANNEL = "com.bisawtak/app_route"
    }
}
