import EmulsionKit
import SwiftUI

extension EnvironmentValues {
    /// The render service views draw with: the shared one unless a preview swaps it.
    @Entry public var renderService: RenderService = .shared
}
