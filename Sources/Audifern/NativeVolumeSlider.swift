import AppKit
import SwiftUI

/// AppKit supplies keyboard, accessibility and native tracking behavior. A
/// pointer drag previews locally and sends exactly one value when released.
struct NativeVolumeSlider: NSViewRepresentable {
    enum Style { case standard, capsule }
    let value: Int
    let range: ClosedRange<Int>
    let enabled: Bool
    let label: String
    var style: Style = .standard
    var preview: (Int?) -> Void
    var commit: (Int) -> Void

    func makeNSView(context: Context) -> ReleaseVolumeSlider {
        let slider = ReleaseVolumeSlider()
        if style == .capsule { slider.cell = CapsuleVolumeSliderCell() }
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
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ReleaseVolumeSlider, context: Context) -> CGSize? {
        guard style == .capsule else { return nil }
        return CGSize(width: max(28, proposal.width ?? 52), height: max(72, proposal.height ?? 174))
    }

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

/// Keep AppKit's slider tracking, keyboard and accessibility behavior while
/// drawing the broad, filled vertical control used by the daily Sound view.
@MainActor final class CapsuleVolumeSliderCell: NSSliderCell {
    override func barRect(flipped: Bool) -> NSRect { controlView?.bounds.insetBy(dx: 1, dy: 1) ?? .zero }
    override func knobRect(flipped: Bool) -> NSRect {
        let bar = barRect(flipped: flipped)
        let fraction = max(0, min(1, (doubleValue - minValue) / max(1, maxValue - minValue)))
        let offset = 24 + CGFloat(fraction) * max(0, bar.height - 48)
        let y = flipped ? bar.maxY - offset : bar.minY + offset
        return NSRect(x: bar.midX - 15, y: y - 3, width: 30, height: 6)
    }
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = barRect(flipped: flipped)
        let path = NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.04 : 0.025).setFill(); path.fill()
        let knob = knobRect(flipped: flipped)
        let height = flipped ? bar.maxY - knob.midY : knob.midY - bar.minY
        let fill = NSRect(x: bar.minX, y: flipped ? knob.midY : bar.minY, width: bar.width, height: height)
        NSGradient(starting: NSColor(Brand.accent).withAlphaComponent(isEnabled ? 0.45 : 0.16),
                   ending: NSColor(Brand.accent).withAlphaComponent(isEnabled ? 0.85 : 0.3))?
            .draw(in: fill, angle: flipped ? 90 : -90)
        let symbol = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        let iconRect = NSRect(x: bar.midX - 11, y: flipped ? bar.maxY - 36 : bar.minY + 14, width: 22, height: 20)
        symbol?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 0.85 : 0.45,
                     respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.10).setStroke(); path.lineWidth = 1; path.stroke()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.withAlphaComponent(isEnabled ? 0.95 : 0.65).setFill()
        let handle = NSBezierPath(roundedRect: knobRect, xRadius: 3, yRadius: 3)
        handle.fill()
        NSColor.black.withAlphaComponent(0.12).setStroke(); handle.lineWidth = 0.5; handle.stroke()
    }
    override func drawTickMarks() {}
}

@MainActor final class ReleaseVolumeSlider: NSSlider {
    override var intrinsicContentSize: NSSize {
        cell is CapsuleVolumeSliderCell ? NSSize(width: 52, height: 174) : super.intrinsicContentSize
    }
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
