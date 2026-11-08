import AppKit

let path = "/Users/dominik/.gemini/antigravity/scratch/Breeze/assets/AppIcon-Dark.png"
let img = NSImage(contentsOfFile: path)!
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!

print("Image size: \(rep.pixelsWide)x\(rep.pixelsHigh)")
// Sample from edge to center along diagonal (x=y)
for i in stride(from: 50, to: 512, by: 40) {
    let c = rep.colorAt(x: i, y: i)!
    print("Diagonal at (\(i),\(i)): R=\(String(format: "%.2f", c.redComponent)) G=\(String(format: "%.2f", c.greenComponent)) B=\(String(format: "%.2f", c.blueComponent)) A=\(String(format: "%.2f", c.alphaComponent))")
}
