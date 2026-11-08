import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let blue = CGColor(red: 0.035, green: 0.30, blue: 0.76, alpha: 1)
context.setFillColor(blue)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 278, y: 265, width: 468, height: 550),
    cornerWidth: 100, cornerHeight: 100, transform: nil))
context.fillPath()
context.setFillColor(blue)
context.addPath(CGPath(roundedRect: CGRect(x: 326, y: 490, width: 372, height: 245),
    cornerWidth: 38, cornerHeight: 38, transform: nil))
context.fillPath()
context.fillEllipse(in: CGRect(x: 336, y: 335, width: 70, height: 70))
context.fillEllipse(in: CGRect(x: 618, y: 335, width: 70, height: 70))
context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(34)
context.setLineCap(.round)
context.move(to: CGPoint(x: 401, y: 273))
context.addLine(to: CGPoint(x: 337, y: 178))
context.move(to: CGPoint(x: 623, y: 273))
context.addLine(to: CGPoint(x: 687, y: 178))
context.move(to: CGPoint(x: 361, y: 210))
context.addLine(to: CGPoint(x: 663, y: 210))
context.strokePath()
let directory = URL(fileURLWithPath: "TomsTrains/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent("AppIcon.png") as CFURL,
    UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
try """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
""".write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(
    to: directory.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
