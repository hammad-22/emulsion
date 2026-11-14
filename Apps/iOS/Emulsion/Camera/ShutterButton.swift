import SwiftUI

struct ShutterButton: View {
    let isEnabled: Bool
    let captureCount: Int
    let action: () -> Void

    /// Artistic: near the system Camera's shutter, well above the 44 pt minimum target.
    static let diameter: CGFloat = 76
    private static let ring: CGFloat = 4
    private static let gap: CGFloat = 6

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(.white)
                .padding(Self.ring + Self.gap)
                .overlay { Circle().strokeBorder(.white, lineWidth: Self.ring) }
                .frame(width: Self.diameter, height: Self.diameter)
        }
        .buttonStyle(ShutterPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel("Take Photo")
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: captureCount)
    }
}
