import AppKit
import CoreImage
import LensCore

enum LensPath {
    static func make(in rect: CGRect, shape: LensShape) -> NSBezierPath {
        switch shape {
        case .circle: NSBezierPath(ovalIn: rect)
        case .square, .rectangle: NSBezierPath(rect: rect)
        case .rounded: NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
        }
    }
}

final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .init(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class LensView: NSView {
    static let padding: CGFloat = 18
    var options = LensOptions()
    var magnifiedImage: CGImage?
    var lensRect: CGRect { bounds.insetBy(dx: Self.padding, dy: Self.padding) }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        let rect = lensRect
        let path = LensPath.make(in: rect, shape: options.shape)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        context.saveGState()
        path.addClip()
        if let magnifiedImage {
            context.interpolationQuality = options.smoothPixels ? .high : .none
            context.draw(magnifiedImage, in: rect)
        }
        if options.cursorVisible {
            let cursor = NSCursor.arrow
            let size = NSSize(width: cursor.image.size.width * options.cursorScale,
                              height: cursor.image.size.height * options.cursorScale)
            let origin = CGPoint(x: rect.midX - cursor.hotSpot.x * options.cursorScale,
                                 y: rect.midY - (cursor.image.size.height - cursor.hotSpot.y) * options.cursorScale)
            cursor.image.draw(in: CGRect(origin: origin, size: size), from: .zero,
                              operation: .sourceOver, fraction: 1)
        }
        context.restoreGState()

        if options.border {
            NSGraphicsContext.saveGraphicsState()
            if options.glow {
                let glow = NSShadow()
                glow.shadowColor = NSColor.systemMint.withAlphaComponent(0.7)
                glow.shadowBlurRadius = 9
                glow.shadowOffset = .zero
                glow.set()
            }
            NSColor.systemMint.withAlphaComponent(0.9).setStroke()
            path.lineWidth = options.borderWidth
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

final class SpotlightView: NSView {
    var opacity = 0.45
    var hole: CGRect?
    var shape = LensShape.circle
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        let path = NSBezierPath(rect: bounds)
        if let hole { path.append(LensPath.make(in: hole, shape: shape)) }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(opacity).setFill()
        path.fill()
    }
}

final class OverlayController {
    let lensPanel = OverlayPanel()
    let lensView = LensView()
    private var spotlightPanels: [(screen: NSScreen, panel: OverlayPanel, view: SpotlightView)] = []
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastSource: CGRect?
    private var lastSequence = -1
    private var lastOptions: LensOptions?
    private var lastFrame: CGRect?

    init() { lensPanel.contentView = lensView }

    func rebuildScreens() {
        for item in spotlightPanels { item.panel.orderOut(nil) }
        spotlightPanels = NSScreen.screens.map { screen in
            let panel = OverlayPanel()
            let view = SpotlightView()
            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            return (screen, panel, view)
        }
        invalidate()
    }

    func invalidate() { lastSequence = -1; lastOptions = nil; lastFrame = nil; lastSource = nil }

    func show(image: CIImage, sequence: Int, pointer: CGPoint, screen: NSScreen, options: LensOptions) {
        let frame = LensGeometry.frame(pointer: pointer, screen: screen.frame, options: options)
        let source = LensGeometry.sourceRect(pointer: pointer, screen: screen.frame,
                                             pixelSize: image.extent.size, lensSize: frame.size, zoom: options.zoom)
        if source != lastSource || sequence != lastSequence || options != lastOptions {
            let background = CIImage(color: CIColor(red: 0.055, green: 0.065, blue: 0.08)).cropped(to: source)
            let cropped = image.composited(over: background).cropped(to: source)
            lensView.magnifiedImage = context.createCGImage(cropped, from: source)
            lensView.options = options
            lensView.needsDisplay = true
            lastSequence = sequence
            lastSource = source
        }
        lensPanel.setFrame(frame.insetBy(dx: -LensView.padding, dy: -LensView.padding), display: false)
        if frame != lastFrame || options != lastOptions {
            for item in spotlightPanels {
                if options.spotlight {
                    item.view.opacity = options.dimOpacity
                    item.view.shape = options.shape
                    item.view.hole = item.screen == screen
                        ? frame.offsetBy(dx: -item.screen.frame.minX, dy: -item.screen.frame.minY) : nil
                    item.view.needsDisplay = true
                    if !item.panel.isVisible { item.panel.orderFrontRegardless() }
                } else { item.panel.orderOut(nil) }
            }
            lastFrame = frame
        }
        // Ordering once keeps the lens above the dimming panels without repeated
        // WindowServer order operations at 60 Hz.
        if !lensPanel.isVisible || options.spotlight != lastOptions?.spotlight {
            lensPanel.orderFrontRegardless()
        }
        lastOptions = options
    }

    func hide() {
        lensPanel.orderOut(nil)
        for item in spotlightPanels { item.panel.orderOut(nil) }
        lensView.magnifiedImage = nil
        invalidate()
    }
}
