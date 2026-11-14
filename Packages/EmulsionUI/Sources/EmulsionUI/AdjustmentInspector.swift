import EmulsionCore
import EmulsionKit
import SwiftUI

/// Every adjustment on one glass sheet, sharing its selection with `AdjustmentPanel`.
public struct AdjustmentInspector: View {
    @Binding private var adjustments: Adjustments
    @Binding private var group: AdjustmentGroup
    @Binding private var selectedControls: [AdjustmentGroup: String]
    private let whiteBalanceAsShot: CameraWhiteBalance?

    /// `whiteBalanceAsShot`, a RAW photo's, adds the White Balance group.
    public init(
        adjustments: Binding<Adjustments>, group: Binding<AdjustmentGroup>, selection: Binding<[AdjustmentGroup: String]>,
        whiteBalanceAsShot: CameraWhiteBalance? = nil
    ) {
        _adjustments = adjustments
        _group = group
        _selectedControls = selection
        self.whiteBalanceAsShot = whiteBalanceAsShot
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FilmLabLayout.space) {
                ForEach(AdjustmentGroup.available(whiteBalanceAsShot: whiteBalanceAsShot)) { section in
                    VStack(alignment: .leading, spacing: FilmLabLayout.gap) {
                        Text(section.title)
                            // Case, not a dimmer style: secondary measured 3.2:1 on dark glass, under 4.5:1 for small text (MOV-140).
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.controls(whiteBalanceAsShot: whiteBalanceAsShot)) { control in
                            AdjustmentRuler(control: control, adjustments: $adjustments, isCompact: true)
                        }
                    }
                }
            }
            .padding(FilmLabLayout.inset)
        }
        .clipShape(.rect(cornerRadius: FilmLabLayout.panelCorner))
        .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
        .onChange(of: adjustments) { old, new in select(changedFrom: old, to: new) }
    }

    private func select(changedFrom old: Adjustments, to new: Adjustments) {
        guard let changed = AdjustmentGroup.changedControl(from: old, to: new, whiteBalanceAsShot: whiteBalanceAsShot) else { return }
        if group != changed.group { group = changed.group }
        if selectedControls[changed.group] != changed.control { selectedControls[changed.group] = changed.control }
    }
}
