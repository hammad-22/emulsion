import SwiftUI

/// The large round shutter, with a firm haptic on each press.
struct ShutterButton: View {
    let isEnabled: Bool
    let captureCount: Int
    let action: () -> Void

    /// Close to the system Camera's shutter; well above the 44 pt minimum target.
    static let diameter: CGFloat = 76
    private let ring: CGFloat = 4
    private let gap: CGFloat = 6

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(.white)
                .padding(ring + gap)
                .overlay { Circle().strokeBorder(.white, lineWidth: ring) }
                .frame(width: Self.diameter, height: Self.diameter)
        }
        .buttonStyle(ShutterPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel("Take Photo")
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: captureCount)
    }
}

/// The inner disc shrinks slightly while pressed, like the system shutter.
private struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
