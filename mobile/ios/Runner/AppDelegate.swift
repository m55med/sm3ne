import Flutter
import Foundation
import Speech
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
    // Register the on-device speech-file recognizer channel via the plugin
    // registry's binary messenger. We used to read `window?.rootViewController`
    // here, but at the moment this callback fires the root VC is sometimes
    // still nil — registration would silently no-op and the Dart side would
    // see MissingPluginException on every probeAvailability/requestPermission
    // call (surfaced as "حالة غير معروفة" in settings). Going through the
    // plugin registrar gets us a guaranteed-valid binaryMessenger.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechFileRecognizer") {
      SpeechFileRecognizer.register(with: registrar.messenger())
      BisawtakDiag.log(tag: "stt_channel", msg: "registered via plugin registrar")
    } else {
      BisawtakDiag.log(tag: "stt_channel", msg: "FAILED to obtain registrar — channel will not respond")
    }

    // App Group bridge — lets Flutter mirror the access token + API base URL
    // into the shared container so the Share Extension can run a server
    // fallback without launching the app.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppGroupBridge") {
      AppGroupBridgePlugin.register(with: registrar.messenger())
      BisawtakDiag.log(tag: "appgroup_channel", msg: "registered")
    } else {
      BisawtakDiag.log(tag: "appgroup_channel", msg: "FAILED to obtain registrar")
    }

    // Double-forward fix: the Dart side PULLs any pending shared voice note the
    // moment its handler is ready, via `getPendingSharedFile` on the same
    // `com.bisawtak/share` channel SceneDelegate pushes on. This kills the
    // cold-launch race where the native push fires before Flutter is listening
    // and the first forward is silently dropped. Read+clear is atomic enough
    // for our single-consumer use. Key kept in sync with SceneDelegate.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareHandoffPull") {
      let channel = FlutterMethodChannel(
        name: "com.bisawtak/share",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "getPendingSharedFile" {
          let defaults = UserDefaults.standard
          let path = defaults.string(forKey: "pending_shared_file")
          if path != nil { defaults.removeObject(forKey: "pending_shared_file") }
          BisawtakDiag.log(tag: "pull", msg: "getPendingSharedFile → \(path ?? "nil")")
          result(path)
        } else {
          // `sharedFile` (native→Dart push) is handled on the Dart side; any
          // other Dart→native call on this channel is unknown.
          result(FlutterMethodNotImplemented)
        }
      }
      BisawtakDiag.log(tag: "pull_channel", msg: "registered")
    } else {
      BisawtakDiag.log(tag: "pull_channel", msg: "FAILED to obtain registrar")
    }
  }

  // Handle "Open with" file URLs. With the UIScene lifecycle this is rarely
  // hit (SceneDelegate.openURLContexts handles it), but keep it safe: stash the
  // path in the pull slot so Dart picks it up even if the VC isn't ready, and
  // never force-unwrap the root controller (that used to crash on a nil VC).
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if url.isFileURL {
      UserDefaults.standard.set(url.path, forKey: "pending_shared_file")
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(name: "com.bisawtak/share", binaryMessenger: controller.binaryMessenger)
        channel.invokeMethod("sharedFile", arguments: url.path)
      }
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

/// Native bridge for transcribing an audio FILE on-device using Apple's
/// SFSpeechURLRecognitionRequest. Lives outside the Flutter plugin because
/// `speech_to_text` only exposes mic input — file input requires direct use
/// of the Speech framework. We invoke it from Dart via MethodChannel
/// `com.bisawtak/stt_file`.
///
/// Behavior:
///   - Requires both speech-recognition authorization AND a readable file.
///   - Forces `requiresOnDeviceRecognition = true` so we never silently
///     send audio to Apple's servers.
///   - Returns the FINAL result (not partials) when the file is fully
///     consumed. Includes a confidence score so the orchestrator can apply
///     its own quality gate.
///   - 1-minute SFSpeechRecognizer limit is enforced at the request layer
///     by Apple; longer files will throw and the caller falls back to the
///     server pipeline.
@objc class SpeechFileRecognizer: NSObject {
  static let shared = SpeechFileRecognizer()

  private var activeTask: SFSpeechRecognitionTask?

