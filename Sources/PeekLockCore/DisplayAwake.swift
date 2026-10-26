import Foundation
import IOKit.pwr_mgt

/// Holds a `PreventUserIdleDisplaySleep` power assertion (visible in `pmset -g assertions`).
final class DisplayAwake {
  static let assertionName = "PeekLock: input locked"
  private var assertionID: IOPMAssertionID = 0
  private(set) var isHeld = false

  /// Returns false if IOKit refused the assertion (locking still proceeds).
  @discardableResult
  func acquire() -> Bool {
    guard !isHeld else { return true }
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      DisplayAwake.assertionName as CFString,
      &assertionID)
    isHeld = result == kIOReturnSuccess
    return isHeld
  }

  func release() {
    guard isHeld else { return }
    IOPMAssertionRelease(assertionID)
    isHeld = false
    assertionID = 0
  }

  deinit { release() }
}
