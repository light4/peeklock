import Foundation
import Testing

/// `peeklock` command-line behaviour (never locks input).
extension E2E {
  @Suite struct CLI {
    @Test func help() {
      let result = run([Env.cli.path, "--help"])
      #expect(result.status == 0)
      #expect(result.stdout.contains("Usage: peeklock [-b]"))
      #expect(result.stdout.contains("--app"))
    }

    @Test func version() throws {
      let result = run([Env.cli.path, "--version"])
      #expect(result.status == 0)
      let source = try String(
        contentsOf: Env.repoRoot.appendingPathComponent("Sources/PeekLockCore/Version.swift"),
        encoding: .utf8)
      let expected = try #require(
        source.split(separator: "\"").dropFirst().first.map(String.init))
      #expect(
        result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "peeklock \(expected)")
    }

    @Test func unknownOptionExits2() {
      let result = run([Env.cli.path, "--definitely-not-an-option"])
      #expect(result.status == 2)
      #expect(result.stderr.contains("unknown option --definitely-not-an-option"))
      #expect(result.stderr.contains("Usage: peeklock"))
    }

    @Test func statusReportsPermissionsAndSettings() {
      let result = run([Env.cli.path, "--status"])
      #expect(result.status == 0)
      for prefix in [
        "Accessibility: ", "Authentication: ", "Unlock hotkey: ",
        "Keep display awake while locked: ", "Secure Event Input active: ",
      ] {
        #expect(
          result.stdout.contains("\n\(prefix)") || result.stdout.hasPrefix(prefix), "\(prefix)")
      }
    }

    @Test(.enabled("PeekLock.app is running; --app would really lock") { !Env.appRunning })
    func appModeWithoutRunningAppFails() {
      let result = run([Env.cli.path, "--app"])
      #expect(result.status == 1)
      #expect(result.stderr.contains("PeekLock.app is not running"))
    }

    /// Never a fake lock: without Accessibility the CLI must exit 1 instead of locking.
    /// CI only (it opens System Settings), and only where Accessibility is missing.
    @Test(.enabled("CI without Accessibility only") { Env.inCI && !Env.accessibilityGranted })
    func refusesToLockWithoutAccessibility() {
      let result = run([Env.cli.path], timeout: 30)
      #expect(result.status == 1)
      #expect(result.stderr.contains("Accessibility permission missing"))
      #expect(result.stderr.contains("not locking"))
    }
  }
}
