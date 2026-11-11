import EmulsionKit
import SwiftUI

/// The back lenses on a glass capsule. The selected one is filled, bolder and reads
/// "1×", so the choice doesn't rely on color.
struct LensPicker: View {
    let capabilities: CameraCapabilities
    let axis: Axis
    let select: (CameraLens) -> Void

    @ScaledMetric private var buttonSize: CGFloat = 44
    private let spacing: CGFloat = 4

    var body: some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            ForEach(capabilities.lenses) { option in
                lensButton(option, isSelected: option.lens == capabilities.lens)
            }
        }
        .padding(spacing)
        .glassEffect(.regular, in: .capsule)
    }

    private func lensButton(_ option: LensOption, isSelected: Bool) -> some View {
        Button {
            select(option.lens)
        } label: {
            Text(option.title(isSelected: isSelected))
                .font(isSelected ? .footnote.weight(.bold) : .caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: buttonSize, height: buttonSize)
                .background(isSelected ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.clear), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Text(option.accessibilityLabel)
        }
    }
}
