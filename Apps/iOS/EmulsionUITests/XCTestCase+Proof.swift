import XCTest

extension XCTestCase {
    /// Keeps a screenshot in the result bundle, named for the PR's Proof section.
    @MainActor
    func keepScreenshot(_ app: XCUIApplication, named name: String) {
        // iPhone Duo has two screens, one of them off, and the app's own screenshot can be the
        // blank one; keep whichever screen is lit.
        let shots = XCUIScreen.screens.count > 1 ? XCUIScreen.screens.map { $0.screenshot() } : [app.screenshot()]
        for shot in shots where !shot.isBlank || shots.count == 1 {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Keeps a screenshot and the screen's accessibility tree in reading order: each labelled
    /// element's role, label, value and state. Not a record of a person using VoiceOver.
    @MainActor
    func keepProof(_ app: XCUIApplication, named name: String) throws {
        keepScreenshot(app, named: name)
        var lines: [String] = []
        func visit(_ element: any XCUIElementSnapshot) {
            if !element.label.isEmpty {
                let value = (element.value as? String).flatMap { $0.isEmpty ? nil : ", value \"\($0)\"" } ?? ""
                let state = (element.isSelected ? ", selected" : "") + (element.isEnabled ? "" : ", dimmed")
                lines.append("\(Self.role(element.elementType)) \"\(element.label)\"\(value)\(state)")
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
