import SwiftUI

extension GeometryProxy {
    /// Regular width, or a fold present (flat or not): the system split arrangement owns the
    /// canvas. Always false before iOS 27.1, which keeps the ordinary-iPhone layout.
    func isExpandedCanvas(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        return horizontalSizeClass == .regular
            || !reservedRegions(kind: .division, options: .includeInactive).isEmpty
    }
}
