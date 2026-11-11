#if DEBUG
    import EmulsionCore
    import EmulsionKit
    import SwiftUI

    /// The shared controls on one screen, for checking them in light and dark, at large text
    /// sizes and with Reduce Transparency. The iOS debug build opens it with `--component-gallery`.
    public struct ComponentGallery: View {
        @State private var adjustments = Adjustments()
        @State private var isComparing = false
        @State private var group = AdjustmentGroup.light
        @State private var selection: [AdjustmentGroup: String] = [:]
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
                        AdjustmentPanel(adjustments: $adjustments, group: $group, selection: $selection)
                        AdjustmentInspector(adjustments: $adjustments, group: $group, selection: $selection)
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
