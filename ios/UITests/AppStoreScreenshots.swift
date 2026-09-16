import XCTest

final class AppStoreScreenshots: XCTestCase {
    private func save(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testCaptureStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean", "--uitest-premium"]
        app.launch()

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        save("01-giris", in: app)

        name.tap()
        name.typeText("Ayşe")
        app.buttons["createAccount"].tap()

        let checkin = app.buttons["checkInButton"]
        XCTAssertTrue(checkin.waitForExistence(timeout: 15))
        save("02-ana-ekran", in: app)

        checkin.tap()
        XCTAssertTrue(app.otherElements["completedCard"].waitForExistence(timeout: 15)
            || app.staticTexts["Bugün haber verdiniz."].waitForExistence(timeout: 5))
        save("03-haber-verildi", in: app)

        app.descendants(matching: .any)["Ailem"].firstMatch.tap()
        save("04-ailem", in: app)

        app.buttons["Yakınımı davet et"].tap()
        let create = app.buttons["Davet oluştur"]
        if create.waitForExistence(timeout: 10) {
            create.tap()
            _ = app.images["invitationQR"].waitForExistence(timeout: 10)
        }
        save("05-davet", in: app)

        app.descendants(matching: .any)["Ayarlar"].firstMatch.tap()
        save("06-ayarlar", in: app)
    }

    @MainActor
    func testCapturePaywall() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean"]
        app.launch()

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        name.typeText("Ayşe")
        app.buttons["createAccount"].tap()
        XCTAssertTrue(app.buttons["checkInButton"].waitForExistence(timeout: 15))

        app.descendants(matching: .any)["Ailem"].firstMatch.tap()
        let banner = app.buttons["premiumBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        _ = app.buttons["subscribeButton"].waitForExistence(timeout: 10)
        save("07-premium", in: app)
    }
}
