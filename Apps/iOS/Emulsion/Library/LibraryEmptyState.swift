import EmulsionKit
import EmulsionUI
import SwiftUI

/// The first thing a new user sees: what Emulsion does, and two ways to start.
struct LibraryEmptyState: View {
    @Binding var error: String?

    @Environment(PhotoStore.self) private var store
    /// Scales with Dynamic Type, from the large title it sits above.
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: FilmLabLayout.space) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: symbolSize, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(spacing: FilmLabLayout.gap) {
                    Text("Make room for light")
                        .font(.largeTitle.weight(.semibold))
                    Text("Import a photo, or try a sample, to develop it as a film negative and print.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                GlassEffectContainer {
                    VStack(spacing: FilmLabLayout.gap) {
                        PhotoImportButton { error = $0.localizedDescription }
                            .buttonStyle(.glassProminent)
                        Button("Try Sample Photos", systemImage: "photo.stack", action: addSamples)
                            .buttonStyle(.glass)
                    }
                    .controlSize(.large)
                }
            }
            .padding(FilmLabLayout.generous)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
    }

    private func addSamples() {
        do {
            try store.addSamples()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
