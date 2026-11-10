import EmulsionCore
import EmulsionUI
import SwiftUI

/// The photo being edited. Touch and hold it, or turn on Compare, to see the original.
struct ComparablePhoto: View {
    let url: URL
    let adjustments: Adjustments
    let isComparing: Bool

    @GestureState private var isHolding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Long enough that taps and slider reaches don't flash the original.
    private let holdDuration = 0.2

    private var showsOriginal: Bool { isComparing || isHolding }

    var body: some View {
        RenderedPhoto(url: url, adjustments: adjustments, showsOriginal: showsOriginal)
            .accessibilityLabel(showsOriginal ? "Original photo" : "Edited photo")
            .accessibilityAddTraits(.isImage)
            .gesture(hold)
            .sensoryFeedback(.impact(weight: .light), trigger: isHolding) { _, isHolding in isHolding }
            .overlay(alignment: .topLeading) {
                if showsOriginal {
                    Text("Original")
                        .font(.caption.bold())
                        .padding(.horizontal, FilmLabLayout.gap)
                        .padding(.vertical, FilmLabLayout.compact)
                        .glassEffect()
                        .padding(FilmLabLayout.compact)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: badgeFade), value: showsOriginal)
    }

    /// Quick enough to keep up with a press; a fade, so it's also fine with Reduce Motion.
    private let badgeFade = 0.15

    /// True from the moment the hold is recognized until the finger lifts.
    private var hold: some Gesture {
        LongPressGesture(minimumDuration: holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isHolding) { value, isHolding, _ in
                if case .second(true, _) = value { isHolding = true }
            }
    }
}
