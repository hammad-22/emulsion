import SwiftUI

/// The corner mark on a thumbnail while selecting photos.
public struct SelectionBadge: View {
    private let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .tint)
            .font(.title3)
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius)
            .padding(FilmLabLayout.compact)
            .accessibilityHidden(true)
    }

    private let shadowOpacity = 0.35
    private let shadowRadius: CGFloat = 2
}
