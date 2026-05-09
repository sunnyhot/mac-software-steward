#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = root.appendingPathComponent("native/Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconFiles: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, fileName) in iconFiles {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render \(fileName)"])
    }
    try png.write(to: iconsetURL.appendingPathComponent(fileName))
}

try? FileManager.default.removeItem(at: icnsURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    bounds.fill()

    let inset = size * 0.035
    let baseRect = bounds.insetBy(dx: inset, dy: inset)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: size * 0.22, yRadius: size * 0.22)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
    shadow.shadowBlurRadius = size * 0.035
    shadow.set()

    NSGradient(colors: [
        color(0x0D, 0x76, 0x58),
        color(0x21, 0x44, 0x5F),
        color(0x2F, 0x67, 0xA7)
    ])?.draw(in: basePath, angle: 135)
    NSShadow().set()

    let glowPath = NSBezierPath(ovalIn: NSRect(x: size * 0.08, y: size * 0.58, width: size * 0.46, height: size * 0.38))
    color(0x84, 0xE0, 0xB2, alpha: 0.28).setFill()
    glowPath.fill()

    let panelRect = NSRect(x: size * 0.18, y: size * 0.22, width: size * 0.64, height: size * 0.56)
    let panel = NSBezierPath(roundedRect: panelRect, xRadius: size * 0.075, yRadius: size * 0.075)
    NSColor.white.withAlphaComponent(0.92).setFill()
    panel.fill()
    color(0xE4, 0xED, 0xE8).setStroke()
    panel.lineWidth = max(1, size * 0.008)
    panel.stroke()

    let titleLine = NSBezierPath(roundedRect: NSRect(x: size * 0.27, y: size * 0.66, width: size * 0.34, height: size * 0.035), xRadius: size * 0.018, yRadius: size * 0.018)
    color(0x1C, 0x37, 0x38, alpha: 0.68).setFill()
    titleLine.fill()

    for index in 0..<3 {
        let dot = NSBezierPath(ovalIn: NSRect(x: size * (0.26 + CGFloat(index) * 0.045), y: size * 0.60, width: size * 0.025, height: size * 0.025))
        color(0x1C, 0x37, 0x38, alpha: 0.42).setFill()
        dot.fill()
    }

    drawCube(in: NSRect(x: size * 0.34, y: size * 0.34, width: size * 0.24, height: size * 0.22), size: size)
    drawUpgradeArrow(in: NSRect(x: size * 0.54, y: size * 0.34, width: size * 0.19, height: size * 0.22), size: size)

    let checkBadge = NSBezierPath(ovalIn: NSRect(x: size * 0.64, y: size * 0.55, width: size * 0.16, height: size * 0.16))
    color(0xF5, 0xB8, 0x42).setFill()
    checkBadge.fill()
    drawCheck(in: NSRect(x: size * 0.675, y: size * 0.595, width: size * 0.09, height: size * 0.07), size: size)

    return image
}

func drawCube(in rect: NSRect, size: CGFloat) {
    let stroke = color(0x14, 0x58, 0x73)
    stroke.setStroke()
    let lineWidth = max(1.2, size * 0.014)

    let top = NSPoint(x: rect.midX, y: rect.maxY)
    let leftTop = NSPoint(x: rect.minX, y: rect.maxY - rect.height * 0.28)
    let leftBottom = NSPoint(x: rect.minX, y: rect.minY + rect.height * 0.28)
    let bottom = NSPoint(x: rect.midX, y: rect.minY)
    let rightBottom = NSPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28)
    let rightTop = NSPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.28)

    let outline = NSBezierPath()
    outline.move(to: top)
    outline.line(to: rightTop)
    outline.line(to: rightBottom)
    outline.line(to: bottom)
    outline.line(to: leftBottom)
    outline.line(to: leftTop)
    outline.close()
    outline.lineJoinStyle = .round
    outline.lineWidth = lineWidth
    outline.stroke()

    let internals = NSBezierPath()
    internals.move(to: leftTop)
    internals.line(to: rect.center)
    internals.line(to: rightTop)
    internals.move(to: rect.center)
    internals.line(to: bottom)
    internals.lineWidth = lineWidth
    internals.lineCapStyle = .round
    internals.lineJoinStyle = .round
    internals.stroke()
}

func drawUpgradeArrow(in rect: NSRect, size: CGFloat) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.midX, y: rect.minY))
    path.line(to: NSPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18))
    path.move(to: NSPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.46))
    path.line(to: NSPoint(x: rect.midX, y: rect.maxY - rect.height * 0.14))
    path.line(to: NSPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.46))
    color(0x10, 0x77, 0x5C).setStroke()
    path.lineWidth = max(1.6, size * 0.018)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func drawCheck(in rect: NSRect, size: CGFloat) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.midY))
    path.line(to: NSPoint(x: rect.minX + rect.width * 0.38, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
    NSColor.white.setStroke()
    path.lineWidth = max(1.5, size * 0.014)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: alpha)
}

extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
