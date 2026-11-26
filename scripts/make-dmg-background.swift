import AppKit
import CoreGraphics
import Foundation

// Draws the disk image background: a soft vertical gradient with a single chevron
// between the two icon positions. Deterministic, so the asset can be regenerated.
//
// Usage: swift scripts/make-dmg-background.swift <output.png>

let width = 1200
let height = 800

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: make-dmg-background.swift <output.png>", code: 2)
}

guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("the sRGB color space is not available")
}
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("the bitmap context could not be created")
}

guard
    let top = CGColor(colorSpace: space, components: [0.97, 0.97, 0.98, 1]),
    let bottom = CGColor(colorSpace: space, components: [0.91, 0.91, 0.94, 1]),
    let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])
else {
    fail("the gradient could not be created")
}
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(height)),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// The chevron sits between the application icon and the Applications folder.
guard let stroke = CGColor(colorSpace: space, components: [0.66, 0.66, 0.70, 1]) else {
    fail("the chevron color could not be created")
}
context.setStrokeColor(stroke)
context.setLineWidth(7)
context.setLineCap(.round)
context.setLineJoin(.round)
let middle = CGFloat(height) / 2
context.move(to: CGPoint(x: 552, y: middle + 22))
context.addLine(to: CGPoint(x: 604, y: middle))
context.addLine(to: CGPoint(x: 552, y: middle - 22))
context.strokePath()

guard let image = context.makeImage() else {
    fail("the image could not be rendered")
}
let representation = NSBitmapImageRep(cgImage: image)
guard let data = representation.representation(using: .png, properties: [:]) else {
    fail("the PNG data could not be produced")
}
do {
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    fail("the PNG could not be written: \(error.localizedDescription)")
}
