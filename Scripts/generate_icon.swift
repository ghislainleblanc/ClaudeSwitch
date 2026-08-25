import AppKit

// Usage: swift generate_icon.swift <output-directory>
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

let canvas: CGFloat = 1024
let margin: CGFloat = 100
let cornerRadius: CGFloat = 185

func tintedSymbol(_ name: String, weight: NSFont.Weight = .semibold, color: NSColor) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: 512, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else {
        fatalError("missing SF Symbol: \(name)")
    }
    return NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func draw(_ image: NSImage, centeredAt center: CGPoint, height: CGFloat) {
    let aspect = image.size.width / image.size.height
    let rect = CGRect(x: center.x - height * aspect / 2,
                      y: center.y - height / 2,
                      width: height * aspect,
                      height: height)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// Render the 1024pt master.
let masterRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: masterRep)!
NSGraphicsContext.current = context
context.imageInterpolation = .high

let squircleRect = CGRect(x: margin, y: margin, width: canvas - 2 * margin, height: canvas - 2 * margin)
let squircle = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Soft baked-in drop shadow, standard for macOS icons.
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = CGSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
color(0xC4633E).setFill()
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Two-tone diagonal background, clipped to the squircle:
// top-left = personal (Claude clay), bottom-right = work (slate).
NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()

NSGradient(starting: color(0xE5926F), ending: color(0xC4633E))!
    .draw(in: squircleRect, angle: -60)

let workTriangle = NSBezierPath()
workTriangle.move(to: CGPoint(x: squircleRect.minX, y: squircleRect.minY))
workTriangle.line(to: CGPoint(x: squircleRect.maxX, y: squircleRect.maxY))
workTriangle.line(to: CGPoint(x: squircleRect.maxX, y: squircleRect.minY))
workTriangle.close()
NSGraphicsContext.current?.saveGraphicsState()
workTriangle.addClip()
NSGradient(starting: color(0x4A5A6E), ending: color(0x303C4C))!
    .draw(in: squircleRect, angle: -60)
NSGraphicsContext.current?.restoreGraphicsState()

// Profile symbols.
draw(tintedSymbol("person.fill", color: .white), centeredAt: CGPoint(x: 372, y: 668), height: 260)
draw(tintedSymbol("briefcase.fill", color: .white), centeredAt: CGPoint(x: 660, y: 366), height: 230)

// Center swap badge on the seam.
let badgeRadius: CGFloat = 148
let badgeRect = CGRect(x: canvas / 2 - badgeRadius, y: canvas / 2 - badgeRadius,
                       width: badgeRadius * 2, height: badgeRadius * 2)
NSGraphicsContext.current?.saveGraphicsState()
let badgeShadow = NSShadow()
badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
badgeShadow.shadowOffset = CGSize(width: 0, height: -8)
badgeShadow.shadowBlurRadius = 18
badgeShadow.set()
NSColor.white.setFill()
NSBezierPath(ovalIn: badgeRect).fill()
NSGraphicsContext.current?.restoreGraphicsState()

draw(tintedSymbol("arrow.left.arrow.right", weight: .bold, color: color(0x37414F)),
     centeredAt: CGPoint(x: canvas / 2, y: canvas / 2), height: 118)

NSGraphicsContext.current?.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard let masterCG = masterRep.cgImage else { fatalError("master render failed") }

// Emit every appiconset size.
let files: [(String, Int)] = [
    ("icon_16.png", 16), ("icon_16@2x.png", 32),
    ("icon_32.png", 32), ("icon_32@2x.png", 64),
    ("icon_128.png", 128), ("icon_128@2x.png", 256),
    ("icon_256.png", 256), ("icon_256@2x.png", 512),
    ("icon_512.png", 512), ("icon_512@2x.png", 1024),
]

for (name, pixels) in files {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let sizeContext = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = sizeContext
    sizeContext.imageInterpolation = .high
    sizeContext.cgContext.draw(masterCG, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
    try data.write(to: outputDirectory.appending(path: name))
    print("wrote \(name) (\(pixels)px)")
}
