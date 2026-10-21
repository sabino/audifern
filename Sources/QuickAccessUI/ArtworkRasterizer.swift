import AppKit
import ImageIO
import SwiftUI

/// Downsample directly to the final backing pixels, including the mirror.
/// Avoid enlarging a smaller SwiftUI raster after it has already been resized.
@MainActor public enum ArtworkRasterizer {
    private static let images = NSCache<NSString, NSImage>()
    public static func image(url: URL, size: CGSize, scale: CGFloat, mirrored: Bool) -> NSImage? {
        let scale = max(1, min(3, scale))
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        let key = "\(url.path)-\(width)x\(height)-\(mirrored)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard width > 0, height > 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        if mirrored { context.translateBy(x: CGFloat(width), y: 0); context.scaleBy(x: -1, y: 1) }
        let factor = min(CGFloat(width) / CGFloat(thumbnail.width), CGFloat(height) / CGFloat(thumbnail.height))
        let target = CGSize(width: CGFloat(thumbnail.width) * factor, height: CGFloat(thumbnail.height) * factor)
        context.draw(thumbnail, in: CGRect(x: (CGFloat(width) - target.width) / 2, y: (CGFloat(height) - target.height) / 2, width: target.width, height: target.height))
        guard let pixels = context.makeImage() else { return nil }
        let result = NSImage(cgImage: pixels, size: size)
        images.setObject(result, forKey: key, cost: width * height * 4)
        images.totalCostLimit = 12 * 1_024 * 1_024
        return result
    }
}
