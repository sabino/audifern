import AppKit
import Foundation

enum AppResources {
    /// SwiftPM's generated accessor also contains a development build path.
    /// Prefer the packaged Resources directory so distributed apps are portable.
    static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("Audifern_Audifern.bundle"),
           let bundled = Bundle(url: resourceURL) { return bundled }
        return Bundle.module
    }()

    @MainActor static let brandMark = image("BrandMark")
    @MainActor static let hearingAid = image("HearingAid")

    @MainActor private static func image(_ name: String) -> NSImage {
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Required application artwork is missing: \(name)")
        }
        return image
    }
}
