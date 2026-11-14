import CoreLocation
import CoreMotion
import Flutter
import UIKit

/// Samples Earth location only while a foreground diagnostic is running.
private final class DiagnosticLocation: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private(set) var running = false
  private var locations: [[String: Any]] = []
  private var heading: CLHeading?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    manager.headingFilter = kCLHeadingFilterNone
  }

  /// Requests foreground permission from the explicit Start Test action.
  func start() {
    running = true
    clear()
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    }
    updateAuthorization()
  }

  /// Stops both Core Location streams without changing permission settings.
  func stop() {
    running = false
    manager.stopUpdatingLocation()
    manager.stopUpdatingHeading()
    clear()
  }

  /// Discards pending samples from the previous measurement window.
  func clear() {
    locations.removeAll()
    heading = nil
  }

  /// Selects the screen's top edge for compass measurements as it rotates.
  func orient(_ orientation: UIInterfaceOrientation) {
    let axes: CLDeviceOrientation
    switch orientation {
    case .landscapeLeft: axes = .landscapeRight
    case .landscapeRight: axes = .landscapeLeft
    case .portraitUpsideDown: axes = .portraitUpsideDown
    default: axes = .portrait
    }
    if manager.headingOrientation != axes {
      manager.headingOrientation = axes
      heading = nil
    }
  }

  /// Returns permission and runtime availability with the pending observations.
  func snapshot(servicesEnabled: Bool?) -> [String: Any] {
    let authorization: String
    switch manager.authorizationStatus {
    case .notDetermined: authorization = "Not determined"
    case .restricted: authorization = "Restricted"
    case .denied: authorization = "Denied"
    case .authorizedAlways, .authorizedWhenInUse: authorization = "Authorized"
    @unknown default: authorization = "Unknown"
    }
    var data: [String: Any] = [
      "authorization": authorization,
      "precise": authorization == "Authorized" && manager.accuracyAuthorization == .fullAccuracy,
      "locations": locations,
      "compass": CLLocationManager.headingAvailable()
    ]
    if let servicesEnabled { data["services"] = servicesEnabled }
    if let heading, heading.trueHeading >= 0, (0...25).contains(heading.headingAccuracy),
       (0...5).contains(Date().timeIntervalSince(heading.timestamp)) {
      data["heading"] = heading.trueHeading
      data["headingAccuracy"] = heading.headingAccuracy
    }
    locations.removeAll(keepingCapacity: true)
    return data
  }

  /// Starts authorized streams only during the active foreground test.
  private func updateAuthorization() {
    guard running else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.startUpdatingLocation()
      if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    default:
      manager.stopUpdatingLocation()
      manager.stopUpdatingHeading()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    updateAuthorization()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations updates: [CLLocation]) {
    guard running else { return }
    for sample in updates {
      var entry: [String: Any] = [
        "latitude": sample.coordinate.latitude,
        "longitude": sample.coordinate.longitude,
        "accuracy": sample.horizontalAccuracy,
        "time": sample.timestamp.timeIntervalSince1970,
        "received": Date().timeIntervalSince1970
      ]
      if sample.speed >= 0 { entry["speed"] = sample.speed }
      if sample.speedAccuracy >= 0 { entry["speedAccuracy"] = sample.speedAccuracy }
      if sample.course >= 0 { entry["course"] = sample.course }
      if sample.courseAccuracy >= 0 { entry["courseAccuracy"] = sample.courseAccuracy }
      locations.append(entry)
    }
    if locations.count > 64 { locations.removeFirst(locations.count - 64) }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    if running { heading = newHeading }
  }
}

/// Projects the current interface top edge into Core Motion's horizontal frame.
private final class DiagnosticMotion {
  private let manager = CMMotionManager()
  private var samples: [[String: Any]] = []
  private var presentation: UIInterfaceOrientation = .unknown
  private var bootEpoch = 0.0

