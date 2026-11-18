import XCTest

final class LaunchTests: XCTestCase {
    func testLaunchAndPairingScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["连接电脑"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["拍摄"].exists)
        XCTAssertTrue(app.buttons["连拍"].exists)
        XCTAssertTrue(app.buttons["相册"].exists)
        XCTAssertFalse(app.staticTexts["无法读取已配对电脑，请解锁手机后重试"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "CommandC home"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["配对电脑"].tap()
        XCTAssertTrue(app.navigationBars["连接电脑"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["扫描配对二维码"].exists)
        let pairing = XCTAttachment(screenshot: app.screenshot()); pairing.name = "CommandC pairing"; pairing.lifetime = .keepAlways; add(pairing)
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

    func testBurstPreviewAndIndependentCapture() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-camera"]
        app.launch()
        XCTAssertTrue(app.buttons["连拍"].waitForExistence(timeout: 10))
        app.buttons["连拍"].tap()
        let shutter = app.buttons["连拍：拍摄一张并继续取景"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 3))
        shutter.tap(); shutter.tap()
        XCTAssertTrue(app.buttons["查看 2 张"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["相册"].isEnabled)
        XCTAssertTrue(app.buttons["截屏 / 录屏"].isEnabled)
        attach(app, "CommandC burst camera")
        app.buttons["查看 2 张"].tap()
        XCTAssertTrue(app.buttons["确认并发送"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["确认并发送"].isEnabled)
        attach(app, "CommandC group preview")
        app.buttons["返回取景"].tap()
        app.buttons["拍摄"].tap()
        XCTAssertTrue(app.buttons["待发 2 张 · 查看"].waitForExistence(timeout: 3))
        app.buttons["拍摄：轻触拍照，长按录像"].tap()
        XCTAssertTrue(app.buttons["确认上传"].waitForExistence(timeout: 3))
        attach(app, "CommandC photo preview")
        app.buttons["重新拍摄"].tap()
        XCTAssertTrue(app.buttons["查看 2 张"].waitForExistence(timeout: 3))
        app.buttons["查看 2 张"].tap()
        app.buttons["移除第 2 张"].tap()
        XCTAssertTrue(app.staticTexts["预览 1 / 1"].waitForExistence(timeout: 3))
    }

    func testSwipeModesAndScreenShareEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-camera"]
        app.launch()
        let finder = app.otherElements["viewfinder"]
        XCTAssertTrue(finder.waitForExistence(timeout: 10))
        finder.swipeLeft()
        XCTAssertTrue(app.buttons["连拍：拍摄一张并继续取景"].waitForExistence(timeout: 3))
        finder.swipeRight()
        XCTAssertTrue(app.buttons["拍摄：轻触拍照，长按录像"].waitForExistence(timeout: 3))
        app.buttons["截屏 / 录屏"].tap()
        if #available(iOS 27.0, *) {
            XCTAssertTrue(app.buttons["开始屏幕采集"].waitForExistence(timeout: 3))
            app.buttons["开始屏幕采集"].tap()
            XCTAssertTrue(app.staticTexts["跨 App 屏幕采集需要在 iPhone 真机测试。"].waitForExistence(timeout: 3))
            let islandStep = app.descendants(matching: .any)["screenCaptureGuideStep2"].firstMatch
            XCTAssertTrue(islandStep.isHittable)
            XCTAssertTrue(islandStep.label.contains("长按屏幕顶部的灵动岛"))
            attach(app, "CommandC native screen controls")
            let actionButtonGuide = app.buttons["用操作按钮截图"]
            for _ in 0..<3 where !actionButtonGuide.isHittable { app.swipeUp() }
            XCTAssertTrue(actionButtonGuide.isHittable)
            actionButtonGuide.tap()
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "长按机身操作按钮")).firstMatch.waitForExistence(timeout: 3))
            attach(app, "CommandC Action button instructions")
            actionButtonGuide.tap()
            app.swipeUp()
            XCTAssertFalse(app.staticTexts["系统截图"].exists)
            XCTAssertFalse(app.staticTexts["系统录屏"].exists)
            XCTAssertFalse(app.buttons["选择截图"].exists)
            XCTAssertFalse(app.buttons["选择录屏视频"].exists)
            attach(app, "CommandC capture-only screen")
        } else {
            XCTAssertTrue(app.buttons["选择截图"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["选择录屏视频"].exists)
        }
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["相册"].waitForExistence(timeout: 3))
    }

    func testActiveScreenCaptureUsesIslandControls() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native screen capture needs iOS 27") }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-camera", "--ui-screen-capture-active"]
        app.launch()
        let screenTools = app.buttons["截屏 / 录屏"]
        XCTAssertTrue(screenTools.waitForExistence(timeout: 10))
        screenTools.tap()
        app.buttons["开始屏幕采集"].tap()

        let stop = app.buttons["停止采集"]
        XCTAssertTrue(stop.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["1.5 秒后截取"].exists)
        XCTAssertFalse(app.buttons["开始录屏"].exists)
        attach(app, "CommandC active screen capture")

        stop.tap()
        XCTAssertTrue(app.buttons["开始屏幕采集"].waitForExistence(timeout: 3))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
