import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BisawtakDiag.log(tag: "apns_native", msg: "app_launched bundle=\(Bundle.main.bundleIdentifier ?? "?")")
    // Belt-and-braces: explicitly kick off APNs registration. The Firebase
    // Messaging plugin's auto-swizzling SHOULD do this after the user grants
    // notification permission, but in production we saw it silently skip on
    // some devices (perm granted, but `didRegister`/`didFail` never fired
    // → no APNs token → no FCM token → no /devices/register). Calling
    // registerForRemoteNotifications here forces Apple to invoke one of the
    // two delegate callbacks deterministically.
    //
    // It's safe to call even when the user hasn't granted permission yet —
    // iOS just no-ops in that case. Once they accept the prompt later, the
    // Firebase plugin re-calls this; idempotent.
    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
      BisawtakDiag.log(tag: "apns_native", msg: "registerForRemoteNotifications_called")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Handle "Open with" file URLs
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if url.isFileURL {
      // Copy to Documents/Inbox if not already there
      let controller = window?.rootViewController as? FlutterViewController
      let channel = FlutterMethodChannel(name: "com.bisawtak/share", binaryMessenger: controller!.binaryMessenger)
      channel.invokeMethod("sharedFile", arguments: url.path)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  // -- APNs registration probes ---------------------------------------------
  // Apple invokes one of these two callbacks after
  // `registerForRemoteNotifications`. Firebase swizzling normally captures
  // them and surfaces them via FCM — but in some setups the FAILURE
  // callback fires and Firebase silently logs it. Override both so we can
  // mirror the EXACT error to /diag/log and finally see what Apple is
  // refusing for.

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    let preview = String(hex.prefix(16))
    BisawtakDiag.log(tag: "apns_native", msg: "didRegister token_prefix=\(preview)… len=\(deviceToken.count)")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let ns = error as NSError
    // Logs everything so the server-side diag has enough to attribute the
    // failure: no iCloud, no internet to APNs, sandbox/production mismatch,
    // app entitlement missing, ...
    let info = String(describing: ns.userInfo).prefix(200)
    BisawtakDiag.log(
      tag: "apns_native",
      msg: "didFail domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) userInfo=\(info)"
    )
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}

/// Fire-and-forget native logger that mirrors our Flutter `RemoteLogger`.
/// Needed because the two APNs callbacks above can fire BEFORE the Flutter
/// engine is fully ready to dispatch a method-channel call — using a pure
/// URLSession POST sidesteps that ordering problem entirely.
private enum BisawtakDiag {
  static func log(tag: String, msg: String) {
    NSLog("[BisawtakDiag][\(tag)] \(msg)")
    guard let url = URL(string: "https://voice.neojeen.com/api/v1/diag/log") else { return }
    var req = URLRequest(url: url, timeoutInterval: 5)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let safeMsg = msg.count > 480 ? String(msg.prefix(480)) + "…" : msg
    let payload: [String: String] = ["tag": tag, "msg": safeMsg]
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    URLSession.shared.dataTask(with: req).resume()
  }
}
