import XCTest

extension XCUIApplication {
    enum Presentation {
        /// AX5, the largest accessibility text size.
        static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        /// Xcode's right-to-left pseudolanguage: English text laid out right to left.
        static let rightToLeft = ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
    }

    var photos: XCUIElementQuery { buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")) }

    @MainActor
    static func launchLibrary(_ presentation: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = LaunchArgument.libraryArguments + presentation
        app.launch()
        return app
    }

    @MainActor
    static func launchEmptyLibrary(_ presentation: [String] = []) throws -> XCUIApplication {
        let app = launchLibrary(presentation)
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5), "--library opens the library")
        let samples = app.buttons["Try Sample Photos"]
        guard samples.waitForExistence(timeout: 5) else {
            // Skip only for a library that already has photos; a missing action is a failure.
            XCTAssertTrue(app.photos.firstMatch.exists, "An empty library offers Try Sample Photos")
            throw XCTSkip("Needs an empty library; uninstall the isolated proof app first.")
        }
        for _ in 0..<3 where !samples.isHittable { app.swipeUp() }
        return app
    }

    @MainActor
    static func launchSampleLibrary(_ presentation: [String] = []) throws -> XCUIApplication {
        let app = try launchEmptyLibrary(presentation)
        app.buttons["Try Sample Photos"].tap()
        XCTAssertTrue(app.photos.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func openFirstPhoto() {
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10))
        photos.firstMatch.tap()
        let editPhoto = buttons["Edit Photo"]
        if editPhoto.waitForExistence(timeout: 2) { editPhoto.tap() }
        XCTAssertTrue(buttons["Looks"].waitForExistence(timeout: 5))
    }

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

    /// Skips contrast on a folded iPhone Duo, where that audit is unreliable (MOV-140).
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
