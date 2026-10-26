import Carbon.HIToolbox
import Foundation

/// System-wide hotkey via Carbon `RegisterEventHotKey` (needs no extra permission).
public final class GlobalHotkey {
  private var ref: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: () -> Void
  private static let signature: OSType = 0x504B_4C4B  // "PKLK"

  public init(action: @escaping () -> Void) {
    self.action = action
  }

  deinit { unregister() }

  @discardableResult
  public func register(_ hotkey: Hotkey) -> Bool {
    unregister()
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let userInfo = Unmanaged.passUnretained(self).toOpaque()
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userInfo in
        guard let userInfo else { return noErr }
        let me = Unmanaged<GlobalHotkey>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async { me.action() }
        return noErr
      }, 1, &spec, userInfo, &handler)
    guard installStatus == noErr else { return false }
    let id = EventHotKeyID(signature: GlobalHotkey.signature, id: 1)
    let status = RegisterEventHotKey(
      UInt32(hotkey.keyCode), hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
    if status != noErr {
      unregister()
      return false
    }
    return true
  }

  public func unregister() {
    if let ref { UnregisterEventHotKey(ref) }
    if let handler { RemoveEventHandler(handler) }
    ref = nil
    handler = nil
  }
}
