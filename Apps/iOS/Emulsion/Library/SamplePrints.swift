import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct SamplePrints: View {
    var body: some View {
        let prints = Array(PhotoStore.sampleURLs.prefix(Layout.count).enumerated())
        let middle = Double(prints.count - 1) / 2
        ZStack {
            ForEach(prints, id: \.element) { index, url in
                let position = Double(index) - middle
                RenderedPhoto(url: url, adjustments: Adjustments(), contentMode: .fill)
                    .frame(width: Layout.printSize.width, height: Layout.printSize.height)
                    .clipShape(.rect(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .rotationEffect(.degrees(position * Layout.lean))
                    .offset(x: position * Layout.spread, y: abs(position) * Layout.drop)
                    .zIndex(-abs(position))
            }
        }
        .frame(height: Layout.printSize.height + Layout.drop * 2)
        .accessibilityHidden(true)
    }

    // Artistic: a 4:5 print, and how far each one leans and sits from the middle.
    private enum Layout {
        static let printSize = CGSize(width: 120, height: 150)
        static let count = 3
        static let lean = 9.0
        static let spread: CGFloat = 70
        static let drop: CGFloat = 12
    }
}
