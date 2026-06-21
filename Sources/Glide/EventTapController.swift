//
//  EventTapController.swift
//  Glide
//
//  One active session-level CGEventTap covers scroll wheels, extra mouse buttons,
//  and left clicks. The C callback dispatches by event type to the engine/remapper.
//
//  Safety: the callback does only fast, non-blocking work (no WindowServer IPC).
//  If macOS ever disables the tap for taking too long, we re-enable it only a
//  bounded number of consecutive times — so a stall self-recovers in a couple of
//  seconds instead of wedging all input until a force-shutdown.
//

import CoreGraphics
import CoreFoundation
import Foundation

private var eventTapPort: CFMachPort?
private var consecutiveTimeouts = 0
private let maxConsecutiveTimeouts = 3

private func glideTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout:
        consecutiveTimeouts += 1
        if consecutiveTimeouts <= maxConsecutiveTimeouts, let port = eventTapPort {
            CGEvent.tapEnable(tap: port, enable: true)
        } else {
            NSLog("Glide: tap disabled after repeated timeouts — leaving it off so input stays responsive. Re-enable via the menu.")
        }
        return Unmanaged.passUnretained(event)

    case .tapDisabledByUserInput:
        if let port = eventTapPort { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)

    case .scrollWheel:
        consecutiveTimeouts = 0
        if let out = ScrollEngine.shared.handleScroll(event) {
            return Unmanaged.passUnretained(out)
        }
        return nil

    case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
        consecutiveTimeouts = 0
        // Gestures get first claim on the configured gesture button.
        let g = GestureEngine.shared.handle(event, type: type)
        if g.handled {
            if let pass = g.pass { return Unmanaged.passUnretained(pass) }
            return nil
        }
        if type == .otherMouseDragged {
            return Unmanaged.passUnretained(event)
        }
        if let out = ButtonRemapper.shared.handle(event, type: type) {
            return Unmanaged.passUnretained(out)
        }
        return nil

    case .leftMouseDown:
        consecutiveTimeouts = 0
        // A click should feel instant — kill any in-flight fling.
        ScrollEngine.shared.stopAnimation()
        return Unmanaged.passUnretained(event)

    default:
        return Unmanaged.passUnretained(event)
    }
}

final class EventTapController {

    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        guard eventTapPort == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: glideTapCallback,
            userInfo: nil
        ) else {
            return false
        }

        eventTapPort = tap
        consecutiveTimeouts = 0
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTapPort {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTapPort = nil
    }

    var isRunning: Bool {
        guard let tap = eventTapPort else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
}
