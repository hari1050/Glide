//
//  ScrollEngine.swift
//  Glide
//
//  The core: classify each scroll event, leave trackpad/continuous input alone,
//  and for genuine mouse-wheel "notches" either (a) pass through, (b) reverse/
//  swap-and-replay a single line event, or (c) swallow it and replay it as a
//  stream of small interpolated pixel events driven by a display-refresh timer.
//

import AppKit
import QuartzCore

final class ScrollEngine: NSObject {
    static let shared = ScrollEngine()

    /// Sentinel stamped on events we synthesize, so the tap ignores its own output.
    static let magic: Int64 = 0x47_4C_49_44_45 // "GLIDE"

    private let source = CGEventSource(stateID: .hidSystemState)

    // Animation state (all touched on the main thread only).
    private var bufferY = 0.0
    private var bufferX = 0.0
    private var targetPID: pid_t?
    private var currentLocation = CGPoint.zero
    private var displayLink: CADisplayLink?

    /// A copy of the most recent real wheel event. We replay copies of it (with
    /// overwritten deltas) so synthetic events keep all the routing/context an
    /// app needs — building events from scratch does not reliably scroll.
    private var snapshot: CGEvent?

    // MARK: - Entry point from the event tap (main thread)

    /// Returns the event to pass through, or nil to swallow it.
    func handleScroll(_ event: CGEvent) -> CGEvent? {
        // Our own synthetic events — never reprocess.
        if event.getIntegerValueField(.eventSourceUserData) == ScrollEngine.magic {
            return event
        }

        let cfg = SettingsStore.shared.config
        guard cfg.enabled else { return event }

        // Leave trackpad / already-continuous input untouched.
        if isContinuousOrTrackpad(event) { return event }

        // Per-app pass-through. Target app comes from the event annotation; no
        // WindowServer call here (that would deadlock the tap).
        if TargetApp.isExcluded(event, config: cfg) { return event }
        let pid = TargetApp.pid(of: event)
        currentLocation = event.location

        // Read the wheel delta in "lines" (fall back to fixed-point for hi-res wheels).
        var dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        var dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        if dy == 0, dx == 0 {
            dy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            dx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
        guard dy != 0 || dx != 0 else { return event }

        let origHadOnlyVertical = (dx == 0 && dy != 0)

        if cfg.reverseVertical { dy = -dy }
        if cfg.reverseHorizontal { dx = -dx }

        // Scroll function keys (held modifiers).
        let flags = event.flags
        var speedMul = cfg.speed
        if let f = cfg.dashKey.flag, flags.contains(f) { speedMul *= cfg.dashMultiplier }
        var smooth = cfg.smoothEnabled
        if let f = cfg.blockKey.flag, flags.contains(f) { smooth = false }
        let toggleHorizontal = cfg.toggleKey.flag.map { flags.contains($0) } ?? false

        let shift = flags.contains(.maskShift)
        let wantHorizontal = (cfg.shiftToHorizontal && shift) || toggleHorizontal
        let willSwap = wantHorizontal && origHadOnlyVertical
        if willSwap { dx = dy; dy = 0 }

        // Nothing to change → pass through untouched (lowest latency, lossless).
        if !smooth && !cfg.reverseVertical && !cfg.reverseHorizontal && !willSwap {
            return event
        }

        if !smooth {
            // Reverse/swap in place and let the original event flow to the app.
            applyDeltasInPlace(event, dy: dy, dx: dx)
            return event
        }

        // Smooth path: snapshot the event, accumulate into the buffer, animate.
        snapshot = event.copy()
        bufferY += dy * cfg.step * speedMul
        bufferX += dx * cfg.step * speedMul
        targetPID = pid
        startLink()
        return nil
    }

    /// Stop any in-flight fling immediately (e.g. on left click).
    func stopAnimation() {
        bufferY = 0
        bufferX = 0
        displayLink?.isPaused = true
    }

    // MARK: - Classification

    private func isContinuousOrTrackpad(_ e: CGEvent) -> Bool {
        if e.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { return true }
        if e.getDoubleValueField(.scrollWheelEventScrollPhase) != 0 { return true }
        if e.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0 { return true }
        return false
    }

    // MARK: - Animation

    private func startLink() {
        if displayLink == nil {
            // CADisplayLink via NSScreen is the modern, refresh-synced timer (macOS 14+).
            let link = (NSScreen.main ?? NSScreen.screens.first)?
                .displayLink(target: self, selector: #selector(step(_:)))
            link?.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    @objc private func step(_ link: CADisplayLink) {
        let cfg = SettingsStore.shared.config

        // Per-frame fraction, normalized to a 120fps baseline so the feel is
        // independent of the display's refresh rate.
        let dt = max(1.0 / 240.0, link.targetTimestamp - link.timestamp)
        let base = min(0.95, max(0.04, 1.0 - cfg.smoothness))
        let factor = 1.0 - pow(1.0 - base, dt * 120.0)

        var stepY = bufferY * factor
        var stepX = bufferX * factor
        if abs(bufferY) < 1.0 { stepY = bufferY }
        if abs(bufferX) < 1.0 { stepX = bufferX }

        bufferY -= stepY
        bufferX -= stepX

        if stepY != 0 || stepX != 0 {
            postSmoothScroll(dy: stepY, dx: stepX)
        }

        if abs(bufferY) < 0.1 && abs(bufferX) < 0.1 {
            bufferY = 0
            bufferX = 0
            link.isPaused = true
        }
    }

    // MARK: - Posting

    /// Replay a copy of the original wheel event as a continuous (pixel) scroll.
    private func postSmoothScroll(dy: Double, dx: Double) {
        guard let event = snapshot?.copy() else {
            // Fallback: build one from scratch (less reliable, rarely hit).
            guard let fresh = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                      wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else { return }
            fresh.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            fresh.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
            fresh.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
            fresh.setIntegerValueField(.eventSourceUserData, value: ScrollEngine.magic)
            fresh.location = currentLocation
            dispatch(fresh, pid: targetPID)
            return
        }
        // Convert the copied notch into a clean continuous pixel event.
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollEngine.magic)
        dispatch(event, pid: targetPID)
    }

    /// Overwrite an event's deltas in place (used for the non-smooth reverse/swap path).
    private func applyDeltasInPlace(_ event: CGEvent, dy: Double, dx: Double) {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(dy.rounded()))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(dx.rounded()))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
    }

    private func dispatch(_ event: CGEvent, pid: pid_t?) {
        // Deliver straight to the target app. This does NOT touch the session
        // cursor stream, so mouse movement stays responsive while a fling
        // animates. Session re-injection would flood cursor movement.
        if let pid, pid > 0 {
            event.postToPid(pid)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }
}
