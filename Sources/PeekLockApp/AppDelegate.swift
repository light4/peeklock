import AppKit
import PeekLockCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let settings = Settings.shared
  private lazy var controller = LockController(settings: settings)
  private var statusItem: NSStatusItem!
  private let idleMonitor = IdleMonitor()
  private var lockHotkey: GlobalHotkey?
  private var settingsWindow: SettingsWindowController?

  private var lockItem: NSMenuItem!
  private var blankItem: NSMenuItem!
  private var permissionItem: NSMenuItem!
  private var statusLine: NSMenuItem!

  func applicationDidFinishLaunching(_ notification: Notification) {
    Log.info("PeekLock started. \(Permissions.summary)")
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    buildMenu()
    updateIcon()

    controller.onStateChange = { [weak self] _ in
      self?.updateIcon()
      self?.refreshMenu()
    }
    controller.onMessage = { [weak self] message in
      self?.statusLine.title = message
      self?.statusLine.isHidden = false
    }

    lockHotkey = GlobalHotkey { [weak self] in self?.lock(blank: false) }
    applySettings()

    idleMonitor.onIdle = { [weak self] in
      guard let self, !self.controller.isLocked else { return }
      self.lock(blank: false, interactive: false)
    }
    idleMonitor.start()

    DistributedNotificationCenter.default().addObserver(
      forName: Settings.lockNotification, object: nil, queue: .main
    ) { [weak self] note in
      let blank = (note.userInfo?["blank"] as? String) == "1"
      self?.lock(blank: blank)
    }

    if !Permissions.accessibilityGranted {
      Permissions.request()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller.unlock()
  }

  // MARK: - Settings

  func applySettings() {
    if settings.lockHotkeyEnabled {
      if lockHotkey?.register(settings.lockHotkey) != true {
        Log.error("Could not register lock hotkey \(settings.lockHotkey)")
      }
    } else {
      lockHotkey?.unregister()
    }
    idleMonitor.thresholdMinutes = settings.idleMinutes
    refreshMenu()
  }

  // MARK: - Menu

  private func buildMenu() {
    let menu = NSMenu()
    menu.delegate = self
    lockItem = NSMenuItem(title: "Lock Input", action: #selector(lockAction), keyEquivalent: "")
    blankItem = NSMenuItem(
      title: "Lock Input & Blank Screen", action: #selector(lockBlankAction), keyEquivalent: "")
    permissionItem = NSMenuItem(
      title: "Grant Accessibility Permission…", action: #selector(permissionAction),
      keyEquivalent: "")
    statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    statusLine.isEnabled = false
    statusLine.isHidden = true

    menu.addItem(lockItem)
    menu.addItem(blankItem)
    menu.addItem(.separator())
    menu.addItem(permissionItem)
    menu.addItem(statusLine)
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ","))
    menu.addItem(
      NSMenuItem(title: "About PeekLock", action: #selector(aboutAction), keyEquivalent: ""))
    menu.addItem(
      NSMenuItem(title: "Quit PeekLock", action: #selector(quitAction), keyEquivalent: "q"))
    menu.items.forEach { $0.target = self }
    statusItem.menu = menu
    refreshMenu()
  }

  func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

  private func refreshMenu() {
    guard lockItem != nil else { return }
    let lockKey = settings.lockHotkeyEnabled ? "  (\(settings.lockHotkey))" : ""
    lockItem.title = "Lock Input" + lockKey
    lockItem.isEnabled = !controller.isLocked
    blankItem.isEnabled = !controller.isLocked
    let granted = Permissions.accessibilityGranted
    permissionItem.isHidden = granted
  }

  private func updateIcon() {
    let locked = controller.isLocked
    let image = NSImage(
      systemSymbolName: locked ? "lock.fill" : "lock.open",
      accessibilityDescription: locked ? "PeekLock: locked" : "PeekLock: unlocked")
    image?.isTemplate = true
    statusItem.button?.image = image
    statusItem.button?.toolTip =
      locked ? "Input locked — press \(settings.unlockHotkey) to unlock" : "PeekLock"
  }

  // MARK: - Actions

  private func lock(blank: Bool, interactive: Bool = true) {
    guard !controller.isLocked else { return }
    do {
      try controller.lock(blank: blank)
    } catch {
      Log.error("Lock refused: \(error)")
      if interactive { showPermissionAlert(message: "\(error)") }
    }
  }

  private func showPermissionAlert(message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "PeekLock cannot lock"
    alert.informativeText =
      "\(message)\n\nPeekLock needs Accessibility permission to block input. "
      + "Enable PeekLock in System Settings › Privacy & Security › Accessibility, then try again.\n\n"
      + Permissions.summary
    alert.addButton(withTitle: "Open Accessibility Settings")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      Permissions.request()
      Permissions.openAccessibilitySettings()
    }
  }

  @objc private func lockAction() { lock(blank: false) }
  @objc private func lockBlankAction() { lock(blank: true) }

  @objc private func permissionAction() {
    Permissions.request()
    Permissions.openAccessibilitySettings()
  }

  @objc private func settingsAction() {
    if settingsWindow == nil {
      settingsWindow = SettingsWindowController(
        settings: settings,
        onChange: { [weak self] in
          self?.applySettings()
          self?.updateIcon()
        },
        onRecording: { [weak self] recording in
          // Avoid triggering a lock while the user records a new combination.
          if recording { self?.lockHotkey?.unregister() } else { self?.applySettings() }
        })
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.showWindow(nil)
    settingsWindow?.window?.makeKeyAndOrderFront(nil)
  }

  @objc private func aboutAction() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .credits: NSAttributedString(
        string: "xtrlock-style input lock for macOS.\n\(Permissions.summary)\n"
          + "Authentication: \(Authenticator.availability())")
    ])
  }

  @objc private func quitAction() { NSApp.terminate(nil) }
}
