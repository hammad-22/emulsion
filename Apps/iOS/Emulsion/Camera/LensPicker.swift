import EmulsionKit
import EmulsionUI
import SwiftUI

/// The back lenses on a glass capsule. The selected one is filled, bolder and reads
/// "1×", so the choice doesn't rely on color.
struct LensPicker: View {
    let capabilities: CameraCapabilities
    let select: (CameraLens) -> Void

    @ScaledMetric private var buttonSize = FilmLabLayout.minimumControlHeight
    private let spacing = FilmLabLayout.hairline

    var body: some View {
        HStack(spacing: spacing) {
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
                .background(.white.opacity(isSelected ? FilmLabLayout.selectedFill : 0), in: .circle)
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
