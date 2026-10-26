import AppKit
import PeekLockCore

/// Button that records a key combination when clicked.
final class HotkeyRecorder: NSButton {
  var hotkey: Hotkey { didSet { updateTitle() } }
  var onChange: ((Hotkey) -> Void)?
  var onRecording: ((Bool) -> Void)?
  private var recording = false {
    didSet {
      updateTitle()
      onRecording?(recording)
    }
  }

  init(hotkey: Hotkey) {
    self.hotkey = hotkey
    super.init(frame: .zero)
    bezelStyle = .rounded
    target = self
    action = #selector(toggle)
    updateTitle()
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  override var acceptsFirstResponder: Bool { true }

  @objc private func toggle() {
    recording.toggle()
    if recording { window?.makeFirstResponder(self) }
  }

  private func updateTitle() {
    title = recording ? "Press keys… (⎋ cancels)" : hotkey.description
  }

  override func resignFirstResponder() -> Bool {
    if recording { recording = false }
    return super.resignFirstResponder()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard recording else { return super.performKeyEquivalent(with: event) }
    capture(event)
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard recording else { return super.keyDown(with: event) }
    capture(event)
  }

  private func capture(_ event: NSEvent) {
    if event.keyCode == 53 {  // Escape
      recording = false
      return
    }
    let mods = event.modifierFlags.intersection(Hotkey.relevantModifiers)
    // Require at least one of ⌃ ⌥ ⌘ so a plain key (or ⇧+key) cannot be the hotkey.
    guard !mods.intersection([.control, .option, .command]).isEmpty else {
      NSSound.beep()
      return
    }
    hotkey = Hotkey(keyCode: event.keyCode, modifiers: mods)
    recording = false
    onChange?(hotkey)
  }
}

final class SettingsWindowController: NSWindowController {
  private let settings: Settings
  private let onChange: () -> Void
  private let permissionLabel = NSTextField(labelWithString: "")

  init(settings: Settings, onChange: @escaping () -> Void, onRecording: @escaping (Bool) -> Void) {
    self.settings = settings
    self.onChange = onChange
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "PeekLock Settings"
    window.isReleasedWhenClosed = false
    super.init(window: window)

    let unlockRecorder = HotkeyRecorder(hotkey: settings.unlockHotkey)
    unlockRecorder.onRecording = onRecording
    unlockRecorder.onChange = { [weak self] in
      self?.settings.unlockHotkey = $0
      self?.onChange()
    }

    let lockRecorder = HotkeyRecorder(hotkey: settings.lockHotkey)
    lockRecorder.onRecording = onRecording
    lockRecorder.onChange = { [weak self] in
      self?.settings.lockHotkey = $0
      self?.onChange()
    }

    let lockEnabled = NSButton(
      checkboxWithTitle: "Enable global lock hotkey", target: self,
      action: #selector(lockEnabledChanged(_:)))
    lockEnabled.state = settings.lockHotkeyEnabled ? .on : .off

    let idleField = NSTextField(string: "\(settings.idleMinutes)")
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 1440
    formatter.allowsFloats = false
    idleField.formatter = formatter
    idleField.target = self
    idleField.action = #selector(idleChanged(_:))
    idleField.widthAnchor.constraint(equalToConstant: 60).isActive = true
    let idleRow = NSStackView(views: [
      idleField, NSTextField(labelWithString: "minutes (0 = off)"),
    ])

    let badge = NSButton(
      checkboxWithTitle: "Show “Locked” badge in screen corners", target: self,
      action: #selector(badgeChanged(_:)))
    badge.state = settings.showBadge ? .on : .off

    let cursor = NSButton(
      checkboxWithTitle: "Show padlock cursor while locked", target: self,
      action: #selector(cursorChanged(_:)))
    cursor.state = settings.lockCursor ? .on : .off

    let openAX = NSButton(
      title: "Accessibility…", target: self, action: #selector(openAccessibility))
    let openIM = NSButton(
      title: "Input Monitoring…", target: self, action: #selector(openInputMonitoring))
    let permissionRow = NSStackView(views: [permissionLabel, openAX, openIM])

    let grid = NSGridView(views: [
      [NSTextField(labelWithString: "Unlock hotkey:"), unlockRecorder],
      [NSTextField(labelWithString: "Lock hotkey:"), lockRecorder],
      [NSGridCell.emptyContentView, lockEnabled],
      [NSTextField(labelWithString: "Auto-lock when idle:"), idleRow],
      [NSTextField(labelWithString: "While locked:"), badge],
      [NSGridCell.emptyContentView, cursor],
      [NSTextField(labelWithString: "Permissions:"), permissionRow],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.rowSpacing = 10
    grid.columnSpacing = 10
    grid.translatesAutoresizingMaskIntoConstraints = false

    let content = NSView()
    content.addSubview(grid)
    NSLayoutConstraint.activate([
      grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
      grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
      grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
    ])
    window.contentView = content
    window.center()
    refreshPermissions()

    NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
    ) { [weak self] _ in self?.refreshPermissions() }
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  private func refreshPermissions() {
    permissionLabel.stringValue =
      (Permissions.accessibilityGranted ? "✅ Accessibility" : "⚠️ Accessibility")
      + (Permissions.inputMonitoringGranted ? "  ✅ Input Mon." : "  ⚠️ Input Mon.")
  }

  @objc private func lockEnabledChanged(_ sender: NSButton) {
    settings.lockHotkeyEnabled = sender.state == .on
    onChange()
  }

  @objc private func idleChanged(_ sender: NSTextField) {
    settings.idleMinutes = sender.integerValue
    onChange()
  }

  @objc private func badgeChanged(_ sender: NSButton) {
    settings.showBadge = sender.state == .on
    onChange()
  }

  @objc private func cursorChanged(_ sender: NSButton) {
    settings.lockCursor = sender.state == .on
    onChange()
  }

  @objc private func openAccessibility() {
    Permissions.request()
    Permissions.openAccessibilitySettings()
  }

  @objc private func openInputMonitoring() {
    Permissions.request()
    Permissions.openInputMonitoringSettings()
  }
}
