import AppKit

// OpenWhisper app icon generator (1024x1024, macOS Big Sur style)
// Usage: swift Scripts/make_icon.swift [output.png]

let size: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap rep") }

guard let nsgfx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("gfx context") }
let ctx = nsgfx.cgContext

// Work in top-left origin coordinates
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Squircle background (824x824 @ 100,100, r=185 — Apple grid)

let inset: CGFloat = 100
let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius: CGFloat = 185
let squircle = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.addPath(squircle)
ctx.clip()

// Vertical gradient: deep indigo -> violet
let bgColors = [
    CGColor(srgbRed: 0.118, green: 0.106, blue: 0.294, alpha: 1),  // #1E1B4B
    CGColor(srgbRed: 0.298, green: 0.114, blue: 0.584, alpha: 1),  // #4C1D95
    CGColor(srgbRed: 0.486, green: 0.227, blue: 0.929, alpha: 1),  // #7C3AED
] as CFArray
let bgGradient = CGGradient(colorsSpace: sRGB, colors: bgColors, locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 512, y: 100),
    end: CGPoint(x: 512, y: 924),
    options: []
)

// Soft radial glow behind the mic
let glowColors = [
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20),
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray
let glow = CGGradient(colorsSpace: sRGB, colors: glowColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 512, y: 460), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 460), endRadius: 340,
    options: []
)

// Subtle top sheen
let sheenColors = [
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10),
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray
let sheen = CGGradient(colorsSpace: sRGB, colors: sheenColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    sheen,
    start: CGPoint(x: 512, y: 100),
    end: CGPoint(x: 512, y: 560),
    options: []
)

// MARK: - Microphone (centered ~460)

let micWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let micSoft = CGColor(srgbRed: 0.878, green: 0.906, blue: 1.0, alpha: 1)

// Capsule body: 190x330 at center x=512, y 285..615
let capsule = CGPath(roundedRect: CGRect(x: 417, y: 285, width: 190, height: 330), cornerWidth: 95, cornerHeight: 95, transform: nil)
ctx.addPath(capsule)
let capsuleGradient = CGGradient(colorsSpace: sRGB, colors: [micWhite, micSoft] as CFArray, locations: [0.0, 1.0])!
ctx.saveGState()
ctx.clip()
ctx.drawLinearGradient(capsuleGradient, start: CGPoint(x: 512, y: 285), end: CGPoint(x: 512, y: 615), options: [])
ctx.restoreGState()

// Holder bracket: U shape wrapping the capsule
ctx.setStrokeColor(micWhite)
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: 512, y: 450), radius: 232, startAngle: .pi * 0.14, endAngle: .pi * 0.86, clockwise: false)
ctx.strokePath()

// Stem
ctx.setFillColor(micWhite)
ctx.fill(CGRect(x: 500, y: 612, width: 24, height: 100))

// Base
let base = CGPath(roundedRect: CGRect(x: 422, y: 706, width: 180, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil)
ctx.addPath(base)
ctx.fillPath()

// MARK: - Whisper waves (left + right of mic)

let waveSpecs: [(radius: CGFloat, width: CGFloat, alpha: CGFloat)] = [
    (300, 30, 0.95),
    (358, 25, 0.65),
    (414, 20, 0.38),
]
let span: CGFloat = .pi * 0.21  // ~38°
for wave in waveSpecs {
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: wave.alpha))
    ctx.setLineWidth(wave.width)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: 512, y: 450), radius: wave.radius, startAngle: -span, endAngle: span, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: CGPoint(x: 512, y: 450), radius: wave.radius, startAngle: .pi - span, endAngle: .pi + span, clockwise: false)
    ctx.strokePath()
}

// Inner highlight stroke on the squircle edge
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
ctx.setLineWidth(3)
ctx.addPath(squircle)
ctx.strokePath()

// MARK: - Export

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon-1024.png"
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try! png.write(to: url)
print("wrote \(outPath)")
