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

  /// A vertical forward edge has no horizontal bearing.
  func testVerticalTopHasNoYaw() {
    let vertical = CMRotationMatrix(
      m11: 0, m12: 0, m13: 1, m21: 0, m22: 1, m23: 0, m31: -1, m32: 0, m33: 0
    )
    XCTAssertNil(ScreenTopAttitude.project(vertical, orientation: .landscapeRight)?.yaw)
    XCTAssertNil(ScreenTopAttitude.project(vertical, orientation: .unknown))
  }
}
