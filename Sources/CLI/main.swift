import AppKit
import PeekLockCore

let version = peekLockVersion
let usage = """
  Usage: peeklock [-b] [--app] [--status] [--help] [--version]

  Lock keyboard and mouse input while the screen keeps showing its content
  (like xtrlock for X11). The pointer can still move but clicks, scrolling,
  gestures and keys are swallowed. Press the unlock hotkey (default ⌃⌥⌘U)
  to authenticate with Touch ID or your macOS login password.

  Options:
    -b          Blank the screen (black) while locked, like xtrlock -b.
    --app       Ask the running PeekLock menu bar app to lock instead of
                locking from this process (uses the app's permissions).
    --status    Print permission / authentication status and exit.
    -h, --help  Show this help.
    --version   Show version.

  Permissions: an event-swallowing tap needs Accessibility. When run from a
  terminal, grant it to the terminal app (Terminal, iTerm, Ghostty, ...).
  Exit status: 0 after a successful unlock, 1 on error, 2 on bad usage.
  """

func fail(_ message: String, code: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data("peeklock: \(message)\n".utf8))
  exit(code)
}

var blank = false
var viaApp = false
for arg in CommandLine.arguments.dropFirst() {
  switch arg {
  case "-b": blank = true
  case "--app": viaApp = true
  case "-h", "--help":
    print(usage)
    exit(0)
  case "--version":
    print("peeklock \(version)")
    exit(0)
  case "--status":
    print(Permissions.summary)
    print("Authentication: \(Authenticator.availability())")
    print("Unlock hotkey: \(Settings.shared.unlockHotkey)")
    print("Keep display awake while locked: \(Settings.shared.keepDisplayAwake)")
    print("Secure Event Input active: \(Permissions.secureInputEnabled)")
    exit(0)
  default:
    FileHandle.standardError.write(Data("peeklock: unknown option \(arg)\n\n\(usage)\n".utf8))
    exit(2)
  }
}

if viaApp {
  let running = NSRunningApplication.runningApplications(withBundleIdentifier: Settings.domain)
  guard !running.isEmpty else { fail("PeekLock.app is not running") }
  DistributedNotificationCenter.default().postNotificationName(
    Settings.lockNotification, object: nil, userInfo: ["blank": blank ? "1" : "0"],
    deliverImmediately: true)
  exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard Permissions.accessibilityGranted else {
  Permissions.request()
  Permissions.openAccessibilitySettings()
  fail(
    "Accessibility permission missing for this process (grant it to your terminal app); not locking."
  )
}

let controller = LockController()
controller.onMessage = { FileHandle.standardError.write(Data("peeklock: \($0)\n".utf8)) }
controller.onStateChange = { state in
  if state == .unlocked { exit(0) }
}

// Release the lock cleanly on SIGTERM/SIGHUP (e.g. `pkill peeklock` over SSH).
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGHUP] {
  signal(sig, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
  source.setEventHandler {
    controller.unlock()
    exit(0)
  }
  source.resume()
  signalSources.append(source)
}

do {
  try controller.lock(blank: blank)
} catch {
  fail("\(error)")
}
app.run()
