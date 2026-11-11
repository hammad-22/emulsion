import EmulsionCore
import EmulsionKit
import SwiftUI

/// Every adjustment at once, grouped and on one glass sheet, for canvases with room beside
/// the photo. Shares its selection with `AdjustmentPanel`: the ruler touched last here is the
/// one the panel shows when the canvas narrows again.
public struct AdjustmentInspector: View {
    @Binding private var adjustments: Adjustments
    @Binding private var group: AdjustmentGroup
    @Binding private var selectedControls: [AdjustmentGroup: String]

    public init(adjustments: Binding<Adjustments>, group: Binding<AdjustmentGroup>, selection: Binding<[AdjustmentGroup: String]>) {
        _adjustments = adjustments
        _group = group
        _selectedControls = selection
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FilmLabLayout.space) {
                ForEach(AdjustmentGroup.allCases) { section in
                    VStack(alignment: .leading, spacing: FilmLabLayout.gap) {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.controls) { control in
                            InspectorRow(control: control, adjustments: $adjustments) {
                                group = section
                                selectedControls[section] = control.id
                            }
                        }
                    }
                }
            }
            .padding(FilmLabLayout.inset)
            .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
        }
    }
}

private struct InspectorRow: View {
    let control: AdjustmentControl
    @Binding var adjustments: Adjustments
    let onChange: () -> Void

    var body: some View {
        AdjustmentRuler(control: control, adjustments: $adjustments, identifier: "adjustment-ruler-\(control.id)")
            .onChange(of: adjustments[keyPath: control.keyPath]) { onChange() }
    }
}
