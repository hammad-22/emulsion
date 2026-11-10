import EmulsionCore
import EmulsionKit
import SwiftUI

/// One labeled slider for an `AdjustmentControl`. Double-tap the value to reset it. A light
/// haptic tap marks leaving, crossing or returning to the unedited value, like a detent.
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

    public var body: some View {
        VStack(alignment: .leading, spacing: FilmLabLayout.compact) {
            labelLayout {
                Text(control.title)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(control.formatted(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .onTapGesture(count: 2) { value.wrappedValue = defaultValue }
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            Slider(value: value, in: control.range)
                .accessibilityLabel(control.title)
                .accessibilityValue(control.formatted(value.wrappedValue))
                .accessibilityAction(named: "Reset") { value.wrappedValue = defaultValue }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: side)
    }

    /// Title and value on one line, or stacked at accessibility text sizes so long titles
    /// aren't broken mid-word.
    private var labelLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }
}
