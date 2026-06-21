//
//  SettingsView.swift
//  Glide
//
//  SwiftUI settings window hosted in an AppKit NSWindow. Binds directly to the
//  shared Config; every edit persists immediately and is read live by the engine.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            ScrollingTab().tabItem { Label("Scrolling", systemImage: "arrow.up.arrow.down") }
            ButtonsTab().tabItem { Label("Buttons", systemImage: "computermouse") }
            GesturesTab().tabItem { Label("Gestures", systemImage: "hand.draw") }
            AppsTab().tabItem { Label("Apps", systemImage: "app.badge") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 500)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var store: SettingsStore
    @State private var trusted = Permissions.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Enable Glide", isOn: $store.config.enabled)
                Toggle("Launch at login", isOn: Binding(
                    get: { store.config.launchAtLogin },
                    set: { newValue in
                        LaunchAtLogin.set(newValue)
                        store.config.launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
            }
            Section("Permission") {
                HStack {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Accessibility granted — Glide is active."
                                 : "Accessibility not granted. Glide can't read scroll events yet.")
                    Spacer()
                }
                if !trusted {
                    Button("Open Accessibility Settings…") {
                        Permissions.promptIfNeeded(); Permissions.openSystemSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            trusted = Permissions.isTrusted
        }
    }
}

// MARK: - Scrolling

private struct ScrollingTab: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Smoothing") {
                Toggle("Smooth scrolling", isOn: $store.config.smoothEnabled)
                slider("Step (distance per notch)", value: $store.config.step, range: 10...120, format: "%.0f px")
                slider("Speed", value: $store.config.speed, range: 0.2...3.0, format: "%.2f×")
                slider("Smoothness (tail length)", value: $store.config.smoothness, range: 0.3...0.95, format: "%.2f")
                    .disabled(!store.config.smoothEnabled)
            }
            Section("Direction") {
                Toggle("Reverse vertical scrolling", isOn: $store.config.reverseVertical)
                Toggle("Reverse horizontal scrolling", isOn: $store.config.reverseHorizontal)
                Toggle("Hold Shift to scroll horizontally", isOn: $store.config.shiftToHorizontal)
            }
            Section("Function keys (hold to change scrolling)") {
                Picker("Faster (dash)", selection: $store.config.dashKey) {
                    ForEach(ModifierKey.allCases) { Text($0.label).tag($0) }
                }
                if store.config.dashKey != .none {
                    slider("Dash speed", value: $store.config.dashMultiplier, range: 2...10, format: "%.0f×")
                }
                Picker("Scroll horizontally (toggle)", selection: $store.config.toggleKey) {
                    ForEach(ModifierKey.allCases) { Text($0.label).tag($0) }
                }
                Picker("Raw / no smoothing (block)", selection: $store.config.blockKey) {
                    ForEach(ModifierKey.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Reusable action editor

struct ActionEditor: View {
    @Binding var action: MappedAction
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Picker("", selection: kindBinding) {
                ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 175)

            if case .keyShortcut(let code, let mods) = action {
                Button(recording ? "Press keys…" : shortcutText(code, mods)) { toggleRecording() }
                    .frame(minWidth: 95)
            }
            if case .launchApp(let path) = action {
                Text(path.isEmpty ? "(choose app)" : (path as NSString).lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { ActionKind(from: action) },
            set: { newKind in
                action = newKind.toAction(existing: action)
                if case .launchApp = action { pickApp() }
            }
        )
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            action = .launchApp(path: url.path)
        }
    }

    private func toggleRecording() {
        if recording { stopRecording(); return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            var flags: CGEventFlags = []
            if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
            if event.modifierFlags.contains(.shift) { flags.insert(.maskShift) }
            if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
            if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
            action = .keyShortcut(keyCode: event.keyCode, modifiers: flags.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Buttons

private struct ButtonsTab: View {
    @EnvironmentObject var store: SettingsStore
    @State private var capturing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remap extra mouse buttons (middle, side, and beyond). The left and right buttons can't be remapped.")
                .font(.footnote).foregroundStyle(.secondary)

            List {
                ForEach($store.config.buttonMappings) { $mapping in
                    HStack {
                        Text(buttonLabel(mapping.buttonNumber)).frame(width: 80, alignment: .leading)
                        ActionEditor(action: $mapping.action)
                        Spacer()
                        Button(role: .destructive) {
                            store.config.buttonMappings.removeAll { $0.id == mapping.id }
                        } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 210)

            HStack {
                Button(capturing ? "Press a mouse button…" : "Add Button…") { startCapture() }
                    .disabled(capturing || !Permissions.isTrusted)
                if !Permissions.isTrusted {
                    Text("Grant Accessibility first.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding()
    }

    private func startCapture() {
        capturing = true
        ButtonRemapper.shared.pendingCapture = { number in
            capturing = false
            if !store.config.buttonMappings.contains(where: { $0.buttonNumber == number }) {
                store.config.buttonMappings.append(ButtonMapping(buttonNumber: number, action: .none))
            }
        }
    }
}

// MARK: - Gestures

private struct GesturesTab: View {
    @EnvironmentObject var store: SettingsStore
    @State private var capturing = false

    var body: some View {
        Form {
            Section("Gesture button") {
                HStack {
                    Text(store.config.gestureButton >= 0 ? buttonLabel(store.config.gestureButton) : "None")
                    Spacer()
                    Button(capturing ? "Press a button…" : "Set…") { capture() }
                        .disabled(capturing || !Permissions.isTrusted)
                    if store.config.gestureButton >= 0 {
                        Button("Clear") { store.config.gestureButton = -1 }
                    }
                }
                Text("Hold this button and move the mouse, then release — the direction you moved fires its action. Pick an extra button (not left/right).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Directions") {
                gestureRow("↑  Up", $store.config.gestureUp)
                gestureRow("↓  Down", $store.config.gestureDown)
                gestureRow("←  Left", $store.config.gestureLeft)
                gestureRow("→  Right", $store.config.gestureRight)
            }
            .disabled(store.config.gestureButton < 0)
        }
        .formStyle(.grouped)
    }

    private func gestureRow(_ label: String, _ action: Binding<MappedAction>) -> some View {
        HStack {
            Text(label).frame(width: 64, alignment: .leading)
            ActionEditor(action: action)
        }
    }

    private func capture() {
        capturing = true
        ButtonRemapper.shared.pendingCapture = { number in
            capturing = false
            store.config.gestureButton = number
        }
    }
}

// MARK: - Apps

private struct AppsTab: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glide does nothing in these apps — scrolling and button remapping pass straight through.")
                .font(.footnote).foregroundStyle(.secondary)

            List {
                ForEach(store.config.excludedApps, id: \.self) { bid in
                    HStack {
                        Text(appName(bid))
                        Spacer()
                        Text(bid).font(.caption).foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            store.config.excludedApps.removeAll { $0 == bid }
                        } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 250)

            Button("Add App…") { addApp() }
        }
        .padding()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let bid = Bundle(url: url)?.bundleIdentifier,
           !store.config.excludedApps.contains(bid) {
            store.config.excludedApps.append(bid)
        }
    }

    private func appName(_ bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bid
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "computermouse.fill").font(.system(size: 44))
            Text("Glide").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("No network access, no telemetry, no analytics.", systemImage: "wifi.slash")
                Label("Only permission used: Accessibility.", systemImage: "hand.raised")
                Label("All settings stay on this Mac.", systemImage: "lock")
            }
            .font(.callout)
            Spacer()
        }
        .padding().frame(maxWidth: .infinity)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Action kind (for the Picker)

enum ActionKind: String, CaseIterable, Identifiable {
    case none, keyShortcut, missionControl, appExpose, spaceLeft, spaceRight, spotlight, screenshotRegion, screenshotFull, launchApp
    var id: String { rawValue }

    var title: String {
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

    init(from action: MappedAction) {
        switch action {
        case .none:             self = .none
        case .keyShortcut:      self = .keyShortcut
        case .missionControl:   self = .missionControl
        case .appExpose:        self = .appExpose
        case .spaceLeft:        self = .spaceLeft
        case .spaceRight:       self = .spaceRight
        case .spotlight:        self = .spotlight
        case .screenshotRegion: self = .screenshotRegion
        case .screenshotFull:   self = .screenshotFull
        case .launchApp:        self = .launchApp
        }
    }

    func toAction(existing: MappedAction) -> MappedAction {
        switch self {
        case .none:             return .none
        case .keyShortcut:
            if case .keyShortcut = existing { return existing }
            return .keyShortcut(keyCode: 0, modifiers: 0)
        case .missionControl:   return .missionControl
        case .appExpose:        return .appExpose
        case .spaceLeft:        return .spaceLeft
        case .spaceRight:       return .spaceRight
        case .spotlight:        return .spotlight
        case .screenshotRegion: return .screenshotRegion
        case .screenshotFull:   return .screenshotFull
        case .launchApp:
            if case .launchApp = existing { return existing }
            return .launchApp(path: "")
        }
    }
}

// MARK: - Display helpers

func buttonLabel(_ number: Int) -> String {
    switch number {
    case 2: return "Middle"
    case 3: return "Back"
    case 4: return "Forward"
    default: return "Button \(number + 1)"
    }
}

func shortcutText(_ code: UInt16, _ mods: UInt64) -> String {
    let flags = CGEventFlags(rawValue: mods)
    var s = ""
    if flags.contains(.maskControl) { s += "⌃" }
    if flags.contains(.maskAlternate) { s += "⌥" }
    if flags.contains(.maskShift) { s += "⇧" }
    if flags.contains(.maskCommand) { s += "⌘" }
    s += keyName(code)
    return s.isEmpty ? "Set…" : s
}

func keyName(_ code: UInt16) -> String {
    let map: [UInt16: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
        18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",25:"9",26:"7",28:"8",29:"0",
        31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
        36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",
        123:"←",124:"→",125:"↓",126:"↑",
        122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6"
    ]
    return map[code] ?? "#\(code)"
}
