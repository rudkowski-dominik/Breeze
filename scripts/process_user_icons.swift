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

func cropAndClean(centerX: CGFloat, centerY: CGFloat, size: CGFloat, isDark: Bool) -> CGImage {
    let cropRect = CGRect(x: centerX - size/2, y: centerY - size/2, width: size, height: size)
    let croppedCg = cgImage.cropping(to: cropRect)!
    
    let w = croppedCg.width
    let h = croppedCg.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
        return croppedCg
    }
    
    ctx.draw(croppedCg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let pixelBuffer = ctx.data else { return croppedCg }
    let ptr = pixelBuffer.bindMemory(to: UInt8.self, capacity: w * h * 4)
    
    let center = CGPoint(x: CGFloat(w)/2.0, y: CGFloat(h)/2.0)
    let squircleR: CGFloat = size * 0.415
    
    for y in 0..<h {
        for x in 0..<w {
            let offset = (y * w + x) * 4
            let r = Float(ptr[offset]) / 255.0
            let g = Float(ptr[offset + 1]) / 255.0
            let b = Float(ptr[offset + 2]) / 255.0
            
            let dx = abs(CGFloat(x) - center.x)
            let dy = abs(CGFloat(y) - center.y)
            let dist = max(dx, dy)
            
            // Only process outside / shadow boundary
            if dist > squircleR - 18 {
                let minC = min(r, min(g, b))
                if minC > 0.985 {
                    // Pure white background -> transparent
                    ptr[offset + 3] = 0
                    ptr[offset] = 0
                    ptr[offset + 1] = 0
                    ptr[offset + 2] = 0
                } else if minC > 0.85 {
                    // Outer shadow feathering
                    let alpha = max(0.0, min(1.0, (1.0 - minC) * 3.2))
                    let newA = UInt8(alpha * 255.0)
                    ptr[offset + 3] = newA
                    if isDark {
                        ptr[offset] = UInt8(Float(ptr[offset]) * 0.12 * alpha)
                        ptr[offset + 1] = UInt8(Float(ptr[offset + 1]) * 0.18 * alpha)
                        ptr[offset + 2] = UInt8(Float(ptr[offset + 2]) * 0.35 * alpha)
                    } else {
                        ptr[offset] = UInt8(Float(ptr[offset]) * 0.20 * alpha)
                        ptr[offset + 1] = UInt8(Float(ptr[offset + 1]) * 0.25 * alpha)
                        ptr[offset + 2] = UInt8(Float(ptr[offset + 2]) * 0.40 * alpha)
                    }
                }
            }
        }
    }
    
    return ctx.makeImage() ?? croppedCg
}

func renderCanvas(cgImage: CGImage, targetSize: CGFloat) -> NSImage {
    let outImg = NSImage(size: NSSize(width: targetSize, height: targetSize))
    outImg.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        outImg.unlockFocus()
        return outImg
    }
    ctx.interpolationQuality = .high
    
    // Scale squircle to occupy ~82% of macOS app icon canvas (Apple standard icon grid)
    let iconSize = targetSize * 0.84
    let origin = (targetSize - iconSize) / 2.0
    let targetRect = CGRect(x: origin, y: origin, width: iconSize, height: iconSize)
    
    ctx.draw(cgImage, in: targetRect)
    outImg.unlockFocus()
    return outImg
}

let lightCg = cropAndClean(centerX: 280.5, centerY: 265, size: 480, isDark: false)
let darkCg = cropAndClean(centerX: 751.0, centerY: 265, size: 480, isDark: true)

let rootDir = "/Users/dominik/.gemini/antigravity/scratch/Breeze"
let assetsDir = "\(rootDir)/assets"
try? FileManager.default.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

// Save high-resolution PNGs
let light1024 = renderCanvas(cgImage: lightCg, targetSize: 1024)
let dark1024 = renderCanvas(cgImage: darkCg, targetSize: 1024)

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

// Create iconset for icns generation
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

print("Generated iconsets for Dark, Light, and default AppIcon.")
