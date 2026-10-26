import AppKit
import CoreGraphics

/// Swallows keyboard, mouse button, scroll, gesture and media-key events with a HID-level
/// `CGEventTap`, while still letting the pointer move.
public final class EventBlocker {
  public enum Mode {
    /// Everything (except pointer motion) is swallowed; the unlock hotkey is detected.
    case blocking
    /// Everything passes through (used while the system authentication dialog is shown).
    case passthrough
  }

  public var mode: Mode = .blocking
  public var unlockHotkey: Hotkey
  /// Called on the main thread when the unlock hotkey is pressed in `.blocking` mode.
  public var onUnlockHotkey: (() -> Void)?
  /// Called on the main thread when the pointer moves while blocking.
  public var onPointerMoved: (() -> Void)?

  public private(set) var blockedCount = 0
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  /// Raw `CGEventType` values that are intercepted. `mouseMoved` (5) is deliberately absent.
  static let interceptedTypes: [UInt32] = [
    1, 2, 3, 4,  // left/right mouse down/up
    6, 7,  // left/right mouse dragged (converted to mouseMoved)
    10, 11, 12,  // keyDown, keyUp, flagsChanged
    14,  // NX_SYSDEFINED: media / brightness / volume keys
    18, 19, 20,  // rotate, beginGesture, endGesture
    22, 23, 24,  // scrollWheel, tabletPointer, tabletProximity
    25, 26, 27,  // other mouse down/up/dragged
    29, 30, 31, 32, 34,  // gesture, magnify, swipe, smartMagnify, pressure
  ]

  static var eventMask: CGEventMask {
    interceptedTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
  }

  public init(unlockHotkey: Hotkey) {
    self.unlockHotkey = unlockHotkey
  }

  public var isActive: Bool { tap != nil }

  /// Installs the tap. Returns false if macOS refuses (no Accessibility permission).
  @discardableResult
  public func start() -> Bool {
    if tap != nil { return true }
    let userInfo = Unmanaged.passUnretained(self).toOpaque()
    guard
      let port = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: EventBlocker.eventMask,
        callback: eventBlockerCallback,
        userInfo: userInfo)
    else { return false }
    tap = port
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    blockedCount = 0
    return true
  }

  public func stop() {
    if let port = tap {
      CGEvent.tapEnable(tap: port, enable: false)
      CFMachPortInvalidate(port)
    }
    if let src = source {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
    }
    tap = nil
    source = nil
  }

  fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // macOS disables slow or interrupted taps; turn it straight back on.
      if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
      return Unmanaged.passUnretained(event)
    default:
      break
    }

    if mode == .passthrough { return Unmanaged.passUnretained(event) }

    switch type {
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      // Keep the pointer moving even if a button is physically held down.
      event.type = .mouseMoved
      onPointerMoved?()
      return Unmanaged.passUnretained(event)
    case .keyDown:
      let code = event.getIntegerValueField(.keyboardEventKeycode)
      let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
      if !isRepeat, unlockHotkey.matches(keyCode: code, flags: event.flags) {
        DispatchQueue.main.async { [weak self] in self?.onUnlockHotkey?() }
      }
    default:
      break
    }
    blockedCount += 1
    return nil
  }
}

private func eventBlockerCallback(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let blocker = Unmanaged<EventBlocker>.fromOpaque(userInfo).takeUnretainedValue()
  return blocker.handle(type: type, event: event)
}
