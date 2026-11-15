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
  private var includesHeading = false
  private var callbackBatch = 0

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    manager.headingFilter = kCLHeadingFilterNone
  }

  /// Requests foreground permission from the explicit Start Test action.
  func start(includesHeading: Bool) {
    self.includesHeading = includesHeading
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
      if includesHeading && CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
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
    callbackBatch += 1
    for sample in updates {
      var entry: [String: Any] = [
        "latitude": sample.coordinate.latitude,
        "longitude": sample.coordinate.longitude,
        "accuracy": sample.horizontalAccuracy,
        "time": sample.timestamp.timeIntervalSince1970,
        "received": Date().timeIntervalSince1970,
        "callbackBatch": callbackBatch
      ]
      if let source = sample.sourceInformation {
        entry["simulatedBySoftware"] = source.isSimulatedBySoftware
        entry["producedByAccessory"] = source.isProducedByAccessory
      }
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
    guard let screen = ScreenTopAttitude.project(
      motion.attitude.rotationMatrix, orientation: presentation
    ) else { return }
    let degrees = 180 / Double.pi
    let rate = motion.rotationRate
    let sampleTime = bootEpoch + motion.timestamp
    var sample: [String: Any] = [
      "time": sampleTime,
      "received": Date().timeIntervalSince1970,
      "frame": screen.frame,
      "pitch": motion.attitude.pitch * degrees,
      "roll": motion.attitude.roll * degrees,
      "rotationRate": sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z) * degrees
    ]
    if let yaw = screen.yaw { sample["yaw"] = yaw }
    samples.append(sample)
    if samples.count > 48 { samples.removeFirst(samples.count - 48) }
  }
}

/// Converts the UI's current physical top edge into a clockwise relative azimuth.
enum ScreenTopAttitude {
  static func project(
    _ matrix: CMRotationMatrix, orientation: UIInterfaceOrientation
  ) -> (frame: String, yaw: Double?)? {
    let frame: String
    let x: Double
    let y: Double
    // The rows of Core Motion's reference-to-device matrix express the device
    // axes in the reference frame. UIKit landscape senses are screen-relative.
    switch orientation {
    case .landscapeLeft: (frame, x, y) = ("Landscape left", -matrix.m11, -matrix.m12)
    case .landscapeRight: (frame, x, y) = ("Landscape right", matrix.m11, matrix.m12)
    case .portraitUpsideDown: (frame, x, y) = ("Portrait upside down", -matrix.m21, -matrix.m22)
    case .portrait: (frame, x, y) = ("Portrait", matrix.m21, matrix.m22)
    default: return nil
    }
    // The horizontal azimuth vanishes if the top edge points nearly vertically.
    let yaw = hypot(x, y) >= 0.25 ? atan2(-y, x) * 180 / Double.pi : nil
    return (frame, yaw)
  }
}

/// Captures cumulative CMPedometer data for one foreground measurement window.
private final class DiagnosticPedometer {
  private let pedometer = CMPedometer()
  private var generation = 0
  private var running = false
  private var samples: [[String: Any]] = []
  private var error: [String: Any]?
  private var captureQuery: [String: Any]?
  private var started: Date?

  /// Stops older callbacks and starts an independent count from the current time.
  func start() {
    stop()
    guard CMPedometer.isStepCountingAvailable() else { return }
    let authorization = CMPedometer.authorizationStatus()
    guard authorization != .denied && authorization != .restricted else { return }
    let from = Date()
    let current = generation
    started = from
    running = true
    pedometer.startUpdates(from: from) { [weak self] data, failure in
      DispatchQueue.main.async {
        guard let self, self.running, self.generation == current else { return }
        if let failure = failure as NSError? {
          self.error = ["domain": failure.domain, "code": failure.code]
          self.pedometer.stopUpdates()
          self.running = false
          return
        }
        guard let data else { return }
        var sample: [String: Any] = [
          "start": data.startDate.timeIntervalSince1970,
          "end": data.endDate.timeIntervalSince1970,
          "received": Date().timeIntervalSince1970,
          "steps": data.numberOfSteps.intValue
        ]
        if let distance = data.distance { sample["distance"] = distance.doubleValue }
        if let cadence = data.currentCadence { sample["cadence"] = cadence.doubleValue }
        self.samples.append(sample)
        if self.samples.count > 32 { self.samples.removeFirst(self.samples.count - 32) }
      }
    }
  }

  /// Clears the buffer and invalidates callbacks racing a mode or scene change.
  func stop() {
    generation += 1
    if running { pedometer.stopUpdates() }
    running = false
    started = nil
    error = nil
    captureQuery = nil
    samples.removeAll(keepingCapacity: true)
  }

