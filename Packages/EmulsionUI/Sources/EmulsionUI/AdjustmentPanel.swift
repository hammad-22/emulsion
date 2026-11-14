import EmulsionCore
import EmulsionKit
import SwiftUI

/// A single selected adjustment on native glass, with the rest available on demand.
public struct AdjustmentPanel: View {
    @Binding private var adjustments: Adjustments
    @Binding private var selectedGroup: AdjustmentGroup
    @Binding private var selectedControls: [AdjustmentGroup: String]
    private let whiteBalanceAsShot: CameraWhiteBalance?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `whiteBalanceAsShot` is a RAW photo's as-shot white balance, which adds the White Balance
    /// group; nil for other photos.
    public init(
        adjustments: Binding<Adjustments>, group: Binding<AdjustmentGroup>, selection: Binding<[AdjustmentGroup: String]>,
        whiteBalanceAsShot: CameraWhiteBalance? = nil
    ) {
        _adjustments = adjustments
        _selectedGroup = group
        _selectedControls = selection
        self.whiteBalanceAsShot = whiteBalanceAsShot
    }

    private var groups: [AdjustmentGroup] { AdjustmentGroup.available(whiteBalanceAsShot: whiteBalanceAsShot) }
    /// The selected group, or Light while this photo doesn't have it (White Balance on a photo
    /// that isn't RAW, or whose as-shot white balance is still being read).
    private var group: AdjustmentGroup { groups.contains(selectedGroup) ? selectedGroup : .light }

    public var body: some View {
        // Built once per update: this body runs on every ruler step.
        let group = group
        let controls = group.controls(whiteBalanceAsShot: whiteBalanceAsShot)
        let selectedControl = controls.first { $0.id == selectedControls[group] } ?? controls[0]
        VStack(spacing: FilmLabLayout.compact) {
            header(group, selectedControl)
            AdjustmentRuler(control: selectedControl, adjustments: $adjustments)
            controlPicker(group, controls, selectedControl)
        }
        .padding(FilmLabLayout.inset)
        .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
        .sensoryFeedback(.selection, trigger: selectedControl.id)
    }

    private func header(_ group: AdjustmentGroup, _ selectedControl: AdjustmentControl) -> some View {
        HStack {
            Menu {
                Picker("Adjustments", selection: $selectedGroup) {
                    ForEach(groups) { Text($0.title).tag($0) }
                }
            } label: {
                Label(group.title, systemImage: "chevron.down")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: FilmLabLayout.minimumControlHeight)
            }
            .accessibilityLabel("Adjustment group")
            .accessibilityValue(group.title)
            Spacer()
            Button {
                adjustments[keyPath: selectedControl.keyPath] = Adjustments()[keyPath: selectedControl.keyPath]
            } label: {
                // Sized inside the label, so the whole minimum touch area is the button.
                Label("Reset Adjustment", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: FilmLabLayout.minimumControlHeight, minHeight: FilmLabLayout.minimumControlHeight)
                    .contentShape(.rect)
            }
            // What iOS draws here anyway; on macOS it keeps the larger label out of a push-button bezel.
            .buttonStyle(.borderless)
            .disabled(adjustments[keyPath: selectedControl.keyPath] == Adjustments()[keyPath: selectedControl.keyPath])
        }
    }

    /// A row that scrolls sideways; a column at accessibility sizes, so no name is cut off.
    @ViewBuilder
    private func controlPicker(_ group: AdjustmentGroup, _ controls: [AdjustmentControl], _ selectedControl: AdjustmentControl)
        -> some View
    {
        let buttons = ForEach(controls) { control in
            Button {
                selectedControls[group] = control.id
            } label: {
                Text(control.title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, FilmLabLayout.gap)
                    .frame(minHeight: FilmLabLayout.minimumControlHeight)
                    .background(control.id == selectedControl.id ? Color.primary.opacity(0.12) : Color.clear, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(control.accessibilityLabel)
            .accessibilityAddTraits(control.id == selectedControl.id ? .isSelected : [])
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: FilmLabLayout.hairline) { buttons }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: FilmLabLayout.compact) { buttons }
            }
            .scrollIndicators(.hidden)
        }
    }
}
