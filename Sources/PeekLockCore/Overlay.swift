import AppKit

/// Panel that never activates the app by itself but may become key (needed for cursor rects).
final class OverlayPanel: NSPanel {
  var allowKey = false
  override var canBecomeKey: Bool { allowKey }
  override var canBecomeMain: Bool { false }
}

/// Full-screen view that shows the padlock cursor.
final class CursorView: NSView {
  var cursor: NSCursor = .arrow

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: cursor)
  }

  override func mouseMoved(with event: NSEvent) { cursor.set() }
  override func cursorUpdate(with event: NSEvent) { cursor.set() }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
        owner: self))
  }
}

/// Small rounded "Locked" badge shown in a screen corner.
final class BadgeView: NSView {
  private let label = NSTextField(labelWithString: "")
  private let icon = NSImageView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
    icon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
    icon.contentTintColor = .white
    icon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
    label.textColor = .white
    label.font = .systemFont(ofSize: 12, weight: .medium)
    let stack = NSStackView(views: [icon, label])
    stack.orientation = .horizontal
    stack.spacing = 6
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  var text: String {
    get { label.stringValue }
    set { label.stringValue = newValue }
  }
}

/// Manages per-screen badge and cover windows.
final class OverlayManager {
  private var badges: [OverlayPanel] = []
  private var covers: [OverlayPanel] = []
  private var screenObserver: NSObjectProtocol?

  private(set) var blank = false
  private(set) var useCursor = true
  private(set) var showBadge = true
  private var badgeText = ""

  static let lockCursor: NSCursor = {
    let size = NSSize(width: 26, height: 26)
    let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
    let base = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(config)
    let image = NSImage(size: size, flipped: false) { rect in
      guard let base else { return false }
      let inner = NSRect(
        x: (rect.width - base.size.width) / 2, y: (rect.height - base.size.height) / 2,
        width: base.size.width, height: base.size.height)
      let tint: (NSColor) -> NSImage = { color in
        let tinted = NSImage(size: base.size, flipped: false) { r in
          base.draw(in: r)
          color.set()
          r.fill(using: .sourceAtop)
          return true
        }
        return tinted
      }
      let outline = tint(.black)
      for dx in [-1.5, 0, 1.5] {
        for dy in [-1.5, 0, 1.5] where dx != 0 || dy != 0 {
          outline.draw(in: inner.offsetBy(dx: dx, dy: dy))
        }
      }
      tint(.white).draw(in: inner)
      return true
    }
    return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
  }()

  func show(blank: Bool, useCursor: Bool, showBadge: Bool, badgeText: String) {
    self.blank = blank
    self.useCursor = useCursor
    self.showBadge = showBadge
    self.badgeText = badgeText
    rebuild()
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.rebuild() }
  }

  func hide() {
    if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
    screenObserver = nil
    (badges + covers).forEach { $0.orderOut(nil) }
    badges = []
    covers = []
  }

  /// Temporarily hide covers so the authentication dialog is reachable.
  func setCoversVisible(_ visible: Bool) {
    for cover in covers {
      if visible {
        cover.orderFrontRegardless()
      } else {
        cover.orderOut(nil)
      }
    }
    if visible { focusCover() }
  }

  func setBadgeText(_ text: String) {
    badgeText = text
    for panel in badges {
      (panel.contentView as? BadgeView)?.text = text
      fitBadge(panel)
    }
  }

  private func rebuild() {
    (badges + covers).forEach { $0.orderOut(nil) }
    badges = []
    covers = []
    for screen in NSScreen.screens {
      if blank || useCursor { covers.append(makeCover(screen)) }
      if showBadge { badges.append(makeBadge(screen)) }
    }
    covers.forEach { $0.orderFrontRegardless() }
    badges.forEach { $0.orderFrontRegardless() }
    focusCover()
  }

  private func focusCover() {
    guard useCursor, let cover = covers.first(where: { $0.screen == NSScreen.main }) ?? covers.first
    else { return }
    NSApp.activate(ignoringOtherApps: true)
    cover.makeKey()
    cover.invalidateCursorRects(for: cover.contentView!)
    OverlayManager.lockCursor.set()
  }

  private func basePanel(frame: NSRect) -> OverlayPanel {
    let panel = OverlayPanel(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.level = .screenSaver
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.isOpaque = false
    panel.hasShadow = false
    panel.backgroundColor = .clear
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    return panel
  }

  private func makeCover(_ screen: NSScreen) -> OverlayPanel {
    let panel = basePanel(frame: screen.frame)
    panel.setFrame(screen.frame, display: false)
    panel.allowKey = useCursor
    // A fully transparent window still receives mouse events when ignoresMouseEvents is false;
    // the event tap swallows clicks anyway, the window only exists to own the cursor.
    panel.backgroundColor = blank ? .black : NSColor.black.withAlphaComponent(0.001)
    panel.isOpaque = blank
    panel.ignoresMouseEvents = !useCursor
    panel.acceptsMouseMovedEvents = true
    let view = CursorView(frame: NSRect(origin: .zero, size: screen.frame.size))
    view.cursor = useCursor ? OverlayManager.lockCursor : .arrow
    panel.contentView = view
    return panel
  }

  private func makeBadge(_ screen: NSScreen) -> OverlayPanel {
    let panel = basePanel(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    panel.ignoresMouseEvents = true
    let view = BadgeView(frame: .zero)
    view.text = badgeText
    panel.contentView = view
    fitBadge(panel, screen: screen)
    return panel
  }

  private func fitBadge(_ panel: OverlayPanel, screen: NSScreen? = nil) {
    guard let view = panel.contentView, let screen = screen ?? panel.screen ?? NSScreen.main
    else { return }
    let size = view.fittingSize
    let visible = screen.visibleFrame
    let origin = NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12)
    panel.setFrame(NSRect(origin: origin, size: size), display: true)
  }
}
