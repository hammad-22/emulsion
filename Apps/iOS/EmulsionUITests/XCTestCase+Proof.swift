import XCTest

extension XCTestCase {
    /// Keeps a screenshot in the result bundle, named for the PR's Proof section.
    @MainActor
    func keepScreenshot(_ app: XCUIApplication, named name: String) {
        // iPhone Duo has two screens, and the app's own screenshot is blank on the inner one.
        let screens = XCUIScreen.screens
        for (index, screen) in screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screens.count > 1 ? screen.screenshot() : app.screenshot())
            attachment.name = screens.count > 1 ? "\(name) screen \(index + 1)" : name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Keeps a screenshot and, beside it, what assistive technology is given for the screen in
    /// reading order: each labelled element's role, label, value and state. A record of the
    /// accessibility tree (containers and their children both appear), not of a person using
    /// VoiceOver.
    @MainActor
    func keepProof(_ app: XCUIApplication, named name: String) throws {
        keepScreenshot(app, named: name)
        var lines: [String] = []
        func visit(_ element: any XCUIElementSnapshot) {
            if !element.label.isEmpty {
                let value = (element.value as? String).flatMap { $0.isEmpty ? nil : ", value \"\($0)\"" } ?? ""
                let state = (element.isSelected ? ", selected" : "") + (element.isEnabled ? "" : ", dimmed")
                let line = "\(Self.role(element.elementType)) \"\(element.label)\"\(value)\(state)"
                lines.append(line)
            }
            element.children.forEach(visit)
        }
        visit(try app.snapshot())
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "\(name) spoken"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func role(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: "Button"
        case .staticText: "Text"
        case .image: "Image"
        case .navigationBar: "Navigation bar"
        case .toggle, .switch: "Toggle"
        case .cell: "Cell"
        default: "Element"
        }
    }
}
