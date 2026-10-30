import AppKit
import CoreImage
import ScreenCaptureKit

/// Integration regression for a stream started while all app windows are hidden.
/// Only synthetic marker matches are reported. Desktop pixels are never saved.
enum CaptureFeedbackCheck {
    static func run() async -> String {
        guard CGPreflightScreenCaptureAccess(), let screen = NSScreen.main, let id = screen.displayID else {
            return "PERMISSION_REQUIRED\n"
        }
        let panel = OverlayPanel()
        let frame = CGRect(x: screen.frame.midX - 150, y: screen.frame.midY - 100, width: 300, height: 200)
        panel.setFrame(frame, display: false)
        panel.contentView = MarkerView(frame: CGRect(origin: .zero, size: frame.size))
        let capture = ScreenCapture()
        var log: [String] = []
        defer { panel.close() }
        do {
            for visibleOnly in [true, false] {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: visibleOnly)
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                log.append("hidden-start visibleOnly=\(visibleOnly) ownApplications=\(own.count)")
            }
            try await capture.start(displayID: id, scale: screen.backingScaleFactor, fps: 60)
            panel.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(650))
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CheckError.display }
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
            config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
            config.showsCursor = false
            let unfiltered = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
            let control = hasMarker(CIImage(cgImage: unfiltered), screen: screen.frame, frame: frame)
            log.append(control ? "PASS: unfiltered positive control contains marker" : "FAIL: marker control not visible")
            if let image = capture.image {
                log.append(hasMarker(image, screen: screen.frame, frame: frame)
                    ? "FAIL: own overlay entered capture (feedback possible)"
                    : "PASS: own overlay excluded from capture")
            } else { log.append("FAIL: no stream frame") }
            await capture.stop()
            panel.orderOut(nil)

            // Toggle off/on with every window hidden, then create an entirely
            // new panel after the exclusion filter was constructed.
            try await capture.start(displayID: id, scale: screen.backingScaleFactor, fps: 60)
            let latePanel = OverlayPanel()
            let lateFrame = frame.offsetBy(dx: 45, dy: 35)
            latePanel.setFrame(lateFrame, display: false)
            latePanel.contentView = MarkerView(frame: CGRect(origin: .zero, size: lateFrame.size))
            latePanel.orderFrontRegardless()
            defer { latePanel.close() }
            try await Task.sleep(for: .milliseconds(650))
            let lateControl = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
            log.append(hasMarker(CIImage(cgImage: lateControl), screen: screen.frame, frame: lateFrame)
                ? "PASS: newly-created panel positive control" : "FAIL: newly-created panel control")
            if let image = capture.image {
                log.append(hasMarker(image, screen: screen.frame, frame: lateFrame)
                    ? "FAIL: new panel entered capture after restart"
                    : "PASS: new panel excluded after hidden-window restart")
            } else { log.append("FAIL: no frame after restart") }
            await capture.stop()
        } catch {
            await capture.stop()
            log.append("ERROR: \(error.localizedDescription)")
        }
        return log.joined(separator: "\n") + "\n"
    }

    private static func hasMarker(_ image: CIImage, screen: CGRect, frame: CGRect) -> Bool {
        let context = CIContext()
        let sx = image.extent.width / screen.width
        let sy = image.extent.height / screen.height
        return (0..<4).allSatisfy { index in
            let point = CGPoint(x: (frame.minX + frame.width * (Double(index) + 0.5) / 4 - screen.minX) * sx,
                                y: (frame.midY - screen.minY) * sy)
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return index.isMultiple(of: 2)
                ? pixel[0] > 220 && pixel[1] < 35 && pixel[2] > 220
                : pixel[0] < 35 && pixel[1] > 220 && pixel[2] > 220
        }
    }

    private final class MarkerView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            for index in 0..<4 {
                (index.isMultiple(of: 2) ? NSColor.magenta : NSColor.cyan).setFill()
                NSRect(x: bounds.width * Double(index) / 4, y: 0, width: bounds.width / 4, height: bounds.height).fill()
            }
        }
    }
    enum CheckError: Error { case display }
}
