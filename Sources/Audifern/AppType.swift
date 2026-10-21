import SwiftUI

/// Desktop reading sizes are deliberately larger than SwiftUI's compact Mac
/// defaults. Secondary copy remains readable on a laptop at normal distance.
enum AppType {
    static let body = Font.system(size: 17)
    static let callout = Font.system(size: 16)
    static let caption = Font.system(size: 14)
    static let small = Font.system(size: 13)
    static let headline = Font.system(size: 19, weight: .semibold)
    static let subheading = Font.system(size: 21, weight: .semibold)
}
