import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift GenerateAppIcon.swift <iconset-directory>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true

    let dimension = CGFloat(pixels)
    let inset = dimension * 0.055
    let iconRect = NSRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let background = NSBezierPath(roundedRect: iconRect, xRadius: dimension * 0.22, yRadius: dimension * 0.22)
    NSColor(red: 0.122, green: 0.220, blue: 0.141, alpha: 1).setFill()
    background.fill()

    let highlight = NSBezierPath(ovalIn: NSRect(
        x: dimension * 0.15,
        y: dimension * 0.54,
        width: dimension * 0.70,
        height: dimension * 0.31
    ))
    NSColor.white.withAlphaComponent(0.055).setFill()
    highlight.fill()

    let markColor = NSColor(red: 0.949, green: 0.969, blue: 0.906, alpha: 1)
    markColor.setFill()
    let centerY = dimension * 0.50
    let endpointWidth = dimension * 0.075
    let endpointHeight = dimension * 0.40
    for centerX in [dimension * 0.27, dimension * 0.73] {
        let rect = NSRect(
            x: centerX - endpointWidth / 2,
            y: centerY - endpointHeight / 2,
            width: endpointWidth,
            height: endpointHeight
        )
        NSBezierPath(roundedRect: rect, xRadius: endpointWidth / 2, yRadius: endpointWidth / 2).fill()
    }

    let dotSize = dimension * 0.082
    for centerX in [dimension * 0.41, dimension * 0.50, dimension * 0.59] {
        NSBezierPath(ovalIn: NSRect(
            x: centerX - dotSize / 2,
            y: centerY - dotSize / 2,
            width: dotSize,
            height: dotSize
        )).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for variant in variants {
    let destination = outputDirectory.appendingPathComponent(variant.name)
    try drawIcon(pixels: variant.pixels).write(to: destination, options: .atomic)
}
