import CoreGraphics

/// Screen geometry independent of Spaces, Dock visibility and NSScreen ordering.
public struct DisplayConfiguration: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let scale: CGFloat

    public init(id: UInt32, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }

    /// Moving a display in the desktop layout does not invalidate its stream.
    public func hasSameCaptureFormat(as other: DisplayConfiguration) -> Bool {
        id == other.id && frame.size == other.frame.size && scale == other.scale
    }
}
