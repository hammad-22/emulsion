import SwiftUI

/// The corner mark on a thumbnail while selecting photos: a ring, filled with a checkmark
/// once selected. Plain symbols rather than glass, which belongs to controls, not content.
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

    /// Enough to keep the white ring visible on a bright photo.
    private let shadowOpacity = 0.35
    private let shadowRadius: CGFloat = 2
}
