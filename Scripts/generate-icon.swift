#!/usr/bin/env swift
import AppKit

// Original vector artwork, licensed with the project. No third-party assets.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}
func render(_ size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { throw CocoaError(.coderInvalidValue) }
    context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let tile = CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864), cornerWidth: 190, cornerHeight: 190, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0.2, 0.08, 0, 0.22))
    context.addPath(tile); context.setFillColor(color(1, 0.42, 0.06)); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(tile); context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(1, 0.72, 0.20), color(1, 0.42, 0.06), color(0.91, 0.22, 0.04)] as CFArray,
        locations: [0, 0.6, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 220, y: 940), end: CGPoint(x: 800, y: 80), options: [])
    context.restoreGState()
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat, _ fill: CGColor) {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(fill); context.fillPath()
    }
    rect(200, 322, 624, 380, 52, color(0.20, 0.10, 0.06))
    let cream = color(1, 0.96, 0.88)
    rect(244, 410, 152, 206, 18, color(1, 0.96, 0.88, 0.65))
    rect(436, 398, 152, 230, 18, cream)
    rect(628, 410, 152, 206, 18, color(1, 0.96, 0.88, 0.65))
    for index in 0..<5 {
        let x = CGFloat(250 + index * 120)
        rect(x, 652, 44, 22, 7, color(1, 0.56, 0.12))
        rect(x, 350, 44, 22, 7, color(1, 0.42, 0.07))
    }
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return png
}
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
    try render(points * scale).write(to: iconset.appendingPathComponent(name))
}
try render(1024).write(to: resources.appendingPathComponent("AppIcon.png"))
print("Generated original AppIcon PNGs (16–1024 px).")
