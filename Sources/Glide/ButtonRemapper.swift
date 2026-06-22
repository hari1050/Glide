//
//  ButtonRemapper.swift
//  Glide
//
//  Handles the extra mouse buttons (middle / back / forward / 6+). A mapped
//  button is swallowed (both its down and up) and triggers an action. The same
//  path powers "capture" mode used by the settings UI to learn a button number.
//

import AppKit
import CoreGraphics

final class ButtonRemapper {
    static let shared = ButtonRemapper()
    private init() {}

    /// When set, the next button press is reported (and swallowed) instead of acting.
    var pendingCapture: ((Int) -> Void)?

    /// Buttons whose `down` we swallowed, so we also swallow the matching `up`.
    private var swallowed = Set<Int>()

    /// Returns the event to pass through, or nil to swallow.
    func handle(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        let cfg = SettingsStore.shared.config
        guard cfg.enabled else { return event }

        let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        // Capture mode (from the settings UI) takes priority over everything.
        if type == .otherMouseDown, let capture = pendingCapture {
            pendingCapture = nil
            swallowed.insert(number)
            DispatchQueue.main.async { capture(number) }
            return nil
        }

        // Always swallow the `up` for a button whose `down` we swallowed,
        // even if the cursor has since moved over an excluded app.
        if type == .otherMouseUp, swallowed.contains(number) {
            swallowed.remove(number)
            return nil
        }

        // Per-app pass-through: leave excluded apps' buttons untouched.
        if TargetApp.isExcluded(event, config: cfg) { return event }

        if type == .otherMouseDown,
           let mapping = cfg.buttonMappings.first(where: {
               $0.buttonNumber == number && $0.action != .none
           }) {
            swallowed.insert(number)
            ActionRunner.run(mapping.action)
            return nil
        }
        return event
    }
}
