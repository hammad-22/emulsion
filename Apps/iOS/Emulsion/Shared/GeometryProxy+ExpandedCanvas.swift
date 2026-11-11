import SwiftUI

extension GeometryProxy {
    /// A fold present (flat or not), or a canvas regular in both directions: the system split
    /// arrangement owns it. Regular width alone isn't enough: a large iPhone in landscape is
    /// regular-width but too short for the split. Always false before iOS 27.1, which keeps
    /// the ordinary-iPhone layout.
    func isExpandedCanvas(horizontalSizeClass: UserInterfaceSizeClass?, verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        return !reservedRegions(kind: .division, options: .includeInactive).isEmpty
            || (horizontalSizeClass == .regular && verticalSizeClass == .regular)
    }
}
