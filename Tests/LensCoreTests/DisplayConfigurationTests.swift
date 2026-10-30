import CoreGraphics
import Testing
@testable import LensCore

struct DisplayConfigurationTests {
    private let original = DisplayConfiguration(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)

    @Test func unchangedDisplayDoesNotNeedNewCapture() {
        let afterSpaceSwitch = DisplayConfiguration(id: 1, frame: original.frame, scale: 2)
        #expect(original == afterSpaceSwitch)
        #expect(original.hasSameCaptureFormat(as: afterSpaceSwitch))
    }

    @Test func desktopRearrangementUpdatesLayoutWithoutRestartingCapture() {
        let moved = DisplayConfiguration(id: 1, frame: original.frame.offsetBy(dx: -1920, dy: 200), scale: 2)
        #expect(original != moved)
        #expect(original.hasSameCaptureFormat(as: moved))
    }

    @Test func changedMonitorResolutionOrScaleNeedsNewCapture() {
        let anotherDisplay = DisplayConfiguration(id: 2, frame: original.frame, scale: 2)
        let resized = DisplayConfiguration(id: 1, frame: CGRect(x: 0, y: 0, width: 1280, height: 800), scale: 2)
        let nonRetina = DisplayConfiguration(id: 1, frame: original.frame, scale: 1)
        #expect(!original.hasSameCaptureFormat(as: anotherDisplay))
        #expect(!original.hasSameCaptureFormat(as: resized))
        #expect(!original.hasSameCaptureFormat(as: nonRetina))
    }
}
