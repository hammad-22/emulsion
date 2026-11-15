import SwiftUI

struct ShutterPressStyle: ButtonStyle {
    private static let pressedScale = 0.92
    private static let pressAnimation = Animation.snappy(duration: 0.15)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .animation(Self.pressAnimation, value: configuration.isPressed)
    }
}
