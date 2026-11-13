import XCTest

/// Accessibility checks across camera → library → editor → Looks at the largest text size and
/// right to left (MOV-140). Native audits use the same engine as Accessibility Inspector; they
/// don't replace a human VoiceOver walkthrough. Run on a fresh install of an isolated bundle ID.
final class AccessibilityUITests: XCTestCase {
    private let photoQuery = NSPredicate(format: "label BEGINSWITH 'Photo from'")

    /// "Try Sample Photos" must stay whole and reachable at the largest accessibility size.
    @MainActor
    func testEmptyLibraryActionsAtLargestText() throws {
        let app = XCUIApplication.launchLibrary(XCUIApplication.Presentation.largestText)
        let samples = app.buttons["Try Sample Photos"]
        guard samples.waitForExistence(timeout: 5) else {
            throw XCTSkip("Needs an empty library; uninstall the isolated proof app first.")
        }
        for _ in 0..<3 where !samples.isHittable { app.swipeUp() }
        XCTAssertTrue(samples.isHittable)
        XCTAssertTrue(app.buttons["Import"].isHittable)
        try keepProof(app, named: "Empty library AX5")
        try app.audit([.textClipped, .sufficientElementDescription, .trait])
    }

    @MainActor
    func testCameraLabelsTraitsAndHitRegions() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.Presentation.largestText
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["viewfinder"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 5))
        try keepProof(app, named: "Camera AX5")
        // The recipe strip scrolls sideways, which the audit reads as clipped text, so text
        // clipping is checked while the strip is hidden. Unfolded, it is always shown.
        let recipe = app.buttons["Recipe"]
        guard recipe.exists else {
            XCTAssertTrue(app.buttons["Everyday"].exists)
            return try app.audit([.sufficientElementDescription, .trait, .hitRegion])
        }
        try app.audit([.sufficientElementDescription, .trait, .hitRegion, .textClipped])
        recipe.tap()
        XCTAssertTrue(app.buttons["Everyday"].waitForExistence(timeout: 2))
        try keepProof(app, named: "Camera recipes AX5")
        try app.audit([.sufficientElementDescription, .trait, .hitRegion])
        recipe.tap()
    }

    /// Camera → library → editor → Looks at the default text size, keeping a screenshot and
    /// the spoken elements of each screen. Run with Reduce Transparency or Reduce Motion set
    /// on the simulator for those proofs.
    @MainActor
    func testWalkthroughKeepsSpokenElements() throws {
        let camera = XCUIApplication()
        camera.launch()
        XCTAssertTrue(camera.buttons["Take Photo"].waitForExistence(timeout: 10))
        sleep(1)
        try keepProof(camera, named: "Walkthrough 1 camera")
        camera.terminate()

        let app = try launchSamples([])
        defer { removeSamples(app) }
        sleep(2)
        try keepProof(app, named: "Walkthrough 2 library")
        let ruler = try openAdjustments(app)
        XCTAssertEqual(ruler.value as? String, "0.0 EV")
        try keepProof(app, named: "Walkthrough 3 editor")
        try app.audit([.sufficientElementDescription, .trait, .hitRegion, .contrast])
        app.buttons["Looks"].tap()
        XCTAssertTrue(app.navigationBars["Looks"].waitForExistence(timeout: 5))
        sleep(1)
        try keepProof(app, named: "Walkthrough 4 looks")
    }

    /// The editor's toolbar and adjustment panel at the largest text size: every control stays
    /// labelled and reachable.
    @MainActor
    func testEditorAtLargestText() throws {
        let app = try launchSamples(XCUIApplication.Presentation.largestText)
        defer { removeSamples(app) }
        try keepProof(app, named: "Library AX5")
        try app.audit([.sufficientElementDescription, .trait, .textClipped])
        let ruler = try openAdjustments(app)
        XCTAssertTrue(ruler.isHittable)
        try keepProof(app, named: "Editor AX5")
        try app.audit([.sufficientElementDescription, .trait, .textClipped])
        app.buttons["Looks"].tap()
        XCTAssertTrue(app.navigationBars["Looks"].waitForExistence(timeout: 5))
        try keepProof(app, named: "Looks AX5")
        try app.audit([.sufficientElementDescription, .trait])
    }

    /// Right to left, the screens mirror and the ruler still adjusts in the direction its
    /// scale moves.
    @MainActor
    func testRightToLeftWalkthrough() throws {
        let app = try launchSamples(XCUIApplication.Presentation.rightToLeft)
        defer { removeSamples(app) }
        try keepProof(app, named: "RTL library")
        let ruler = try openAdjustments(app)
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        let value = try XCTUnwrap(ruler.value as? String)
        XCTAssertTrue(value.hasPrefix("+"), "Dragging left increases the value in either direction, like the scale it moves (got \(value))")
        try keepProof(app, named: "RTL editor")
        try app.audit([.sufficientElementDescription, .trait, .hitRegion])
        app.buttons["Looks"].tap()
        XCTAssertTrue(app.navigationBars["Looks"].waitForExistence(timeout: 5))
        try keepProof(app, named: "RTL looks")
    }

    @MainActor
    private func launchSamples(_ presentation: [String]) throws -> XCUIApplication {
        let app = XCUIApplication.launchLibrary(presentation)
        let samples = app.buttons["Try Sample Photos"]
        guard samples.waitForExistence(timeout: 5) else {
            throw XCTSkip("Needs an empty library; uninstall the isolated proof app first.")
        }
        for _ in 0..<3 where !samples.isHittable { app.swipeUp() }
        samples.tap()
        XCTAssertTrue(app.buttons.matching(photoQuery).firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// Opens the first photo's editor with its adjustments showing, and returns the Exposure
    /// ruler. The expanded canvas (iPhone Duo unfolded) shows every ruler without a tap.
    @MainActor
    private func openAdjustments(_ app: XCUIApplication) throws -> XCUIElement {
        app.buttons.matching(photoQuery).firstMatch.tap()
        let editPhoto = app.buttons["Edit Photo"]
        if editPhoto.waitForExistence(timeout: 2) { editPhoto.tap() }
        XCTAssertTrue(app.buttons["Looks"].waitForExistence(timeout: 5))
        if app.buttons["Adjust"].exists { app.buttons["Adjust"].tap() }
        let ruler = app.otherElements.matching(identifier: "adjustment-ruler").firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertEqual(ruler.label, "Exposure")
        return ruler
    }

    @MainActor
    private func removeSamples(_ app: XCUIApplication) {
        if app.navigationBars["Looks"].exists { app.buttons["Done"].tap() }
        if !app.navigationBars["Library"].exists { app.buttons["BackButton"].tap() }
        guard app.buttons["Select"].waitForExistence(timeout: 5) else { return }
        app.buttons["Select"].tap()
        let photos = app.buttons.matching(photoQuery)
        let count = photos.count
        for index in 0..<count { photos.element(boundBy: index).tap() }
        app.buttons["Delete"].tap()
        app.buttons["Delete \(count) Photos"].tap()
        XCTAssertTrue(app.buttons["Try Sample Photos"].waitForExistence(timeout: 5))
    }
}
