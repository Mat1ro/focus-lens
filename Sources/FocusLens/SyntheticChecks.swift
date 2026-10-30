import AppKit
import CoreImage
import LensCore

enum SyntheticChecks {
    enum Failure: Error { case image, unexpectedPixel, notClickThrough }

    static func run(output: URL) throws {
        // Four coloured quadrants expose inverted coordinates and wrong crop centres.
        let size = CGSize(width: 800, height: 600)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmap = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
                                     bytesPerRow: 3200, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.image }
        for (rect, color) in [
            (CGRect(x: 0, y: 0, width: 400, height: 300), NSColor.red),
            (CGRect(x: 400, y: 0, width: 400, height: 300), NSColor.green),
            (CGRect(x: 0, y: 300, width: 400, height: 300), NSColor.blue),
            (CGRect(x: 400, y: 300, width: 400, height: 300), NSColor.white)
        ] {
            bitmap.setFillColor(color.cgColor)
            bitmap.fill(rect)
        }
        guard let image = bitmap.makeImage() else { throw Failure.image }
        let ciImage = CIImage(cgImage: image)
        let context = CIContext()
        let screen = CGRect(origin: .zero, size: size)
        var options = LensOptions()
        options.width = 200
        options.height = 160
        options.cursorVisible = false
        let source = LensGeometry.sourceRect(pointer: CGPoint(x: 200, y: 450), screen: screen,
                                             pixelSize: size, lensSize: CGSize(width: 200, height: 200), zoom: 2)
        guard let crop = context.createCGImage(ciImage, from: source) else { throw Failure.image }
        let sampled = NSBitmapImageRep(cgImage: crop).colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB)
        guard let sampled, sampled.blueComponent > 0.9, sampled.redComponent < 0.1 else { throw Failure.unexpectedPixel }

        for shape in LensShape.allCases {
            options.shape = shape
            let view = LensView(frame: CGRect(x: 0, y: 0, width: 236,
                                              height: shape == .circle || shape == .square ? 236 : 196))
            view.options = options
            view.magnifiedImage = image
            let panel = OverlayPanel()
            panel.setFrame(view.frame, display: false)
            panel.contentView = view
            guard panel.ignoresMouseEvents, !panel.canBecomeKey, !panel.canBecomeMain else { throw Failure.notClickThrough }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure.image }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.image }
            try png.write(to: output.appendingPathComponent("lens-\(shape.rawValue).png"))
            panel.close()
        }
    }
}
