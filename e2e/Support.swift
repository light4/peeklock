import ApplicationServices
import Foundation
import Testing

/// Root suite. `.serialized` applies recursively, so tests never overlap — important because
/// the lock tests really block input and the bundle test launches a second app instance.
@Suite(.serialized) enum E2E {}

enum Env {
  static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
  static let bundleID = "io.i01.peeklock"

  /// Directory containing the built `peeklock` and `PeekLockApp` products.
  static let productsDirectory: URL = {
    var candidates = Bundle.allBundles
      .filter { $0.bundlePath.hasSuffix(".xctest") }
      .map { $0.bundleURL.deletingLastPathComponent() }
    candidates += [
      repoRoot.appendingPathComponent(".build/out/Products/Debug"),
      repoRoot.appendingPathComponent(".build/debug"),
    ]
    return candidates.first {
      FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("peeklock").path)
    } ?? candidates[0]
  }()

  static var cli: URL { productsDirectory.appendingPathComponent("peeklock") }

  static var inCI: Bool { ProcessInfo.processInfo.environment["CI"] == "true" }
  static var lockTestsRequested: Bool {
    ProcessInfo.processInfo.environment["PEEKLOCK_E2E_LOCK"] == "1"
  }
  /// TCC attributes permissions to the responsible process (the terminal / CI agent), so this
  /// equals what the spawned `peeklock` sees.
  static var accessibilityGranted: Bool { AXIsProcessTrusted() }

  static var appRunning: Bool { run(["pgrep", "-x", "PeekLock"]).status == 0 }

  static var signingIdentity: String? {
    let out = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout
    return out.split(separator: "\n").first { $0.contains("\"Apple Development: ") }
      .flatMap { $0.split(separator: " ").first { $0.count == 40 } }
      .map(String.init)
  }
}

struct ProcessResult {
  var status: Int32
  var stdout: String
  var stderr: String
}

/// Runs a command to completion (never throws on non-zero exit; tests assert on it).
@discardableResult
func run(_ argv: [String], timeout: TimeInterval = 120, cwd: URL = Env.repoRoot) -> ProcessResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = argv
  process.currentDirectoryURL = cwd
  let out = Pipe()
  let err = Pipe()
  process.standardOutput = out
  process.standardError = err
  do { try process.run() } catch {
    return ProcessResult(status: -1, stdout: "", stderr: "\(error)")
  }
  // Drain both pipes concurrently so a chatty child cannot block on a full pipe.
  var outData = Data()
  var errData = Data()
  let group = DispatchGroup()
  for (pipe, isOut) in [(out, true), (err, false)] {
    group.enter()
    DispatchQueue.global().async {
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if isOut { outData = data } else { errData = data }
      group.leave()
    }
  }
  let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
  DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
  group.wait()
  process.waitUntilExit()
  killer.cancel()
  return ProcessResult(
    status: process.terminationStatus,
    stdout: String(decoding: outData, as: UTF8.self),
    stderr: String(decoding: errData, as: UTF8.self))
}

/// Polls `condition` until it is true or `timeout` elapses.
func waitUntil(timeout: TimeInterval, interval: TimeInterval = 0.2, _ condition: () -> Bool)
  -> Bool
{
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return true }
    Thread.sleep(forTimeInterval: interval)
  }
  return condition()
}
