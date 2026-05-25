#!/usr/bin/env swift
// Generates the Scrobblr AppIcon at every required size. Custom-drawn rather
// than reusing an SF Symbol; gives the app a recognisable mark.
//
// Composition:
//   * Gradient ground: deep red → magenta diagonal (Last.fm heritage, but
//     pushed warmer/softer to differentiate from the literal Last.fm logo).
//   * Soft scrobble-pulse rings emanating from upper-left, suggesting
//     submission radiating outward.
//   * Custom-drawn waveform of seven bars at varying heights, centered.
//     Each bar has rounded caps and a subtle inner gradient (top brighter
//     than base) to give the glyph dimensionality.
//   * Top highlight glaze for the macOS Big-Sur-style glass feel.
//
//   swift tools/generate-icon.swift

import AppKit
import CoreImage

let sizes: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

let outDir = "Scrobblr/Assets.xcassets/AppIcon.appiconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func draw(_ pixelSize: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep alloc failed") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let size = CGFloat(pixelSize)

    // Apple icon corner radius (Big Sur+ formula: ~22.37% of side).
    let cornerRadius = size * 0.2237
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let clip = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(clip); ctx.clip()

    // 1. Background gradient.
    let bg = [
        NSColor(srgbRed: 0.98, green: 0.27, blue: 0.36, alpha: 1).cgColor,
        NSColor(srgbRed: 0.74, green: 0.13, blue: 0.30, alpha: 1).cgColor,
        NSColor(srgbRed: 0.45, green: 0.06, blue: 0.28, alpha: 1).cgColor,
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: bg, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bgGrad,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: [])

    // 2. Scrobble-pulse rings; three concentric arcs from upper-left.
    let center = CGPoint(x: size * 0.18, y: size * 0.82)
    for i in 0..<3 {
        let r = size * (0.35 + CGFloat(i) * 0.18)
        let ring = CGMutablePath()
        ring.addEllipse(in: CGRect(
            x: center.x - r, y: center.y - r,
            width: r * 2, height: r * 2
        ))
        ctx.saveGState()
        ctx.setLineWidth(size * 0.012)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12 - CGFloat(i) * 0.025).cgColor)
        ctx.addPath(ring); ctx.strokePath()
        ctx.restoreGState()
    }

    // 3. Custom waveform; seven bars, varying heights, mirrored asymmetry.
    // Heights chosen to feel like an actual audio signal mid-beat rather
    // than a symmetric SF-Symbol shape.
    let barHeights: [CGFloat] = [0.45, 0.72, 0.55, 0.92, 0.62, 0.78, 0.40]
    let barCount = barHeights.count
    let totalWidth = size * 0.62
    let gap = size * 0.02
    let barWidth = (totalWidth - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
    let baseX = (size - totalWidth) / 2
    let cy = size * 0.5

    for (i, h) in barHeights.enumerated() {
        let barHeight = size * 0.62 * h
        let x = baseX + CGFloat(i) * (barWidth + gap)
        let y = cy - barHeight / 2
        let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
        let barPath = CGPath(roundedRect: barRect,
                             cornerWidth: barWidth / 2,
                             cornerHeight: barWidth / 2,
                             transform: nil)
        ctx.saveGState()
        ctx.addPath(barPath); ctx.clip()
        let barGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [
                                    NSColor.white.withAlphaComponent(1).cgColor,
                                    NSColor.white.withAlphaComponent(0.78).cgColor,
                                 ] as CFArray,
                                 locations: [0, 1])!
        ctx.drawLinearGradient(barGrad,
            start: CGPoint(x: 0, y: barRect.maxY),
            end: CGPoint(x: 0, y: barRect.minY),
            options: [])
        ctx.restoreGState()
    }

    // 4. Top highlight glaze; subtle gloss across the upper third.
    ctx.saveGState()
    let glaze = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [
                            NSColor.white.withAlphaComponent(0.22).cgColor,
                            NSColor.white.withAlphaComponent(0).cgColor,
                           ] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(glaze,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: size * 0.55),
        options: [])
    ctx.restoreGState()

    // 5. Inner edge shadow; gives the rounded square depth.
    ctx.saveGState()
    let inset: CGFloat = max(1, size * 0.004)
    let innerRect = rect.insetBy(dx: inset, dy: inset)
    let innerPath = CGPath(roundedRect: innerRect,
                           cornerWidth: cornerRadius - inset,
                           cornerHeight: cornerRadius - inset,
                           transform: nil)
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(inset * 2)
    ctx.addPath(innerPath); ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:])
    else { fatalError("png encode failed at \(pixelSize)") }
    return png
}

var contentsImages: [[String: String]] = []
for (pt, scale) in sizes {
    let px = pt * scale
    let data = draw(px)
    let filename = "icon_\(pt)x\(pt)@\(scale)x.png"
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(filename)
    try data.write(to: url)
    contentsImages.append([
        "size": "\(pt)x\(pt)",
        "idiom": "mac",
        "filename": filename,
        "scale": "\(scale)x",
    ])
    print("wrote \(filename) (\(px)px)")
}

let contents: [String: Any] = [
    "images": contentsImages,
    "info": ["version": 1, "author": "xcode"],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted])
try json.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("Contents.json"))
print("wrote Contents.json")
