import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the project's artwork in code: the application icon set and the disk image
// background. Both are generated, so they can be reproduced and adjusted without an
// external asset to keep in sync.
//
// Usage:
//   swift scripts/make-artwork.swift icon <AppIcon.appiconset>
//   swift scripts/make-artwork.swift background <output.png>

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: make-artwork.swift <icon|background> <output>", code: 2)
}
let mode = CommandLine.arguments[1]
let output = CommandLine.arguments[2]

guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("the sRGB color space is not available")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    guard let value = CGColor(colorSpace: space, components: [red, green, blue, alpha]) else {
        fail("a color could not be created")
    }
    return value
}

func makeContext(width: Int, height: Int) -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("a \(width)x\(height) bitmap context could not be created")
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    return context
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fail("the PNG destination for \(url.lastPathComponent) could not be created")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("\(url.lastPathComponent) could not be written")
    }
}

// MARK: - Application icon

/// Apple's icon grid: an 824-point rounded square centred on a 1024-point canvas with
/// transparent margins, because macOS does not mask application icons. The corner radius
/// is a ratio of the artwork side, so the two values cannot drift apart.
let iconCanvas: CGFloat = 1024
let iconArtworkSide: CGFloat = 824
let iconCornerRatio: CGFloat = 0.225
let iconCornerRadius = iconArtworkSide * iconCornerRatio

let iconPanelSize = CGSize(width: 460, height: 296)
let iconPanelCornerRadius: CGFloat = 30
let iconPanelInset: CGFloat = 16
let iconPanelInnerCornerRadius: CGFloat = 18
let iconPanelShadowBlur: CGFloat = 34
let iconPanelShadowOffset: CGFloat = -10
let iconPanelVerticalOffset: CGFloat = 10
let iconHighlightInset: CGFloat = 60
let iconHighlightRadius: CGFloat = 520
let iconArcOriginInset: CGFloat = 10

/// One broadcast arc rule: three rings that leave the panel corner, fading outwards.
let iconArcRadii: [CGFloat] = [58, 108, 158]
let iconArcWidth: CGFloat = 19
let iconArcBaseOpacity: CGFloat = 0.90
let iconArcOpacityStep: CGFloat = 0.24

func makeIconMaster() -> CGImage {
    let context = makeContext(width: Int(iconCanvas), height: Int(iconCanvas))

    let inset = (iconCanvas - iconArtworkSide) / 2
    let body = CGRect(x: inset, y: inset, width: iconArtworkSide, height: iconArtworkSide)
    let shape = CGPath(
        roundedRect: body,
        cornerWidth: iconCornerRadius,
        cornerHeight: iconCornerRadius,
        transform: nil
    )

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
            start: CGPoint(x: 0, y: iconCanvas),
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
            startCenter: CGPoint(x: iconCanvas / 2, y: iconCanvas - iconHighlightInset),
            startRadius: 0,
            endCenter: CGPoint(x: iconCanvas / 2, y: iconCanvas - iconHighlightInset),
            endRadius: iconHighlightRadius,
            options: []
        )
    }
    context.restoreGState()

    // Screen: a widescreen panel, slightly above the optical centre.
    let panel = CGRect(
        x: (iconCanvas - iconPanelSize.width) / 2,
        y: (iconCanvas - iconPanelSize.height) / 2 - iconPanelVerticalOffset,
        width: iconPanelSize.width,
        height: iconPanelSize.height
    )
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: iconPanelShadowOffset),
        blur: iconPanelShadowBlur,
        color: color(0, 0, 0, 0.35)
    )
    context.addPath(CGPath(
        roundedRect: panel,
        cornerWidth: iconPanelCornerRadius,
        cornerHeight: iconPanelCornerRadius,
        transform: nil
    ))
    context.setFillColor(color(0.98, 0.98, 1))
    context.fillPath()
    context.restoreGState()

    let inner = panel.insetBy(dx: iconPanelInset, dy: iconPanelInset)
    let innerPath = CGPath(
        roundedRect: inner,
        cornerWidth: iconPanelInnerCornerRadius,
        cornerHeight: iconPanelInnerCornerRadius,
        transform: nil
    )
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

    // Broadcast arcs leaving the top-right corner, clipped to the body so they never
    // cross its edge. The opacity fades with the edge number.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let origin = CGPoint(x: panel.maxX - iconArcOriginInset, y: panel.maxY - iconArcOriginInset)
    context.setLineCap(.round)
    for (index, radius) in iconArcRadii.enumerated() {
        context.addArc(
            center: origin,
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false
        )
        let opacity = iconArcBaseOpacity - CGFloat(index) * iconArcOpacityStep
        context.setStrokeColor(color(1, 1, 1, opacity))
        context.setLineWidth(iconArcWidth)
        context.strokePath()
    }
    context.restoreGState()

    guard let image = context.makeImage() else {
        fail("the icon could not be rendered")
    }
    return image
}

