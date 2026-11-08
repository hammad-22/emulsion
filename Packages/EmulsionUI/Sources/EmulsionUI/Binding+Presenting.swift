import SwiftUI

extension Binding where Value == Bool {
    /// True while `value` holds something; setting false clears it. For alerts and sheets
    /// driven by an optional message or item.
    public init<Wrapped: Sendable>(isPresenting value: Binding<Wrapped?>) {
        self.init(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
