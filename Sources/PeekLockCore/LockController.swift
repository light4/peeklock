import AppKit

/// Coordinates the event tap, overlays and authentication.
public final class LockController {
  public enum State: Equatable {
    case unlocked
    case locked
    case authenticating
  }

  public enum LockError: Error, CustomStringConvertible {
    case accessibilityDenied
    case tapUnavailable
    case alreadyLocked

    public var description: String {
      switch self {
      case .accessibilityDenied:
        return "Accessibility permission is missing; refusing to lock."
      case .tapUnavailable:
        return "macOS refused to install the event tap; refusing to lock."
      case .alreadyLocked:
        return "Already locked."
      }
    }
  }

  public private(set) var state: State = .unlocked {
    didSet { if oldValue != state { onStateChange?(state) } }
  }

  public var onStateChange: ((State) -> Void)?
  /// Diagnostic messages (auth failures, warnings).
  public var onMessage: ((String) -> Void)?

  private let settings: Settings
  private let blocker: EventBlocker
  private let overlays = OverlayManager()
  private let authenticator = Authenticator()
  private var previousApp: NSRunningApplication?
  private var debugTimer: Timer?
  private var unlockHotkey: Hotkey
  private var reportedAuthTargets: Set<pid_t> = []

  public init(settings: Settings = .shared) {
    self.settings = settings
    unlockHotkey = settings.unlockHotkey
    blocker = EventBlocker(unlockHotkey: unlockHotkey)
    blocker.onUnlockHotkey = { [weak self] in self?.requestUnlock() }
    blocker.onAuthEventFiltered = { [weak self] allowed, pid, path in
      guard let self, !self.reportedAuthTargets.contains(pid) else { return }
      self.reportedAuthTargets.insert(pid)
      let name = path.isEmpty ? "?" : path
      self.onMessage?(
        "During authentication, input to pid \(pid) (\(name)) was \(allowed ? "allowed" : "blocked")."
      )
    }
  }

  public var isLocked: Bool { state != .unlocked }

  private var lockedBadgeText: String { "Locked · \(unlockHotkey) to unlock" }

  /// Starts blocking input. Never enters a locked state unless the tap is really installed.
  public func lock(blank: Bool = false) throws {
    guard state == .unlocked else { throw LockError.alreadyLocked }
    guard Permissions.accessibilityGranted else { throw LockError.accessibilityDenied }
    unlockHotkey = settings.unlockHotkey
    blocker.unlockHotkey = unlockHotkey
    blocker.mode = .blocking
    guard blocker.start() else { throw LockError.tapUnavailable }

    if Permissions.secureInputEnabled {
      onMessage?(
        "Warning: Secure Event Input is enabled by another app; keystrokes may bypass PeekLock.")
    }

    let front = NSWorkspace.shared.frontmostApplication
    previousApp =
      front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    overlays.show(
      blank: blank, useCursor: settings.lockCursor, showBadge: settings.showBadge,
      badgeText: lockedBadgeText)
    state = .locked
    armDebugAutoUnlock()
  }

  /// Invoked by the unlock hotkey: shows the Touch ID / password dialog.
  public func requestUnlock() {
    guard state == .locked else { return }
    state = .authenticating
    // Input may reach only the LocalAuthentication dialog; every other app stays locked.
    reportedAuthTargets = []
    blocker.mode = .authenticating
    overlays.setCoversVisible(false)
    overlays.setBadgeText("Authenticating…")
    NSApp.activate(ignoringOtherApps: true)
    authenticator.authenticate(reason: "unlock PeekLock") { [weak self] outcome in
      guard let self else { return }
      switch outcome {
      case .success:
        self.unlock()
      case .cancelled:
        self.relock(message: nil)
      case .timedOut:
        self.relock(message: "Authentication timed out; still locked.")
      case .failed(let reason):
        self.relock(message: "Authentication failed: \(reason)")
      }
    }
  }

  private func relock(message: String?) {
    guard state == .authenticating else { return }
    blocker.mode = .blocking
    overlays.setBadgeText(lockedBadgeText)
    overlays.setCoversVisible(true)
    state = .locked
    if let message { onMessage?(message) }
  }

  /// Unconditionally releases the lock (after successful auth, debug timer or termination).
  public func unlock() {
    guard state != .unlocked else { return }
    debugTimer?.invalidate()
    debugTimer = nil
    authenticator.cancel()
    blocker.stop()
    overlays.hide()
    NSCursor.arrow.set()
    state = .unlocked
    previousApp?.activate()
    previousApp = nil
  }

  private func armDebugAutoUnlock() {
    #if DEBUG
      let seconds = settings.debugAutoUnlockSeconds
      guard seconds > 0 else { return }
      onMessage?("DEBUG build: auto-unlocking in \(seconds)s (safety net).")
      debugTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) {
        [weak self] _ in
        self?.onMessage?("DEBUG build: safety auto-unlock fired.")
        self?.unlock()
      }
    #endif
  }
}
