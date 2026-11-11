import SwiftUI

extension ToolbarContent {
    @ToolbarContentBuilder
    func preferVerticalAxis() -> some ToolbarContent {
        if #available(iOS 27.1, *) {
            axisBehavior(.verticalPreferred)
        } else {
            self
        }
    }
}
