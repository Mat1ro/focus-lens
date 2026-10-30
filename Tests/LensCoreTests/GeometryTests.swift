import Foundation
import CoreGraphics
import Testing
@testable import LensCore

struct GeometryTests {
    @Test(arguments: LensShape.allCases, LensPlacement.allCases)
    func lensRemainsVisibleAtEveryCorner(shape: LensShape, placement: LensPlacement) {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -1920, y: -240, width: 1920, height: 1080),
                       CGRect(x: 500, y: 982, width: 800, height: 600)]
        var options = LensOptions()
        options.width = 800
        options.height = 600
        options.shape = shape
        options.placement = placement
        for screen in screens {
            let corners = [CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX, y: screen.minY),
                           CGPoint(x: screen.minX, y: screen.maxY), CGPoint(x: screen.maxX, y: screen.maxY)]
            for corner in corners {
                let frame = LensGeometry.frame(pointer: corner, screen: screen, options: options)
                #expect(screen.contains(frame))
                #expect(frame.width > 0 && frame.height > 0)
                if shape == .circle || shape == .square { #expect(frame.width == frame.height) }
            }
        }
    }

    @Test func retinaSourceUsesPhysicalPixels() {
        let source = LensGeometry.sourceRect(pointer: CGPoint(x: 500, y: 400),
                                             screen: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                             pixelSize: CGSize(width: 2000, height: 1600),
                                             lensSize: CGSize(width: 300, height: 200), zoom: 2)
        #expect(source == CGRect(x: 850, y: 700, width: 300, height: 200))
    }

    @Test func leftDisplayWithOffsetUsesLocalCoordinates() {
        let source = LensGeometry.sourceRect(pointer: CGPoint(x: -1700, y: 100),
                                             screen: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                                             pixelSize: CGSize(width: 1920, height: 1080),
                                             lensSize: CGSize(width: 400, height: 200), zoom: 2)
        #expect(source.midX == 220)
        #expect(source.midY == 300)
        #expect(source.size == CGSize(width: 200, height: 100))
    }

    @Test func cursorStaysCentredAtEdgeInsteadOfBeingClippedByCircle() {
        let source = LensGeometry.sourceRect(pointer: .zero,
                                             screen: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                             pixelSize: CGSize(width: 2000, height: 1600),
                                             lensSize: CGSize(width: 340, height: 340), zoom: 2.5)
        #expect(source.midX == 0)
        #expect(source.midY == 0)
        #expect(source.minX < 0 && source.minY < 0)
    }

    @Test func pinKeepsOutputStableWhileSourceMoves() {
        var options = LensOptions()
        options.placement = .topRight
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let a = CGPoint(x: 100, y: 100), b = CGPoint(x: 1000, y: 600)
        let frameA = LensGeometry.frame(pointer: a, screen: screen, options: options)
        let frameB = LensGeometry.frame(pointer: b, screen: screen, options: options)
        #expect(frameA == frameB)
        let cropA = LensGeometry.sourceRect(pointer: a, screen: screen, pixelSize: screen.size, lensSize: frameA.size, zoom: 2)
        let cropB = LensGeometry.sourceRect(pointer: b, screen: screen, pixelSize: screen.size, lensSize: frameB.size, zoom: 2)
        #expect(cropB.midX - cropA.midX == 900)
        #expect(cropB.midY - cropA.midY == 500)
    }

    @Test func persistedValuesCannotProduceInvalidGeometry() throws {
        var options = LensOptions()
        options.zoom = .nan
        options.width = -.infinity
        options.height = 999_999
        options.dimOpacity = -1
        options.frameRate = 10000
        options.normalize()
        #expect(options.zoom == 2.5)
        #expect(options.width == 340)
        #expect(options.height == 600)
        #expect(options.dimOpacity == 0.1)
        #expect(options.frameRate == 60)
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(LensOptions.self, from: data) == options)
    }
}
