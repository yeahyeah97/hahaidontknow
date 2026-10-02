import XCTest

final class TouchRoutingUITests: XCTestCase {
    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["milazy.key.a"].waitForExistence(timeout: 10))
        return app
    }

    func testPhysicalEdgeAndGapTapsReachTheKeyboard() {
        let app = application()
        let a = app.buttons["milazy.key.a"], l = app.buttons["milazy.key.l"]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let left = origin.withOffset(CGVector(dx: 1, dy: a.frame.midY - app.frame.minY))
        let right = origin.withOffset(CGVector(dx: app.frame.width - 1, dy: l.frame.midY - app.frame.minY))
        for _ in 0..<4 { left.tap(); right.tap() }
        let output = app.staticTexts["milazy.touchOutput"]
        XCTAssertEqual(output.value as? String, "alalalal")
        let s = app.buttons["milazy.key.s"]
        origin.withOffset(CGVector(dx: (a.frame.maxX + s.frame.minX) / 2 - app.frame.minX,
                                  dy: a.frame.midY - app.frame.minY)).tap()
        XCTAssertTrue(["alalalala", "alalalals"].contains(output.value as? String ?? ""))
    }

    func testPhysicalDragDoesNotInsertANeighborOrLoseTheFirstKey() {
        let app = application()
        let a = app.buttons["milazy.key.a"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let s = app.buttons["milazy.key.s"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: s)
        XCTAssertEqual(app.staticTexts["milazy.touchOutput"].value as? String, "a")
    }
}
