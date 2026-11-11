import EmulsionCore
import EmulsionUI
import SwiftUI

/// The photo being edited, with nothing drawn over it. Touch and hold to see the original;
/// `isHolding` tells the editor, which names what's on screen in its title.
struct ComparablePhoto: View {
    let url: URL
    let adjustments: Adjustments
    let isComparing: Bool
    @Binding var isHolding: Bool

    @GestureState private var isPressed = false
    /// Long enough that taps and slider reaches don't flash the original.
    private let holdDuration = 0.2

    private var showsOriginal: Bool { isComparing || isPressed }

    var body: some View {
        RenderedPhoto(url: url, adjustments: adjustments, showsOriginal: showsOriginal)
            .accessibilityLabel(showsOriginal ? "Original photo" : "Edited photo")
            .accessibilityAddTraits(.isImage)
            .gesture(hold)
            .onChange(of: isPressed) { _, isPressed in isHolding = isPressed }
            .sensoryFeedback(.impact(weight: .light), trigger: isPressed) { _, isPressed in isPressed }
    }

    /// True from the moment the hold is recognized until the finger lifts.
    private var hold: some Gesture {
        LongPressGesture(minimumDuration: holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isPressed) { value, isPressed, _ in
                if case .second(true, _) = value { isPressed = true }
            }
    }
}
