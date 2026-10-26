import Foundation

/// Shared preferences for the menu bar app and the CLI (domain `io.i01.peeklock`).
public final class Settings {
  public static let domain = "io.i01.peeklock"
  public static let shared = Settings()

  public static let lockNotification = Notification.Name("io.i01.peeklock.lock")
  public static let settingsChangedNotification = Notification.Name(
    "io.i01.peeklock.settingsChanged")

  private let defaults: UserDefaults

  private enum Key {
    static let unlockHotkey = "unlockHotkey"
    static let lockHotkey = "lockHotkey"
    static let lockHotkeyEnabled = "lockHotkeyEnabled"
    static let idleMinutes = "idleMinutes"
    static let showBadge = "showBadge"
    static let lockCursor = "lockCursor"
    static let keepDisplayAwake = "keepDisplayAwake"
    static let debugAutoUnlockSeconds = "debugAutoUnlockSeconds"
  }

  init() {
    if Bundle.main.bundleIdentifier == Settings.domain {
      defaults = .standard
    } else {
      defaults = UserDefaults(suiteName: Settings.domain) ?? .standard
    }
  }

  private func hotkey(_ key: String, fallback: Hotkey) -> Hotkey {
    guard let data = defaults.data(forKey: key),
      let value = try? JSONDecoder().decode(Hotkey.self, from: data)
    else { return fallback }
    return value
  }

  private func setHotkey(_ value: Hotkey, _ key: String) {
    defaults.set(try? JSONEncoder().encode(value), forKey: key)
  }

  /// Combination that brings up Touch ID / password authentication while locked.
  public var unlockHotkey: Hotkey {
    get { hotkey(Key.unlockHotkey, fallback: .defaultUnlock) }
    set { setHotkey(newValue, Key.unlockHotkey) }
  }

  /// Global combination that locks (menu bar app only).
  public var lockHotkey: Hotkey {
    get { hotkey(Key.lockHotkey, fallback: .defaultLock) }
    set { setHotkey(newValue, Key.lockHotkey) }
  }

  public var lockHotkeyEnabled: Bool {
    get { defaults.object(forKey: Key.lockHotkeyEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.lockHotkeyEnabled) }
  }

  /// Auto-lock after this many idle minutes; 0 disables.
  public var idleMinutes: Int {
    get { max(0, defaults.integer(forKey: Key.idleMinutes)) }
    set { defaults.set(max(0, newValue), forKey: Key.idleMinutes) }
  }

  public var showBadge: Bool {
    get { defaults.object(forKey: Key.showBadge) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.showBadge) }
  }

  /// Show a padlock cursor while locked (requires briefly activating PeekLock).
  public var lockCursor: Bool {
    get { defaults.object(forKey: Key.lockCursor) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.lockCursor) }
  }

  /// Prevent idle display sleep while locked (default on).
  public var keepDisplayAwake: Bool {
    get { defaults.object(forKey: Key.keepDisplayAwake) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.keepDisplayAwake) }
  }

  /// Debug builds only: auto-unlock after N seconds (0 disables). Default 60.
  public var debugAutoUnlockSeconds: Int {
    get {
      if let env = ProcessInfo.processInfo.environment["PEEKLOCK_DEBUG_AUTOUNLOCK"],
        let value = Int(env)
      {
        return max(0, value)
      }
      return defaults.object(forKey: Key.debugAutoUnlockSeconds) as? Int ?? 60
    }
    set { defaults.set(max(0, newValue), forKey: Key.debugAutoUnlockSeconds) }
  }

  public func synchronize() { defaults.synchronize() }
}
