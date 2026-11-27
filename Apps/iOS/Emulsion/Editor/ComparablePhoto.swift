import EmulsionCore
import EmulsionUI
import SwiftUI

struct ComparablePhoto: View {
    let url: URL
    let adjustments: Adjustments
    let isComparing: Bool
    @Binding var isHolding: Bool

    @GestureState private var isPressed = false
    /// Long enough that taps and slider reaches don't flash the original.
    private static let holdDuration = 0.2

    private var showsOriginal: Bool { isComparing || isPressed }

    var body: some View {
        RenderedPhoto(url: url, adjustments: adjustments, showsOriginal: showsOriginal)
            .accessibilityLabel(showsOriginal ? "Original photo" : "Edited photo")
            .accessibilityAddTraits(.isImage)
            .gesture(hold)
            .onChange(of: isPressed) { _, isPressed in isHolding = isPressed }
            .sensoryFeedback(.impact(weight: .light), trigger: isPressed) { _, isPressed in isPressed }
    }

    private var hold: some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isPressed) { value, isPressed, _ in
                if case .second(true, _) = value { isPressed = true }
            }
    }
}
