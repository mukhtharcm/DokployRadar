#!/usr/bin/swift

import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    fputs("Usage: generate-dmg-background.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = CGSize(width: 1280, height: 720)
let rect = CGRect(origin: .zero, size: canvasSize)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Unable to create bitmap context.\n", stderr)
    exit(1)
}

bitmap.size = canvasSize

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create graphics context.\n", stderr)
    exit(1)
}

let context = graphicsContext.cgContext

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func drawBackground() {
    let gradient = NSGradient(colors: [
        color(245, 249, 252),
        color(233, 241, 247)
    ]) ?? NSGradient(starting: color(245, 249, 252), ending: color(233, 241, 247))!
    gradient.draw(in: NSBezierPath(rect: rect), angle: -12)
}

func drawGlow(center: CGPoint, radius: CGFloat, glowColor: NSColor) {
    context.saveGState()

    let colors = [glowColor.withAlphaComponent(0.25).cgColor, glowColor.withAlphaComponent(0.0).cgColor] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]

    guard
        let rgb = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(colorsSpace: rgb, colors: colors, locations: locations)
    else {
        context.restoreGState()
        return
    }

    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    context.restoreGState()
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

func drawConnector() {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 340, y: 360))
    path.curve(
        to: CGPoint(x: 938, y: 360),
        controlPoint1: CGPoint(x: 498, y: 420),
        controlPoint2: CGPoint(x: 752, y: 300)
    )

    context.saveGState()
    context.setLineCap(.round)
    context.setLineWidth(10)
    context.addPath(path.cgPath)
    context.replacePathWithStrokedPath()
    context.clip()

    let colors = [
        color(72, 187, 248, 0.32).cgColor,
        color(94, 212, 173, 0.24).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]

    if
        let rgb = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(colorsSpace: rgb, colors: colors, locations: locations)
    {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 300, y: 420),
            end: CGPoint(x: 980, y: 300),
            options: []
        )
    }

    context.restoreGState()
}

func drawInsetFrame() {
    let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 24, yRadius: 24)
    frame.lineWidth = 3
    color(255, 255, 255, 0.58).setStroke()
    frame.stroke()
}

drawBackground()
drawGlow(center: CGPoint(x: 278, y: 360), radius: 250, glowColor: color(72, 187, 248))
drawGlow(center: CGPoint(x: 1000, y: 360), radius: 220, glowColor: color(94, 212, 173))
drawConnector()
drawRing(center: CGPoint(x: 282, y: 360), radius: 136, lineWidth: 10, strokeColor: color(13, 32, 45, 0.10))
drawRing(center: CGPoint(x: 282, y: 360), radius: 96, lineWidth: 8, strokeColor: color(72, 187, 248, 0.16))
drawRing(center: CGPoint(x: 998, y: 360), radius: 122, lineWidth: 8, strokeColor: color(94, 212, 173, 0.18))
drawInsetFrame()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode DMG background image.\n", stderr)
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
    fputs("Failed to write DMG background image: \(error)\n", stderr)
    exit(1)
}
