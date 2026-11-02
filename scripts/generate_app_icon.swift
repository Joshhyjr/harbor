import Foundation
import CoreGraphics
import ImageIO

// An opaque vector-rendered sailboat matches Harbor's palette; iOS supplies the rounded icon mask.
let side = 1024
let bitmap = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
bitmap.setFillColor(CGColor(red: 0.28, green: 0.33, blue: 0.96, alpha: 1))
bitmap.fill(CGRect(x: 0, y: 0, width: side, height: side))
bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
func polygon(_ points: [CGPoint]) {
    bitmap.beginPath()
    bitmap.move(to: points[0])
    points.dropFirst().forEach { bitmap.addLine(to: $0) }
    bitmap.closePath()
    bitmap.fillPath()
}
polygon([CGPoint(x: 535, y: 790), CGPoint(x: 535, y: 400), CGPoint(x: 800, y: 400)])
polygon([CGPoint(x: 490, y: 690), CGPoint(x: 490, y: 400), CGPoint(x: 255, y: 400)])
bitmap.fill(CGRect(x: 505, y: 340, width: 14, height: 470))
polygon([CGPoint(x: 225, y: 355), CGPoint(x: 815, y: 355), CGPoint(x: 735, y: 245), CGPoint(x: 325, y: 245)])
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = root.appendingPathComponent("Harbor/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let output = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(output, bitmap.makeImage()!, nil)
guard CGImageDestinationFinalize(output) else { fatalError("Could not save app icon") }
print("Generated opaque 1024 × 1024 Harbor app icon")
