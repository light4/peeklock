import Foundation
import IOKit.pwr_mgt

/// Holds a `PreventUserIdleDisplaySleep` power assertion (visible in `pmset -g assertions`),
/// the same assertion `caffeinate -d` takes.
public final class DisplayAwake {
  /// Held by `LockController` while input is locked.
  public static let lockAssertionName = "PeekLock: input locked"
  /// Held while the user enables "Keep Display Awake" from the menu, independent of locking.
  public static let manualAssertionName = "PeekLock: keep display awake"

  private let name: String
  private var assertionID: IOPMAssertionID = 0
  public private(set) var isHeld = false

  public init(name: String) {
    self.name = name
  }

  /// Returns false if IOKit refused the assertion.
  @discardableResult
  public func acquire() -> Bool {
    guard !isHeld else { return true }
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      name as CFString,
      &assertionID)
    isHeld = result == kIOReturnSuccess
    return isHeld
  }

  public func release() {
    guard isHeld else { return }
    IOPMAssertionRelease(assertionID)
    isHeld = false
    assertionID = 0
  }

  deinit { release() }
}
