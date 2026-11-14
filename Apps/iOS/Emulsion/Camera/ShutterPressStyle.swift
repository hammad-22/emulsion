import SwiftUI

/// The inner disc shrinks slightly while pressed, like the system shutter.
struct ShutterPressStyle: ButtonStyle {
    private let pressedScale = 0.92
    private let animation = Animation.snappy(duration: 0.15)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(animation, value: configuration.isPressed)
    }
}
