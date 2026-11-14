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
    private let whiteBalanceAsShot: CameraWhiteBalance?

    /// `whiteBalanceAsShot` is a RAW photo's as-shot white balance, which adds the White Balance
    /// group; nil for other photos.
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
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
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

    /// A ruler move changes one control; Reset Edits changes several and keeps the selection.
    private func select(changedFrom old: Adjustments, to new: Adjustments) {
        guard let changed = AdjustmentGroup.changedControl(from: old, to: new, whiteBalanceAsShot: whiteBalanceAsShot) else { return }
        if group != changed.group { group = changed.group }
        if selectedControls[changed.group] != changed.control { selectedControls[changed.group] = changed.control }
    }
}
