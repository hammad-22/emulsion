import EmulsionCore
import EmulsionKit
import SwiftUI

/// A single selected adjustment on native glass, with the rest available on demand.
public struct AdjustmentPanel: View {
    @Binding private var adjustments: Adjustments
    @Binding private var group: AdjustmentGroup
    @Binding private var selectedControls: [AdjustmentGroup: String]

    public init(adjustments: Binding<Adjustments>, group: Binding<AdjustmentGroup>, selection: Binding<[AdjustmentGroup: String]>) {
        _adjustments = adjustments
        _group = group
        _selectedControls = selection
    }

    private var selectedControl: AdjustmentControl {
        group.controls.first { $0.id == selectedControls[group] } ?? group.controls[0]
    }

    public var body: some View {
        VStack(spacing: FilmLabLayout.compact) {
            header
            AdjustmentRuler(control: selectedControl, adjustments: $adjustments)
            controlPicker
        }
        .padding(FilmLabLayout.inset)
        .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
        .sensoryFeedback(.selection, trigger: selectedControl.id)
    }

    private var header: some View {
        HStack {
            Menu {
                Picker("Adjustments", selection: $group) {
                    ForEach(AdjustmentGroup.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label(group.title, systemImage: "chevron.down")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: FilmLabLayout.minimumControlHeight)
            }
            .accessibilityLabel("Adjustment group")
            Spacer()
            Button("Reset Adjustment", systemImage: "arrow.counterclockwise") {
                adjustments[keyPath: selectedControl.keyPath] = Adjustments()[keyPath: selectedControl.keyPath]
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: FilmLabLayout.minimumControlHeight, minHeight: FilmLabLayout.minimumControlHeight)
            .disabled(adjustments[keyPath: selectedControl.keyPath] == Adjustments()[keyPath: selectedControl.keyPath])
        }
    }

    private var controlPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: FilmLabLayout.compact) {
                ForEach(group.controls) { control in
                    Button {
                        selectedControls[group] = control.id
                    } label: {
                        Text(control.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, FilmLabLayout.gap)
                            .frame(minHeight: FilmLabLayout.minimumControlHeight)
                            .background(control.id == selectedControl.id ? Color.primary.opacity(0.12) : Color.clear, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(control.id == selectedControl.id ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
