import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, pixels) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),
                       ("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),
                       ("512x512",512),("512x512@2x",1024)] {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let scale = CGFloat(pixels) / 512
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let background = NSBezierPath(roundedRect: CGRect(x: 20, y: 20, width: 472, height: 472), xRadius: 110, yRadius: 110)
    NSGradient(starting: NSColor(red: 0.08, green: 0.16, blue: 0.2, alpha: 1),
               ending: NSColor(red: 0.025, green: 0.07, blue: 0.09, alpha: 1))!.draw(in: background, angle: 90)
    let lens = NSBezierPath(ovalIn: CGRect(x: 112, y: 162, width: 240, height: 240))
    NSColor.systemMint.withAlphaComponent(0.13).setFill()
    lens.fill()
    NSColor.systemMint.setStroke()
    lens.lineWidth = 18
    lens.stroke()
    let handle = NSBezierPath()
    handle.move(to: CGPoint(x: 320, y: 187))
    handle.line(to: CGPoint(x: 398, y: 109))
    handle.lineWidth = 27
    handle.lineCapStyle = .round
    handle.stroke()
    let plus = NSBezierPath()
    plus.move(to: CGPoint(x: 232, y: 236)); plus.line(to: CGPoint(x: 232, y: 328))
    plus.move(to: CGPoint(x: 186, y: 282)); plus.line(to: CGPoint(x: 278, y: 282))
    NSColor.white.withAlphaComponent(0.9).setStroke()
    plus.lineWidth = 13
    plus.lineCapStyle = .round
    plus.stroke()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(name).png"))
}
