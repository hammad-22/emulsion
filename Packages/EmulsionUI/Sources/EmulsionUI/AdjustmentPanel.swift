import EmulsionCore
import EmulsionKit
import SwiftUI

/// One group of sliders (Light, Color, Texture) on a glass panel.
public struct AdjustmentPanel: View {
    @Binding var adjustments: Adjustments
    @State private var group = AdjustmentGroup.light
    /// Matches the concentric corners of Liquid Glass sheets.
    private let cornerRadius: CGFloat = 24

    public init(adjustments: Binding<Adjustments>) {
        _adjustments = adjustments
    }

    public var body: some View {
        VStack(spacing: 16) {
            Picker("Adjustments", selection: $group) {
                ForEach(AdjustmentGroup.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(group.controls) { AdjustmentSlider($0, adjustments: $adjustments) }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        .padding()
    }
}