  /// Starts relative device motion in the arbitrary north-free frame.
  func start(orientation: UIInterfaceOrientation) {
    presentation = orientation
    clear()
    guard manager.isDeviceMotionAvailable,
          CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical)
    else { return }
    bootEpoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    manager.deviceMotionUpdateInterval = 0.1
    manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
      if let motion { self?.record(motion) }
    }
  }

  /// Ends delivery and discards unconsumed native motion samples.
  func stop() {
    manager.stopDeviceMotionUpdates()
    clear()
  }

  func clear() { samples.removeAll(keepingCapacity: true) }

  /// Drains bounded samples and reports the availability of the underlying sensors.
  func snapshot(orientation: UIInterfaceOrientation) -> [String: Any] {
    if presentation != orientation {
      presentation = orientation
      clear()
    }
    let data: [String: Any] = [
      "motion": manager.isDeviceMotionAvailable &&
        CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical),
      "gyro": manager.isGyroAvailable,
      "accelerometer": manager.isAccelerometerAvailable,
      "magnetometer": manager.isMagnetometerAvailable,
      "orientations": samples
    ]
    clear()
    return data
  }

  /// Converts device axes to the screen top vector using the attitude matrix.
  private func record(_ motion: CMDeviceMotion) {
    guard manager.isDeviceMotionActive else { return }
    let matrix = motion.attitude.rotationMatrix
    let frame: String
    let horizontalX: Double
    let horizontalY: Double
    switch presentation {
    case .landscapeLeft: (frame, horizontalX, horizontalY) = ("Landscape left", -matrix.m11, -matrix.m12)
    case .landscapeRight: (frame, horizontalX, horizontalY) = ("Landscape right", matrix.m11, matrix.m12)
    case .portraitUpsideDown: (frame, horizontalX, horizontalY) = ("Portrait upside down", -matrix.m21, -matrix.m22)
    case .portrait: (frame, horizontalX, horizontalY) = ("Portrait", matrix.m21, matrix.m22)
    default: return
    }
    let degrees = 180 / Double.pi
    let rate = motion.rotationRate
    let sampleTime = bootEpoch + motion.timestamp
    var sample: [String: Any] = [
      "time": sampleTime,
      "received": Date().timeIntervalSince1970,
      "frame": frame,
      "pitch": motion.attitude.pitch * degrees,
      "roll": motion.attitude.roll * degrees,
      "rotationRate": sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z) * degrees
    ]
    // When the screen top points skyward its horizontal bearing is undefined.
    if hypot(horizontalX, horizontalY) >= 0.25 {
      sample["yaw"] = atan2(-horizontalY, horizontalX) * degrees
    }
    samples.append(sample)
    if samples.count > 48 { samples.removeFirst(samples.count - 48) }
  }
}

/// Registers one foreground-only diagnostic bridge with the scene's Flutter engine.
final class SensorDiagnostics: NSObject, FlutterPlugin {
  private var location: DiagnosticLocation?
  private let motion = DiagnosticMotion()
  private var servicesEnabled: Bool?
  private var checkingServices = false
  private var exporting = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "sidera_vi/sensor_diagnostics", binaryMessenger: registrar.messenger())
    let bridge = SensorDiagnostics()
    registrar.addMethodCallDelegate(bridge, channel: channel)
    NotificationCenter.default.addObserver(
      bridge, selector: #selector(stop), name: UIApplication.didEnterBackgroundNotification, object: nil
    )
  }

  /// Dispatches explicit test actions and reads samples without streaming in the background.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if location == nil { location = DiagnosticLocation() }
    let orientation = window?.windowScene?.interfaceOrientation ?? .unknown
    switch call.method {
    case "start":
      guard UIApplication.shared.applicationState != .background else {
        result(FlutterError(code: "background", message: "Open the app to start the test.", details: nil))
        return
      }
      location?.orient(orientation)
      location?.start()
      motion.start(orientation: orientation)
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "reset":
      location?.clear()
      motion.clear()
      result(nil)
    case "clearMotion":
      motion.clear()
      result(nil)
    case "snapshot":
      readServicesAvailability()
      location?.orient(orientation)
      let locationData = location?.snapshot(servicesEnabled: servicesEnabled) ?? [:]
      let motionData = motion.snapshot(orientation: orientation)
      result(locationData.merging(motionData) { _, latest in latest }.merging([
        "model": modelIdentifier,
        "os": UIDevice.current.systemVersion
      ]) { _, latest in latest })
    case "export":
      guard let content = call.arguments as? String else {
        result(FlutterError(code: "invalid_report", message: "Report is unavailable.", details: nil))
        return
      }
      shareReport(content, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Stops both services when the diagnostic ends or the app enters the background.
  @objc private func stop() {
    location?.stop()
    motion.stop()
  }

  /// Reads the system-wide Location Services switch off the main thread.
  private func readServicesAvailability() {
    guard !checkingServices else { return }
    checkingServices = true
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let enabled = CLLocationManager.locationServicesEnabled()
      DispatchQueue.main.async {
        self?.servicesEnabled = enabled
        self?.checkingServices = false
      }
    }
  }

  private var window: UIWindow? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }?
      .windows.first(where: \.isKeyWindow)
  }

  /// Uses the hardware family identifier without device names or serial numbers.
  private var modelIdentifier: String {
    var system = utsname()
    uname(&system)
    return withUnsafeBytes(of: system.machine) { bytes in
      String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
  }

  /// Writes the report only for an explicit share and removes the temporary copy afterward.
  private func shareReport(_ report: String, result: @escaping FlutterResult) {
    guard !exporting, let window, var presenter = window.rootViewController else {
      result(FlutterError(code: "share_unavailable", message: "Report sharing is unavailable.", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("sidera-sensor-report-\(UUID().uuidString).json")
    do {
      try report.write(to: file, atomically: true, encoding: .utf8)
    } catch {
      result(FlutterError(code: "write_failed", message: "Could not create the report.", details: nil))
      return
    }
    exporting = true
    let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    share.popoverPresentationController?.sourceView = presenter.view
    share.popoverPresentationController?.sourceRect = CGRect(
      x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1
    )
    share.completionWithItemsHandler = { [weak self] _, _, _, _ in
      try? FileManager.default.removeItem(at: file)
      self?.exporting = false
    }
    presenter.present(share, animated: true)
    result(nil)
  }
}
