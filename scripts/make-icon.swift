import AppKit

// Draw the app's own icon using an OS-provided symbol; no vendor artwork.
guard CommandLine.arguments.count == 2 else { fatalError("Usage: make-icon.swift OUTPUT.iconset") }
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
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.64, blue: 0.62, alpha: 1), ending: NSColor(srgbRed: 0.05, green: 0.27, blue: 0.43, alpha: 1))!
        gradient.draw(in: shape, angle: -55)
        if let symbol = NSImage(systemSymbolName: "ear.badge.waveform", accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white])) {
            let size = canvas * 0.58
            symbol.draw(in: NSRect(x: canvas * 0.21, y: canvas * 0.20, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
