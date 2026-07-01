import XCTest

final class ReaderFlowUITests: XCTestCase {
    func testLaunchShowsLibrary() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["ReaderFlow"].waitForExistence(timeout: 5))
    }
}
