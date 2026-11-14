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

    /// True on a folded iPhone Duo: one screen is off. There the contrast audit reads the dark
    /// screen (MOV-140: it reported ~20:1 text as failing, or threw "Invalid target app"),
    /// so a contrast check can't be trusted.
    @MainActor
    static var hasDarkScreen: Bool {
        XCUIScreen.screens.count > 1 && XCUIScreen.screens.contains { $0.screenshot().isBlank }
    }
}

extension XCUIScreenshot {
    /// Every pixel black, judged on an 8×8 reduction.
    fileprivate var isBlank: Bool {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let image = image.cgImage,
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels.enumerated().allSatisfy { index, value in index % 4 == 3 || value == 0 }
    }
}
