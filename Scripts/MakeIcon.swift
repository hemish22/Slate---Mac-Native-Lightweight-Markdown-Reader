import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var chunks = Data()
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let size = points * scale
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let rect = CGRect(x: 58, y: 58, width: 908, height: 908)
    let path = CGPath(roundedRect: rect, cornerWidth: 208, cornerHeight: 208, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x373947), color(0x1c1d27)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 300, y: 966), end: CGPoint(x: 730, y: 58), options: [])
    context.restoreGState()
    context.setStrokeColor(color(0x88859f, 0.35))
    context.setLineWidth(3)
    context.addPath(path)
    context.strokePath()

    // A document panel and the familiar Markdown M + down arrow.
    let panel = CGRect(x: 188, y: 226, width: 648, height: 580)
    context.setFillColor(color(0x242632))
    context.addPath(CGPath(roundedRect: panel, cornerWidth: 48, cornerHeight: 48, transform: nil))
    context.fillPath()
    context.setStrokeColor(color(0x77728d, 0.48))
    context.setLineWidth(5)
    context.addPath(CGPath(roundedRect: panel, cornerWidth: 48, cornerHeight: 48, transform: nil))
    context.strokePath()
    context.setStrokeColor(color(0x454553))
    context.move(to: CGPoint(x: 190, y: 698)); context.addLine(to: CGPoint(x: 834, y: 698)); context.strokePath()
    for x in [232, 259, 286] {
        context.setFillColor(color(x == 232 ? 0xc099ff : 0x737187))
        context.fillEllipse(in: CGRect(x: x, y: 742, width: 11, height: 11))
    }
    context.setStrokeColor(color(0xd7bbff))
    context.setLineWidth(43)
    context.setLineCap(.square)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 280, y: 408)); context.addLine(to: CGPoint(x: 280, y: 594))
    context.addLine(to: CGPoint(x: 374, y: 486)); context.addLine(to: CGPoint(x: 468, y: 594)); context.addLine(to: CGPoint(x: 468, y: 408)); context.strokePath()
    context.setStrokeColor(color(0xc099ff))
    context.move(to: CGPoint(x: 660, y: 594)); context.addLine(to: CGPoint(x: 660, y: 419)); context.strokePath()
    context.move(to: CGPoint(x: 591, y: 471)); context.addLine(to: CGPoint(x: 660, y: 402)); context.addLine(to: CGPoint(x: 729, y: 471)); context.strokePath()
    context.setStrokeColor(color(0x8a7aab, 0.7))
    context.setLineWidth(12)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: 279, y: 309)); context.addLine(to: CGPoint(x: 486, y: 309)); context.strokePath()
    context.setStrokeColor(color(0x565264))
    context.move(to: CGPoint(x: 531, y: 309)); context.addLine(to: CGPoint(x: 744, y: 309)); context.strokePath()
    let suffix = scale == 2 ? "@2x" : ""
    let file = output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Failed to write icon") }
    let tag: String
    switch (points, scale) {
    case (16, 1): tag = "icp4"
    case (16, 2): tag = "ic11"
    case (32, 1): tag = "icp5"
    case (32, 2): tag = "ic12"
    case (128, 1): tag = "ic07"
    case (128, 2): tag = "ic13"
    case (256, 1): tag = "ic08"
    case (256, 2): tag = "ic14"
    case (512, 1): tag = "ic09"
    default: tag = "ic10"
    }
    let png = try Data(contentsOf: file)
    chunks.append(Data(tag.utf8))
    chunks.append(bigEndian(png.count + 8))
    chunks.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndian(chunks.count + 8))
icns.append(chunks)
try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
