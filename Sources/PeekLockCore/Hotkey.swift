import AppKit
import Carbon.HIToolbox

/// A key combination: a virtual key code plus device-independent modifiers.
public struct Hotkey: Codable, Equatable, CustomStringConvertible {
  public var keyCode: UInt16
  /// Raw value of `NSEvent.ModifierFlags` limited to ⌃⌥⇧⌘.
  public var modifierRaw: UInt

  public static let relevantModifiers: NSEvent.ModifierFlags = [
    .control, .option, .shift, .command,
  ]

  public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
    self.keyCode = keyCode
    self.modifierRaw = modifiers.intersection(Hotkey.relevantModifiers).rawValue
  }

  public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierRaw) }

  /// Default unlock combination: ⌃⌥⌘U.
  public static let defaultUnlock = Hotkey(
    keyCode: UInt16(kVK_ANSI_U), modifiers: [.control, .option, .command])
  /// Default lock combination: ⌃⌥⌘L.
  public static let defaultLock = Hotkey(
    keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .option, .command])

  /// Whether a Core Graphics key event matches this hotkey exactly (extra modifiers do not match).
  public func matches(keyCode code: Int64, flags: CGEventFlags) -> Bool {
    guard code == Int64(keyCode) else { return false }
    return Hotkey.modifiers(from: flags) == modifiers
  }

  public static func modifiers(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
    var result: NSEvent.ModifierFlags = []
    if flags.contains(.maskControl) { result.insert(.control) }
    if flags.contains(.maskAlternate) { result.insert(.option) }
    if flags.contains(.maskShift) { result.insert(.shift) }
    if flags.contains(.maskCommand) { result.insert(.command) }
    return result
  }

  /// Modifier mask for Carbon `RegisterEventHotKey`.
  public var carbonModifiers: UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(.control) { result |= UInt32(controlKey) }
    if modifiers.contains(.option) { result |= UInt32(optionKey) }
    if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
    if modifiers.contains(.command) { result |= UInt32(cmdKey) }
    return result
  }

  public var description: String {
    var text = ""
    if modifiers.contains(.control) { text += "⌃" }
    if modifiers.contains(.option) { text += "⌥" }
    if modifiers.contains(.shift) { text += "⇧" }
    if modifiers.contains(.command) { text += "⌘" }
    return text + Hotkey.keyName(keyCode)
  }

  static func keyName(_ code: UInt16) -> String {
    let names: [Int: String] = [
      kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
      kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
      kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
      kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
      kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
      kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
      kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
      kVK_ANSI_9: "9", kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥",
      kVK_Delete: "⌫", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
      kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11",
      kVK_F12: "F12", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
      kVK_DownArrow: "↓", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Slash: "/",
      kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
      kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\",
      kVK_ANSI_Grave: "`",
    ]
    return names[Int(code)] ?? "Key\(code)"
  }
}
