import AppKit
import Carbon
import SwiftUI

@main struct FocusLensApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var model = AppModel()
    private lazy var hotKeys = HotKeyManager()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--permission-flow-check"), CommandLine.arguments.count > index + 1 {
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                let probeModel = AppModel(preflight: { false })
                probeModel.verifyPermission()
                while probeModel.isCheckingPermission { try? await Task.sleep(for: .milliseconds(100)) }
                probeModel.refreshPermission()
                let result = probeModel.hasPermission
                    ? "PASS: negative preflight did not block real capture; successful verification survives refresh.\n"
                    : "FAIL: \(probeModel.errorMessage ?? "No screen access")\n"
                probeModel.shutdown()
                try? Data(result.utf8).write(to: output)
                NSApp.terminate(nil)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--permission-status"), CommandLine.arguments.count > index + 1 {
            // Use `open -n ... --args --permission-status path` to inspect this
            // app's TCC identity rather than inheriting a terminal's permission.
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let status = "version=\(version)\npreflight=\(CGPreflightScreenCaptureAccess())\npath=\(Bundle.main.bundlePath)\n"
            try? Data(status.utf8).write(to: output)
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--feedback-check"), CommandLine.arguments.count > index + 1 {
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                let result = await CaptureFeedbackCheck.run()
                try? Data(result.utf8).write(to: output)
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--capture-check") {
            runCaptureCheck()
            return
        }
        if CommandLine.arguments.contains("--render-preview") {
            renderPreview()
            return
        }
        if let id = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        hotKeys.onAction = { [weak self] action in
            guard let self else { return }
            self.model.perform(action)
            if self.model.errorMessage != nil { self.showSettings() }
        }
        model.onActivated = { [weak self] in self?.settingsWindow?.orderOut(nil) }
        model.onStateChanged = { [weak self] in
            self?.updateStatusIcon()
            if self?.model.errorMessage != nil { self?.showSettings() }
        }
        let failures = hotKeys.register(preferences: model.preferences)
        model.shortcutMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        updateStatusIcon()
        showSettings()
        if CommandLine.arguments.contains("--request-screen-access") {
            model.requestPermission()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        hotKeys.shutdown()
    }

    private func updateStatusIcon() {
        let symbol = model.isEnabled ? "plus.magnifyingglass" : "magnifyingglass"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Focus Lens")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "Focus Lens · \(model.status)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Focus Lens", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        for action in [LensAction.toggle, .spotlight, .zoomIn, .zoomOut, .pin] {
            let title: String
            if action == .toggle { title = model.isEnabled ? "Выключить лупу" : "Включить лупу" }
            else { title = action.title }
            let item = NSMenuItem(title: title + "    " + model.preferences.shortcut(for: action).title,
                                  action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if action == .spotlight { item.state = model.preferences.options.spotlight ? .on : .off }
            if action == .pin { item.state = model.preferences.options.placement != .follow ? .on : .off }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Завершить Focus Lens", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = LensAction(rawValue: raw) else { return }
        model.perform(action)
    }
    @objc private func openSettings() { showSettings() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func showSettings() {
        if model.isEnabled { model.setEnabled(false) }
        if settingsWindow == nil {
            let view = NSHostingView(rootView: SettingsView(model: model, hotKeys: hotKeys))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Focus Lens"
            window.titlebarAppearsTransparent = true
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        model.refreshPermission()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Renders our own UI and a synthetic capture frame. Never reads desktop pixels.
    private func renderPreview() {
        guard let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
              CommandLine.arguments.count > index + 1 else { NSApp.terminate(nil); return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        let previewModel = AppModel(preferences: Preferences(defaults: UserDefaults(suiteName: "FocusLens.Preview")!))
        let view = NSHostingView(rootView: SettingsView(model: previewModel, hotKeys: hotKeys))
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 800, height: 620),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        settingsWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw PreviewError.renderFailed }
                view.cacheDisplay(in: view.bounds, to: rep)
                guard let png = rep.representation(using: .png, properties: [:]) else { throw PreviewError.renderFailed }
                try png.write(to: directory.appendingPathComponent("Focus-Lens-settings.png"))
                try SyntheticChecks.run(output: directory)
                try Data("UI render and synthetic overlay checks passed.\n".utf8)
                    .write(to: directory.appendingPathComponent("preview-check.txt"))
            } catch {
                try? Data(String(reflecting: error).utf8).write(to: directory.appendingPathComponent("preview-error.txt"))
            }
            previewModel.shutdown()
            settingsWindow?.orderOut(nil)
            NSApp.terminate(nil)
        }
    }
    enum PreviewError: Error { case renderFailed }

    private func runCaptureCheck() {
        guard let index = CommandLine.arguments.firstIndex(of: "--capture-check"),
              CommandLine.arguments.count > index + 1 else { NSApp.terminate(nil); return }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        // Match normal startup: the app has registered, hidden overlay windows.
        _ = model
        Task { @MainActor in
            var result = "PERMISSION_REQUIRED: no capture attempted.\n"
            if CGPreflightScreenCaptureAccess(), let screen = NSScreen.main, let id = screen.displayID {
                let capture = ScreenCapture()
                do {
                    try await capture.start(displayID: id, scale: screen.backingScaleFactor, fps: 60)
                    try await Task.sleep(for: .seconds(2))
                    if let image = capture.image {
                        result = "PASS: live frames=\(capture.sequence), pixels=\(Int(image.extent.width))x\(Int(image.extent.height)); no pixels saved.\n"
                    } else { result = "FAIL: stream started without a complete frame.\n" }
                } catch { result = "FAIL: \(error.localizedDescription)\n" }
                await capture.stop()
                result += capture.image == nil ? "PASS: frame released after stop.\n" : "FAIL: frame retained after stop.\n"
            }
            try? Data(result.utf8).write(to: output)
            NSApp.terminate(nil)
        }
    }
}
