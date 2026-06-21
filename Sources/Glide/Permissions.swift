//
//  Permissions.swift
//  Glide
//
//  Accessibility is the only permission Glide needs. macOS requires it for any
//  process that taps and rewrites input events (CGEventTap). Nothing here touches
//  the network or any private user data.
//

import ApplicationServices
import AppKit

enum Permissions {

    /// Whether this process is currently trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the system Accessibility prompt (adds Glide to the list in
    /// System Settings ▸ Privacy & Security ▸ Accessibility).
    @discardableResult
    static func promptIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open the Accessibility pane directly.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
