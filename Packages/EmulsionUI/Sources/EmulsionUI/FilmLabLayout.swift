import SwiftUI

/// Shared spacing and corner radii. Artistic values chosen for this interface.
public enum FilmLabLayout {
    /// Between library thumbnails: tight, so the grid reads as one sheet of photographs.
    public static let gridSpacing: CGFloat = 2
    public static let hairline: CGFloat = 4
    public static let compact: CGFloat = 8
    public static let gap: CGFloat = 12
    public static let inset: CGFloat = 16
    public static let space: CGFloat = 24
    public static let generous: CGFloat = 32
    public static let panelCorner: CGFloat = 28
    /// Apple's default iPhone control height (HIG Accessibility).
    public static let minimumControlHeight: CGFloat = 44
}
