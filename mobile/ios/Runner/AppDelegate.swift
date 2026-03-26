import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
}
