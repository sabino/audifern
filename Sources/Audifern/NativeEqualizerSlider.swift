import AppKit
import SwiftUI

/// Edits only an in-memory EQ draft. The separate Apply action owns transport.
struct NativeEqualizerSlider: NSViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let enabled: Bool
    let label: String
    let change: (Double) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.isVertical = true; slider.isContinuous = true; slider.controlSize = .large
        slider.target = context.coordinator; slider.action = #selector(Coordinator.changed(_:))
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = range.lowerBound; slider.maxValue = range.upperBound
        slider.doubleValue = min(range.upperBound, max(range.lowerBound, value))
        slider.isEnabled = enabled; slider.trackFillColor = NSColor(Brand.accent)
        slider.setAccessibilityLabel(label)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeEqualizerSlider
        init(_ parent: NativeEqualizerSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) {
            guard parent.enabled, parent.step.isFinite, parent.step > 0 else { return }
            let quantized = (slider.doubleValue / parent.step).rounded() * parent.step
            parent.change(min(parent.range.upperBound, max(parent.range.lowerBound, quantized)))
        }
    }
}
