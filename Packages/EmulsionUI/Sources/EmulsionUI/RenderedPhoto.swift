import EmulsionCore
import EmulsionKit
import SwiftUI

/// A photo developed and printed with its adjustments, or the untouched original for
/// before/after, rendered off the main actor at the size it's shown. Re-renders when the
/// edit or the size changes; the last image stays up meanwhile, so slider drags don't flash.
public struct RenderedPhoto: View {
    private let url: URL
    private let adjustments: Adjustments
    private let contentMode: ContentMode
    private let showsOriginal: Bool

    @Environment(\.renderService) private var renderService
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var failed = false

    public init(url: URL, adjustments: Adjustments, contentMode: ContentMode = .fit, showsOriginal: Bool = false) {
        self.url = url
        self.adjustments = adjustments
        self.contentMode = contentMode
        self.showsOriginal = showsOriginal
    }

    public var body: some View {
        GeometryReader { proxy in
            let request = Request(url: url, adjustments: adjustments, showsOriginal: showsOriginal, pixels: pixels(for: proxy.size))
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .task(id: request) { await render(request) }
        }
        .clipped()
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if failed {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("This photo couldn't be rendered")
        } else {
            ProgressView()
        }
    }

    /// Longest side of the frame in pixels, so the preview is sharp but no larger than shown.
    private func pixels(for size: CGSize) -> CGFloat {
        max(size.width, size.height) * displayScale
    }

    private func render(_ request: Request) async {
        guard request.pixels > 0 else { return }
        do {
            let rendered =
                request.showsOriginal
                ? try await renderService.original(request.url, maxDimension: request.pixels)
                : try await renderService.image(request.url, request.adjustments, maxDimension: request.pixels)
            // A newer request replaced this one while it rendered; its result is stale.
            guard !Task.isCancelled else { return }
            image = rendered
            failed = false
        } catch is CancellationError {
        } catch {
            failed = image == nil
        }
    }

    private struct Request: Equatable {
        let url: URL
        let adjustments: Adjustments
        let showsOriginal: Bool
        let pixels: CGFloat
    }
}
