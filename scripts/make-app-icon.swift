import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the application icon and writes a complete macOS AppIcon set.
//
// The icon is drawn in code on purpose: it can be regenerated, it has no external asset to
// keep in sync, and it follows Apple's icon grid (an 824-point rounded square centred on a
// 1024-point canvas with transparent margins), because macOS does not mask app icons.
//
// Usage: swift scripts/make-app-icon.swift <AppIcon.appiconset>

let canvas: CGFloat = 1024
let artworkSide: CGFloat = 824
let cornerRadius: CGFloat = 185.4

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: make-app-icon.swift <AppIcon.appiconset>", code: 2)
}
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])

guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("the sRGB color space is not available")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    guard let value = CGColor(colorSpace: space, components: [red, green, blue, alpha]) else {
        fail("a color could not be created")
    }
    return value
}

/// Renders the artwork on a transparent canvas.
func makeMaster() -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: Int(canvas),
        height: Int(canvas),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    let inset = (canvas - artworkSide) / 2
    let body = CGRect(x: inset, y: inset, width: artworkSide, height: artworkSide)
    let shape = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Body: deep blue to indigo, with a soft light from the top.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(
        colorsSpace: space,
        colors: [color(0.22, 0.42, 0.92), color(0.05, 0.13, 0.36)] as CFArray,
        locations: [0, 1]
    )
    if let background {
        context.drawLinearGradient(
            background,
            start: CGPoint(x: 0, y: canvas),
            end: CGPoint(x: 0, y: inset),
            options: []
        )
    }
    let highlight = CGGradient(
        colorsSpace: space,
        colors: [color(1, 1, 1, 0.18), color(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )
    if let highlight {
        context.drawRadialGradient(
            highlight,
            startCenter: CGPoint(x: canvas / 2, y: canvas - 60),
            startRadius: 0,
            endCenter: CGPoint(x: canvas / 2, y: canvas - 60),
            endRadius: 520,
            options: []
        )
    }
    context.restoreGState()

    // Screen: a widescreen panel, slightly above the optical centre.
    let panelWidth: CGFloat = 460
    let panelHeight: CGFloat = 296
    let panel = CGRect(
        x: (canvas - panelWidth) / 2,
        y: (canvas - panelHeight) / 2 - 10,
        width: panelWidth,
        height: panelHeight
    )
    let panelPath = CGPath(
        roundedRect: panel,
        cornerWidth: 30,
        cornerHeight: 30,
        transform: nil
    )
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 34, color: color(0, 0, 0, 0.35))
    context.addPath(panelPath)
    context.setFillColor(color(0.98, 0.98, 1))
    context.fillPath()
    context.restoreGState()

    // Inner screen: a calm gradient that reads as "on".
    let innerInset: CGFloat = 16
    let inner = panel.insetBy(dx: innerInset, dy: innerInset)
    let innerPath = CGPath(roundedRect: inner, cornerWidth: 18, cornerHeight: 18, transform: nil)
    context.saveGState()
    context.addPath(innerPath)
    context.clip()
    let screen = CGGradient(
        colorsSpace: space,
        colors: [color(0.12, 0.30, 0.72), color(0.05, 0.12, 0.34)] as CFArray,
        locations: [0, 1]
    )
    if let screen {
        context.drawLinearGradient(
            screen,
            start: CGPoint(x: 0, y: inner.maxY),
            end: CGPoint(x: 0, y: inner.minY),
            options: []
        )
    }
    context.restoreGState()

    // A soft sheen across the panel, so the screen is not a flat block.
    context.saveGState()
    context.addPath(innerPath)
    context.clip()
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [color(1, 1, 1, 0.14), color(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )
    if let sheen {
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: inner.minX, y: inner.maxY),
            end: CGPoint(x: inner.midX, y: inner.minY),
            options: []
        )
    }
    context.restoreGState()

    // Broadcast arcs leaving the top-right corner of the panel, clipped to the icon body
    // so they never cross its edge.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let origin = CGPoint(x: panel.maxX - 10, y: panel.maxY - 10)
    context.setLineCap(.round)
    for (index, radius) in [CGFloat(58), 108, 158].enumerated() {
        context.addArc(
            center: origin,
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false
        )
        context.setStrokeColor(color(1, 1, 1, 0.90 - CGFloat(index) * 0.24))
        context.setLineWidth(19)
        context.strokePath()
    }
    context.restoreGState()

    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return false
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

func scaled(_ image: CGImage, pixels: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return context.makeImage()
}

struct Entry {
    let filename: String
    let size: String
    let scale: String
    let pixels: Int
}

let entries: [Entry] = [
    Entry(filename: "icon_16x16.png", size: "16x16", scale: "1x", pixels: 16),
    Entry(filename: "icon_16x16@2x.png", size: "16x16", scale: "2x", pixels: 32),
    Entry(filename: "icon_32x32.png", size: "32x32", scale: "1x", pixels: 32),
    Entry(filename: "icon_32x32@2x.png", size: "32x32", scale: "2x", pixels: 64),
    Entry(filename: "icon_128x128.png", size: "128x128", scale: "1x", pixels: 128),
    Entry(filename: "icon_128x128@2x.png", size: "128x128", scale: "2x", pixels: 256),
    Entry(filename: "icon_256x256.png", size: "256x256", scale: "1x", pixels: 256),
    Entry(filename: "icon_256x256@2x.png", size: "256x256", scale: "2x", pixels: 512),
    Entry(filename: "icon_512x512.png", size: "512x512", scale: "1x", pixels: 512),
    Entry(filename: "icon_512x512@2x.png", size: "512x512", scale: "2x", pixels: 1024),
]

guard let master = makeMaster() else {
    fail("the icon could not be rendered")
}

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for entry in entries {
    guard let image = scaled(master, pixels: entry.pixels) else {
        fail("the \(entry.pixels) pixel variant could not be rendered")
    }
    guard writePNG(image, to: outputDir.appendingPathComponent(entry.filename)) else {
        fail("the \(entry.filename) variant could not be written")
    }
}

let images = entries.map { entry in
    """
        {
          "filename" : "\(entry.filename)",
          "idiom" : "mac",
          "scale" : "\(entry.scale)",
          "size" : "\(entry.size)"
        }
    """
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
do {
    try contents.write(to: outputDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
} catch {
    fail("the asset catalog description could not be written: \(error.localizedDescription)")
}
