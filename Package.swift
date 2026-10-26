// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "PeekLock",
  platforms: [.macOS(.v13)],
  products: [
    // Named PeekLockApp so it does not collide with `peeklock` on case-insensitive filesystems.
    .executable(name: "PeekLockApp", targets: ["PeekLockApp"]),
    .executable(name: "peeklock", targets: ["peeklock"]),
    .library(name: "PeekLockCore", targets: ["PeekLockCore"]),
  ],
  targets: [
    .target(
      name: "PeekLockCore",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("LocalAuthentication"),
      ]
    ),
    .executableTarget(name: "PeekLockApp", dependencies: ["PeekLockCore"]),
    .executableTarget(name: "peeklock", dependencies: ["PeekLockCore"], path: "Sources/CLI"),
    // End-to-end tests only (no unit tests): black-box checks against the built products.
    // Depends on the executables so `swift test` builds them first.
    .testTarget(name: "E2E", dependencies: ["peeklock", "PeekLockApp"], path: "e2e"),
  ]
)
