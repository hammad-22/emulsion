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

    /// The library's photos, matched by the label `PhotoGrid` gives each one.
    var photos: XCUIElementQuery { buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")) }

    /// Launches on the library instead of the camera (debug builds).
    @MainActor
    static func launchLibrary(_ presentation: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--library"] + presentation
        app.launch()
        return app
    }

    /// Launches on an empty library, scrolled so "Try Sample Photos" can be tapped, or skips
    /// the test when the library already has photos.
    @MainActor
    static func launchEmptyLibrary(_ presentation: [String] = []) throws -> XCUIApplication {
        let app = launchLibrary(presentation)
        let samples = app.buttons["Try Sample Photos"]
        guard samples.waitForExistence(timeout: 5) else {
            throw XCTSkip("Needs an empty library; uninstall the isolated proof app first.")
        }
        for _ in 0..<3 where !samples.isHittable { app.swipeUp() }
        return app
    }

    /// Launches on the library with the sample photos added.
    @MainActor
    static func launchSampleLibrary(_ presentation: [String] = []) throws -> XCUIApplication {
        let app = try launchEmptyLibrary(presentation)
        app.buttons["Try Sample Photos"].tap()
        XCTAssertTrue(app.photos.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// Deletes every photo, leaving the empty library for the next test.
    @MainActor
    func removeSamples() {
        if navigationBars["Looks"].exists { buttons["Done"].tap() }
        if !navigationBars["Library"].exists { buttons["BackButton"].tap() }
        guard buttons["Select"].waitForExistence(timeout: 5) else { return }
        buttons["Select"].tap()
        let count = photos.count
        for index in 0..<count { photos.element(boundBy: index).tap() }
        buttons["Delete"].tap()
        buttons[count == 1 ? "Delete 1 Photo" : "Delete \(count) Photos"].tap()
        XCTAssertTrue(buttons["Try Sample Photos"].waitForExistence(timeout: 5))
    }

    /// A native accessibility audit (the engine behind Accessibility Inspector) whose failures
    /// name the element, so a finding can be traced without opening the result bundle.
    ///
    /// On a folded iPhone Duo the contrast audit reads the switched-off inner screen: it failed
    /// text measured at about 20:1, or threw "Invalid target app" (MOV-140). Unfolded, with the
    /// outer screen off, it works. Contrast is left out when folded, and a contrast-only audit
    /// skips the test.
    @MainActor
    func audit(_ types: XCUIAccessibilityAuditType, file: StaticString = #filePath, line: UInt = #line) throws {
        var types = types
        if types.contains(.contrast), Self.isFoldedDuo {
            types.remove(.contrast)
            if types.isEmpty { throw XCTSkip("The contrast audit can't read a folded iPhone Duo.") }
        }
        try performAccessibilityAudit(for: types) { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) \"\($0.label)\" \($0.identifier)" } ?? "no element"
            XCTFail("\(issue.compactDescription): \(element)", file: file, line: line)
            return true
        }
    }

    /// The outer screen comes first; folded, the inner one is off.
    @MainActor
    private static var isFoldedDuo: Bool {
        XCUIScreen.screens.dropFirst().contains { $0.screenshot().isBlank }
    }
}

extension XCUIScreenshot {
    /// Every pixel black, judged on an 8×8 reduction.
    var isBlank: Bool {
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
