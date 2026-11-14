#if DEBUG
    import EmulsionCore
    import EmulsionKit
    import SwiftUI

    /// The shared controls on one screen, for accessibility proof (`--component-gallery` on iOS).
    public struct ComponentGallery: View {
        @State private var adjustments = Adjustments()
        @State private var isComparing = false
        @State private var group = AdjustmentGroup.light
        @State private var selection: [AdjustmentGroup: String] = [:]
        /// A stand-in as-shot white balance, so the gallery shows a RAW photo's White Balance group.
        private let whiteBalanceAsShot = CameraWhiteBalance(temperature: 5200, tint: 8)
        /// Room for a few rulers, so the inspector's own scrolling shows inside the gallery.
        private let inspectorHeight: CGFloat = 480

        public init() {}

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: FilmLabLayout.space) {
                        GlassEffectContainer {
                            HStack(spacing: FilmLabLayout.gap) {
                                Toggle("Compare", systemImage: "square.split.2x1", isOn: $isComparing)
                                    .toggleStyle(.button)
                                Button("Reset Edits", systemImage: "arrow.counterclockwise") { adjustments = Adjustments() }
                            }
                            .buttonStyle(.glass)
                        }
                        HStack {
                            SelectionBadge(isSelected: false)
                            SelectionBadge(isSelected: true)
                        }
                        .background(.gray, in: .rect)
                        AdjustmentPanel(
                            adjustments: $adjustments, group: $group, selection: $selection, whiteBalanceAsShot: whiteBalanceAsShot)
                        AdjustmentInspector(
                            adjustments: $adjustments, group: $group, selection: $selection, whiteBalanceAsShot: whiteBalanceAsShot
                        )
                        .frame(height: inspectorHeight)
                    }
                    .padding(FilmLabLayout.inset)
                }
                .navigationTitle("Components")
            }
        }
    }

    #Preview("Controls") {
        ComponentGallery()
    }
#endif
