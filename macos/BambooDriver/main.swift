// BambooDriver — menu-bar user-space driver for the Wacom CTL-470 on Apple silicon.

import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tablet = Tablet()
    private let poster = PenEventPoster()
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "No tablet connected", action: nil, keyEquivalent: "")
    private var mappingItems: [NSMenuItem] = []
    private let loginItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = defaults.string(forKey: "mappingArea"), let area = MappingArea(rawValue: saved) {
            poster.mappingArea = area
        }
        if defaults.object(forKey: "keepProportions") != nil {
            poster.keepProportions = defaults.bool(forKey: "keepProportions")
        }
        buildMenu()
        enableLoginItemOnFirstInstalledLaunch()
        requestAccessibility()

        tablet.onSample = { [poster] sample, model in poster.post(sample, model: model) }
        tablet.onConnectionChange = { [weak self] model in
            self?.statusLine.title = model.map { "Connected: Wacom \($0.name)" } ?? "No tablet connected"
        }
        tablet.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [tablet] _ in tablet.reassertWacomMode() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tablet.stop()
    }

    private func requestAccessibility() {
        // Posting pointer events needs Accessibility; macOS shows the grant prompt once.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        NSLog("BambooDriver: accessibility trusted = %@", trusted ? "yes" : "no")
        if !trusted {
            statusLine.title = "Grant Accessibility in System Settings"
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "BambooDriver")

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let mapHeader = NSMenuItem(title: "Map Tablet To", action: nil, keyEquivalent: "")
        menu.addItem(mapHeader)
        for area in MappingArea.allCases {
            let item = NSMenuItem(title: area.rawValue, action: #selector(selectMapping(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = area.rawValue
            item.indentationLevel = 1
            item.state = area == poster.mappingArea ? .on : .off
            mappingItems.append(item)
            menu.addItem(item)
        }
        let proportions = NSMenuItem(title: "Keep Proportions", action: #selector(toggleProportions(_:)), keyEquivalent: "")
        proportions.target = self
        proportions.state = poster.keepProportions ? .on : .off
        menu.addItem(proportions)
        menu.addItem(.separator())
        loginItem.action = #selector(toggleLoginItem(_:))
        loginItem.target = self
        menu.addItem(loginItem)
        updateLoginItemState()
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BambooDriver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func selectMapping(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let area = MappingArea(rawValue: raw) else { return }
        poster.mappingArea = area
        defaults.set(raw, forKey: "mappingArea")
        mappingItems.forEach { $0.state = $0 == sender ? .on : .off }
    }

    /// Registers the login item once, the first time the app runs from an Applications folder,
    /// so a fresh install starts at login without the user hunting for the setting.
    private func enableLoginItemOnFirstInstalledLaunch() {
        guard !defaults.bool(forKey: "loginItemConfigured"),
              Bundle.main.bundlePath.contains("/Applications/") else { return }
        try? SMAppService.mainApp.register()
        defaults.set(true, forKey: "loginItemConfigured")
        updateLoginItemState()
    }

    private func updateLoginItemState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("BambooDriver: login item change failed: %@", error.localizedDescription)
        }
        defaults.set(true, forKey: "loginItemConfigured")
        updateLoginItemState()
    }

    @objc private func toggleProportions(_ sender: NSMenuItem) {
        poster.keepProportions.toggle()
        defaults.set(poster.keepProportions, forKey: "keepProportions")
        sender.state = poster.keepProportions ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
