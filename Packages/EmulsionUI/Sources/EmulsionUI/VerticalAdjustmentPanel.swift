import EmulsionCore
import EmulsionKit
import SwiftUI

public struct VerticalAdjustmentPanel: View {
    @Binding var adjustments: Adjustments
    @Binding var selectedGroup: AdjustmentGroup
    @Binding var selection: [AdjustmentGroup: String]
    let whiteBalanceAsShot: CameraWhiteBalance?

    public init(
        adjustments: Binding<Adjustments>, group: Binding<AdjustmentGroup>, selection: Binding<[AdjustmentGroup: String]>,
        whiteBalanceAsShot: CameraWhiteBalance?
    ) {
        _adjustments = adjustments
        _selectedGroup = group
        _selection = selection
        self.whiteBalanceAsShot = whiteBalanceAsShot
    }

    public var body: some View {
        let groups = AdjustmentGroup.available(whiteBalanceAsShot: whiteBalanceAsShot)
        let group = groups.contains(selectedGroup) ? selectedGroup : .light
        let controls = group.controls(whiteBalanceAsShot: whiteBalanceAsShot)
        let control = controls.first { $0.id == selection[group] } ?? controls[0]
        VStack(spacing: FilmLabLayout.hairline) {
            Menu {
                ForEach(groups) { section in
                    Section(section.title) {
                        ForEach(section.controls(whiteBalanceAsShot: whiteBalanceAsShot)) { option in
                            Button {
                                selectedGroup = section
                                selection[section] = option.id
                            } label: {
                                let title = option.title(for: adjustments.process)
                                if option.id == control.id { Label(title, systemImage: "checkmark") } else { Text(title) }
                            }
                        }
                    }
                }
            } label: {
                Label("Choose Adjustment", systemImage: "slider.vertical.3")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: FilmLabLayout.minimumControlHeight, minHeight: FilmLabLayout.minimumControlHeight)
            }
            .accessibilityValue(group.title)
            AdjustmentRuler(control: control, adjustments: $adjustments, axis: .vertical)
            Button {
                adjustments[keyPath: control.keyPath] = Adjustments()[keyPath: control.keyPath]
            } label: {
                Label("Reset Adjustment", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: FilmLabLayout.minimumControlHeight, minHeight: FilmLabLayout.minimumControlHeight)
            }
            .buttonStyle(.borderless)
            .disabled(adjustments[keyPath: control.keyPath] == Adjustments()[keyPath: control.keyPath])
        }
        .padding(FilmLabLayout.compact)
        .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
        .sensoryFeedback(.selection, trigger: control.id)
    }
}
