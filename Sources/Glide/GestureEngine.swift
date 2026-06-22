//
//  GestureEngine.swift
//  Glide
//
//  Mouse gestures: hold the configured gesture button and move the mouse; on
//  release, the dominant stroke direction fires its mapped action.
//

import AppKit
import CoreGraphics

final class GestureEngine {
    static let shared = GestureEngine()
    private init() {}

    private var active = false
    private var startLocation = CGPoint.zero

    /// Minimum travel (points) before a movement counts as a directional stroke.
    private let threshold = 18.0

    /// Returns (handled, passThrough). handled=true means this event belongs to
    /// the gesture system; passThrough is the event to forward (nil to swallow).
    func handle(_ event: CGEvent, type: CGEventType) -> (handled: Bool, pass: CGEvent?) {
        let cfg = SettingsStore.shared.config
        guard cfg.enabled, cfg.gestureButton >= 0 else { return (false, event) }

        switch type {
        case .otherMouseDown:
            if Int(event.getIntegerValueField(.mouseEventButtonNumber)) == cfg.gestureButton {
                // Leave excluded apps alone — pass the button through normally.
                if TargetApp.isExcluded(event, config: cfg) { return (false, event) }
                active = true
                startLocation = event.location
                return (true, nil) // swallow the press; it belongs to the gesture
            }

        case .otherMouseDragged:
            if active { return (true, nil) } // swallow movement while gesturing

        case .otherMouseUp:
            if active, Int(event.getIntegerValueField(.mouseEventButtonNumber)) == cfg.gestureButton {
                active = false
                let disp = CGPoint(x: event.location.x - startLocation.x,
                                   y: event.location.y - startLocation.y)
                fire(displacement: disp, cfg: cfg)
                return (true, nil)
            }

        default:
            break
        }
        return (false, event)
    }

    private func fire(displacement d: CGPoint, cfg: Config) {
        let ax = abs(d.x), ay = abs(d.y)
        guard max(ax, ay) >= threshold else { return } // too small — ignore

        // CGEvent y-axis grows downward (top-left origin).
        let action: MappedAction
        if ax > ay {
            action = d.x > 0 ? cfg.gestureRight : cfg.gestureLeft
        } else {
            action = d.y > 0 ? cfg.gestureDown : cfg.gestureUp
        }
        ActionRunner.run(action)
    }
}
