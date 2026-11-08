import EmulsionCore
import EmulsionKit
import SwiftUI

/// One labeled slider for an `AdjustmentControl`. Double-tap the value to reset it.
public struct AdjustmentSlider: View {
    private let control: AdjustmentControl
    @Binding private var adjustments: Adjustments

    public init(_ control: AdjustmentControl, adjustments: Binding<Adjustments>) {
        self.control = control
        _adjustments = adjustments
    }

    private var value: Binding<Double> { $adjustments[dynamicMember: control.keyPath] }
    private var defaultValue: Double { Adjustments()[keyPath: control.keyPath] }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title)
                Spacer()
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
    }
}
