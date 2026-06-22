import AppKit
import Foundation

struct IconGeneratorError: Error, CustomStringConvertible {
    let description: String
}

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("usage: swift scripts/generate-app-icon.swift [--output PATH]")
    exit(0)
}

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputURL = URL(fileURLWithPath: value(after: "--output") ?? "Sources/ArxivResearchApp/Resources", relativeTo: rootURL)
    .standardizedFileURL
let iconsetURL = outputURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = outputURL.appendingPathComponent("AppIcon.icns")

let iconEntries: [(name: String, pixels: Int, icnsType: String?)] = [
    ("icon_16x16.png", 16, "icp4"),
    ("icon_16x16@2x.png", 32, nil),
    ("icon_32x32.png", 32, "icp5"),
    ("icon_32x32@2x.png", 64, "icp6"),
    ("icon_128x128.png", 128, "ic07"),
    ("icon_128x128@2x.png", 256, nil),
    ("icon_256x256.png", 256, "ic08"),
    ("icon_256x256@2x.png", 512, nil),
    ("icon_512x512.png", 512, "ic09"),
    ("icon_512x512@2x.png", 1024, "ic10")
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func scaled(_ value: CGFloat, for canvas: CGFloat) -> CGFloat {
    value * canvas / 1024
}

func roundedPath(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, canvas: CGFloat) -> NSBezierPath {
    NSBezierPath(
        roundedRect: NSRect(
            x: scaled(x, for: canvas),
            y: scaled(y, for: canvas),
            width: scaled(width, for: canvas),
            height: scaled(height, for: canvas)
        ),
        xRadius: scaled(radius, for: canvas),
        yRadius: scaled(radius, for: canvas)
    )
}

func drawIcon(pixelSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconGeneratorError(description: "Unable to create bitmap for \(pixelSize)x\(pixelSize)")
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconGeneratorError(description: "Unable to create drawing context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    let canvas = CGFloat(pixelSize)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

    let background = roundedPath(x: 64, y: 64, width: 896, height: 896, radius: 204, canvas: canvas)
    color(47, 52, 56).setFill()
    background.fill()

    let inner = roundedPath(x: 92, y: 92, width: 840, height: 840, radius: 176, canvas: canvas)
    color(66, 72, 78, 0.55).setStroke()
    inner.lineWidth = scaled(18, for: canvas)
    inner.stroke()

    let paperShadow = roundedPath(x: 252, y: 178, width: 520, height: 668, radius: 52, canvas: canvas)
    color(24, 27, 30, 0.22).setFill()
    paperShadow.transform(using: AffineTransform(translationByX: 0, byY: -scaled(18, for: canvas)))
    paperShadow.fill()

    let paper = roundedPath(x: 252, y: 196, width: 520, height: 668, radius: 52, canvas: canvas)
    color(244, 240, 229).setFill()
    paper.fill()

    color(221, 215, 201).setStroke()
    paper.lineWidth = scaled(10, for: canvas)
    paper.stroke()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: scaled(628, for: canvas), y: scaled(864, for: canvas)))
    fold.line(to: NSPoint(x: scaled(772, for: canvas), y: scaled(720, for: canvas)))
    fold.line(to: NSPoint(x: scaled(628, for: canvas), y: scaled(720, for: canvas)))
    fold.close()
    color(224, 218, 204).setFill()
    fold.fill()
    color(200, 194, 183).setStroke()
    fold.lineWidth = scaled(9, for: canvas)
    fold.stroke()

    let orbit = NSBezierPath(ovalIn: NSRect(
        x: scaled(278, for: canvas),
        y: scaled(336, for: canvas),
        width: scaled(500, for: canvas),
        height: scaled(228, for: canvas)
    ))
    var orbitTransform = AffineTransform(translationByX: scaled(528, for: canvas), byY: scaled(450, for: canvas))
    orbitTransform.rotate(byDegrees: -22)
    orbitTransform.translate(x: -scaled(528, for: canvas), y: -scaled(450, for: canvas))
    orbit.transform(using: orbitTransform)
    color(31, 149, 145).setStroke()
    orbit.lineWidth = scaled(36, for: canvas)
    orbit.lineCapStyle = .round
    orbit.stroke()

    let orbitHighlight = NSBezierPath(ovalIn: NSRect(
        x: scaled(330, for: canvas),
        y: scaled(382, for: canvas),
        width: scaled(396, for: canvas),
        height: scaled(132, for: canvas)
    ))
    orbitHighlight.transform(using: orbitTransform)
    color(105, 199, 193, 0.34).setStroke()
    orbitHighlight.lineWidth = scaled(13, for: canvas)
    orbitHighlight.stroke()

    let nodeRect = NSRect(
        x: scaled(640, for: canvas),
        y: scaled(506, for: canvas),
        width: scaled(112, for: canvas),
        height: scaled(112, for: canvas)
    )
    color(38, 39, 40, 0.20).setFill()
    NSBezierPath(ovalIn: nodeRect.offsetBy(dx: 0, dy: -scaled(10, for: canvas))).fill()
    color(232, 159, 55).setFill()
    NSBezierPath(ovalIn: nodeRect).fill()
    color(255, 218, 132, 0.60).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: scaled(670, for: canvas),
        y: scaled(560, for: canvas),
        width: scaled(38, for: canvas),
        height: scaled(38, for: canvas)
    )).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGeneratorError(description: "Unable to encode PNG for \(pixelSize)x\(pixelSize)")
    }
    return data
}

func appendFourCC(_ value: String, to data: inout Data) throws {
    guard let bytes = value.data(using: .macOSRoman), bytes.count == 4 else {
        throw IconGeneratorError(description: "Invalid ICNS type \(value)")
    }
    data.append(bytes)
}

func appendBigEndianUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

func writeICNS(entries: [(type: String, data: Data)], to outputURL: URL) throws {
    let iconPayloadLength = try entries.reduce(UInt32(8)) { partial, entry in
        let elementLength = entry.data.count + 8
        guard elementLength <= Int(UInt32.max), partial <= UInt32.max - UInt32(elementLength) else {
            throw IconGeneratorError(description: "ICNS payload is too large")
        }
        return partial + UInt32(elementLength)
    }

    var icns = Data()
    try appendFourCC("icns", to: &icns)
    appendBigEndianUInt32(iconPayloadLength, to: &icns)

    for entry in entries {
        try appendFourCC(entry.type, to: &icns)
        appendBigEndianUInt32(UInt32(entry.data.count + 8), to: &icns)
        icns.append(entry.data)
    }

    try icns.write(to: outputURL, options: .atomic)
}

do {
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    var icnsEntries: [(type: String, data: Data)] = []
    for entry in iconEntries {
        let data = try drawIcon(pixelSize: entry.pixels)
        try data.write(to: iconsetURL.appendingPathComponent(entry.name), options: .atomic)
        if let icnsType = entry.icnsType {
            icnsEntries.append((type: icnsType, data: data))
        }
    }

    if FileManager.default.fileExists(atPath: icnsURL.path) {
        try FileManager.default.removeItem(at: icnsURL)
    }
    try writeICNS(entries: icnsEntries, to: icnsURL)
    print("Generated \(icnsURL.path)")
} catch {
    fputs("generate-app-icon: \(error)\n", stderr)
    exit(1)
}
