import CoreMotion
import UIKit
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  /// A clockwise turn has the same relative sign in both landscape layouts.
  func testLandscapeScreenTop() throws {
    let initial = CMRotationMatrix(
      m11: 1, m12: 0, m13: 0, m21: 0, m22: 1, m23: 0, m31: 0, m32: 0, m33: 1
    )
    let clockwise = CMRotationMatrix(
      m11: 0, m12: -1, m13: 0, m21: 1, m22: 0, m23: 0, m31: 0, m32: 0, m33: 1
    )
    let orientations: [UIInterfaceOrientation] = [.landscapeLeft, .landscapeRight]
    for orientation in orientations {
      let from = try XCTUnwrap(ScreenTopAttitude.project(initial, orientation: orientation)?.yaw)
      let to = try XCTUnwrap(ScreenTopAttitude.project(clockwise, orientation: orientation)?.yaw)
      let delta = to - from
      XCTAssertEqual(delta < 0 ? delta + 360 : delta, 90, accuracy: 0.0001)
    }
    let opposite = try XCTUnwrap(ScreenTopAttitude.project(initial, orientation: .landscapeLeft)?.yaw)
    XCTAssertEqual(abs(opposite), 180, accuracy: 0.0001)
  }

  func testWalkingCaptureKeepsBoundedRowsAndDrainsWithoutLosingTiming() throws {
    let capture = WalkingMotionCapture(capacity: 2, started: 100, uptime: 20)
    let values = Array(repeating: 0.0, count: 13)
    capture.append(at: 19, values: values, orientation: .portrait)
    capture.append(at: 20.02, values: values, orientation: .landscapeLeft)
    capture.append(at: 20.04, values: values, orientation: .landscapeLeft)
    capture.append(at: 20.04, values: values, orientation: .landscapeLeft)
    capture.append(at: 20.16, values: values, orientation: .landscapeRight)
    let batch = capture.drain()
    let rows = try XCTUnwrap(batch["samples"] as? [[Double]])
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(rows[0].count, 16)
    XCTAssertEqual(rows[0][0], 20.04, accuracy: 0.0001)
    XCTAssertEqual(rows[1][14], 0.12, accuracy: 0.0001)
    XCTAssertEqual(rows[1][15], Double(UIInterfaceOrientation.landscapeRight.rawValue))
    XCTAssertEqual(batch["nativeDropped"] as? Int, 1)
    XCTAssertEqual((capture.drain()["samples"] as? [[Double]])?.count, 0)

    capture.append(at: 20.18, values: values, orientation: .landscapeRight)
    capture.finish(reason: "appInactive", ended: 101, uptime: 20.2)
    capture.finish(reason: "operator", ended: 103, uptime: 20.5)
    capture.append(at: 20.3, values: values, orientation: .landscapeRight)
    let stopped = capture.drain()
    XCTAssertEqual(stopped["active"] as? Bool, false)
    XCTAssertEqual(stopped["reason"] as? String, "appInactive")
    XCTAssertEqual((stopped["samples"] as? [[Double]])?.count, 1)
    XCTAssertEqual(stopped["endUptime"] as? Double, 20.2)
  }

  func testWalkingCaptureClosesAtTimeLimit() {
    let capture = WalkingMotionCapture(started: 100, uptime: 10)
    capture.append(at: 100.1, values: Array(repeating: 0.0, count: 13), orientation: .landscapeLeft)
    let batch = capture.drain()
    XCTAssertEqual(batch["active"] as? Bool, false)
    XCTAssertEqual(batch["reason"] as? String, "timeLimit")
    XCTAssertEqual((batch["samples"] as? [[Double]])?.count, 0)
  }

  /// A vertical forward edge has no horizontal bearing.
  func testVerticalTopHasNoYaw() {
    let vertical = CMRotationMatrix(
      m11: 0, m12: 0, m13: 1, m21: 0, m22: 1, m23: 0, m31: -1, m32: 0, m33: 0
    )
    XCTAssertNil(ScreenTopAttitude.project(vertical, orientation: .landscapeRight)?.yaw)
    XCTAssertNil(ScreenTopAttitude.project(vertical, orientation: .unknown))
  }
}
