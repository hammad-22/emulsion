import XCTest

/// End-to-end walk through the app from an empty library: add the sample photos, select
/// two, cancel and confirm deleting the selection, edit the remaining photo, compare with
/// the original, reset, rotate, save to Photos and delete.
/// Screenshots are kept in the result bundle as PR proof. Run on a fresh install
/// with an isolated test bundle identifier so the owner's library stays untouched.
final class LibraryToEditorUITests: XCTestCase {
    @MainActor
    func testEmptyLibraryExplanationContrast() throws {
        let app = launchLibrary()
        guard app.buttons["Try Sample Photos"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Needs an empty library; uninstall the isolated proof app first.")
        }
        let explanation = "Import a photo, or try a sample, to develop it as a film negative and print."
        // This regression targets the explanation; full-screen contrast findings remain in MOV-59/MOV-135.
        try app.performAccessibilityAudit(for: .contrast) { issue in
            issue.element?.label != explanation
        }
    }

    @MainActor
    func testEmptyLibraryTextScalingAndLabels() throws {
        let app = launchLibrary()
        guard app.buttons["Try Sample Photos"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Needs an empty library; uninstall the isolated proof app first.")
        }
        try app.performAccessibilityAudit(for: [.textClipped, .dynamicType, .sufficientElementDescription, .trait, .hitRegion])
        app.swipeUp()
        app.swipeUp()
        keepScreenshot(app, named: "Empty library accessibility")
        try app.performAccessibilityAudit(for: [.textClipped, .dynamicType, .sufficientElementDescription, .trait])
    }

    @MainActor
    func testLibraryEditorLooksLabelsTraitsAndHitRegions() throws {
        let app = try launchSampleLibrary()
        defer { removeSamples(app) }
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        keepScreenshot(app, named: "Library accessibility")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
        photo.tap()
        app.buttons["Adjust"].tap()
        let ruler = app.otherElements["adjustment-ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertEqual(ruler.label, "Exposure")
        XCTAssertEqual(ruler.value as? String, "0.0 EV")
        keepScreenshot(app, named: "Editor accessibility")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
        app.buttons["Looks"].tap()
        XCTAssertTrue(app.navigationBars["Looks"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "Looks accessibility")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
    }

    @MainActor
    func testAppliedLookHasSelectedTrait() throws {
        let app = try launchSampleLibrary()
        defer { removeSamples(app) }
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        photo.tap()
        app.buttons["Looks"].tap()
        let look = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Warm Light'")).firstMatch
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        look.tap()
        app.buttons["Looks"].tap()
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        XCTAssertTrue(look.isSelected, "The applied look exposes selection to assistive technology")
        keepScreenshot(app, named: "Applied look accessibility")
    }

    @MainActor
    func testAdjustmentGroupValueAndHitRegions() throws {
        let app = try launchSampleLibrary()
        defer { removeSamples(app) }
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        photo.tap()
        app.buttons["Adjust"].tap()
        XCTAssertTrue(app.otherElements["adjustment-ruler"].waitForExistence(timeout: 5))
        let group = app.descendants(matching: .any).matching(identifier: "Adjustment group").firstMatch
        XCTAssertEqual(group.value as? String, "Light")
        try app.performAccessibilityAudit(for: .hitRegion)
        group.tap()
        app.buttons["Color"].tap()
        XCTAssertEqual(group.value as? String, "Color")
        XCTAssertEqual(app.otherElements["adjustment-ruler"].label, "Warmth")
    }

    @MainActor
    func testSamplesEditCompareAndSave() throws {
        let app = launchLibrary()

        let samples = app.buttons["Try Sample Photos"]
        guard samples.waitForExistence(timeout: 2) else { throw XCTSkip("Needs an empty library; uninstall the app first.") }
        keepScreenshot(app, named: "1 Empty library")
        samples.tap()

        let firstPhoto = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 5))
        sleep(2)
        keepScreenshot(app, named: "2 Library with samples")

        app.buttons["Select"].tap()
        firstPhoto.tap()
        XCTAssertTrue(app.navigationBars["1 Selected"].waitForExistence(timeout: 2))
        XCTAssertTrue(firstPhoto.isSelected)
        keepScreenshot(app, named: "2b Selecting")
        let photos = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'"))
        photos.element(boundBy: 1).tap()
        XCTAssertTrue(app.navigationBars["2 Selected"].waitForExistence(timeout: 2))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete 2 Photos"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "2c Confirm selection deletion")
        XCTAssertTrue(app.staticTexts["Delete 2 photos?"].exists, "The title resolves its localized inflection")
        app.otherElements["dismiss popup"].tap()
        XCTAssertTrue(app.navigationBars["2 Selected"].waitForExistence(timeout: 2))
        XCTAssertEqual(photos.count, 3, "Cancel keeps all photos and the selection")
        app.buttons["Delete"].tap()
        app.buttons["Delete 2 Photos"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 photo"].waitForExistence(timeout: 5))
        XCTAssertEqual(photos.count, 1, "Confirm removes exactly the selected photos")
        firstPhoto.tap()

        app.buttons["Adjust"].tap()
        let exposure = app.otherElements["adjustment-ruler"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        sleep(2)
        keepScreenshot(app, named: "3 Editor")

        let reset = app.buttons["Reset Edits"]
        XCTAssertFalse(reset.isEnabled, "Nothing to reset before the first edit")
        dragRuler(exposure)
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        XCTAssertFalse(reset.isEnabled)
        let scrollStart = exposure.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let scrollEnd = exposure.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.95))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        XCTAssertFalse(reset.isEnabled, "A mostly vertical scroll must not adjust exposure")
        dragRuler(exposure)
        XCTAssertTrue(reset.isEnabled)
        exposure.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).doubleTap()
        XCTAssertFalse(reset.isEnabled, "A double tap on the scale returns it to neutral")
        dragRuler(exposure)
        let editedExposure = exposure.value as? String
        app.buttons["Hide Adjustments"].tap()
        XCTAssertFalse(exposure.isHittable)
        app.buttons["Adjust"].tap()
        XCTAssertEqual(exposure.value as? String, editedExposure, "Hiding controls preserves the edit")
        app.buttons["Adjustment group"].tap()
        app.buttons["Color"].tap()
        let warmth = app.otherElements["adjustment-ruler"]
        XCTAssertEqual(warmth.label, "Warmth")
        dragRuler(warmth)
        let editedWarmth = warmth.value as? String
        sleep(2)
        keepScreenshot(app, named: "4 Edited")

