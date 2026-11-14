import XCTest

/// Accessibility checks across camera → library → editor → Looks at the largest text size and
/// right to left (MOV-140). Native audits use the same engine as Accessibility Inspector; they
/// don't replace a human VoiceOver walkthrough. Run on a fresh install of an isolated bundle ID.
final class AccessibilityUITests: XCTestCase {
    /// "Try Sample Photos" must stay whole and reachable at the largest accessibility size.
    @MainActor
    func testEmptyLibraryActionsAtLargestText() throws {
        let app = try XCUIApplication.launchEmptyLibrary(XCUIApplication.Presentation.largestText)
        XCTAssertTrue(app.buttons["Try Sample Photos"].isHittable)
        XCTAssertTrue(app.buttons["Import"].isHittable)
        try keepProof(app, named: "Empty library AX5")
        try app.audit([.textClipped, .sufficientElementDescription, .trait])
    }

    @MainActor
    func testCameraLabelsTraitsAndHitRegions() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.Presentation.largestText
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.viewfinder].waitForExistence(timeout: 10))
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

    /// Run with Reduce Transparency or Reduce Motion set on the simulator for those proofs.
    @MainActor
    func testWalkthroughKeepsSpokenElements() throws {
        let camera = XCUIApplication()
        camera.launch()
        XCTAssertTrue(camera.buttons["Take Photo"].waitForExistence(timeout: 10))
        sleep(1)
        try keepProof(camera, named: "Walkthrough 1 camera")
        camera.terminate()

        let app = try XCUIApplication.launchSampleLibrary()
        defer { app.removeSamples() }
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

    @MainActor
    func testEditorAtLargestText() throws {
        let app = try XCUIApplication.launchSampleLibrary(XCUIApplication.Presentation.largestText)
        defer { app.removeSamples() }
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

    /// Right to left, the screens mirror and the ruler still adjusts by dragging. Whether its
    /// scale should also mirror is open (MOV-140); today it matches left to right.
    @MainActor
    func testRightToLeftWalkthrough() throws {
        let app = try XCUIApplication.launchSampleLibrary(XCUIApplication.Presentation.rightToLeft)
        defer { app.removeSamples() }
        try keepProof(app, named: "RTL library")
        let ruler = try openAdjustments(app)
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        let value = try XCTUnwrap(ruler.value as? String)
        XCTAssertNotEqual(value, "0.0 EV", "Dragging the ruler adjusts it right to left")
        try keepProof(app, named: "RTL editor")
        try app.audit([.sufficientElementDescription, .trait, .hitRegion])
        app.buttons["Looks"].tap()
        XCTAssertTrue(app.navigationBars["Looks"].waitForExistence(timeout: 5))
        try keepProof(app, named: "RTL looks")
    }

    /// Opens the first photo's editor with its adjustments showing, and returns the Exposure
    /// ruler. The expanded canvas (iPhone Duo unfolded) shows every ruler without a tap.
    @MainActor
    private func openAdjustments(_ app: XCUIApplication) throws -> XCUIElement {
        app.photos.firstMatch.tap()
        let editPhoto = app.buttons["Edit Photo"]
        if editPhoto.waitForExistence(timeout: 2) { editPhoto.tap() }
        XCTAssertTrue(app.buttons["Looks"].waitForExistence(timeout: 5))
        if app.buttons["Adjust"].exists { app.buttons["Adjust"].tap() }
        let ruler = app.otherElements.matching(identifier: AccessibilityID.adjustmentRuler).firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertEqual(ruler.label, "Exposure")
        return ruler
    }
}
