import AppKit
import LensCore
import Observation
import ScreenCaptureKit

@Observable final class AppModel {
    let preferences: Preferences
    private(set) var isEnabled = false
    private(set) var isStarting = false
    private(set) var hasPermission: Bool
    private(set) var isCheckingPermission = false
    var errorMessage: String?
    var shortcutMessage: String?
    var onActivated: (() -> Void)?
    var onStateChanged: (() -> Void)?
    private let overlay = OverlayController()
    private var capture: ScreenCapture?
    private var timer: Timer?
    private var sessionTask: Task<Void, Never>?
    private var generation = 0
    private(set) var captureStartCount = 0
    private var displayLayout: [DisplayConfiguration] = []
    private var activeDisplayConfiguration: DisplayConfiguration?
    private var activeDisplayID: CGDirectDisplayID?
    private var activeFPS = 60
    private var captureAccessVerified = false
    private let preflight: () -> Bool
    private var observers: [any NSObjectProtocol] = []

    init(preferences: Preferences = Preferences(), preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        self.preferences = preferences
        self.preflight = preflight
        self.hasPermission = preflight()
        displayLayout = NSScreen.displayLayout
        overlay.rebuildScreens()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenParametersChanged()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.setEnabled(false) } })
    }

    var status: String {
        if isStarting { return "Подключаю экран…" }
        return isEnabled ? "Лупа включена" : "Готова к работе"
    }

    func refreshPermission() {
        hasPermission = captureAccessVerified || preflight()
        if hasPermission { errorMessage = nil }
    }

    /// A negative preflight can describe an obsolete authorization after an
    /// update. Explicit user actions ask ScreenCaptureKit itself; it still
    /// enforces macOS consent and returns the authoritative capture error.
    func verifyPermission() {
        guard !isCheckingPermission else { return }
        if isEnabled || preflight() || captureAccessVerified {
            refreshPermission()
            return
        }
        isCheckingPermission = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCheckingPermission = false }
            let probe = ScreenCapture()
            do {
                guard let screen = self.currentScreen(), let id = screen.displayID else {
                    throw ScreenCapture.CaptureError.displayMissing
                }
                try await probe.start(displayID: id, scale: screen.backingScaleFactor, fps: 30)
                for _ in 0..<30 {
                    if probe.image != nil { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard probe.image != nil else { throw ScreenCapture.CaptureError.noFrame }
                self.hasPermission = true
                self.captureAccessVerified = true
                self.errorMessage = nil
            } catch { self.reportCaptureError(error) }
            await probe.stop()
            self.onStateChanged?()
        }
    }

    func requestPermission() {
        if preflight() || captureAccessVerified {
            refreshPermission()
            return
        }
        hasPermission = CGRequestScreenCaptureAccess()
        if !hasPermission { openPrivacySettings() }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        errorMessage = nil
        if enabled {
            guard !isCheckingPermission else { return }
            isEnabled = true
            onActivated?()
            restartCapture()
            startTimer()
        } else {
            isEnabled = false
            isStarting = false
            generation += 1
            sessionTask?.cancel()
            timer?.invalidate()
            timer = nil
            overlay.hide()
            let oldCapture = capture
            capture = nil
            activeDisplayID = nil
            activeDisplayConfiguration = nil
            Task { await oldCapture?.stop() }
        }
        onStateChanged?()
    }

    private func startTimer() {
        timer?.invalidate()
        let fps = preferences.options.frameRate
        activeFPS = fps
        let timer = Timer(timeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func currentScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
    }

    private func screenParametersChanged() {
        // A notification alone does not mean the physical display changed.
        // Comparing IDs, full frames and scale avoids querying ScreenCaptureKit
        // again when only the workspace / menu bar / Dock visibility changes.
        let newLayout = NSScreen.displayLayout
        guard newLayout != displayLayout else { return }
        displayLayout = newLayout
        overlay.rebuildScreens()
        guard isEnabled, let configuration = currentScreen()?.captureConfiguration else { return }
        if activeDisplayConfiguration?.hasSameCaptureFormat(as: configuration) != true {
            restartCapture()
        } else {
            // A monitor moved in the desktop layout; its existing stream is valid.
            activeDisplayConfiguration = configuration
        }
    }

    private func restartCapture() {
        guard isEnabled, let screen = currentScreen(), let id = screen.displayID else { return }
        generation += 1
        captureStartCount += 1
        activeDisplayConfiguration = screen.captureConfiguration
        let currentGeneration = generation
        sessionTask?.cancel()
        let oldCapture = capture
        let newCapture = ScreenCapture()
        newCapture.onFailure = { [weak self] message in
            guard let self, self.generation == currentGeneration, self.isEnabled else { return }
            self.setEnabled(false)
            self.errorMessage = "Захват экрана остановлен: \(message)"
            self.onStateChanged?()
        }
        capture = newCapture
        activeDisplayID = id
        isStarting = true
        overlay.hide()
        let scale = screen.backingScaleFactor
        let fps = preferences.options.frameRate
        sessionTask = Task { [weak self] in
            await oldCapture?.stop()
            do {
                try Task.checkCancellation()
                try await newCapture.start(displayID: id, scale: scale, fps: fps)
                guard let self, self.generation == currentGeneration, self.isEnabled else {
                    await newCapture.stop()
                    return
                }
                self.isStarting = false
                self.hasPermission = true
                self.captureAccessVerified = true
                self.onStateChanged?()
            } catch {
                await newCapture.stop()
                guard let self, self.generation == currentGeneration, !Task.isCancelled else { return }
                self.setEnabled(false)
                self.reportCaptureError(error)
                self.onStateChanged?()
            }
        }
    }

    private func reportCaptureError(_ error: any Error) {
        let systemError = error as NSError
        if systemError.domain == SCStreamErrorDomain && systemError.code == SCStreamError.Code.userDeclined.rawValue {
            captureAccessVerified = false
            hasPermission = false
            errorMessage = "macOS не подтвердила доступ для этой сборки. Если переключатель уже включён, удали старую запись Focus Lens кнопкой «−», добавь текущее приложение через «+» и включи доступ заново."
        } else {
            errorMessage = "Не удалось получить изображение экрана: \(error.localizedDescription)"
        }
    }

    private func tick() {
        guard isEnabled, let screen = currentScreen() else { return }
        if screen.displayID != activeDisplayID {
            restartCapture()
            return
        }
        if activeFPS != preferences.options.frameRate {
            startTimer()
            restartCapture()
            return
        }
        guard let capture, let image = capture.image else { return }
        overlay.show(image: image, sequence: capture.sequence, pointer: NSEvent.mouseLocation,
                     screen: screen, options: preferences.options)
    }

    func perform(_ action: LensAction) {
        switch action {
        case .toggle: setEnabled(!isEnabled)
        case .spotlight: preferences.options.spotlight.toggle()
        case .zoomIn: preferences.options.zoom = min(10, preferences.options.zoom + 0.5)
        case .zoomOut: preferences.options.zoom = max(1.5, preferences.options.zoom - 0.5)
        case .larger:
            preferences.options.width = min(800, preferences.options.width + 40)
            preferences.options.height = min(600, preferences.options.height + 30)
        case .smaller:
            preferences.options.width = max(160, preferences.options.width - 40)
            preferences.options.height = max(120, preferences.options.height - 30)
        case .shape:
            let shapes = LensShape.allCases
            let index = shapes.firstIndex(of: preferences.options.shape) ?? 0
            preferences.options.shape = shapes[(index + 1) % shapes.count]
        case .pin:
            preferences.options.placement = preferences.options.placement == .follow ? .topRight : .follow
        }
        onStateChanged?()
    }

    func shutdown() {
        setEnabled(false)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}

extension NSScreen {
    static var displayLayout: [DisplayConfiguration] {
        screens.compactMap(\.captureConfiguration).sorted { $0.id < $1.id }
    }

    var captureConfiguration: DisplayConfiguration? {
        guard let displayID else { return nil }
        return DisplayConfiguration(id: displayID, frame: frame, scale: backingScaleFactor)
    }

    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
