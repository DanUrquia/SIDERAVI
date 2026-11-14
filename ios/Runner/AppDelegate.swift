import Flutter
import UIKit

/// Bridges UIKit application startup to Flutter's scene-owned view controller.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterPluginRegistrant {
  /// Gives Flutter 3.35 the registrant before UIKit loads the scene storyboard.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    pluginRegistrant = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Registers plugins on the registry from the scene's Flutter view controller.
  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "SideraSensorDiagnostics") {
      SensorDiagnostics.register(with: registrar)
    }
  }
}
