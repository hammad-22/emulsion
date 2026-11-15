import SwiftUI

extension GeometryProxy {
    /// Whether the system split arrangement owns the canvas; see Apps/iOS/AGENTS.md, "Expanded canvas".
    func isExpandedCanvas(horizontalSizeClass: UserInterfaceSizeClass?, verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        return !reservedRegions(kind: .division, options: .includeInactive).isEmpty
            || (horizontalSizeClass == .regular && verticalSizeClass == .regular)
    }
}
