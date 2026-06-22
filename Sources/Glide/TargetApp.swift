//
//  TargetApp.swift
//  Glide
//
//  Resolves the app an input event is headed to, straight from the event's own
//  annotation (`eventTargetUnixProcessID`). This is fast and, crucially, makes NO
//  WindowServer query — a synchronous IPC inside a tap callback deadlocks all
//  input. Result is cached by PID so NSRunningApplication is only hit on change.
//

import AppKit
import CoreGraphics

enum TargetApp {
    private static var lastPID: pid_t = -1
    private static var lastBundleId: String?

    /// PID of the app receiving the event, or nil if unknown.
    static func pid(of event: CGEvent) -> pid_t? {
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        return pid > 0 ? pid : nil
    }

    /// Bundle id of the receiving app, cached by PID.
    static func bundleId(of event: CGEvent) -> String? {
        guard let pid = pid(of: event) else { return nil }
        if pid != lastPID {
            lastPID = pid
            lastBundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        return lastBundleId
    }

    /// Whether Glide should leave this app entirely alone (scrolling, buttons,
    /// and gestures all pass through).
    static func isExcluded(_ event: CGEvent, config: Config) -> Bool {
        guard !config.excludedApps.isEmpty, let bid = bundleId(of: event) else { return false }
        return config.excludedApps.contains(bid)
    }
}
