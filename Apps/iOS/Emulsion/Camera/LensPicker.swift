import EmulsionKit
import EmulsionUI
import SwiftUI

struct LensPicker: View {
    let capabilities: CameraCapabilities
    let select: (CameraLens) -> Void

    @ScaledMetric private var buttonSize = FilmLabLayout.minimumControlHeight

    var body: some View {
        HStack(spacing: FilmLabLayout.hairline) {
            ForEach(capabilities.lenses) { option in
                lensButton(option, isSelected: option.lens == capabilities.lens)
            }
        }
        .padding(FilmLabLayout.hairline)
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
