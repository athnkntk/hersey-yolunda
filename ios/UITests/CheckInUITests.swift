import XCTest

final class CheckInUITests: XCTestCase {
    @MainActor
    func testLoginProfileAndRealBackendCheckIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean"]
        app.launch()
        XCTAssertFalse(app.textFields["phoneField"].exists)
        XCTAssertFalse(app.textFields["otpField"].exists)
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        name.typeText("Ayse Test")
        app.buttons["createAccount"].tap()
        let checkin = app.buttons["checkInButton"]
        XCTAssertTrue(checkin.waitForExistence(timeout: 15))
        XCTAssertTrue(checkin.isEnabled)
        checkin.tap()
        XCTAssertTrue(app.otherElements["completedCard"].waitForExistence(timeout: 15) || app.staticTexts["Bugün haber verdiniz."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["checkInButton"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Check-in backend onayı"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.tabBars.buttons["Ailem"].tap()
        app.buttons["Yakınımı davet et"].tap()
        let create = app.buttons["Davet oluştur"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(app.buttons["Daveti paylaş"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["invitationQR"].exists)
        let invitationCode = app.descendants(matching: .any)["invitationCode"].firstMatch
        for _ in 0..<3 where !invitationCode.exists { app.swipeUp() }
        XCTAssertTrue(invitationCode.waitForExistence(timeout: 5))
        app.tabBars.buttons["Ayarlar"].tap()
        app.buttons["Kontrol saati"].tap()
        XCTAssertTrue(app.buttons["Programı kaydet"].waitForExistence(timeout: 10))
        app.buttons["Programı kaydet"].tap()
        XCTAssertTrue(app.alerts["Bilgilendirme"].waitForExistence(timeout: 10))
        app.alerts.buttons["Tamam"].tap()
    }

    @MainActor
    func testLargeTextWelcomeRemainsScrollable() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        for _ in 0..<6 where !name.isHittable { app.swipeUp() }
        XCTAssertTrue(name.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "En büyük yazı boyutunda giriş"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
