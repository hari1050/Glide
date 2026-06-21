//
//  AppDelegate.swift
//  Glide
//
//  Owns the menu-bar item, the settings window, the Accessibility hand-off, and
//  the lifetime of the event tap.
//

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let tap = EventTapController()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep config's login flag in sync with the real system state.
        SettingsStore.shared.config.launchAtLogin = LaunchAtLogin.isEnabled

        setupStatusItem()
        rebuildMenu()

        cancellable = SettingsStore.shared.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }

        if Permissions.isTrusted {
            startEngine()
        } else {
            Permissions.promptIfNeeded()
            startPermissionWatch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.stop()
    }

    // MARK: - Engine lifecycle

    private func startEngine() {
        _ = tap.start()
        rebuildMenu()
    }

    private func startPermissionWatch() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Permissions.isTrusted {
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.startEngine()
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = symbolImage()
        statusItem = item
    }

    private func symbolImage() -> NSImage? {
        let on = SettingsStore.shared.config.enabled && Permissions.isTrusted
        let name = on ? "computermouse.fill" : "computermouse"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Glide")
        image?.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        statusItem?.button?.image = symbolImage()

        let menu = NSMenu()

        let header = NSMenuItem(title: "Glide", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !Permissions.isTrusted {
            let warn = NSMenuItem(title: "⚠︎ Needs Accessibility permission", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
            menu.addItem(NSMenuItem(title: "Grant Accessibility…",
                                    action: #selector(grantAccessibility),
                                    keyEquivalent: ""))
        }

        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = SettingsStore.shared.config.enabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Glide", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil { item.target = self }
        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        SettingsStore.shared.config.enabled.toggle()
        // Re-create the tap when switching on — recovers it if the safety valve
        // had shut it off after repeated timeouts.
        if SettingsStore.shared.config.enabled, Permissions.isTrusted {
            tap.stop()
            _ = tap.start()
        }
    }

    @objc private func grantAccessibility() {
        Permissions.promptIfNeeded()
        Permissions.openSystemSettings()
        startPermissionWatch()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(SettingsStore.shared)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Glide Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 460))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
