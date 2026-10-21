import AppKit
import QuickAccessUI

@MainActor enum HearingAidImage {
    static func image(size: CGSize, scale: CGFloat, mirrored: Bool) -> NSImage {
        guard let url = AppResources.bundle.url(forResource: "HearingAid", withExtension: "png"),
              let image = ArtworkRasterizer.image(url: url, size: size, scale: scale, mirrored: mirrored) else { return AppResources.hearingAid }
        return image
    }
}
