import CoreGraphics
import Foundation

/// Fires `onIdle` once the HID idle time exceeds the configured threshold.
public final class IdleMonitor {
  private var timer: Timer?
  private var fired = false
  public var thresholdMinutes: Int = 0
  public var onIdle: (() -> Void)?

  public init() {}

  public static var idleSeconds: TimeInterval {
    // ~0 is kCGAnyInputEventType.
    CGEventSource.secondsSinceLastEventType(
      .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
  }

  public func start() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    guard thresholdMinutes > 0 else { return }
    let idle = IdleMonitor.idleSeconds
    if idle >= TimeInterval(thresholdMinutes * 60) {
      if !fired {
        fired = true
        onIdle?()
      }
    } else {
      fired = false
    }
  }
}
