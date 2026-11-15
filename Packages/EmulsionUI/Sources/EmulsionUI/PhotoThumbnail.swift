import EmulsionCore
import SwiftUI

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
