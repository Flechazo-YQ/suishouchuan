import XCTest

final class LaunchTests: XCTestCase {
    func testLaunchAndPairingScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["CommandV"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["拍照"].exists)
        XCTAssertTrue(app.buttons["相册"].exists)
        XCTAssertFalse(app.staticTexts["无法读取已配对电脑，请解锁手机后重试"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "CommandV home"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["配对电脑"].tap()
        XCTAssertTrue(app.navigationBars["连接电脑"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["扫描配对二维码"].exists)
        let pairing = XCTAttachment(screenshot: app.screenshot()); pairing.name = "CommandV pairing"; pairing.lifetime = .keepAlways; add(pairing)
    }
}