  /// Registers the method channel. Called once from AppDelegate during
  /// plugin registration.
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.bisawtak/stt_file",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        SpeechFileRecognizer.shared.isAvailable(call, result: result)
      case "requestPermission":
        // Standalone permission request so the Dart side can prompt the
        // user proactively from the settings screen (instead of waiting
        // for the first transcribe attempt to trigger Apple's dialog).
        SFSpeechRecognizer.requestAuthorization { status in
          DispatchQueue.main.async {
            result(Self.authStatusString(status))
          }
        }
      case "recognize":
        SpeechFileRecognizer.shared.recognize(call, result: result)
      case "cancel":
        SpeechFileRecognizer.shared.cancel()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // -- isAvailable: probe both authorization and recognizer for the locale.
  // Returns a dictionary so Dart can show a precise reason ("not_authorized"
  // / "no_recognizer" / "no_on_device_support") without surfacing all of
  // Apple's enum cases.

  private func isAvailable(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let localeId = args["localeId"] as? String ?? "ar-EG"
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
    let auth = SFSpeechRecognizer.authorizationStatus()

    var supportsOnDevice = false
    if let r = recognizer {
      supportsOnDevice = r.supportsOnDeviceRecognition
    }

    result([
      "auth_status": Self.authStatusString(auth),
      "recognizer_available": recognizer?.isAvailable ?? false,
      "supports_on_device": supportsOnDevice,
    ])
  }

  // -- recognize: the workhorse. Awaits authorization, then runs the
  // SFSpeechURLRecognitionRequest synchronously (well, async via callback)
  // and packages the FINAL result.

  private func recognize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let filePath = args["filePath"] as? String else {
      result(["success": false, "reason": "missing_filePath"])
      return
    }
    let localeId = args["localeId"] as? String ?? "ar-EG"

    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard status == .authorized else {
          result([
            "success": false,
            "reason": "not_authorized:\(Self.authStatusString(status))",
          ])
          return
        }
        self.performRecognition(filePath: filePath, localeId: localeId, result: result)
      }
    }
  }

  private func performRecognition(
    filePath: String,
    localeId: String,
    result: @escaping FlutterResult
  ) {
    let url = URL(fileURLWithPath: filePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(["success": false, "reason": "file_not_found"])
      return
    }

    let locale = Locale(identifier: localeId)
    guard let recognizer = SFSpeechRecognizer(locale: locale),
          recognizer.isAvailable else {
      result(["success": false, "reason": "recognizer_unavailable"])
      return
    }

    // Forcing on-device guarantees no audio leaves the device. If the locale
    // doesn't have an on-device model installed, the request errors out
    // instantly and the orchestrator's fallback kicks in.
    guard recognizer.supportsOnDeviceRecognition else {
      result(["success": false, "reason": "no_on_device_support"])
      return
    }

    let request = SFSpeechURLRecognitionRequest(url: url)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    if #available(iOS 16.0, *) {
      request.addsPunctuation = true
    }

    // Cancel any prior in-flight task — only one file recognition at a time.
    activeTask?.cancel()
    activeTask = recognizer.recognitionTask(with: request) { recognition, error in
      if let error = error {
        let ns = error as NSError
        // Common errors:
        //  1101 (kAFAssistantErrorDomain) — file format or empty audio
        //  1700  — locale not available on this device
        result([
          "success": false,
          "reason": "task_error:\(ns.domain):\(ns.code):\(ns.localizedDescription)",
        ])
        self.activeTask = nil
        return
      }
      guard let recognition = recognition else { return }
      // Wait for the FINAL transcription before returning — partial
      // callbacks fire every chunk.
      if recognition.isFinal {
        let text = recognition.bestTranscription.formattedString
        // Average per-segment confidence; SFSpeech doesn't expose a single
        // utterance-level number.
        let segments = recognition.bestTranscription.segments
        let confidence: Double
        if segments.isEmpty {
          confidence = 0
        } else {
          let total = segments.reduce(0.0) { $0 + Double($1.confidence) }
          confidence = total / Double(segments.count)
        }
        result([
          "success": true,
          "text": text,
          "confidence": confidence,
          "segment_count": segments.count,
        ])
        self.activeTask = nil
      }
    }
  }

  private func cancel() {
    activeTask?.cancel()
    activeTask = nil
  }

  private static func authStatusString(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch s {
    case .authorized:      return "authorized"
    case .denied:          return "denied"
    case .restricted:      return "restricted"
    case .notDetermined:   return "notDetermined"
    @unknown default:      return "unknown"
    }
  }
}
