import AppKit
import CoreGraphics

let inputPath = "/Users/dominik/.gemini/antigravity/brain/279c540e-fa02-4786-ba13-c3af16ead743/.user_uploaded/media_1794164265924_01a1d535.jpg"
guard let sourceImage = NSImage(contentsOfFile: inputPath),
      let tiffData = sourceImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let cgImage = bitmap.cgImage else {
    print("Failed to load source image")
    exit(1)
}

func renderNativeAppleSquircleIcon(centerX: CGFloat, centerY: CGFloat, sourceSize: CGFloat, targetCanvasSize: CGFloat = 1024.0) -> NSImage {
    // 1. Crop exactly the icon content from source
    let srcRect = CGRect(x: centerX - sourceSize/2, y: centerY - sourceSize/2, width: sourceSize, height: sourceSize)
    let croppedCg = cgImage.cropping(to: srcRect)!

    // 2. Apple HIG standard icon proportions:
    // Canvas is 1024x1024, squircle is ~834x834 pt, corner radius is 0.2237 * width (~186.5 pt)
    let squircleSize: CGFloat = 834.0
    let cornerRadius: CGFloat = squircleSize * 0.2237
    let squircleOrigin = CGPoint(
        x: (targetCanvasSize - squircleSize) / 2.0,
        y: (targetCanvasSize - squircleSize) / 2.0 + 8.0 // standard +8pt optical centering for drop shadow
    )
    let squircleRect = CGRect(origin: squircleOrigin, size: CGSize(width: squircleSize, height: squircleSize))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: Int(targetCanvasSize), height: Int(targetCanvasSize), bitsPerComponent: 8, bytesPerRow: Int(targetCanvasSize) * 4, space: colorSpace, bitmapInfo: bitmapInfo)!

    // 3. Render authentic macOS icon drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 24, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 4. Clip to continuous Apple squircle path to completely eliminate outer background white artifacts
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // 5. Draw the user's high-res icon perfectly centered into the squircle
    ctx.interpolationQuality = .high
    ctx.draw(croppedCg, in: squircleRect)

    // 6. Subtle inner rim stroke for enhanced glass depth
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    ctx.restoreGState()

    let resultCg = ctx.makeImage()!
    return NSImage(cgImage: resultCg, size: NSSize(width: targetCanvasSize, height: targetCanvasSize))
}

let rootDir = "/Users/dominik/.gemini/antigravity/scratch/Breeze"
let assetsDir = "\(rootDir)/assets"
try? FileManager.default.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

// Render Light and Dark icons with exact Apple HIG squircle geometry
let light1024 = renderNativeAppleSquircleIcon(centerX: 280.5, centerY: 264.5, sourceSize: 406.0)
let dark1024 = renderNativeAppleSquircleIcon(centerX: 751.0, centerY: 265.5, sourceSize: 406.0)

func savePNG(image: NSImage, path: String) {
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

savePNG(image: light1024, path: "\(assetsDir)/AppIcon-Light.png")
savePNG(image: dark1024, path: "\(assetsDir)/AppIcon-Dark.png")
savePNG(image: dark1024, path: "\(rootDir)/AppIcon_preview.png")

// Generate standard Apple iconsets
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

print("Generated pixel-perfect native macOS squircle iconsets!")
