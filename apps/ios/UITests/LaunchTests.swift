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
        let expiry = Int64(Date().addingTimeInterval(300).timeIntervalSince1970 * 1000)
        let json = "{\"v\":1,\"deviceId\":\"12345678-1234-4234-8234-123456789abc\",\"name\":\"CI-PC\",\"addresses\":[\"192.168.1.2\"],\"port\":43821,\"fingerprint\":\"\(String(repeating: "a", count: 64))\",\"code\":\"\(String(repeating: "b", count: 32))\",\"expiresAt\":\(expiry)}"
        var link = URLComponents(); link.scheme = "imagebridge"; link.host = "pair"; link.queryItems = [URLQueryItem(name: "data", value: json)]
        let field = app.textFields["或粘贴电脑端配对链接"]
        field.tap(); field.typeText(link.string! + "\n")
        app.buttons["使用配对链接"].tap()
        let confirmation = app.alerts["配对电脑"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts["允许向「CI-PC」发送素材？"].exists)
        confirmation.buttons["取消"].tap()
    }
}
