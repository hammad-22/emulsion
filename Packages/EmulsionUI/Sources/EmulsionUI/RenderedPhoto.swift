import EmulsionCore
import EmulsionKit
import SwiftUI

/// A photo developed and printed with its adjustments, or the untouched original for
/// before/after, rendered off the main actor at the size it's shown.
/// Until the first render, it shows the caller's `placeholder` (an earlier frame of the same
/// variant), then a cached thumbnail; failing those, a filled frame (a thumbnail) waits as a
/// quiet placeholder and a fitted one shows progress.
/// Re-renders when the edit or size changes, keeping the last image so slider drags don't flash
/// and showing each render that finishes during a drag (`RenderOrder`).
public struct RenderedPhoto: View {
    private let url: URL
    private let adjustments: Adjustments
    private let contentMode: ContentMode
    private let showsOriginal: Bool
    private let placeholder: CGImage?
    private let onRender: ((CGImage) -> Void)?

    @Environment(\.renderService) private var renderService
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var failed = false
    @State private var order = RenderOrder()

    /// `onRender` receives each render as it is shown, so a caller can pass it back as
    /// `placeholder` when this view is rebuilt in another layout.
    public init(
        url: URL, adjustments: Adjustments, contentMode: ContentMode = .fit, showsOriginal: Bool = false,
        placeholder: CGImage? = nil, onRender: ((CGImage) -> Void)? = nil
    ) {
        self.url = url
        self.adjustments = adjustments
        self.contentMode = contentMode
        self.showsOriginal = showsOriginal
        self.placeholder = placeholder
        self.onRender = onRender
    }

    public var body: some View {
        GeometryReader { proxy in
            let request = Request(url: url, adjustments: adjustments, showsOriginal: showsOriginal, pixels: pixels(for: proxy.size))
            content(request)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .task(id: request) { await render(request) }
        }
        .clipped()
    }

    /// The last render, or until there is one, the caller's placeholder or the cached thumbnail
    /// for this exact request: a photo scrolled back into the library grid appears without a
    /// placeholder frame.
    @ViewBuilder private func content(_ request: Request) -> some View {
        if let image = image ?? placeholder ?? cachedThumbnail(request) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if failed {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("This photo couldn't be rendered")
        } else if contentMode == .fill {
            Rectangle().fill(.quaternary)
        } else {
            ProgressView()
        }
    }

    private func cachedThumbnail(_ request: Request) -> CGImage? {
        request.showsOriginal ? nil : renderService.cachedThumbnail(request.url, request.adjustments, maxDimension: request.pixels)
    }

    /// Longest side of the frame in pixels, so the preview is sharp but no larger than shown.
    private func pixels(for size: CGSize) -> CGFloat {
        max(size.width, size.height) * displayScale
    }

    private func render(_ request: Request) async {
        guard request.pixels > 0 else { return }
        let ticket = order.begin()
        do {
            let rendered =
                request.showsOriginal
                ? try await renderService.original(request.url, maxDimension: request.pixels)
                : try await renderService.image(request.url, request.adjustments, maxDimension: request.pixels)
            guard order.shouldShow(ticket) else { return }
            image = rendered
            failed = false
            onRender?(rendered)
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
