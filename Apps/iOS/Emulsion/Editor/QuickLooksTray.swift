import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct QuickLooksTray: View {
    let session: EditSession
    let isVertical: Bool
    @Environment(RecipeStore.self) private var store
    @ScaledMetric private var preferredSwatchWidth = 92.0
    @State private var frames: [Int: CGRect] = [:]
    @GestureState private var finger: CGPoint?
    @GestureState private var browseTranslation: CGFloat?
    @State private var browseStart: CGFloat?
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollMetrics = ScrollMetrics()

    private static let coordinateSpace = "quick-looks-swatches"
    private static let holdDuration: TimeInterval = 0.22
    private static let edgeWidth: CGFloat = 24
    private static let edgeStep: CGFloat = 14
    private static let edgeInterval = Duration.milliseconds(45)

    private var recipes: [Recipe] { CuratedLooks.recipes + store.recipes }
    private var swatchWidth: CGFloat { min(preferredSwatchWidth, 128) }
    private var verticalTrayWidth: CGFloat { swatchWidth + FilmLabLayout.compact }

    var body: some View {
        swatches
            .coordinateSpace(name: Self.coordinateSpace)
            .highPriorityGesture(scrubGesture.exclusively(before: browseGesture))
            .simultaneousGesture(swatchTap)
            .onChange(of: finger) { _, point in
                if let point { select(at: point) }
            }
            .onChange(of: browseTranslation) { _, translation in
                browse(translation)
            }
            .onPreferenceChange(SwatchFrames.self) { updated in
                frames = updated
                if let finger { select(at: finger) }
            }
            .frame(width: isVertical ? verticalTrayWidth : nil)
            .padding(FilmLabLayout.compact)
            .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
    }

    private var swatches: some View {
        ScrollView(isVertical ? .vertical : .horizontal) {
            if isVertical {
                LazyVStack(spacing: FilmLabLayout.compact) { options }
            } else {
                LazyHStack(alignment: .top, spacing: FilmLabLayout.compact) { options }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: !isVertical)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollMetrics.self, of: metrics) { _, value in scrollMetrics = value }
        .task(id: finger != nil) { await scrollAtEdge() }
    }

    private var scrubGesture: some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace)))
            .updating($finger) { value, location, _ in
                if case .second(true, let drag?) = value { location = drag.location }
            }
    }

    private var swatchTap: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpace))
            .onEnded { select(at: $0.location) }
    }

    private var browseGesture: some Gesture {
        DragGesture()
            .updating($browseTranslation) { value, translation, _ in
                translation = isVertical ? value.translation.height : value.translation.width
            }
    }

    private func browse(_ translation: CGFloat?) {
        guard let translation else {
            browseStart = nil
            return
        }
        let start = browseStart ?? scrollMetrics.offset
        browseStart = start
        scroll(to: start - translation)
    }

    private func select(at point: CGPoint) {
        guard CGRect(origin: .zero, size: scrollMetrics.viewport).contains(point),
            let index = frames.first(where: { $0.value.contains(point) })?.key,
            recipes.indices.contains(index)
        else { return }
        select(recipes[index])
    }

    private func select(_ recipe: Recipe) {
        guard !recipe.matches(session.adjustments) else { return }
        session.apply(recipe)
    }

    private func metrics(_ geometry: ScrollGeometry) -> ScrollMetrics {
        ScrollMetrics(
            viewport: geometry.containerSize,
            offset: isVertical ? geometry.contentOffset.y : geometry.contentOffset.x,
            length: isVertical ? geometry.contentSize.height : geometry.contentSize.width)
    }

    private func scroll(to requestedOffset: CGFloat) {
        let viewport = scrollMetrics.viewport
        let extent = isVertical ? viewport.height : viewport.width
        let offset = min(max(0, scrollMetrics.length - extent), max(0, requestedOffset))
        guard offset != scrollMetrics.offset else { return }
        if isVertical { scrollPosition.scrollTo(y: offset) } else { scrollPosition.scrollTo(x: offset) }
    }

    private func scrollAtEdge() async {
        while let finger, !Task.isCancelled {
            let size = scrollMetrics.viewport
            if CGRect(origin: .zero, size: size).contains(finger) {
                let coordinate = isVertical ? finger.y : finger.x
                let extent = isVertical ? size.height : size.width
                let step: CGFloat =
                    coordinate < Self.edgeWidth ? -Self.edgeStep : (coordinate > extent - Self.edgeWidth ? Self.edgeStep : 0)
                if step != 0 { scroll(to: scrollMetrics.offset + step) }
            }
            do { try await Task.sleep(for: Self.edgeInterval) } catch { return }
        }
    }

    @ViewBuilder private var options: some View {
        ForEach(Array(recipes.enumerated()), id: \.offset) { index, recipe in
            let isSelected = recipe.matches(session.adjustments)
            Button {
                select(recipe)
            } label: {
                VStack(spacing: FilmLabLayout.hairline) {
                    LookSwatch(url: session.url, adjustments: recipe.applying(to: session.adjustments))
                        .frame(width: swatchWidth, height: swatchWidth)
                        .clipShape(.rect(cornerRadius: FilmLabLayout.gap))
                        .overlay(alignment: .bottomTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.8))
                                    .padding(FilmLabLayout.hairline)
                            }
                        }
                    Text(recipe.name)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: swatchWidth)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recipe.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SwatchFrames.self, value: [index: geometry.frame(in: .named(Self.coordinateSpace))])
                }
            }
        }
    }
}

private struct ScrollMetrics: Equatable {
    var viewport: CGSize = .zero
    var offset: CGFloat = 0
    var length: CGFloat = 0
}

private enum SwatchFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
