import EmulsionCore
import EmulsionKit
import SwiftUI

/// The editor's controls on one sheet of Liquid Glass: a group picker above that group's
/// sliders. Every group is laid out and only the chosen one shown, so the panel keeps one
/// height and the photo beside it doesn't resize when the group changes.
public struct AdjustmentPanel: View {
    @Binding private var adjustments: Adjustments
    @Binding private var group: AdjustmentGroup
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(adjustments: Binding<Adjustments>, group: Binding<AdjustmentGroup>) {
        _adjustments = adjustments
        _group = group
    }

    public var body: some View {
        VStack(spacing: FilmLabLayout.inset) {
            groupPicker
            ZStack {
                ForEach(AdjustmentGroup.allCases) { item in
                    Grid(alignment: .leading, horizontalSpacing: FilmLabLayout.gap, verticalSpacing: FilmLabLayout.compact) {
                        ForEach(item.controls) { AdjustmentSlider($0, adjustments: $adjustments) }
                    }
                    .opacity(item == group ? 1 : 0)
                    .allowsHitTesting(item == group)
                    .accessibilityHidden(item != group)
                }
            }
        }
        .padding(FilmLabLayout.inset)
        .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
        .sensoryFeedback(.selection, trigger: group)
    }

    /// Segments side by side; a menu at accessibility text sizes, where three titles
    /// can't share the width.
    @ViewBuilder private var groupPicker: some View {
        let picker = Picker("Adjustments", selection: $group) {
            ForEach(AdjustmentGroup.allCases) { Text($0.title).tag($0) }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}
