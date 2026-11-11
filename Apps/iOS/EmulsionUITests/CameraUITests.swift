import XCTest

/// The camera as the app opens on it, in the Simulator's stand-in camera (the sample
/// photos as a live viewfinder): switch lens, tap to focus, take a photo, find it in the
/// library, delete it and come back. Screenshots are kept in the result bundle as PR proof.
final class CameraUITests: XCTestCase {
    @MainActor
    func testCaptureAppearsInLibrary() throws {
        let app = XCUIApplication()
        app.launch()

        let viewfinder = app.descendants(matching: .any)["viewfinder"]
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 10))
        let library = app.buttons["Library"]
        let photos = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'"))
        let photosBefore = try countPhotos(app, library: library, photos: photos)
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 5))
        sleep(1)
        keepScreenshot(app, named: "Camera 1 Viewfinder")

        let ultraWide = app.buttons["Ultra Wide, 0.5×"]
        XCTAssertTrue(ultraWide.waitForExistence(timeout: 5))
        ultraWide.tap()
        XCTAssertTrue(ultraWide.isSelected)
        XCTAssertFalse(app.buttons["Resolution"].isEnabled, "the stand-in ultra wide has no 48 MP")
        sleep(1)
        keepScreenshot(app, named: "Camera 2 Ultra Wide")
        app.buttons["Wide, 1×"].tap()

        viewfinder.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["focus-reticle"].waitForExistence(timeout: 1))
        keepScreenshot(app, named: "Camera 3 Focus")

        app.buttons["Take Photo"].tap()
        sleep(2)
        keepScreenshot(app, named: "Camera 4 Captured")

        library.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(photos.count, photosBefore + 1, "the capture is in the library")
        sleep(1)
        keepScreenshot(app, named: "Camera 5 Library")

        // Deletes the capture (newest first), leaving the library as it was for the next test.
        photos.firstMatch.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.buttons["Delete 1 Photo"].tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", photosBefore), object: photos)
        XCTAssertEqual(XCTWaiter.wait(for: [deleted], timeout: 5), .completed)
        app.buttons["Camera"].tap()
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Take Photo"].isEnabled, "the camera runs again")
    }

    /// Opens the library to count what's already there, then returns to the camera.
    @MainActor
    private func countPhotos(_ app: XCUIApplication, library: XCUIElement, photos: XCUIElementQuery) throws -> Int {
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        let count = photos.count
        app.buttons["Camera"].tap()
        return count
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
