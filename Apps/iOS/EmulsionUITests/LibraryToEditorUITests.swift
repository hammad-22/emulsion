import XCTest

/// End-to-end walk through the app from an empty library: add the sample photos, select
/// one, open one, edit with the sliders, compare with the original, reset, rotate, save to
/// Photos and delete.
/// Screenshots are kept in the result bundle as PR proof. Run on a fresh install
/// (`xcrun simctl uninstall booted com.hammad.emulsion`) so the library starts empty.
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
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 2))
        firstPhoto.tap()

        let exposure = app.sliders["Exposure"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        sleep(2)
        keepScreenshot(app, named: "3 Editor")

        let reset = app.buttons["Reset Edits"]
        XCTAssertFalse(reset.isEnabled, "Nothing to reset before the first edit")
        exposure.adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        XCTAssertFalse(reset.isEnabled)
        exposure.adjust(toNormalizedSliderPosition: 0.6)
        app.buttons["Color"].tap()
        app.sliders["Warmth"].adjust(toNormalizedSliderPosition: 0.7)
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
        XCTAssertTrue(app.sliders["Warmth"].exists, "The panel keeps its group when the layout changes")
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
        firstPhoto.tap()
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        deleteCurrentPhoto(app)
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 photo"].waitForExistence(timeout: 5))
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
