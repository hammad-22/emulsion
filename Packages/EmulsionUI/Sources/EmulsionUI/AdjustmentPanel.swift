import EmulsionCore
import EmulsionKit
import SwiftUI

/// Floating group controls and sliders, with one shared Liquid Glass container.
public struct AdjustmentPanel: View {
    @Binding var adjustments: Adjustments
    @State private var group = AdjustmentGroup.light
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // A restrained tint distinguishes the selected group without coloring the photo.
    private let selectedTintOpacity = 0.16

    public init(adjustments: Binding<Adjustments>) {
        _adjustments = adjustments
    }

    public var body: some View {
        GlassEffectContainer(spacing: FilmLabLayout.gap) {
            VStack(spacing: FilmLabLayout.space) {
                groupLayout {
                    ForEach(AdjustmentGroup.allCases) { item in
                        Button {
                            group = item
                        } label: {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .padding(.vertical, FilmLabLayout.gap)
                                .padding(.horizontal, FilmLabLayout.compact)
                                .frame(maxWidth: .infinity, minHeight: FilmLabLayout.minimumControlHeight)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            .regular.tint(item == group ? Color.accentColor.opacity(selectedTintOpacity) : .clear).interactive()
                        )
                        .accessibilityAddTraits(item == group ? .isSelected : [])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Adjustments")
                VStack(spacing: FilmLabLayout.inset) {
                    ForEach(group.controls) { AdjustmentSlider($0, adjustments: $adjustments) }
                }
                .padding(FilmLabLayout.space)
                .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
            }
        }
        .sensoryFeedback(.selection, trigger: group)
    }

    private var groupLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: FilmLabLayout.gap))
            : AnyLayout(HStackLayout(spacing: FilmLabLayout.gap))
    }
}
