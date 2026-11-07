import AppKit
import CoreGraphics

func renderLiquidGlassIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.saveGState()

    // Dimensions
    let padding = size * 0.08
    let iconRect = CGRect(x: padding, y: padding, width: size - (2 * padding), height: size - (2 * padding))
    let cornerRadius = iconRect.width * 0.2237 // Apple standard squircle ratio

    // 1. Drop shadow for the squircle
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.08, color: NSColor.black.withAlphaComponent(0.40).cgColor)

    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()

    ctx.restoreGState()
    ctx.saveGState()

    // Clip to squircle
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Liquid Glass Deep Cyan/Ice Gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let deepNavy = NSColor(red: 0.04, green: 0.12, blue: 0.28, alpha: 1.0).cgColor
    let vibrantAzure = NSColor(red: 0.0, green: 0.48, blue: 0.95, alpha: 1.0).cgColor
    let iceTurquoise = NSColor(red: 0.10, green: 0.82, blue: 0.92, alpha: 1.0).cgColor
    let gradientColors = [deepNavy, vibrantAzure, iceTurquoise] as CFArray
    let gradientLocations: [CGFloat] = [0.0, 0.65, 1.0]

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: iconRect.midX, y: iconRect.minY), end: CGPoint(x: iconRect.midX, y: iconRect.maxY), options: [])
    }

    // 3. Frosted Glass Inner Glow & Vignette
    if let radialGrad = CGGradient(colorsSpace: colorSpace, colors: [NSColor.white.withAlphaComponent(0.25).cgColor, NSColor.clear.cgColor] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(radialGrad, startCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.85), startRadius: 0, endCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.85), endRadius: iconRect.width * 0.6, options: [])
    }

    // 4. Draw Precision Aerodynamic Glass Fan Propeller
    let center = CGPoint(x: iconRect.midX, y: iconRect.midY)
    let hubRadius = iconRect.width * 0.11
    let bladeLength = iconRect.width * 0.35

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.35).cgColor)

    // Draw 3 curved 3D glass blades
    for i in 0..<3 {
        let baseAngle = CGFloat(i) * (2.0 * CGFloat.pi / 3.0) + (CGFloat.pi / 6.0)
        let bladePath = CGMutablePath()

        let startP = CGPoint(
            x: center.x + hubRadius * cos(baseAngle - 0.2),
            y: center.y + hubRadius * sin(baseAngle - 0.2)
        )
        let tipP = CGPoint(
            x: center.x + bladeLength * cos(baseAngle + 0.55),
            y: center.y + bladeLength * sin(baseAngle + 0.55)
        )
        let ctrlP1 = CGPoint(
            x: center.x + (bladeLength * 0.65) * cos(baseAngle + 0.15),
            y: center.y + (bladeLength * 0.65) * sin(baseAngle + 0.15)
        )
        let endTipP = CGPoint(
            x: center.x + bladeLength * cos(baseAngle + 0.80),
            y: center.y + bladeLength * sin(baseAngle + 0.80)
        )
        let endP = CGPoint(
            x: center.x + hubRadius * cos(baseAngle + 0.35),
            y: center.y + hubRadius * sin(baseAngle + 0.35)
        )
        let ctrlP2 = CGPoint(
            x: center.x + (bladeLength * 0.55) * cos(baseAngle + 0.95),
            y: center.y + (bladeLength * 0.55) * sin(baseAngle + 0.95)
        )

        bladePath.move(to: startP)
        bladePath.addQuadCurve(to: tipP, control: ctrlP1)
        bladePath.addLine(to: endTipP)
        bladePath.addQuadCurve(to: endP, control: ctrlP2)
        bladePath.closeSubpath()

        // Fill blade with translucent frosted glass gradient
        ctx.saveGState()
        ctx.addPath(bladePath)
        ctx.clip()

        let bladeGradColors = [
            NSColor.white.withAlphaComponent(0.95).cgColor,
            NSColor(red: 0.80, green: 0.95, blue: 1.0, alpha: 0.65).cgColor,
            NSColor(red: 0.50, green: 0.85, blue: 1.0, alpha: 0.40).cgColor
        ] as CFArray
        if let bladeGrad = CGGradient(colorsSpace: colorSpace, colors: bladeGradColors, locations: [0.0, 0.5, 1.0]) {
            ctx.drawLinearGradient(bladeGrad, start: startP, end: endTipP, options: [])
        }
        ctx.restoreGState()

        // Blade Bevel Outline
        ctx.addPath(bladePath)
        ctx.setLineWidth(size * 0.007)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.strokePath()
    }

    // 5. Central Hub with glossy metal/glass jewel ring
    let hubPath = CGMutablePath()
    hubPath.addArc(center: center, radius: hubRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)

    ctx.saveGState()
    ctx.addPath(hubPath)
    ctx.clip()
    let hubColors = [
        NSColor.white.withAlphaComponent(0.98).cgColor,
        NSColor(red: 0.82, green: 0.94, blue: 1.0, alpha: 0.85).cgColor,
        NSColor(red: 0.30, green: 0.65, blue: 0.95, alpha: 0.90).cgColor
    ] as CFArray
    if let hubGrad = CGGradient(colorsSpace: colorSpace, colors: hubColors, locations: [0.0, 0.4, 1.0]) {
        ctx.drawLinearGradient(hubGrad, start: CGPoint(x: center.x - hubRadius, y: center.y + hubRadius), end: CGPoint(x: center.x + hubRadius, y: center.y - hubRadius), options: [])
    }
    ctx.restoreGState()

    // Hub Bevel Rim
    ctx.addPath(hubPath)
    ctx.setLineWidth(size * 0.008)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    ctx.strokePath()

    // Inner Hub Dot
    let innerDotPath = CGMutablePath()
    innerDotPath.addArc(center: center, radius: hubRadius * 0.4, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setFillColor(NSColor(red: 0.02, green: 0.25, blue: 0.55, alpha: 0.85).cgColor)
    ctx.addPath(innerDotPath)
    ctx.fillPath()

    ctx.restoreGState() // Restore shadow

    // 6. Liquid Glass Top Specular Glare (Apple Glass Reflection)
    let glarePath = CGMutablePath()
    let glareRect = CGRect(x: iconRect.minX, y: iconRect.midY - (iconRect.height * 0.1), width: iconRect.width, height: iconRect.height * 0.6)
    glarePath.addEllipse(in: glareRect)

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    if let glareGrad = CGGradient(colorsSpace: colorSpace, colors: [NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(glareGrad, start: CGPoint(x: iconRect.midX, y: iconRect.maxY), end: CGPoint(x: iconRect.midX, y: iconRect.midY), options: [])
    }
    ctx.restoreGState()

    // 7. Outer Glass Rim Stroke
    ctx.addPath(squirclePath)
    ctx.setLineWidth(size * 0.012)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
    ctx.strokePath()

    ctx.restoreGState()

    img.unlockFocus()
    return img
}

// Generate the complete iconset
let fm = FileManager.default
let iconsetPath = "/Users/dominik/.gemini/antigravity/scratch/Breeze/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
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

for (filename, size) in iconSizes {
    let img = renderLiquidGlassIcon(size: size)
    if let tiff = img.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: "\(iconsetPath)/\(filename)")
        try! png.write(to: url)
    }
}
print("Generated all icon sizes in \(iconsetPath)")
