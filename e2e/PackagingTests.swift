import AppKit
import Foundation
import Testing

/// Packaging: run scripts/package.swift on the already-built debug products and inspect / launch
/// the resulting PeekLock.app.
extension E2E {
  @Suite struct Packaging {
    /// Packaged once for the whole suite (a fresh temp directory per test run).
    static let packaged: Result<URL, PackagingError> = {
      let output = FileManager.default.temporaryDirectory
        .appendingPathComponent("peeklock-e2e-\(ProcessInfo.processInfo.processIdentifier)")
      var argv = [
        "swift", "scripts/package.swift", "--debug", "--zip",
        "--bin-path", Env.productsDirectory.path, "--output", output.path,
      ]
      if !Env.hasSigningKeychain { argv.append("--adhoc") }
      let result = run(argv, timeout: 600)
      guard result.status == 0 else {
        return .failure(PackagingError(log: result.stdout + result.stderr))
      }
      return .success(output.appendingPathComponent("PeekLock.app"))
    }()

    struct PackagingError: Error, CustomStringConvertible {
      let log: String
      var description: String { "package.swift failed:\n\(log)" }
    }

    var app: URL { get throws { try Self.packaged.get() } }

    @Test func layout() throws {
      let contents = try app.appendingPathComponent("Contents")
      let fm = FileManager.default
      #expect(fm.isExecutableFile(atPath: contents.appendingPathComponent("MacOS/PeekLock").path))
      #expect(fm.isExecutableFile(atPath: contents.appendingPathComponent("Helpers/peeklock").path))
      #expect(fm.fileExists(atPath: contents.appendingPathComponent("Resources/AppIcon.icns").path))
      // Regression: on case-insensitive APFS, MacOS/peeklock would overwrite MacOS/PeekLock.
      #expect(
        try fm.contentsOfDirectory(atPath: contents.appendingPathComponent("MacOS").path) == [
          "PeekLock"
        ])
    }

    @Test func infoPlist() throws {
      let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
      let info = try #require(
        try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
      #expect(info["CFBundleIdentifier"] as? String == Env.bundleID)
      #expect(info["CFBundleExecutable"] as? String == "PeekLock")
      #expect(info["LSUIElement"] as? Bool == true)
      #expect(info["CFBundleIconFile"] as? String == "AppIcon")
    }

    @Test func codesignVerifies() throws {
      let app = try app
      let verify = run(["codesign", "--verify", "--strict", "--verbose=2", app.path])
      #expect(verify.status == 0, "\(verify.stderr)")
      #expect(verify.stderr.contains("satisfies its Designated Requirement"))
      let cli = run([
        "codesign", "-dv", app.appendingPathComponent("Contents/Helpers/peeklock").path,
      ])
      #expect(cli.stderr.contains("Identifier=\(Env.bundleID).cli"))
    }

    /// Regression: with the stable identity, TCC must see a certificate-based requirement (not a
    /// per-build cdhash), otherwise Accessibility has to be granted again after every update.
    @Test(.enabled("needs the PeekLock signing identity") { Env.hasSigningKeychain })
    func designatedRequirementIsCertificateBased() throws {
      let requirement = run(["codesign", "-d", "-r-", try app.path])
      let text = requirement.stdout + requirement.stderr
      #expect(text.contains("identifier \"\(Env.bundleID)\""), "\(text)")
      #expect(text.contains("certificate root = H\""), "\(text)")
      #expect(!text.contains("cdhash"), "\(text)")
    }

    @Test func zipRoundTrip() throws {
      let app = try app
      let output = app.deletingLastPathComponent()
      let version = run([Env.cli.path, "--version"]).stdout
        .trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
          of: "peeklock ", with: "")
      let zip = "PeekLock-\(version).zip"
      #expect(run(["shasum", "-a", "256", "-c", "\(zip).sha256"], cwd: output).status == 0)
      let extracted = output.appendingPathComponent("unzipped")
      try? FileManager.default.removeItem(at: extracted)
      #expect(
        run(["ditto", "-x", "-k", output.appendingPathComponent(zip).path, extracted.path]).status
          == 0)
      let unzippedApp = extracted.appendingPathComponent("PeekLock.app")
      #expect(run(["codesign", "--verify", "--strict", unzippedApp.path]).status == 0)
      let cli = run([
        unzippedApp.appendingPathComponent("Contents/Helpers/peeklock").path, "--version",
      ])
      #expect(cli.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "peeklock \(version)")
    }

    /// Launch a second instance, check it is an accessory (menu bar) app and logs its startup.
    @Test func launchesAsMenuBarAgent() throws {
      let app = try app
      let executable = app.appendingPathComponent("Contents/MacOS/PeekLock").path
      let pids = {
        Set(run(["pgrep", "-f", executable]).stdout.split(separator: "\n").map(String.init))
      }
      let before = pids()
      #expect(run(["open", "-n", "-g", app.path]).status == 0)

      var pid: pid_t?
      _ = waitUntil(timeout: 15, interval: 0.3) {
        pid = pids().subtracting(before).first.flatMap { pid_t($0) }
        return pid != nil
      }
      let launched = try #require(pid, "PeekLock.app did not start")
      defer { kill(launched, SIGTERM) }

      var logged = ""
      let started = waitUntil(timeout: 30, interval: 1) {
        logged =
          run([
            "log", "show", "--last", "2m", "--style", "compact", "--predicate",
            "subsystem == \"\(Env.bundleID)\" AND processID == \(launched)",
          ]).stdout
        return logged.contains("PeekLock started.")
      }
      #expect(started, "startup log line missing:\n\(logged)")

      let running = try #require(NSRunningApplication(processIdentifier: launched))
      #expect(running.activationPolicy == .accessory)
      #expect(running.bundleIdentifier == Env.bundleID)
    }
  }
}
