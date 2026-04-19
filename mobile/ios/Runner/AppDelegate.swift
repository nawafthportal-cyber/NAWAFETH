import Flutter
import FirebaseCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "nawafeth/deep_links"
  private var deepLinkChannel: FlutterMethodChannel?
  private var initialLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      deepLinkChannel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: controller.binaryMessenger
      )
      deepLinkChannel?.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialLink" {
          result(self?.initialLink)
          self?.initialLink = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    let link = url.absoluteString
    if deepLinkChannel == nil {
      initialLink = link
    } else {
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: link)
    }
    return true
  }
}
