import AppKit
import PeekLockCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let settings = Settings.shared
  private lazy var controller = LockController(settings: settings)
  private var statusItem: NSStatusItem!
  private let idleMonitor = IdleMonitor()
  private var lockHotkey: GlobalHotkey?
  private var settingsWindow: SettingsWindowController?
  /// `caffeinate -d` equivalent toggled from the menu; not persisted across launches.
  private let manualAwake = DisplayAwake(name: DisplayAwake.manualAssertionName)

  private var lockItem: NSMenuItem!
  private var blankItem: NSMenuItem!
  private var awakeItem: NSMenuItem!
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
    manualAwake.release()
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
    awakeItem = NSMenuItem(
      title: "Keep Display Awake", action: #selector(awakeAction), keyEquivalent: "")
    statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    statusLine.isEnabled = false
    statusLine.isHidden = true

    menu.addItem(lockItem)
    menu.addItem(blankItem)
    menu.addItem(.separator())
    menu.addItem(awakeItem)
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
    awakeItem.state = manualAwake.isHeld ? .on : .off
    let granted = Permissions.accessibilityGranted
    permissionItem.isHidden = granted
  }

  private func updateIcon() {
    let locked = controller.isLocked
    let awake = manualAwake.isHeld
    let symbol: String
    let description: String
    switch (locked, awake) {
    case (true, true):
      symbol = "lock.display"
      description = "PeekLock: locked, display kept awake"
    case (true, false):
      symbol = "lock.fill"
      description = "PeekLock: locked"
    case (false, true):
      symbol = "lock.open.display"
      description = "PeekLock: unlocked, display kept awake"
    case (false, false):
      symbol = "lock.open"
      description = "PeekLock: unlocked"
    }
    let image =
      NSImage(systemSymbolName: symbol, accessibilityDescription: description)
      ?? NSImage(
        systemSymbolName: locked ? "lock.fill" : "lock.open", accessibilityDescription: description)
    image?.isTemplate = true
    statusItem.button?.image = image
    var tooltip = locked ? "Input locked — press \(settings.unlockHotkey) to unlock" : "PeekLock"
    if awake { tooltip += "\nKeeping display awake" }
    statusItem.button?.toolTip = tooltip
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

  @objc private func awakeAction() {
    if manualAwake.isHeld {
      manualAwake.release()
      Log.info("Keep display awake: off")
    } else if manualAwake.acquire() {
      Log.info("Keep display awake: on")
    } else {
      Log.error("Keep display awake: IOKit refused the power assertion")
      statusLine.title = "Could not keep display awake"
      statusLine.isHidden = false
    }
    updateIcon()
    refreshMenu()
  }

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
