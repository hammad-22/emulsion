import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct LookSwatch: View {
    let url: URL
    let adjustments: Adjustments

    @Environment(\.renderService) private var renderService
    @State private var image: CGImage?

    // Below the retained editor-render size; these reuse the library's thumbnail cache.
    private let maxPixels: CGFloat = 320

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: adjustments, priority: .utility) {
                image = renderService.cachedThumbnail(url, adjustments, maxDimension: maxPixels)
                if image == nil {
                    let rendered = try? await renderService.image(url, adjustments, maxDimension: maxPixels)
                    if !Task.isCancelled { image = rendered }
                }
            }
    }
}
