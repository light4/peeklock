// Build PeekLock.app, sign it, optionally zip and install.
// Usage: swift scripts/package.swift --help
import CryptoKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let releaseBundleID = "io.i01.peeklock"

/// Debug builds get their own bundle ID (as Ghostty does with com.mitchellh.ghostty.debug) so
/// their ad-hoc signature never replaces the TCC grant of the installed release.
func bundleID(debug: Bool) -> String { debug ? "\(releaseBundleID).debug" : releaseBundleID }
let fm = FileManager.default

let usage = """
  Usage: swift scripts/package.swift [options]

  Build PeekLock.app (App + bundled peeklock CLI), sign it, optionally zip and install.

  Options:
    --debug            Package a debug build (60s safety auto-unlock) as "PeekLock Debug" with
                       bundle ID io.i01.peeklock.debug, so it never touches the release's TCC grant
    --identity NAME    codesign identity from the keychain search list (default: ad-hoc).
                       Releases are signed in CI; local builds are ad-hoc, like Ghostty.
    --zip              Also create <output>/PeekLock-<version>.zip and .sha256
    --install          Install to ~/Applications (PeekLock.app, or "PeekLock Debug.app" with
                       --debug); release builds also link the CLI to ~/.local/bin/peeklock
    --bin-path DIR     Use already-built binaries from DIR instead of running `swift build`
    --output DIR       Output directory (default: build/)
    --print-version    Print the version from Sources/PeekLockCore/Version.swift and exit
    -h, --help         Show this help
  """

struct Failure: Error, CustomStringConvertible {
  let description: String
}

// MARK: - Process helpers

@discardableResult
func run(_ argv: [String], capture: Bool = false, quiet: Bool = false) throws -> String {
  if !quiet { print("+ " + argv.joined(separator: " ")) }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = argv
  process.currentDirectoryURL = root
  let pipe = Pipe()
  if capture { process.standardOutput = pipe }
  try process.run()
  let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw Failure(
      description: "command failed (\(process.terminationStatus)): \(argv.joined(separator: " "))")
  }
  return String(decoding: data, as: UTF8.self)
}

func readVersion() throws -> String {
  let file = root.appendingPathComponent("Sources/PeekLockCore/Version.swift")
  let text = try String(contentsOf: file, encoding: .utf8)
  guard let range = text.range(of: #"peekLockVersion = "([^"]+)""#, options: .regularExpression)
  else { throw Failure(description: "cannot find peekLockVersion in \(file.path)") }
  return text[range].split(separator: "\"")[1].description
}

// MARK: - Steps

func buildBinaries(config: String) throws -> URL {
  try run(["swift", "build", "-c", config, "--product", "PeekLockApp"])
  try run(["swift", "build", "-c", config, "--product", "peeklock"])
  let path = try run(["swift", "build", "-c", config, "--show-bin-path"], capture: true)
  return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
}

func assembleBundle(binDir: URL, output: URL, version: String, debug: Bool) throws -> URL {
  let name = debug ? "PeekLock Debug" : "PeekLock"
  let app = output.appendingPathComponent("PeekLock.app")
  try? fm.removeItem(at: app)
  let contents = app.appendingPathComponent("Contents")
  let macos = contents.appendingPathComponent("MacOS")
  let resources = contents.appendingPathComponent("Resources")
  // The CLI lives in Helpers/: on case-insensitive APFS, MacOS/peeklock == MacOS/PeekLock.
  let helpers = contents.appendingPathComponent("Helpers")
  for dir in [macos, resources, helpers] {
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  try fm.copyItem(
    at: binDir.appendingPathComponent("PeekLockApp"), to: macos.appendingPathComponent("PeekLock"))
  try fm.copyItem(
    at: binDir.appendingPathComponent("peeklock"), to: helpers.appendingPathComponent("peeklock"))

  let iconset = output.appendingPathComponent("AppIcon.iconset")
  try? fm.removeItem(at: iconset)
  try run(["swift", "scripts/make-icon.swift", iconset.path])
  try run([
    "iconutil", "-c", "icns", iconset.path, "-o",
    resources.appendingPathComponent("AppIcon.icns").path,
  ])

  let info: [String: Any] = [
    "CFBundleIdentifier": bundleID(debug: debug),
    "CFBundleName": name,
    "CFBundleDisplayName": name,
    "CFBundleExecutable": "PeekLock",
    "CFBundleIconFile": "AppIcon",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
    "LSMinimumSystemVersion": "13.0",
    "LSUIElement": true,
    "NSHighResolutionCapable": true,
    "NSHumanReadableCopyright": "PeekLock — xtrlock-style input lock for macOS",
  ]
  let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
  try plist.write(to: contents.appendingPathComponent("Info.plist"))
  return app
}

func sign(_ app: URL, identity: String, debug: Bool) throws {
  let base = [
    "codesign", "--force", "--options", "runtime", "--timestamp=none", "--sign", identity,
  ]
  try run(
    base + [
      "--identifier", "\(bundleID(debug: debug)).cli",
      app.appendingPathComponent("Contents/Helpers/peeklock").path,
    ])
  try run(base + [app.path])
  try run(["codesign", "--verify", "--strict", "--verbose=2", app.path])
}

func makeZip(_ app: URL, output: URL, version: String) throws {
  let archive = output.appendingPathComponent("PeekLock-\(version).zip")
  try? fm.removeItem(at: archive)
  // ditto keeps the code signature intact.
  try run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path])
  let digest = SHA256.hash(data: try Data(contentsOf: archive))
    .map { String(format: "%02x", $0) }.joined()
  let checksum = output.appendingPathComponent(archive.lastPathComponent + ".sha256")
  try "\(digest)  \(archive.lastPathComponent)\n".write(
    to: checksum, atomically: true, encoding: .utf8)
  print("zipped \(archive.path)\nsha256 \(digest)")
}

