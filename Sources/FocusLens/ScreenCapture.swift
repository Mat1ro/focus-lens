import AppKit
import CoreImage
import ScreenCaptureKit

// SCStreamOutput predates actor annotations. Its callback queue is explicitly
// .main below; @preconcurrency adds the runtime main-actor check at this bridge.
final class ScreenCapture: NSObject, @preconcurrency SCStreamOutput, SCStreamDelegate {
    private(set) var image: CIImage?
    private(set) var sequence = 0
    private var stream: SCStream?
    var onFailure: ((String) -> Void)?

    func start(displayID: CGDirectDisplayID, scale: CGFloat, fps: Int) async throws {
        // The settings window and overlays are hidden when capture starts. A
        // visible-only query omits our application entirely, producing an empty
        // exclusion list and a recursive hall of mirrors once the lens appears.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayMissing
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        // Never start an unfiltered display stream if WindowServer hasn't
        // registered our windows yet. App-wide exclusion also covers panels
        // created later, including Spotlight panels after a display change.
        guard !ownApps.isEmpty else { throw CaptureError.exclusionUnavailable }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.capturesAudio = false
        config.scalesToFit = true
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        // This explicitly delivers frame callbacks on the main queue. No images or
        // mutable capture state cross actor boundaries, and only one frame is retained.
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        stream = newStream
        do {
            try await newStream.startCapture()
            try Task.checkCancellation()
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        let previous = stream
        stream = nil
        image = nil
        if let previous { try? await previous.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard stream === self.stream,
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: rawStatus) == .complete,
                  let buffer = sampleBuffer.imageBuffer else { return }
        image = CIImage(cvPixelBuffer: buffer)
        sequence &+= 1
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.onFailure?(message) }
    }

    enum CaptureError: LocalizedError {
        case displayMissing
        case exclusionUnavailable
        case noFrame
        var errorDescription: String? {
            switch self {
            case .displayMissing: "Экран отключён. Включи лупу ещё раз на доступном экране."
            case .exclusionUnavailable: "macOS ещё не зарегистрировала окна Focus Lens. Открой настройки приложения и включи лупу повторно."
            case .noFrame: "Поток открылся, но macOS не передала кадр. Проверь доступ к экрану и попробуй ещё раз."
            }
        }
    }
}
