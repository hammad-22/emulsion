import XCTest

/// End-to-end walk through the app from an empty library: add the sample photos, select
/// two, cancel and confirm deleting the selection, edit the remaining photo, compare with
/// the original, reset, rotate, save to Photos and delete.
/// Screenshots are kept in the result bundle as PR proof. Run on a fresh install
/// with an isolated test bundle identifier so the owner's library stays untouched.
final class LibraryToEditorUITests: XCTestCase {
    @MainActor
    func testSamplesEditCompareAndSave() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))

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
                    alert.buttons[label].tap()
                    return true
                }
                return false
            }
        }
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