func writeIconSet(to directory: URL) {
    struct Entry {
        let points: Int
        let scaleFactor: Int
        var pixels: Int { points * scaleFactor }
        var filename: String {
            scaleFactor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        }
        var size: String { "\(points)x\(points)" }
        var scale: String { "\(scaleFactor)x" }
    }
    // The catalog asks for these point sizes at both scales; the pixel count is derived,
    // so a typo cannot produce a mismatched asset.
    let entries = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
        .map { Entry(points: $0.0, scaleFactor: $0.1) }

    let master = makeIconMaster()
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        fail("the asset catalog directory could not be created: \(error.localizedDescription)")
    }

    for entry in entries {
        let context = makeContext(width: entry.pixels, height: entry.pixels)
        context.draw(master, in: CGRect(x: 0, y: 0, width: entry.pixels, height: entry.pixels))
        guard let scaled = context.makeImage() else {
            fail("the \(entry.pixels) pixel variant could not be rendered")
        }
        writePNG(scaled, to: directory.appendingPathComponent(entry.filename))
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
        try contents.write(
            to: directory.appendingPathComponent("Contents.json"),
            atomically: true,
            encoding: .utf8
        )
    } catch {
        fail("the asset catalog description could not be written: \(error.localizedDescription)")
    }
}

// MARK: - Disk image background

/// The disk image is 1200x800 pixels and is shown in a 600x400 window, so every coordinate
/// here is twice the Finder points in scripts/dmg-layout.conf, which scripts/make-dmg.sh
/// also reads. The chevron is derived from the icon columns, so moving an icon in the
/// layout file moves the chevron with it.
let dmgBackgroundWidth = 1200
let dmgBackgroundHeight = 800
let dmgChevronOffsetBeforeMidpoint: CGFloat = 24
let dmgChevronOffsetAfterMidpoint: CGFloat = 2
let dmgChevronHalfHeight: CGFloat = 22
let dmgChevronWidth: CGFloat = 7
let dmgPointScale: CGFloat = 2
let dmgLayoutPath = "scripts/dmg-layout.conf"

struct DMGLayout {
    let appX: CGFloat
    let appsX: CGFloat
}

/// Reads the window geometry the packaging script uses. Both files must agree, and this is
/// the only place the numbers live.
func loadDMGLayout() -> DMGLayout {
    guard let text = try? String(contentsOfFile: dmgLayoutPath, encoding: .utf8) else {
        fail("cannot read \(dmgLayoutPath); run this script from the repository root")
    }
    var values: [String: CGFloat] = [:]
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
        let parts = trimmed.split(separator: "=", maxSplits: 1)
        guard parts.count == 2, let value = Double(parts[1]) else { continue }
        values[String(parts[0])] = CGFloat(value)
    }
    guard let appX = values["APP_X"], let appsX = values["APPS_X"] else {
        fail("\(dmgLayoutPath) is missing APP_X or APPS_X")
    }
    return DMGLayout(appX: appX, appsX: appsX)
}

func makeBackground() -> CGImage {
    let layout = loadDMGLayout()
    let context = makeContext(width: dmgBackgroundWidth, height: dmgBackgroundHeight)

    let top = color(0.97, 0.97, 0.98)
    let bottom = color(0.91, 0.91, 0.94)
    if let gradient = CGGradient(
        colorsSpace: space,
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: CGFloat(dmgBackgroundHeight)),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
    }

    context.setStrokeColor(color(0.66, 0.66, 0.70))
    context.setLineWidth(dmgChevronWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let midpoint = (layout.appX + layout.appsX) / 2 * dmgPointScale
    let startX = midpoint - dmgChevronOffsetBeforeMidpoint * dmgPointScale
    let tipX = midpoint + dmgChevronOffsetAfterMidpoint * dmgPointScale
    let middle = CGFloat(dmgBackgroundHeight) / 2
    context.move(to: CGPoint(x: startX, y: middle + dmgChevronHalfHeight))
    context.addLine(to: CGPoint(x: tipX, y: middle))
    context.addLine(to: CGPoint(x: startX, y: middle - dmgChevronHalfHeight))
    context.strokePath()

    guard let image = context.makeImage() else {
        fail("the background could not be rendered")
    }
    return image
}

// MARK: - Entry point

switch mode {
case "icon":
    writeIconSet(to: URL(fileURLWithPath: output))
case "background":
    writePNG(makeBackground(), to: URL(fileURLWithPath: output))
default:
    fail("unknown mode \"\(mode)\"; use icon or background", code: 2)
}
