#!/usr/bin/swift

import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = CGSize(width: 1024, height: 1024)

let image = NSImage(size: canvasSize)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Unable to create graphics context.\n", stderr)
    exit(1)
}

let rect = CGRect(origin: .zero, size: canvasSize)
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func fillRoundedRect(_ rect: CGRect, radius: CGFloat, colors: [NSColor], angle: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    let gradient = NSGradient(colors: colors) ?? NSGradient(starting: colors[0], ending: colors[1])!
    gradient.draw(in: path, angle: angle)
}

func drawRing(center: CGPoint, radius: CGFloat, lineWidth: CGFloat, strokeColor: NSColor) {
    let ringRect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    let path = NSBezierPath(ovalIn: ringRect)
    path.lineWidth = lineWidth
    strokeColor.setStroke()
    path.stroke()
}

func drawArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, lineWidth: CGFloat, strokeColor: NSColor) {
    let path = NSBezierPath()
    path.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: false
    )
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    strokeColor.setStroke()
    path.stroke()
}

func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
    let radians = angle * .pi / 180.0
    return CGPoint(
        x: center.x + cos(radians) * radius,
        y: center.y + sin(radians) * radius
    )
}

func drawSweep(center: CGPoint, radius: CGFloat, angle: CGFloat, color: NSColor) {
    context.saveGState()
    let end = point(center: center, radius: radius, angle: angle)
    context.setLineCap(.round)
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(26)
    context.move(to: center)
    context.addLine(to: end)
    context.strokePath()
    context.restoreGState()
}

fillRoundedRect(
    rect.insetBy(dx: 42, dy: 42),
    radius: 220,
    colors: [
        color(10, 18, 28),
        color(22, 38, 54)
    ],
    angle: -35
)

let framePath = NSBezierPath(roundedRect: rect.insetBy(dx: 42, dy: 42), xRadius: 220, yRadius: 220)
framePath.lineWidth = 5
color(255, 255, 255, 0.08).setStroke()
framePath.stroke()

let center = CGPoint(x: 512, y: 512)
drawRing(center: center, radius: 272, lineWidth: 22, strokeColor: color(94, 212, 173, 0.18))
drawRing(center: center, radius: 194, lineWidth: 16, strokeColor: color(94, 212, 173, 0.28))
drawRing(center: center, radius: 116, lineWidth: 14, strokeColor: color(94, 212, 173, 0.44))

drawArc(center: center, radius: 320, startAngle: 24, endAngle: 88, lineWidth: 28, strokeColor: color(72, 187, 248, 0.42))
drawArc(center: center, radius: 320, startAngle: 214, endAngle: 278, lineWidth: 28, strokeColor: color(72, 187, 248, 0.18))

drawSweep(center: center, radius: 284, angle: 34, color: color(72, 187, 248, 0.82))

let pingCenter = point(center: center, radius: 206, angle: 34)
let glowRect = CGRect(x: pingCenter.x - 70, y: pingCenter.y - 70, width: 140, height: 140)
let glowPath = NSBezierPath(ovalIn: glowRect)
let glowGradient = NSGradient(colors: [
    color(125, 247, 216, 0.58),
    color(125, 247, 216, 0.0)
])!
glowGradient.draw(in: glowPath, relativeCenterPosition: .zero)

color(125, 247, 216).setFill()
NSBezierPath(ovalIn: CGRect(x: pingCenter.x - 22, y: pingCenter.y - 22, width: 44, height: 44)).fill()

color(72, 187, 248, 0.92).setFill()
NSBezierPath(ovalIn: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)).fill()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to encode icon image.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Failed to write icon image: \(error)\n", stderr)
    exit(1)
}
