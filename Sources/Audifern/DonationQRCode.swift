import AppKit
import CoreImage.CIFilterBuiltins

enum DonationQRCode {
    @MainActor private static let context = CIContext()
    @MainActor private static var images: [String: NSImage] = [:]
    /// Local deterministic generation. No QR service receives the destination.
    @MainActor static func image(for payload: String) -> NSImage? {
        if let cached = images[payload] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        // Add four white modules around the complete QR, preserving its quiet
        // zone in light/dark appearances and when the sheet is resized.
        let extent = code.extent.insetBy(dx: -4, dy: -4)
        let background = CIImage(color: .white).cropped(to: extent)
        let framed = code.composited(over: background)
        let scaled = framed.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let image = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: extent.width, height: extent.height))
        images[payload] = result
        return result
    }
}
