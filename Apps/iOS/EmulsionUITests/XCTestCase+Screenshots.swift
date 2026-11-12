import XCTest

extension XCTestCase {
    /// Keeps a screenshot in the result bundle, named for the PR's Proof section.
    @MainActor
    func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
