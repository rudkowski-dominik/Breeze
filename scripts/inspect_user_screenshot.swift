import AppKit

let path = "/Users/dominik/.gemini/antigravity/brain/279c540e-fa02-4786-ba13-c3af16ead743/.user_uploaded/media_1794167361793_52a81a44.png"
let img = NSImage(contentsOfFile: path)!
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!

print("Screenshot dimensions: \(rep.pixelsWide)x\(rep.pixelsHigh)")

// Let's find where the white card is
for y in stride(from: 150, to: 350, by: 20) {
    let c = rep.colorAt(x: 120, y: y)!
    print("x=120, y=\(y): R=\(String(format: "%.2f", c.redComponent)) G=\(String(format: "%.2f", c.greenComponent)) B=\(String(format: "%.2f", c.blueComponent))")
}
