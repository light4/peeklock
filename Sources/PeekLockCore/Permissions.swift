import AppKit
import ApplicationServices
import Carbon

/// Checks the TCC permissions needed for an event-swallowing tap.
public enum Permissions {
  public static let accessibilityURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
  public static let inputMonitoringURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

  /// Required: an active (event-modifying) tap needs Accessibility.
  public static var accessibilityGranted: Bool { AXIsProcessTrusted() }

  /// Informational: listen-only keyboard access.
  public static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

  /// When Secure Event Input is on (e.g. a password field is focused), macOS hides keystrokes
  /// from event taps, so keyboard blocking is not reliable.
  public static var secureInputEnabled: Bool { IsSecureEventInputEnabled() }

  /// Registers PeekLock in both privacy panes and shows the system prompt if needed.
  public static func request() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    _ = CGRequestListenEventAccess()
  }

  public static func openAccessibilitySettings() { NSWorkspace.shared.open(accessibilityURL) }
  public static func openInputMonitoringSettings() { NSWorkspace.shared.open(inputMonitoringURL) }

  public static var summary: String {
    "Accessibility: \(accessibilityGranted ? "granted" : "MISSING"), "
      + "Input Monitoring: \(inputMonitoringGranted ? "granted" : "missing")"
  }
}
