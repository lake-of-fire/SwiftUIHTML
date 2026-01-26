import XCTest

final class SwiftUIHTMLExampleMacOSUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testRenderingResultShowsSnapshotHTML() {
        let app = XCUIApplication()
        app.launch()

        let snapshotCell = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Snapshot Test Preview"))
            .firstMatch
        if !snapshotCell.waitForExistence(timeout: 10) {
            if app.outlines.firstMatch.exists {
                app.outlines.firstMatch.scrollToElement(snapshotCell)
            } else if app.tables.firstMatch.exists {
                app.tables.firstMatch.scrollToElement(snapshotCell)
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.scrollToElement(snapshotCell)
            }
        }
        assertExists(snapshotCell, timeout: 10, name: "Snapshot Test Preview")
        snapshotCell.click()

        assertExists(app.staticTexts["Rendering Result"], timeout: 10, name: "Rendering Result")
    }

    private func assertExists(_ element: XCUIElement, timeout: TimeInterval, name: String) {
        if element.waitForExistence(timeout: timeout) {
            return
        }

        print("Missing \(name). App hierarchy:\n\(XCUIApplication().debugDescription)")
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Missing-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTFail("Expected to find \(name).")
    }
}

private extension XCUIElement {
    func scrollToElement(_ element: XCUIElement) {
        var attempts = 0
        while !element.exists && attempts < 12 {
            let coord = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coord.scroll(byDeltaX: 0, deltaY: -400)
            attempts += 1
        }
    }
}
