import Foundation
import CoreGraphics

public enum LensShape: String, Codable, CaseIterable, Sendable {
    case circle, square, rounded, rectangle

    public var title: String {
        switch self {
        case .circle: "Круг"
        case .square: "Квадрат"
        case .rounded: "Скруглённая"
        case .rectangle: "Прямоугольник"
        }
    }

    public var symbol: String {
        switch self {
        case .circle: "circle"
        case .square: "square"
        case .rounded: "rectangle.roundedtop"
        case .rectangle: "rectangle"
        }
    }
}

public enum LensPlacement: String, Codable, CaseIterable, Sendable {
    case follow, topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .follow: "Следовать за курсором"
        case .topLeft: "Сверху слева"
        case .topRight: "Сверху справа"
        case .bottomLeft: "Снизу слева"
        case .bottomRight: "Снизу справа"
        }
    }
}

public struct LensOptions: Codable, Equatable, Sendable {
    public var zoom = 2.5
    public var width = 340.0
    public var height = 240.0
    public var shape = LensShape.circle
    public var placement = LensPlacement.follow
    public var spotlight = false
    public var dimOpacity = 0.45
    public var border = true
    public var borderWidth = 2.0
    public var glow = true
    public var cursorVisible = true
    public var cursorScale = 1.5
    public var smoothPixels = true
    public var frameRate = 60

    public init() {}

    public mutating func normalize() {
        zoom = zoom.isFinite ? min(max(zoom, 1.5), 10) : 2.5
        width = width.isFinite ? min(max(width, 160), 800) : 340
        height = height.isFinite ? min(max(height, 120), 600) : 240
        dimOpacity = dimOpacity.isFinite ? min(max(dimOpacity, 0.1), 0.8) : 0.45
        borderWidth = borderWidth.isFinite ? min(max(borderWidth, 1), 8) : 2
        cursorScale = cursorScale.isFinite ? min(max(cursorScale, 0.5), 3) : 1.5
        frameRate = frameRate == 30 ? 30 : 60
    }
}

public enum LensGeometry {
    /// AppKit coordinates throughout: screen origin at bottom left, possibly negative.
    public static func frame(pointer: CGPoint, screen: CGRect, options: LensOptions) -> CGRect {
        let margin = min(16.0, min(screen.width, screen.height) / 8)
        let available = screen.insetBy(dx: margin, dy: margin)
        var width = min(options.width, available.width)
        var height = min(options.height, available.height)
        if options.shape == .circle || options.shape == .square {
            width = min(width, available.height)
            height = width
        }
        let x: CGFloat
        let y: CGFloat
        switch options.placement {
        case .follow:
            x = min(max(pointer.x - width / 2, available.minX), available.maxX - width)
            y = min(max(pointer.y - height / 2, available.minY), available.maxY - height)
        case .topLeft: x = available.minX; y = available.maxY - height
        case .topRight: x = available.maxX - width; y = available.maxY - height
        case .bottomLeft: x = available.minX; y = available.minY
        case .bottomRight: x = available.maxX - width; y = available.minY
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Keep the pointer at the lens centre even at a screen edge. The renderer pads
    /// unavailable pixels instead of moving the pointer outside a circular mask.
    public static func sourceRect(pointer: CGPoint, screen: CGRect, pixelSize: CGSize,
                                  lensSize: CGSize, zoom: Double) -> CGRect {
        let sx = pixelSize.width / screen.width
        let sy = pixelSize.height / screen.height
        let size = CGSize(width: lensSize.width / zoom * sx, height: lensSize.height / zoom * sy)
        return CGRect(x: (pointer.x - screen.minX) * sx - size.width / 2,
                      y: (pointer.y - screen.minY) * sy - size.height / 2,
                      width: size.width, height: size.height)
    }
}
