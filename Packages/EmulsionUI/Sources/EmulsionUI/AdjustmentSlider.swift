import EmulsionCore
import EmulsionKit
import SwiftUI

/// One slider for an `AdjustmentControl`, as a row of an `AdjustmentPanel`'s grid: title,
/// slider, value. Double-tap the value to reset it. A light haptic tap marks leaving,
/// crossing or returning to the unedited value, like a detent.
public struct AdjustmentSlider: View {
    private let control: AdjustmentControl
    @Binding private var adjustments: Adjustments
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ control: AdjustmentControl, adjustments: Binding<Adjustments>) {
        self.control = control
        _adjustments = adjustments
    }

    private var value: Binding<Double> { $adjustments[dynamicMember: control.keyPath] }
    private var defaultValue: Double { Adjustments()[keyPath: control.keyPath] }
    /// Which side of the unedited value the slider is on: -1, 0 or +1.
    private var side: Int {
        value.wrappedValue < defaultValue ? -1 : value.wrappedValue > defaultValue ? 1 : 0
    }
    /// Two-sided controls fill from their middle, so the track shows the direction of the change.
    private var neutralValue: Double? { control.range.lowerBound < 0 ? 0 : nil }

    public var body: some View {
        GridRow {
            if dynamicTypeSize.isAccessibilitySize {
                // Stacked, so long titles aren't broken mid-word and the slider keeps its length.
                VStack(alignment: .leading, spacing: FilmLabLayout.hairline) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer()
                        currentValue
                    }
                    slider
                }
                .gridCellColumns(3)
            } else {
                title
                slider
                // As wide as the widest value the control can show, so the slider doesn't
                // change length while it's dragged.
                Text(control.formatted(control.range.lowerBound))
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .trailing) { currentValue.fixedSize() }
            }
        }
        .font(.subheadline)
        .sensoryFeedback(.impact(weight: .light), trigger: side)
    }

    private var title: some View {
        Text(control.title)
            .fontWeight(.medium)
    }

    private var slider: some View {
        Slider(value: value, in: control.range, neutralValue: neutralValue) {
            Text(control.title)
        }
        .accessibilityValue(control.formatted(value.wrappedValue))
        .accessibilityAction(named: "Reset") { value.wrappedValue = defaultValue }
    }

    private var currentValue: some View {
        Text(control.formatted(value.wrappedValue))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .contentShape(.rect)
            .onTapGesture(count: 2) { value.wrappedValue = defaultValue }
            .accessibilityHidden(true)
    }
}
