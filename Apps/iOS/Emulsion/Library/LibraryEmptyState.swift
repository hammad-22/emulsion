import EmulsionKit
import EmulsionUI
import SwiftUI

struct LibraryEmptyState: View {
    @Binding var error: String?

    @Environment(PhotoStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric private var buttonWidth: CGFloat = 260

    var body: some View {
        ScrollView {
            VStack(spacing: FilmLabLayout.generous) {
                // Decorative prints give way at accessibility sizes, keeping the actions on screen (MOV-140).
                if !dynamicTypeSize.isAccessibilitySize { SamplePrints() }
                VStack(spacing: FilmLabLayout.gap) {
                    Text("Make room for light")
                        .font(.largeTitle.weight(.semibold))
                    Text("Import a photo, or try a sample, to develop it as a film negative and print.")
                }
                .multilineTextAlignment(.center)
                GlassEffectContainer {
                    VStack(spacing: FilmLabLayout.gap) {
                        PhotoImportButton(fillsWidth: true) { error = $0.localizedDescription }
                            .buttonStyle(.glassProminent)
                            // Neutral and inverting with the appearance: see Apps/iOS/AGENTS.md (MOV-59).
                            .tint(.primary)
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                        Button(action: addSamples) {
                            Label("Try Sample Photos", systemImage: "photo.stack")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    .labelStyle(.titleAndIcon)
                    .controlSize(.large)
                    .frame(maxWidth: buttonWidth)
                }
            }
            .padding(FilmLabLayout.generous)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
    }

    private func addSamples() {
        Task {
            do {
                try await store.addSamples()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
