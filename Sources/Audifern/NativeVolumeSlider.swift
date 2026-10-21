import AppKit
import SwiftUI

/// AppKit supplies keyboard, accessibility and native tracking behavior. A
/// pointer drag previews locally and sends exactly one value when released.
struct NativeVolumeSlider: NSViewRepresentable {
    let value: Int
    let range: ClosedRange<Int>
    let enabled: Bool
    let label: String
    var preview: (Int?) -> Void
    var commit: (Int) -> Void

    func makeNSView(context: Context) -> ReleaseVolumeSlider {
        let slider = ReleaseVolumeSlider()
        slider.isVertical = true
        slider.controlSize = .large
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.begin = { [weak coordinator = context.coordinator] in coordinator?.begin() }
        slider.end = { [weak coordinator = context.coordinator] value in coordinator?.end(value) }
        return slider
    }
    func updateNSView(_ slider: ReleaseVolumeSlider, context: Context) {
        context.coordinator.parent = self
        slider.isEnabled = enabled && range.lowerBound < range.upperBound
        slider.setAccessibilityLabel(label)
        slider.trackFillColor = NSColor(Brand.accent)
        if !slider.tracking {
            slider.minValue = Double(range.lowerBound)
            slider.maxValue = Double(max(range.lowerBound + 1, range.upperBound))
            slider.numberOfTickMarks = range.count
            slider.allowsTickMarkValuesOnly = true
            slider.doubleValue = Double(value)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: NativeVolumeSlider
        private var originalValue: Int?
        private var originalCommit: ((Int) -> Void)?
        init(_ parent: NativeVolumeSlider) { self.parent = parent }
        func begin() {
            originalValue = parent.value
            originalCommit = parent.commit
        }
        @objc func changed(_ slider: ReleaseVolumeSlider) {
            change(Int(slider.doubleValue.rounded()), tracking: slider.tracking)
        }
        func change(_ value: Int, tracking: Bool) {
            if tracking { parent.preview(value) }
            else if value != parent.value { parent.commit(value) }
        }
        func end(_ value: Int) {
            parent.preview(nil)
            if value != originalValue { originalCommit?(value) }
            originalValue = nil; originalCommit = nil
        }
    }
}

@MainActor final class ReleaseVolumeSlider: NSSlider {
    private(set) var tracking = false
    var begin: (() -> Void)?
    var end: ((Int) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        tracking = true; begin?()
        super.mouseDown(with: event)
        tracking = false
        end?(Int(doubleValue.rounded()))
    }
}
