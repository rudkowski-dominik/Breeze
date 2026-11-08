import AppKit
import CoreGraphics

let inputPath = "/Users/dominik/.gemini/antigravity/brain/279c540e-fa02-4786-ba13-c3af16ead743/.user_uploaded/media_1794164265924_01a1d535.jpg"
guard let sourceImage = NSImage(contentsOfFile: inputPath) else {
    print("Failed to load source image at \(inputPath)")
    exit(1)
}

func renderPixelPerfectIcon(cropRect: NSRect, isDark: Bool) -> NSImage {
    // 1. Extract crop using NSImage (proper macOS upright coordinate system)
    let cropped = NSImage(size: cropRect.size)
    cropped.lockFocus()
    sourceImage.draw(in: NSRect(origin: .zero, size: cropRect.size),
                     from: cropRect,
                     operation: .copy,
                     fraction: 1.0)
    cropped.unlockFocus()

    // 2. Target canvas 1024x1024
    let targetSize = NSSize(width: 1024, height: 1024)
    let finalImage = NSImage(size: targetSize)
    finalImage.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        finalImage.unlockFocus()
        return finalImage
    }

    // Official Apple HIG macOS squircle specification:
    // 824x824 pt on 1024x1024 canvas (corner radius = 824 * 0.2237 = 184.3 pt)
    let squircleSize: CGFloat = 824.0
    let cornerRadius: CGFloat = squircleSize * 0.2237
    let squircleRect = NSRect(
        x: (1024.0 - squircleSize) / 2.0,
        y: (1024.0 - squircleSize) / 2.0 + 8.0, // +8pt optical centering
        width: squircleSize,
        height: squircleSize
    )

    let path = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // A. Subtle neutral black drop shadow (renders beautifully on BOTH dark and light backgrounds!)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 24, color: NSColor.black.withAlphaComponent(0.40).cgColor)
    NSColor.black.setFill()
    path.fill()
    ctx.restoreGState()

    // B. Clip strictly to the continuous squircle path (zero white background bleed)
    ctx.saveGState()
    path.addClip()

    // Draw the cropped icon slightly scaled (-3pt inset to cover edges)
    let drawRect = squircleRect.insetBy(dx: -3, dy: -3)
    cropped.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)

    // C. Elegant glass rim outline
    if isDark {
        NSColor(white: 1.0, alpha: 0.15).setStroke()
    } else {
        NSColor(white: 1.0, alpha: 0.35).setStroke()
    }
    path.lineWidth = 1.5
    path.stroke()

    ctx.restoreGState()

    finalImage.unlockFocus()
    return finalImage
}

let rootDir = "/Users/dominik/.gemini/antigravity/scratch/Breeze"
let assetsDir = "\(rootDir)/assets"
try? FileManager.default.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

// In NSImage coordinate system (y=0 at bottom):
// Dark squircle body:
let darkCrop = NSRect(x: 556, y: 84, width: 380, height: 362)
let dark1024 = renderPixelPerfectIcon(cropRect: darkCrop, isDark: true)

// Light squircle body:
let lightCrop = NSRect(x: 82, y: 56, width: 397, height: 391)
let light1024 = renderPixelPerfectIcon(cropRect: lightCrop, isDark: false)

func savePNG(image: NSImage, path: String) {
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

savePNG(image: dark1024, path: "\(assetsDir)/AppIcon-Dark.png")
savePNG(image: light1024, path: "\(assetsDir)/AppIcon-Light.png")
savePNG(image: dark1024, path: "\(rootDir)/AppIcon_preview.png")

// Generate Apple standard iconsets
func generateIconset(image: NSImage, iconsetName: String) {
    let fm = FileManager.default
    let iconsetPath = "\(rootDir)/\(iconsetName).iconset"
    try? fm.removeItem(atPath: iconsetPath)
    try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    let sizes: [(String, CGFloat)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for (name, size) in sizes {
        let resized = NSImage(size: NSSize(width: size, height: size))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        resized.unlockFocus()
        savePNG(image: resized, path: "\(iconsetPath)/\(name)")
    }
}

generateIconset(image: dark1024, iconsetName: "AppIcon-Dark")
generateIconset(image: light1024, iconsetName: "AppIcon-Light")
generateIconset(image: dark1024, iconsetName: "AppIcon")

print("Generated clean, halo-free icons!")
