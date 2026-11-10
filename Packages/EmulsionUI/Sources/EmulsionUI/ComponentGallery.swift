#if DEBUG
    import EmulsionCore
    import SwiftUI

    /// The shared controls on one screen, for checking them in light and dark, at large text
    /// sizes and with Reduce Transparency. The iOS debug build opens it with `--component-gallery`.
    public struct ComponentGallery: View {
        @State private var adjustments = Adjustments()
        @State private var isComparing = false

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
                        AdjustmentPanel(adjustments: $adjustments)
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