        app.buttons["Compare"].tap()
        XCTAssertTrue(app.staticTexts["Original"].waitForExistence(timeout: 2))
        sleep(2)
        keepScreenshot(app, named: "5 Original")
        app.buttons["Compare"].tap()
        XCTAssertFalse(app.staticTexts["Original"].exists)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertEqual(warmth.label, "Warmth", "The panel keeps its group when the layout changes")
        XCTAssertEqual(warmth.value as? String, editedWarmth, "The selected adjustment retains its value")
        keepScreenshot(app, named: "6 Landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(1)

        allowPhotoLibraryAdds()
        app.buttons["Save to Photos"].tap()
        app.tap()  // Lets the interruption monitor answer the permission alert.
        XCTAssertTrue(app.alerts["Saved to Photos"].waitForExistence(timeout: 20))
        keepScreenshot(app, named: "7 Saved")
        app.alerts["Saved to Photos"].buttons["OK"].tap()

        deleteCurrentPhoto(app)
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(samples.waitForExistence(timeout: 5), "Deleting the remaining photo returns to the empty library")
    }

    @MainActor
    func testLooksContrastAndTextClipping() throws {
        let app = try launchSampleLibrary()
        defer { removeSamples(app) }
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        app.buttons["Looks"].tap()
        XCTAssertTrue(app.navigationBars["Looks"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "Looks initial readability")
        try app.performAccessibilityAudit(for: [.contrast, .textClipped])
        for page in 1...5 {
            app.collectionViews["looks-collection"].swipeUp()
            keepScreenshot(app, named: "Looks text layout \(page)")
            try app.performAccessibilityAudit(for: .textClipped)
        }
    }

    @MainActor
    func testLooksSaveApplyAndDelete() throws {
        let app = try launchSampleLibrary()
        defer { removeSamples(app) }
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        photo.tap()
        app.buttons["Looks"].tap()
        let warm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Warm Light'")).firstMatch
        XCTAssertTrue(warm.waitForExistence(timeout: 5))
        warm.tap()
        app.buttons["Looks"].tap()
        XCTAssertTrue(warm.waitForExistence(timeout: 5))
        XCTAssertTrue(warm.isSelected)
        app.buttons["Save Look"].tap()
        let save = app.alerts["Save Look"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.textFields.firstMatch.tap()
        save.textFields.firstMatch.typeText("Readability Test")
        save.buttons["Save"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Readability Test'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.isHittable, "Saving scrolls to the new look")
        keepScreenshot(app, named: "Saved look")
        saved.tap()
        XCTAssertFalse(app.navigationBars["Looks"].exists)
        app.buttons["Looks"].tap()
        for _ in 0..<5 where !saved.isHittable { app.collectionViews["looks-collection"].swipeUp() }
        XCTAssertTrue(saved.isSelected)
        app.buttons["Options for Readability Test"].tap()
        XCTAssertTrue(app.buttons["Share Look"].waitForExistence(timeout: 5))
        app.buttons["Delete Look"].tap()
        app.buttons["Delete Look"].tap()
        XCTAssertFalse(saved.exists)
    }

    @MainActor
    private func launchLibrary() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--library"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5), "Library tests must open the library")
        return app
    }

    @MainActor
    private func launchSampleLibrary() throws -> XCUIApplication {
        let app = launchLibrary()
        guard app.buttons["Try Sample Photos"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Needs an empty library; uninstall the isolated proof app first.")
        }
        app.buttons["Try Sample Photos"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch.waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func removeSamples(_ app: XCUIApplication) {
        if app.navigationBars["Looks"].exists { app.buttons["Done"].tap() }
        if !app.navigationBars["Library"].exists { app.buttons["BackButton"].tap() }
        guard app.buttons["Select"].waitForExistence(timeout: 5) else { return }
        app.buttons["Select"].tap()
        let photos = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'"))
        let count = photos.count
        for index in 0..<count { photos.element(boundBy: index).tap() }
        app.buttons["Delete"].tap()
        app.buttons["Delete \(count) Photos"].tap()
        XCTAssertTrue(app.buttons["Try Sample Photos"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func dragRuler(_ ruler: XCUIElement) {
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
        let end = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func deleteCurrentPhoto(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        app.buttons["Delete"].tap()
        app.buttons["Delete Photo"].tap()
    }

    @MainActor
    private func allowPhotoLibraryAdds() {
        addUIInterruptionMonitor(withDescription: "Photo library permission") { alert in
            // XCTest calls interruption handlers on the main thread.
            MainActor.assumeIsolated {
                for label in ["Allow Full Access", "Allow", "OK"] where alert.buttons[label].exists {
                    alert.buttons[label].firstMatch.tap()
                    return true
                }
                return false
            }
        }
    }
}
