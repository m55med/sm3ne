import Foundation

/// Keys + helpers for the App Group container shared between the main app and
/// the Share Extension. This file has membership on BOTH the `Runner` and
/// `ShareExtension` targets so the two processes agree on the contract.
///
/// IMPORTANT: keep this file free of any `import Flutter`. The ShareExtension
/// target does NOT link the Flutter framework, so the Flutter-facing bridge
/// (`AppGroupBridgePlugin`) lives in a Runner-only file instead.
enum AppGroup {
  static let id = "group.com.bisawtak.bisawtak"

  // Auth slice mirrored from Flutter (see lib/core/services/app_group_bridge.dart).
  static let accessTokenKey = "access_token"
  static let apiBaseUrlKey = "api_base_url"

  // Share hand-off slot (written by the extension, drained by SceneDelegate).
  static let sharedAudioPathKey = "shared_audio_path"

  // Queue of on-device transcriptions the extension produced while the app
  // was closed. The app flushes these to POST /transcriptions/log on next
  // launch so the history (and admin dashboards) stay complete even though the
  // extension itself can't reliably refresh an expired token.
  static let pendingClientLogsKey = "pending_client_logs"

  static var defaults: UserDefaults? { UserDefaults(suiteName: id) }

  static func apiBaseUrl() -> String {
    let v = defaults?.string(forKey: apiBaseUrlKey) ?? ""
    return v.isEmpty ? "https://voice.neojeen.com/api/v1" : v
  }

  static func accessToken() -> String? {
    let v = defaults?.string(forKey: accessTokenKey) ?? ""
    return v.isEmpty ? nil : v
  }
}
