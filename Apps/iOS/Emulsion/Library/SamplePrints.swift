import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

/// The bundled samples fanned out like prints on a table; decorative, so hidden from VoiceOver.
struct SamplePrints: View {
    /// Artistic: a 4:5 print, and how far each one leans and sits from the middle.
    private let printSize = CGSize(width: 120, height: 150)
    private let printCorner: CGFloat = 10
    private let lean = 9.0
    private let spread: CGFloat = 70
    private let drop: CGFloat = 12
    private let count = 3
    private let shadowOpacity = 0.25
    private let shadowRadius: CGFloat = 12
    private let shadowOffset: CGFloat = 6

    var body: some View {
        let prints = Array(PhotoStore.sampleURLs.prefix(count).enumerated())
        let middle = Double(prints.count - 1) / 2
        ZStack {
            ForEach(prints, id: \.element) { index, url in
                let position = Double(index) - middle
                RenderedPhoto(url: url, adjustments: Adjustments(), contentMode: .fill)
                    .frame(width: printSize.width, height: printSize.height)
                    .clipShape(.rect(cornerRadius: printCorner))
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowOffset)
                    .rotationEffect(.degrees(position * lean))
                    .offset(x: position * spread, y: abs(position) * drop)
                    .zIndex(-abs(position))
            }
        }
        .frame(height: printSize.height + drop * 2)
        .accessibilityHidden(true)
    }
}
