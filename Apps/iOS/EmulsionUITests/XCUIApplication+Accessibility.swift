import XCTest

extension XCUIApplication {
    /// Launch arguments for the system text size and layout direction, so a test sees the app
    /// as a user with those settings would without changing the simulator's settings.
    enum Presentation {
        /// The largest accessibility text size (Settings › Accessibility › Larger Text, AX5).
        static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        /// Xcode's right-to-left pseudolanguage: English text laid out right to left.
        static let rightToLeft = ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
    }

    /// Launches on the library instead of the camera (debug builds).
    @MainActor
    static func launchLibrary(_ presentation: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--library"] + presentation
        app.launch()
        return app
    }

    /// A native accessibility audit (the engine behind Accessibility Inspector) whose failures
    /// name the element, so a finding can be traced without opening the result bundle.
    @MainActor
    func audit(_ types: XCUIAccessibilityAuditType, file: StaticString = #filePath, line: UInt = #line) throws {
        try performAccessibilityAudit(for: types) { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) \"\($0.label)\" \($0.identifier)" } ?? "no element"
            XCTFail("\(issue.compactDescription): \(element)", file: file, line: line)
            return true
        }
    }
}
