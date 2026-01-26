import XCTest

final class SwiftUIHTMLExampleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testRenderingResultShowsSnapshotHTML() {
        let app = XCUIApplication()
        app.launch()

        let snapshotCell = app.buttons["Snapshot Test Preview"].exists
            ? app.buttons["Snapshot Test Preview"]
            : app.staticTexts["Snapshot Test Preview"]
        if !snapshotCell.waitForExistence(timeout: 10) {
            if app.collectionViews.firstMatch.exists {
                app.collectionViews.firstMatch.scrollToElement(snapshotCell)
            } else if app.tables.firstMatch.exists {
                app.tables.firstMatch.scrollToElement(snapshotCell)
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.scrollToElement(snapshotCell)
            }
        }
        assertExists(snapshotCell, timeout: 10, name: "Snapshot Test Preview")
        snapshotCell.tap()

        assertExists(app.staticTexts["Rendering Result"], timeout: 10, name: "Rendering Result")
        let parseStatus = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Parse ok")).firstMatch
        assertExists(parseStatus, timeout: 10, name: "Parse ok")
        print("Parse status label: \(parseStatus.label)")
        XCTAssertFalse(parseStatus.label.contains("children=0"), "Parse result has zero children: \(parseStatus.label)")

        let renderSizeLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Render size:")).firstMatch
        assertExists(renderSizeLabel, timeout: 10, name: "Render size")
        print("Render size label: \(renderSizeLabel.label)")
        XCTAssertFalse(renderSizeLabel.label.contains("0x0"), "Render size is zero: \(renderSizeLabel.label)")
        assertExists(app.staticTexts["Snapshot Test HTML"], timeout: 10, name: "Rendered HTML title")
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
    func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 12) {
        var attempts = 0
        while !element.exists && attempts < maxSwipes {
            swipeUp()
            attempts += 1
        }
    }
}
