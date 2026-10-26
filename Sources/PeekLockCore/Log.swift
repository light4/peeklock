import os

/// Unified logging for PeekLock.
/// View with: `log stream --level info --predicate 'subsystem == "io.i01.peeklock"'`
public enum Log {
  public static let subsystem = "io.i01.peeklock"
  static let logger = Logger(subsystem: subsystem, category: "lock")

  public static func info(_ message: String) {
    logger.notice("\(message, privacy: .public)")
  }

  public static func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
  }
}
