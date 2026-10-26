import CoreGraphics
import Foundation
import Testing

/// Real input locking (opt-in: `PEEKLOCK_E2E_LOCK=1 swift test`).
///
/// Each test locks this Mac for a few seconds with the *debug* CLI, which also auto-unlocks
/// after PEEKLOCK_DEBUG_AUTOUNLOCK seconds as a safety net.
///
/// Method: synthetic probe events (F19 down/up and a zero-delta scroll, both harmless) are posted
/// at the HID tap point and counted by a listen-only *session* tap in this process. PeekLock's HID
/// tap sits in front of the session tap, so while locked the probes must not arrive. Every test
/// first checks that probes do arrive without a lock, so a broken environment fails loudly instead
/// of passing by accident.
///
/// Requires, for the terminal app: Accessibility (post events; peeklock itself) and Input
/// Monitoring (listen-only tap).
extension E2E {
  @Suite(
    .enabled("set PEEKLOCK_E2E_LOCK=1 to run tests that lock input") { Env.lockTestsRequested })
  struct Lock {
    static let probeTag: Int64 = 0x504B_4C4B  // "PKLK" in kCGEventSourceUserData
    static let assertionName = "PeekLock: input locked"

    @Test func swallowsInputAndSIGTERMReleases() throws {
      let listener = try ProbeListener.ready()
      let keepAwake = run([Env.cli.path, "--status"]).stdout
        .contains("Keep display awake while locked: true")
      let lock = try Locker.start()
      defer { lock.forceKill() }

      #expect(lock.isRunning, "\(lock.stderr)")
      #expect(listener.probe() == 0, "keys/scroll leaked through while locked")
      // Default is on; follow the user's setting if it was turned off in Settings.
      #expect(Self.holdsDisplayAssertion(lock.pid) == keepAwake)

      #expect(lock.stop() == 0)
      #expect(listener.probe() == 3, "input still blocked after unlock")
      #expect(!Self.holdsDisplayAssertion(lock.pid), "display-sleep assertion leaked")
    }

    @Test func blankModeLocksAndReleases() throws {
      let listener = try ProbeListener.ready()
      let lock = try Locker.start("-b")
      defer { lock.forceKill() }
      #expect(listener.probe() == 0)
      #expect(lock.stop() == 0)
      #expect(listener.probe() == 3)
    }

    @Test func debugSafetyAutoUnlock() throws {
      let listener = try ProbeListener.ready()
      let lock = try Locker.start(safety: 3)
      defer { lock.forceKill() }
      #expect(listener.probe() == 0)
      #expect(lock.waitForExit(timeout: 15) == 0)
      #expect(lock.stderr.contains("safety auto-unlock fired"))
      #expect(listener.probe() == 3)
    }

    static func holdsDisplayAssertion(_ pid: pid_t) -> Bool {
      run(["pmset", "-g", "assertions"]).stdout.split(separator: "\n").contains {
        $0.contains("pid \(pid)(") && $0.contains(assertionName)
      }
    }
  }
}

/// Listen-only session tap that counts probe events.
final class ProbeListener {
  private(set) var count = 0
  private var tap: CFMachPort?

  struct Unavailable: Error, CustomStringConvertible {
    let description: String
  }

  /// Creates the listener and checks that probes arrive while nothing is locked.
  static func ready() throws -> ProbeListener {
    guard Env.accessibilityGranted, CGPreflightPostEventAccess() else {
      throw Unavailable(description: "grant Accessibility to this terminal app")
    }
    let listener = ProbeListener()
    let mask =
      (CGEventMask(1) << CGEventType.keyDown.rawValue)
      | (CGEventMask(1) << CGEventType.keyUp.rawValue)
      | (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, _, event, info in
          if let info,
            event.getIntegerValueField(.eventSourceUserData) == E2E.Lock.probeTag
          {
            Unmanaged<ProbeListener>.fromOpaque(info).takeUnretainedValue().count += 1
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(listener).toOpaque())
    else { throw Unavailable(description: "cannot create listen tap: grant Input Monitoring") }
    listener.tap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    let control = listener.probe()
    guard control == 3 else {
      throw Unavailable(description: "control probe saw \(control)/3 events without a lock")
    }
    return listener
  }

  deinit {
    if let tap { CFMachPortInvalidate(tap) }
  }

  /// Posts F19 down/up + a zero scroll and returns how many reached the session.
  func probe(settle: TimeInterval = 0.8) -> Int {
    count = 0
    let source = CGEventSource(stateID: .privateState)
    let events = [
      CGEvent(keyboardEventSource: source, virtualKey: 80, keyDown: true),
      CGEvent(keyboardEventSource: source, virtualKey: 80, keyDown: false),
      CGEvent(
        scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0,
        wheel3: 0),
    ].compactMap { $0 }
    for event in events {
      event.setIntegerValueField(.eventSourceUserData, value: E2E.Lock.probeTag)
      event.post(tap: .cghidEventTap)
    }
    let deadline = Date().addingTimeInterval(settle)
    while Date() < deadline {
      CFRunLoopRunInMode(.defaultMode, 0.05, false)
    }
    return count
  }
}

/// Runs the debug CLI and collects its stderr.
final class Locker {
  private let process = Process()
  private let lock = NSLock()
  private var buffer = ""

  var stderr: String { lock.withLock { buffer } }
  var pid: pid_t { process.processIdentifier }
  var isRunning: Bool { process.isRunning }

  static func start(_ args: String..., safety: Int = 20) throws -> Locker {
    let locker = Locker()
    try locker.launch(args, safety: safety)
    let locked = waitUntil(timeout: 10) {
      locker.stderr.contains("auto-unlocking in") || !locker.isRunning
    }
    guard locked, locker.isRunning else {
      locker.forceKill()
      throw ProbeListener.Unavailable(description: "peeklock did not lock:\n\(locker.stderr)")
    }
    Thread.sleep(forTimeInterval: 0.5)  // let the taps settle
    return locker
  }

  private func launch(_ args: [String], safety: Int) throws {
    process.executableURL = Env.cli
    process.arguments = args
    process.currentDirectoryURL = Env.repoRoot
    var env = ProcessInfo.processInfo.environment
    env["PEEKLOCK_DEBUG_AUTOUNLOCK"] = String(safety)
    process.environment = env
    process.standardOutput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let text = String(decoding: handle.availableData, as: UTF8.self)
      guard let self, !text.isEmpty else { return }
      self.lock.withLock { self.buffer += text }
    }
    try process.run()
  }

  func waitForExit(timeout: TimeInterval) -> Int32? {
    guard waitUntil(timeout: timeout, { !process.isRunning }) else { return nil }
    return process.terminationStatus
  }

  func stop() -> Int32? {
    if process.isRunning { process.terminate() }  // SIGTERM → clean unlock
    return waitForExit(timeout: 5)
  }

  /// Never leave the Mac locked.
  func forceKill() {
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
  }
}
