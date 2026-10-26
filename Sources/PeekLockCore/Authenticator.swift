import Foundation
import LocalAuthentication

/// Wraps LocalAuthentication: Touch ID first, falling back to the macOS login password.
public final class Authenticator {
  public enum Outcome: Equatable {
    case success
    case failed(String)
    case cancelled
    case timedOut
  }

  private var context: LAContext?
  private var timeoutItem: DispatchWorkItem?
  private var finished = false

  public init() {}

  public var inProgress: Bool { context != nil }

  /// Human readable description of which methods are available.
  public static func availability() -> String {
    let ctx = LAContext()
    var error: NSError?
    let bio = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    let any = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    switch (bio, any) {
    case (true, _): return "Touch ID + password"
    case (false, true): return "password only (Touch ID unavailable)"
    default: return "unavailable"
    }
  }

  /// Shows the system authentication dialog. `completion` runs on the main thread exactly once.
  public func authenticate(
    reason: String, timeout: TimeInterval = 60, completion: @escaping (Outcome) -> Void
  ) {
    guard context == nil else { return }
    let ctx = LAContext()
    ctx.localizedCancelTitle = "Stay Locked"
    context = ctx
    finished = false

    let finish: (Outcome) -> Void = { [weak self] outcome in
      DispatchQueue.main.async {
        guard let self, !self.finished else { return }
        self.finished = true
        self.timeoutItem?.cancel()
        self.timeoutItem = nil
        self.context = nil
        completion(outcome)
      }
    }

    let item = DispatchWorkItem { [weak ctx] in
      ctx?.invalidate()
      finish(.timedOut)
    }
    timeoutItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)

    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
      if success {
        finish(.success)
      } else if let laError = error as? LAError,
        [.userCancel, .systemCancel, .appCancel].contains(laError.code)
      {
        finish(.cancelled)
      } else {
        finish(.failed(error?.localizedDescription ?? "unknown error"))
      }
    }
  }

  public func cancel() {
    context?.invalidate()
  }
}
