#!/usr/bin/env swift
import AppKit
import Foundation

// 原创矢量心电波形，沿用菜单栏的图形主题；生成所有 macOS 标准图标尺寸。
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent(".build/app-icon-qa", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "CodexPulseIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create icon bitmap."])
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let gradient = NSGradient(starting: NSColor(srgbRed: 0.89, green: 0.94, blue: 1, alpha: 1),
                                    ending: NSColor(srgbRed: 0.99, green: 0.995, blue: 1, alpha: 1)) else {
        throw NSError(domain: "CodexPulseIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create icon gradient."])
    }
    gradient.draw(in: tile, angle: 90)
    NSColor(srgbRed: 0.40, green: 0.58, blue: 0.78, alpha: 0.16).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    let pulse = NSBezierPath()
    pulse.move(to: NSPoint(x: 226, y: 505))
    for point in [NSPoint(x: 345, y: 505), NSPoint(x: 405, y: 695),
                  NSPoint(x: 474, y: 325), NSPoint(x: 541, y: 595),
                  NSPoint(x: 584, y: 505), NSPoint(x: 798, y: 505)] {
        pulse.line(to: point)
    }
    pulse.lineWidth = 42
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1).setStroke()
    pulse.stroke()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexPulseIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot encode icon PNG."])
    }
    return data
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: size * scale).write(to: iconset.appendingPathComponent(filename), options: .atomic)
    }
}
let icon = root.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icon.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "CodexPulseIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}
print("Generated: \(icon.path)")
