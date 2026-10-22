import AppKit
import SwiftUI
import Testing
@testable import Audifern

@Test func volumeScaleKeepsZeroAndBothReportedBoundsInNarrowControls() {
    #expect(VolumeScale.labelledValues(in: -8...3, width: 96) == [-8, 0, 3])
    #expect(VolumeScale.labelledValues(in: -8...3, width: 400) == Array(-8...3))
    #expect(VolumeScale.labelledValues(in: 1...6, width: 96) == [1, 6])
    #expect(VolumeScale.labelledValues(in: 2...2, width: 96) == [2])
}

@MainActor @Test func volumeScaleFollowsNativeThumbAndKeepsZeroAwayFromTheMidpoint() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    // Exercise reported-value updates through the representable, instead of
    // mutating the NSControl underneath SwiftUI's value ownership.
    for value in -8...3 {
        let host = NSHostingView(rootView: NativeVolumeSlider(value: value, range: -8...3, enabled: true,
            label: "Synthetic volume", vertical: false, showsScale: true,
            preview: { _ in }, commit: { _ in }).frame(width: 320, height: 48))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 48)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let slider = try #require(descendants(host).compactMap { $0 as? ReleaseVolumeSlider }.first)
        let scale = try #require(descendants(host).compactMap { $0 as? VolumeSliderHost }.first)
        let cell = try #require(slider.cell as? NSSliderCell)
        #expect(slider.numberOfTickMarks == 12 && !slider.isVertical)
        #expect(slider.doubleValue == Double(value))
        let minimum = scale.scalePosition(for: -8)
        let zero = scale.scalePosition(for: 0)
        let maximum = scale.scalePosition(for: 3)
        #expect(maximum > minimum)
        #expect(abs((zero - minimum) / (maximum - minimum) - 8.0 / 11) < 0.01)
        #expect(zero > (minimum + maximum) / 2)
        let thumb = slider.convert(cell.knobRect(flipped: slider.isFlipped), to: scale)
        #expect(abs(scale.scalePosition(for: value) - thumb.midX) <= 0.5)
        #expect(host.window == nil)
    }
}

@MainActor @Test func filledControlTintHasReadableWhiteLabelsInBothAppearances() throws {
    func luminance(_ value: CGFloat) -> Double {
        let value = Double(value)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let color = try #require(NSColor(Brand.controlTint).usingColorSpace(.sRGB))
    let light = 0.2126 * luminance(color.redComponent) + 0.7152 * luminance(color.greenComponent) + 0.0722 * luminance(color.blueComponent)
    #expect(1.05 / (light + 0.05) >= 4.5)
}