  /// Queries only the current opt-in foreground window when the live feed failed.
  func finishCapture(_ window: [String: Double], completion: @escaping () -> Void) {
    guard let from = started, let captureStart = window["start"], let captureEnd = window["end"],
          captureStart.isFinite, captureEnd.isFinite,
          from.timeIntervalSince1970 >= captureStart,
          from.timeIntervalSince1970 < captureEnd,
          captureEnd <= Date().timeIntervalSince1970,
          CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .authorized
    else {
      captureQuery = ["outcome": "unavailable"]
      completion()
      return
    }
    let current = generation
    let end = Date(timeIntervalSince1970: captureEnd)
    pedometer.queryPedometerData(from: from, to: end) { [weak self] data, failure in
      DispatchQueue.main.async {
        defer { completion() }
        guard let self, self.generation == current else { return }
        if let failure = failure as NSError? {
          self.captureQuery = ["outcome": "error", "domain": failure.domain, "code": failure.code]
          return
        }
        guard let data else {
          self.captureQuery = ["outcome": "noData"]
          return
        }
        var observation: [String: Any] = [
          "outcome": "measured",
          "start": data.startDate.timeIntervalSince1970,
          "end": data.endDate.timeIntervalSince1970,
          "steps": data.numberOfSteps.intValue
        ]
        if let distance = data.distance { observation["distance"] = distance.doubleValue }
        self.captureQuery = observation
      }
    }
  }

  /// Delivers new samples once, with hardware flags and authorization.
  func snapshot() -> [String: Any] {
    let authorization = CMPedometer.authorizationStatus()
    let state: String
    switch authorization {
    case .authorized: state = "authorized"
    case .denied: state = "denied"
    case .restricted: state = "restricted"
    case .notDetermined: state = "notDetermined"
    @unknown default: state = "unknown"
    }
    var data: [String: Any] = [
      "stream": generation,
      "running": running,
      "stepCounting": CMPedometer.isStepCountingAvailable(),
      "distance": CMPedometer.isDistanceAvailable(),
      "cadence": CMPedometer.isCadenceAvailable(),
      "authorization": state,
      "samples": samples
    ]
    if let started { data["started"] = started.timeIntervalSince1970 }
    if let error { data["error"] = error }
    if let captureQuery { data["captureQuery"] = captureQuery }
    captureQuery = nil
    samples.removeAll(keepingCapacity: true)
    return data
  }
}

/// Registers one foreground-only diagnostic bridge with the scene's Flutter engine.
final class SensorDiagnostics: NSObject, FlutterPlugin {
  private var location: DiagnosticLocation?
  private let motion = DiagnosticMotion()
  private let pedometer = DiagnosticPedometer()
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
    case "start", "startMotion", "startLocation":
      guard UIApplication.shared.applicationState != .background else {
        result(FlutterError(code: "background", message: "Open the app to start the test.", details: nil))
        return
      }
      location?.orient(orientation)
      if call.method != "startMotion" {
        location?.start(includesHeading: call.method == "start")
      }
      if call.method == "startLocation" { pedometer.start() }
      if call.method != "startLocation" {
        motion.start(orientation: orientation)
      }
      result(nil)
    case "restartPedometer":
      if location?.running == true && UIApplication.shared.applicationState != .background {
        pedometer.start()
      }
      result(nil)
    case "finishPedometerCapture":
      guard UIApplication.shared.applicationState != .background,
            let argument = call.arguments as? String,
            let data = argument.data(using: .utf8),
            let window = try? JSONDecoder().decode([String: Double].self, from: data)
      else {
        result(FlutterError(code: "invalid_pedometer_capture", message: "Capture window is unavailable.", details: nil))
        return
      }
      pedometer.finishCapture(window) { result(nil) }
    case "stopLocation":
      location?.stop()
      pedometer.stop()
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
        "os": UIDevice.current.systemVersion,
        "stepCounting": CMPedometer.isStepCountingAvailable(),
        "pedometerDistance": CMPedometer.isDistanceAvailable(),
        "pedometerAuthorization": CMPedometer.authorizationStatus().rawValue,
        "pedometer": pedometer.snapshot()
      ]) { _, latest in latest })
    case "export", "exportMovement":
      guard let content = call.arguments as? String else {
        result(FlutterError(code: "invalid_report", message: "Report is unavailable.", details: nil))
        return
      }
      let kind = call.method == "exportMovement" ? "movement" : "sensor"
      shareReport(content, kind: kind, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Stops all foreground sensor streams when the app enters the background.
  @objc private func stop() {
    location?.stop()
    motion.stop()
    pedometer.stop()
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
  private func shareReport(_ report: String, kind: String, result: @escaping FlutterResult) {
    guard !exporting, let window, var presenter = window.rootViewController else {
      result(FlutterError(code: "share_unavailable", message: "Report sharing is unavailable.", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("sidera-\(kind)-report-\(UUID().uuidString).json")
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