/// Release → ~/Applications/PeekLock.app + ~/.local/bin/peeklock.
/// Debug → ~/Applications/PeekLock Debug.app only, so it never replaces the release.
func install(_ app: URL, debug: Bool) throws {
  let home = fm.homeDirectoryForCurrentUser
  let dest = home.appendingPathComponent(
    debug ? "Applications/PeekLock Debug.app" : "Applications/PeekLock.app")
  _ = try? run(
    ["pkill", "-f", dest.appendingPathComponent("Contents/MacOS/PeekLock").path], quiet: true)
  try? fm.removeItem(at: dest)
  try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
  try run(["ditto", app.path, dest.path])
  let target = dest.appendingPathComponent("Contents/Helpers/peeklock")
  guard !debug else {
    print("installed \(dest.path)\ndebug CLI: \(target.path)")
    return
  }
  let link = home.appendingPathComponent(".local/bin/peeklock")
  try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
  try? fm.removeItem(at: link)
  try fm.createSymbolicLink(at: link, withDestinationURL: target)
  print("installed \(dest.path)\nlinked    \(link.path) -> \(target.path)")
}

// MARK: - Main

func main() throws {
  var debug = false
  var zip = false
  var doInstall = false
  var identity: String?
  var binPath: String?
  var outputPath = root.appendingPathComponent("build").path

  var args = CommandLine.arguments.dropFirst()
  func value(_ flag: String) throws -> String {
    guard let next = args.popFirst() else { throw Failure(description: "\(flag) needs a value") }
    return next
  }
  while let arg = args.popFirst() {
    switch arg {
    case "--debug": debug = true
    case "--zip": zip = true
    case "--install": doInstall = true
    case "--identity": identity = try value(arg)
    case "--bin-path": binPath = try value(arg)
    case "--output": outputPath = try value(arg)
    case "--print-version":
      print(try readVersion())
      return
    case "-h", "--help":
      print(usage)
      return
    default:
      throw Failure(description: "unknown option \(arg)\n\n\(usage)")
    }
  }

  let version = try readVersion()
  let output = URL(fileURLWithPath: outputPath, relativeTo: root).standardizedFileURL
  try fm.createDirectory(at: output, withIntermediateDirectories: true)
  let binDir =
    try binPath.map { URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL }
    ?? buildBinaries(config: debug ? "debug" : "release")
  let app = try assembleBundle(binDir: binDir, output: output, version: version, debug: debug)
  try sign(app, identity: identity ?? "-", debug: debug)
  print("built \(app.path) (\(version))")
  if zip { try makeZip(app, output: output, version: version) }
  if doInstall { try install(app, debug: debug) }
}

do {
  try main()
} catch {
  FileHandle.standardError.write(Data("package.swift: \(error)\n".utf8))
  exit(1)
}
