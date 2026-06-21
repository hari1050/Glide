//
//  Settings.swift
//  Glide
//
//  Plain-Codable config persisted to UserDefaults as JSON. One source of truth,
//  read live by the event engine and bound to by the SwiftUI settings UI.
//

import Foundation
import Combine
import CoreGraphics

// MARK: - Modifier keys (for the dash / toggle / block scroll functions)

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case none, control, option, command, shift, fn
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:    return "None"
        case .control: return "⌃ Control"
        case .option:  return "⌥ Option"
        case .command: return "⌘ Command"
        case .shift:   return "⇧ Shift"
        case .fn:      return "fn"
        }
    }

    var flag: CGEventFlags? {
        switch self {
        case .none:    return nil
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .command: return .maskCommand
        case .shift:   return .maskShift
        case .fn:      return .maskSecondaryFn
        }
    }
}

// MARK: - Actions a remapped mouse button can perform

enum MappedAction: Codable, Hashable {
    case none
    case keyShortcut(keyCode: UInt16, modifiers: UInt64) // CGEventFlags rawValue subset
    case missionControl
    case appExpose
    case spaceLeft
    case spaceRight
    case spotlight
    case screenshotRegion
    case screenshotFull
    case launchApp(path: String)

    var label: String {
        switch self {
        case .none:            return "Do Nothing"
        case .keyShortcut:     return "Keyboard Shortcut"
        case .missionControl:  return "Mission Control"
        case .appExpose:       return "App Exposé"
        case .spaceLeft:       return "Switch Space Left"
        case .spaceRight:      return "Switch Space Right"
        case .spotlight:       return "Spotlight"
        case .screenshotRegion:return "Screenshot (Region)"
        case .screenshotFull:  return "Screenshot (Full)"
        case .launchApp:       return "Launch App"
        }
    }
}

struct ButtonMapping: Codable, Identifiable, Hashable {
    var id = UUID()
    var buttonNumber: Int          // CGEvent button number: 2=middle, 3=back, 4=forward, ...
    var action: MappedAction = .none
}

// MARK: - The persisted configuration

struct Config: Codable, Equatable {
    // Master
    var enabled = true                 // global on/off (pause)

    // Smoothing
    var smoothEnabled = true
    var step: Double = 40              // pixels added to the scroll buffer per wheel notch
    var speed: Double = 1.0           // overall multiplier
    var smoothness: Double = 0.82     // 0 = instant, 1 = very long tail (0.05..0.95 useful)

    // Direction
    var reverseVertical = false
    var reverseHorizontal = false
    var shiftToHorizontal = true      // when Shift is held, scroll horizontally

    // Per-app: Glide is disabled (pass-through) for these bundle identifiers
    var excludedApps: [String] = []

    // Mouse button remapping
    var buttonMappings: [ButtonMapping] = []

    // Scroll function keys (hold to temporarily change behavior)
    var dashKey: ModifierKey = .none        // hold → faster scroll
    var dashMultiplier: Double = 5.0
    var toggleKey: ModifierKey = .none      // hold → vertical becomes horizontal
    var blockKey: ModifierKey = .none       // hold → raw (smoothing off)

    // Mouse gestures: hold a button and move; release fires the direction's action
    var gestureButton: Int = -1             // -1 = disabled; else CGEvent button number
    var gestureUp: MappedAction = .none
    var gestureDown: MappedAction = .none
    var gestureLeft: MappedAction = .none
    var gestureRight: MappedAction = .none

    // Login
    var launchAtLogin = false
}

// MARK: - Store

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaultsKey = "GlideConfig.v1"

    @Published var config: Config {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = Config()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
