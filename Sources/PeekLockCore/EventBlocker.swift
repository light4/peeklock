import AppKit
import CoreGraphics
import Darwin

/// Swallows keyboard, mouse button, scroll, gesture and media-key events while still letting
/// the pointer move.
///
/// Two taps are used:
/// - a HID-level tap that decides by event *type* (it runs before routing, so the target
///   process is unknown there);
/// - an annotated-session tap that, while authenticating, decides by *target process*
///   (`kCGEventTargetUnixProcessID` is only filled in at that point), so input can reach the
///   Touch ID / password dialog but no other app.
public final class EventBlocker {
  public enum Mode {
    /// Everything (except pointer motion) is swallowed; the unlock hotkey is detected.
    case blocking
    /// The system authentication dialog is shown: plain typing and mouse buttons may reach the
    /// LocalAuthentication UI process only; everything else stays blocked.
    case authenticating
  }

  public var mode: Mode = .blocking
  public var unlockHotkey: Hotkey
  /// Called on the main thread when the unlock hotkey is pressed in `.blocking` mode.
  public var onUnlockHotkey: (() -> Void)?
  /// Called (main thread) for every event dropped while authenticating; for diagnostics.
  public var onAuthEventFiltered: ((_ allowed: Bool, _ pid: pid_t, _ path: String) -> Void)?

  public private(set) var blockedCount = 0
  private var hidTap: CFMachPort?
  private var hidSource: CFRunLoopSource?
  private var routeTap: CFMachPort?
  private var routeSource: CFRunLoopSource?
  private var pidCache: [pid_t: (allowed: Bool, path: String)] = [:]

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

  /// Types that may reach the authentication dialog (typing and clicking only).
  static let authAllowedTypes: Set<UInt32> = [1, 2, 3, 4, 6, 7, 10, 11, 12]

  static func mask(_ types: [UInt32]) -> CGEventMask {
    types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
  }

  /// Executable path fragments of processes that draw the LocalAuthentication dialog.
  static let authUIPathFragments = [
    "/LocalAuthentication.framework/",  // coreautha.bundle, coreauthd
    "/LocalAuthenticationUI.framework/",  // LocalAuthenticationRemoteService.xpc
    "/LocalAuthenticationCoreUI.framework/",
    "/SecurityAgent.bundle/",  // older macOS password panel
  ]

  public init(unlockHotkey: Hotkey) {
    self.unlockHotkey = unlockHotkey
  }

  public var isActive: Bool { hidTap != nil && routeTap != nil }

  /// Installs both taps. Returns false (and installs nothing) if macOS refuses either.
  @discardableResult
  public func start() -> Bool {
    if isActive { return true }
    let userInfo = Unmanaged.passUnretained(self).toOpaque()
    guard
      let hid = CGEvent.tapCreate(
        tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: EventBlocker.mask(EventBlocker.interceptedTypes),
        callback: hidCallback, userInfo: userInfo)
    else { return false }
    guard
      let route = CGEvent.tapCreate(
        tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: EventBlocker.mask(Array(EventBlocker.authAllowedTypes)),
        callback: routeCallback, userInfo: userInfo)
    else {
      CFMachPortInvalidate(hid)
      return false
    }
    hidTap = hid
    routeTap = route
    hidSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hid, 0)
    routeSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, route, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), hidSource, .commonModes)
    CFRunLoopAddSource(CFRunLoopGetMain(), routeSource, .commonModes)
    CGEvent.tapEnable(tap: hid, enable: true)
    CGEvent.tapEnable(tap: route, enable: true)
    blockedCount = 0
    pidCache = [:]
    return true
  }

  public func stop() {
    for port in [hidTap, routeTap].compactMap({ $0 }) {
      CGEvent.tapEnable(tap: port, enable: false)
      CFMachPortInvalidate(port)
    }
    for src in [hidSource, routeSource].compactMap({ $0 }) {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
    }
    hidTap = nil
    routeTap = nil
    hidSource = nil
    routeSource = nil
  }

  private func reenable(_ type: CGEventType) -> Bool {
    guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return false }
    // macOS disables slow or interrupted taps; turn them straight back on.
    for port in [hidTap, routeTap].compactMap({ $0 }) where !CGEvent.tapIsEnabled(tap: port) {
      CGEvent.tapEnable(tap: port, enable: true)
    }
    return true
  }

  /// Stage 1 (HID): decide by event type.
  fileprivate func handleHID(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if reenable(type) { return Unmanaged.passUnretained(event) }

    switch mode {
    case .authenticating:
      if EventBlocker.authAllowedTypes.contains(type.rawValue),
        !EventBlocker.isSystemShortcut(type: type, event: event)
      {
        // Routed to the target process; checked again by the annotated-session tap.
        return Unmanaged.passUnretained(event)
      }
      blockedCount += 1
      return nil

    case .blocking:
      switch type {
      case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        // Keep the pointer moving even if a button is physically held down.
        event.type = .mouseMoved
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

  /// Stage 2 (annotated session): while authenticating, only the auth UI may receive input.
  fileprivate func handleRoute(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if reenable(type) { return Unmanaged.passUnretained(event) }
    // In blocking mode the HID tap has already dropped these; never let a stray one through.
    guard mode == .authenticating else {
      blockedCount += 1
      return nil
    }
    let pid = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
    let verdict = classify(pid)
    if let report = onAuthEventFiltered {
      DispatchQueue.main.async { report(verdict.allowed, pid, verdict.path) }
    }
    if verdict.allowed { return Unmanaged.passUnretained(event) }
    blockedCount += 1
    return nil
  }

  /// ⌘ / ⌃ combinations (⌘Tab, ⌘Q, ⌥⌘Esc, ⌃⌘Q, ⌘Space, …) are never needed to type a password.
  static func isSystemShortcut(type: CGEventType, event: CGEvent) -> Bool {
    guard type == .keyDown || type == .keyUp else { return false }
    return !event.flags.intersection([.maskCommand, .maskControl]).isEmpty
  }

  private func classify(_ pid: pid_t) -> (allowed: Bool, path: String) {
    if let cached = pidCache[pid] { return cached }
    let path = EventBlocker.executablePath(pid)
    let allowed: Bool
    if pid <= 0 {
      allowed = false
    } else if pid == getpid() {
      allowed = true
    } else {
      allowed = EventBlocker.authUIPathFragments.contains { path.contains($0) }
    }
    let verdict = (allowed: allowed, path: path)
    pidCache[pid] = verdict
    return verdict
  }

  static func executablePath(_ pid: pid_t) -> String {
    guard pid > 0 else { return "" }
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return "" }
    return String(cString: buffer)
  }
}

private func hidCallback(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<EventBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    .handleHID(type: type, event: event)
}

private func routeCallback(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<EventBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    .handleRoute(type: type, event: event)
}
