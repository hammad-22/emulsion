import EmulsionCore
import SwiftUI

/// A square thumbnail of a photo with its film look, for the library grid.
public struct PhotoThumbnail: View {
    private let url: URL
    private let adjustments: Adjustments

    public init(url: URL, adjustments: Adjustments) {
        self.url = url
        self.adjustments = adjustments
    }

    public var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { RenderedPhoto(url: url, adjustments: adjustments, contentMode: .fill) }
            .clipped()
            .contentShape(.rect)
    }
}
