import SwiftUI

struct ShutterButton: View {
    let isEnabled: Bool
    let captureCount: Int
    let action: () -> Void

    /// Close to the system Camera's shutter; well above the 44 pt minimum target.
    static let diameter: CGFloat = 76
    private let ring: CGFloat = 4
    private let gap: CGFloat = 6
    private let disabledOpacity = 0.5

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
        .opacity(isEnabled ? 1 : disabledOpacity)
        .accessibilityLabel("Take Photo")
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: captureCount)
    }
}
