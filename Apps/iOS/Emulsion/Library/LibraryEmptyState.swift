import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

/// The first thing a new user sees: what Emulsion does, and two ways to start.
struct LibraryEmptyState: View {
    @Binding var error: String?

    @Environment(PhotoStore.self) private var store
    /// Both actions share one width, wide enough for the longer title at large text sizes.
    @ScaledMetric private var buttonWidth: CGFloat = 260

    var body: some View {
        ScrollView {
            VStack(spacing: FilmLabLayout.generous) {
                SamplePrints()
                VStack(spacing: FilmLabLayout.gap) {
                    Text("Make room for light")
                        .font(.largeTitle.weight(.semibold))
                    Text("Import a photo, or try a sample, to develop it as a film negative and print.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                GlassEffectContainer {
                    VStack(spacing: FilmLabLayout.gap) {
                        PhotoImportButton(fillsWidth: true) { error = $0.localizedDescription }
                            .buttonStyle(.glassProminent)
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
        do {
            try store.addSamples()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The bundled samples developed with the default look and fanned out like prints on a
/// table: the product shown, instead of described. Decorative, so hidden from VoiceOver.
private struct SamplePrints: View {
    /// Artistic: a 4:5 print, and how far each one leans and sits from the middle.
    private let printSize = CGSize(width: 120, height: 150)
    private let printCorner: CGFloat = 10
    private let lean = 9.0
    private let spread: CGFloat = 70
    private let drop: CGFloat = 12

    var body: some View {
        let prints = Array(PhotoStore.sampleURLs.prefix(3).enumerated())
        let middle = Double(prints.count - 1) / 2
        ZStack {
            ForEach(prints, id: \.element) { index, url in
                let position = Double(index) - middle
                RenderedPhoto(url: url, adjustments: Adjustments(), contentMode: .fill)
                    .frame(width: printSize.width, height: printSize.height)
                    .clipShape(.rect(cornerRadius: printCorner))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .rotationEffect(.degrees(position * lean))
                    .offset(x: position * spread, y: abs(position) * drop)
                    .zIndex(-abs(position))
            }
        }
        .frame(height: printSize.height + drop * 2)
        .accessibilityHidden(true)
    }
}
