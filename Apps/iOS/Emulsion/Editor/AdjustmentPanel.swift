import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

/// One group of sliders (Light, Color, Texture) on a glass panel.
struct AdjustmentPanel: View {
    @Binding var adjustments: Adjustments
    @State private var group = AdjustmentGroup.light
    /// Matches the concentric corners of Liquid Glass sheets.
    private let cornerRadius: CGFloat = 24

    var body: some View {
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
