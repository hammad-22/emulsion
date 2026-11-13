import XCTest

/// The RAW white balance rulers (MOV-137). The bundled samples aren't RAW, so this needs a RAW
/// photo already in the library of the isolated proof app (a synthetic DNG from
/// `RAWDevelopChart`, copied into its library folder); it's skipped without one.
final class WhiteBalanceUITests: XCTestCase {
    @MainActor
    func testRAWPhotoWhiteBalanceRulers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        // A library folder filled by hand has no index, which the app reports once.
        if app.alerts.buttons["OK"].waitForExistence(timeout: 2) { app.alerts.buttons["OK"].tap() }
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        guard photo.waitForExistence(timeout: 2) else { throw XCTSkip("Needs a RAW photo in the library.") }
        photo.tap()
        app.buttons["Adjust"].tap()
        let ruler = app.otherElements["adjustment-ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        app.buttons["Adjustment group"].tap()
        keepScreenshot(app, named: "WB 0 Adjustment groups")
        guard app.buttons["White Balance"].waitForExistence(timeout: 2) else {
            throw XCTSkip("The first photo isn't RAW: white balance doesn't apply to it.")
        }
        app.buttons["White Balance"].tap()

        XCTAssertEqual(ruler.label, "Temperature")
        let asShot = try XCTUnwrap(ruler.value as? String)
        XCTAssertTrue(asShot.hasSuffix("kelvin"), "VoiceOver hears the unit: \(asShot)")
        let reset = app.buttons["Reset Edits"]
        XCTAssertFalse(reset.isEnabled, "As shot is not an edit")
        sleep(2)
        keepScreenshot(app, named: "WB 1 As shot")

        drag(ruler, from: 0.3, to: 0.7)
        XCTAssertNotEqual(ruler.value as? String, asShot)
        XCTAssertTrue(reset.isEnabled)
        sleep(2)
        keepScreenshot(app, named: "WB 2 Temperature lowered")

        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).doubleTap()
        XCTAssertEqual(ruler.value as? String, asShot, "A double tap returns the ruler to as shot")
        XCTAssertFalse(reset.isEnabled, "Back at as shot the photo is unedited")

        app.buttons["White Balance Tint"].tap()
        XCTAssertEqual(ruler.label, "White Balance Tint")
        drag(ruler, from: 0.7, to: 0.3)
        XCTAssertTrue(reset.isEnabled)
        sleep(2)
        keepScreenshot(app, named: "WB 3 Tint raised")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertEqual(ruler.label, "White Balance Tint", "The panel keeps its group when the layout changes")
        keepScreenshot(app, named: "WB 4 Landscape")
        XCUIDevice.shared.orientation = .portrait
        reset.tap()
        XCTAssertFalse(reset.isEnabled)
    }

    /// The inspector (every group at once, as on an unfolded iPhone Duo) in the debug component
    /// gallery, which stands in a RAW photo's as-shot white balance.
    @MainActor
    func testInspectorShowsWhiteBalanceRulers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--component-gallery"]
        app.launch()
        let rulers = app.otherElements.matching(identifier: "adjustment-ruler")
        let temperature = rulers.matching(NSPredicate(format: "label == 'Temperature'")).firstMatch
        let tint = rulers.matching(NSPredicate(format: "label == 'White Balance Tint'")).firstMatch
        XCTAssertTrue(app.staticTexts["White Balance"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !tint.isHittable { app.swipeUp() }
        XCTAssertTrue(temperature.exists)
        XCTAssertTrue(tint.isHittable)
        XCTAssertEqual(temperature.value as? String, "5,200 kelvin")
        XCTAssertEqual(tint.value as? String, "+8")
        keepScreenshot(app, named: "WB 5 Inspector")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
    }

    @MainActor
    private func drag(_ ruler: XCUIElement, from start: CGFloat, to end: CGFloat) {
        ruler.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.7)))
    }
}
