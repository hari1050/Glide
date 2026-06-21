//
//  ActionRunner.swift
//  Glide
//
//  Executes a MappedAction. Keyboard shortcuts and system actions (Mission
//  Control, Spaces, Exposé) are driven through System Events, whose accessibility
//  keystroke API correctly updates the WindowServer's modifier state — which raw
//  synthesized CGEvents do not, so they never trigger system hotkeys.
//
//  This needs the one-time "Automation → System Events" permission. Glide already
//  has Accessibility, so System Events can post the keystroke.
//

import AppKit

enum ActionRunner {

    // Serial background queue: keeps NSAppleScript off the main thread (so the
    // first-run Automation prompt can't block the event tap) and single-threaded.
    private static let scriptQueue = DispatchQueue(label: "com.harishankar.glide.applescript")

    // Virtual key codes (ANSI / AppleScript `key code`).
    private enum Key {
        static let three: UInt16 = 20
        static let four: UInt16  = 21
        static let space: UInt16 = 49
        static let left: UInt16  = 123
        static let right: UInt16 = 124
        static let up: UInt16    = 126
        static let down: UInt16  = 125
    }

    static func run(_ action: MappedAction) {
        switch action {
        case .none:
            return
        case .launchApp(let path):
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                                   configuration: NSWorkspace.OpenConfiguration())
            }
        default:
            guard let combo = keyCombo(for: action) else { return }
            sendKey(combo.code, modifiers: combo.modifiers)
        }
    }

    private static func keyCombo(for action: MappedAction) -> (code: UInt16, modifiers: [String])? {
        switch action {
        case .keyShortcut(let code, let mods): return (code, modifierNames(CGEventFlags(rawValue: mods)))
        case .missionControl:                  return (Key.up, ["control down"])
        case .appExpose:                       return (Key.down, ["control down"])
        case .spaceLeft:                       return (Key.left, ["control down"])
        case .spaceRight:                      return (Key.right, ["control down"])
        case .spotlight:                       return (Key.space, ["command down"])
        case .screenshotRegion:                return (Key.four, ["command down", "shift down"])
        case .screenshotFull:                  return (Key.three, ["command down", "shift down"])
        default:                               return nil
        }
    }

    private static func modifierNames(_ flags: CGEventFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.maskControl)   { names.append("control down") }
        if flags.contains(.maskShift)     { names.append("shift down") }
        if flags.contains(.maskAlternate) { names.append("option down") }
        if flags.contains(.maskCommand)   { names.append("command down") }
        return names
    }

    /// Post a key combo via System Events (reliably triggers system hotkeys).
    private static func sendKey(_ keyCode: UInt16, modifiers: [String]) {
        let using = modifiers.isEmpty ? "" : " using {\(modifiers.joined(separator: ", "))}"
        let source = "tell application \"System Events\" to key code \(keyCode)\(using)"
        scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                NSLog("Glide: System Events keystroke failed (grant Automation permission?): \(error)")
            }
        }
    }
}
