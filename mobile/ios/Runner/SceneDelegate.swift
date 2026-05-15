import Flutter
import UIKit

// TEMPORARY remote diagnostic. POSTs short events to /api/v1/diag/log so we
// can see, from a device, exactly what the share flow is doing. Also goes to
// NSLog. Remove once the share-intent bug is closed.
fileprivate func diag(_ tag: String, _ message: String) {
  NSLog("[DIAG \(tag)] \(message)")
  var req = URLRequest(
    url: URL(string: "https://voice.neojeen.com/api/v1/diag/log")!,
    timeoutInterval: 4
  )
  req.httpMethod = "POST"
  req.setValue("application/json", forHTTPHeaderField: "Content-Type")
  let payload: [String: String] = [
    "tag": String(tag.prefix(40)),
    "msg": String(message.prefix(480)),
  ]
  if let body = try? JSONSerialization.data(withJSONObject: payload) {
    req.httpBody = body
    URLSession.shared.dataTask(with: req).resume()
  }
}

/// Bridges the Share Extension's "shared a voice note" hand-off into Flutter.
///
/// Flow:
///   1. The Share Extension (ios/ShareExtension/ShareViewController.swift) copies
///      the shared audio into the App Group container, stashes its path in the
///      App Group `UserDefaults` under `shared_audio_path`, then opens
///      `bisawtak://shared`.
///   2. Because the app adopts the UIScene lifecycle, that URL open is delivered
///      HERE (UIWindowSceneDelegate) — NOT to `AppDelegate.application(_:open:)`.
///   3. We don't rely on URL routing alone — the responder-chain trick that
///      modern iOS Share Extensions use to open `bisawtak://` is flaky on
///      iOS 18+/26. Instead, we ALSO check the App Group slot in
///      `sceneDidBecomeActive`. That way, even when the URL never arrives, the
///      file the Share Extension stashed still gets picked up the moment the
///      user lands in the app.
///   4. The file is copied OUT of the App Group container into the app's own
///      Documents directory before the path is pushed to Flutter — so Dart's
///      `isPathInsideSandbox()` guard accepts it.
class SceneDelegate: FlutterSceneDelegate {

  private static let appGroupID = "group.com.bisawtak.bisawtak"
  private static let sharedPathKey = "shared_audio_path"
  private static let channelName = "com.bisawtak/share"

  // Cold launch: app was not running, Share Extension (or any bisawtak://)
  // opened it.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    let bisawtakURL = connectionOptions.urlContexts.contains(where: { $0.url.scheme == "bisawtak" })
    diag("scene", "willConnectTo bisawtak-url=\(bisawtakURL)")
    if bisawtakURL {
      deliverSharedAudio(retriesLeft: 24)
    }
  }

  // Warm: app already running, Share Extension opens bisawtak://shared.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)
    let urls = URLContexts.map { $0.url.absoluteString }.joined(separator: ",")
    diag("scene", "openURLContexts urls=[\(urls)]")
    if URLContexts.contains(where: { $0.url.scheme == "bisawtak" }) {
      deliverSharedAudio(retriesLeft: 8)
    }
  }

  // BULLETPROOF: every time the scene becomes active, drain any pending
  // shared-audio path. Catches the case where the Share Extension wrote the
  // file but its application.open() trick to launch the host app failed (a
  // known issue on iOS 18+ — the responder-chain hack is brittle). The user
  // taps the app icon, lands here, and the shared note gets processed.
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    diag("scene", "didBecomeActive — checking shared-audio slot")
    deliverSharedAudio(retriesLeft: 8)
  }

  /// Reads the path the Share Extension stashed, copies the file into the
  /// app's Documents sandbox, and pushes the new in-sandbox path to Flutter.
  /// Retries because on a cold launch the FlutterViewController + Dart-side
  /// channel handler aren't ready the moment the scene connects.
  private func deliverSharedAudio(retriesLeft: Int) {
    let defaults = UserDefaults(suiteName: Self.appGroupID)
    let groupPath = defaults?.string(forKey: Self.sharedPathKey) ?? ""
    if defaults == nil {
      diag("deliver", "UserDefaults(suiteName:) returned nil — App Group not accessible!")
      return
    }
    if groupPath.isEmpty {
      diag("deliver", "no shared_audio_path in App Group (retries=\(retriesLeft))")
      return
    }

    diag("deliver", "found path=\(groupPath) retries=\(retriesLeft)")

    guard let controller = window?.rootViewController as? FlutterViewController else {
      diag("deliver", "FlutterViewController not ready — retry")
      retryLater(retriesLeft)
      return
    }

    let groupURL = URL(fileURLWithPath: groupPath)
    guard FileManager.default.fileExists(atPath: groupURL.path) else {
      // File already consumed or never written — clear the slot and bail.
      diag("deliver", "FILE MISSING at \(groupURL.path) — clearing slot")
      defaults?.removeObject(forKey: Self.sharedPathKey)
      defaults?.synchronize()
      return
    }

    // Copy out of the App Group container into our own Documents directory so
    // Flutter's sandbox guard accepts the path.
    let ext = groupURL.pathExtension.isEmpty ? "m4a" : groupURL.pathExtension
    guard
      let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      NSLog("[SceneDelegate] could not resolve Documents directory")
      return
    }
    let destURL = docsDir.appendingPathComponent("shared_\(UUID().uuidString).\(ext)")
    do {
      try FileManager.default.copyItem(at: groupURL, to: destURL)
      diag("deliver", "copied → \(destURL.lastPathComponent)")
    } catch {
      diag("deliver", "copy failed: \(error.localizedDescription)")
      return
    }

    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: controller.binaryMessenger
    )
    diag("deliver", "invokeMethod sharedFile → Flutter")
    channel.invokeMethod("sharedFile", arguments: destURL.path) { [weak self] result in
      let notImplemented = (result as AnyObject) === FlutterMethodNotImplemented
      if notImplemented {
        // Dart-side handler not up yet — discard this copy and retry from the
        // App Group slot (still populated).
        diag("deliver", "Flutter handler MISSING — retry")
        try? FileManager.default.removeItem(at: destURL)
        self?.retryLater(retriesLeft)
      } else {
        // Delivered. Clear the hand-off slot and the App Group copy so a later
        // launch never reprocesses the same voice note.
        diag("deliver", "✓ Flutter received — clearing slot")
        defaults?.removeObject(forKey: Self.sharedPathKey)
        defaults?.synchronize()
        try? FileManager.default.removeItem(at: groupURL)
      }
    }
  }

  private func retryLater(_ retriesLeft: Int) {
    guard retriesLeft > 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.deliverSharedAudio(retriesLeft: retriesLeft - 1)
    }
  }
}
