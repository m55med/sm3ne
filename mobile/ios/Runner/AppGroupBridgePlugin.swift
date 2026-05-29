import Foundation
import Flutter

/// Flutter <-> App Group bridge. Registered from AppDelegate. Lets Dart push
/// the access token + API base URL into the shared container (and clear it on
/// logout) so the Share Extension can run its server fallback without
/// launching the app. Runner-only — the ShareExtension target doesn't link
/// Flutter, so this must NOT be a member of that target.
enum AppGroupBridgePlugin {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.bisawtak/appgroup",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      let defaults = AppGroup.defaults
      switch call.method {
      case "setValues":
        let args = call.arguments as? [String: Any] ?? [:]
        if let token = args[AppGroup.accessTokenKey] as? String {
          defaults?.set(token, forKey: AppGroup.accessTokenKey)
        }
        if let url = args[AppGroup.apiBaseUrlKey] as? String, !url.isEmpty {
          defaults?.set(url, forKey: AppGroup.apiBaseUrlKey)
        }
        defaults?.synchronize()
        result(true)
      case "clearValues":
        defaults?.removeObject(forKey: AppGroup.accessTokenKey)
        defaults?.synchronize()
        result(true)
      case "drainPendingClientLogs":
        // Returns and clears the queue of on-device logs the extension stashed.
        let queue = defaults?.array(forKey: AppGroup.pendingClientLogsKey) ?? []
        defaults?.removeObject(forKey: AppGroup.pendingClientLogsKey)
        defaults?.synchronize()
        result(queue)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
