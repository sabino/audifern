import AppKit

// Place the canonical SVG's transparent raster export on a native icon tile.
guard CommandLine.arguments.count == 3,
      let mark = NSImage(contentsOfFile: CommandLine.arguments[2]) else { fatalError("Usage: make-icon.swift OUTPUT.iconset MARK.png") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let canvas = CGFloat(pixels)
        let inset = canvas * 0.08
        let shape = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset), xRadius: canvas * 0.20, yRadius: canvas * 0.20)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.99, blue: 0.98, alpha: 1), ending: NSColor(srgbRed: 0.87, green: 0.94, blue: 0.91, alpha: 1))!
        gradient.draw(in: shape, angle: -55)
        mark.draw(in: NSRect(x: canvas * 0.12, y: canvas * 0.12, width: canvas * 0.76, height: canvas * 0.76),
                  from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
