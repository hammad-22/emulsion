import XCTest

extension XCTestCase {
    @MainActor
    func keepScreenshot(_ app: XCUIApplication, named name: String) {
        // On iPhone Duo the app's own screenshot can be the screen that is off.
        let shots = XCUIScreen.screens.count > 1 ? XCUIScreen.screens.map { $0.screenshot() } : [app.screenshot()]
        for shot in shots where !shot.isBlank || shots.count == 1 {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Also keeps the accessibility tree in reading order; not a record of VoiceOver use.
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
