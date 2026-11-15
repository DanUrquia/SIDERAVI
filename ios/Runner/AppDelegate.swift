import Flutter
import Security
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
    if let registrar = registry.registrar(forPlugin: "SideraCrewIdentity") {
      CrewIdentity.register(with: registrar)
    }
  }
}

/// Persists a single Firebase identity per project and astronaut on this iOS device.
private enum CrewIdentity {
  private struct Credential: Codable {
    let uid: String
    let refreshToken: String
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "sidera_vi/crew_identity", binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler(handle)
  }

  private static func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    let arguments = call.arguments as? [String: String]
    let scope: String?
    switch call.method {
    case "read": scope = call.arguments as? String
    case "write": scope = arguments?["scope"]
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    guard let scope,
          scope.range(
            of: #"^[a-z0-9-]+\.(firebaseio\.com|firebasedatabase\.app)/ARES-0[12]$"#,
            options: .regularExpression
          ) != nil
    else {
      result(failure)
      return
    }

    let key: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.bluelionsoft.sideraVi.crew",
      kSecAttrAccount as String: scope,
    ]
    let enrollmentKey = "crewEnrollment/\(scope)"
    if call.method == "read" {
      var query = key
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      if status == errSecItemNotFound {
        UserDefaults.standard.removeObject(forKey: enrollmentKey)
        result(nil)
      } else if status == errSecSuccess, let data = item as? Data,
                let credential = try? JSONDecoder().decode(Credential.self, from: data) {
        UserDefaults.standard.set(credential.uid, forKey: enrollmentKey)
        result(["uid": credential.uid, "refreshToken": credential.refreshToken])
      } else {
        result(failure)
      }
      return
    }

    guard let uid = arguments?["uid"],
          uid.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
          let refreshToken = arguments?["refreshToken"], !refreshToken.isEmpty,
          let data = try? JSONEncoder().encode(Credential(uid: uid, refreshToken: refreshToken))
    else {
      result(failure)
      return
    }

    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      let item = key.merging(attributes) { _, value in value }
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      result(failure)
      return
    }
    // Operators can identify a connected phone using this non-secret Firebase UID.
    UserDefaults.standard.set(uid, forKey: enrollmentKey)
    result(nil)
  }

  private static var failure: FlutterError {
    FlutterError(code: "crewIdentity", message: "Device identity unavailable.", details: nil)
  }
}
