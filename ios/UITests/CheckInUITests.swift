import XCTest

final class CheckInUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean", "--uitest-premium", "--uitest-language", language]
        app.launch()
        return app
    }
    private func dismissNotificationPreprompt(_ app: XCUIApplication) {
        let later = app.buttons["notificationLater"]
        if later.waitForExistence(timeout: 10) { later.tap() }
    }
    private func register(_ app: XCUIApplication, name: String) {
        XCTAssertTrue(app.textFields["nameField"].waitForExistence(timeout: 15))
        app.textFields["nameField"].tap()
        app.textFields["nameField"].typeText(name)
        app.buttons["createAccount"].tap()
        dismissNotificationPreprompt(app)
    }
    /// Sekme dokunuşu yeniden çizim sırasında yutulabilir; hedef görünene kadar tekrar dene.
    private func openTab(_ app: XCUIApplication, tab: String, marker: String) {
        let markerElement = app.descendants(matching: .any)[marker].firstMatch
        for _ in 0..<4 {
            if markerElement.waitForExistence(timeout: 6) { return }
            app.tabBars.buttons[tab].tap()
        }
        XCTAssertTrue(markerElement.waitForExistence(timeout: 10), "expected \(marker) on the \(tab) tab")
    }

    func testLoginProfileAndRealBackendCheckIn() throws {
        let app = launch("tr")
        register(app, name: "Ayse Test")
        let checkin = app.buttons["checkInButton"]
        XCTAssertTrue(checkin.waitForExistence(timeout: 30))
        XCTAssertTrue(checkin.isEnabled)
        checkin.tap()
        XCTAssertTrue(app.otherElements["completedCard"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Ailem"].tap()
        app.buttons["Yakınımı davet et"].tap()
        let create = app.buttons["Davet oluştur"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let invitationCode = app.descendants(matching: .any)["invitationCode"].firstMatch
        for _ in 0..<3 where !invitationCode.exists { app.swipeUp() }
        XCTAssertTrue(invitationCode.waitForExistence(timeout: 10))
        app.tabBars.buttons["Ayarlar"].tap()
        app.buttons["Kontrol saati"].tap()
        let save = app.buttons["Programı kaydet"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        for _ in 0..<10 where !save.isEnabled { sleep(1) }
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.alerts["Bilgilendirme"].waitForExistence(timeout: 15))
        app.alerts.buttons["Tamam"].tap()
    }

    func testEnglishOnboardingCheckInAndSchedule() throws {
        let app = launch("en")
        XCTAssertFalse(app.textFields["phoneField"].exists, "the flow must not ask for a phone number")
        XCTAssertFalse(app.textFields["otpField"].exists, "the flow must not ask for an OTP code")
        register(app, name: "Sarah Miller")
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.tabBars.buttons["Family"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        app.tabBars.buttons["Today"].tap()
        let checkIn = app.buttons["checkInButton"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 30))
        XCTAssertTrue(checkIn.isEnabled)
        XCTAssertTrue(app.staticTexts["I'M OK"].exists, "expected the English I'M OK call to action")
        checkIn.tap()
        XCTAssertTrue(app.otherElements["completedCard"].waitForExistence(timeout: 30))
        openTab(app, tab: "Family", marker: "Invite a relative")
        app.buttons["Invite a relative"].tap()
        XCTAssertTrue(app.staticTexts["Relative"].waitForExistence(timeout: 15), "relationship label must display translated, tag stays backend-compatible")
        let create = app.buttons["Create invitation"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let share = app.descendants(matching: .any)["Share invitation"].firstMatch
        for _ in 0..<3 where !share.exists { app.swipeUp() }
        XCTAssertTrue(share.waitForExistence(timeout: 10), "expected the share action for the invitation")
        XCTAssertTrue(app.images["invitationQR"].exists, "expected the QR invitation image")
        let invitationCode = app.descendants(matching: .any)["invitationCode"].firstMatch
        for _ in 0..<3 where !invitationCode.exists { app.swipeUp() }
        XCTAssertTrue(invitationCode.waitForExistence(timeout: 10))
        openTab(app, tab: "Settings", marker: "Check-in schedule")
        app.buttons["Check-in schedule"].tap()
        let save = app.buttons["scheduleSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        for _ in 0..<10 where !save.isEnabled { sleep(1) }
        save.tap()
        XCTAssertTrue(app.alerts["Information"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.staticTexts["Bilgilendirme"].exists, "a Turkish-only label must not appear in English")
        XCTAssertFalse(app.staticTexts["BEN İYİYİM"].exists)
        XCTAssertFalse(app.staticTexts["Bugün"].exists)
        app.buttons["My account and recovery"].tap()
        let accountID = app.staticTexts["accountIdentifier"].firstMatch.label
        XCTAssertFalse(accountID.isEmpty, "expected the account identifier")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Türkçe"].tap()
        XCTAssertTrue(app.tabBars.buttons["Bugün"].waitForExistence(timeout: 15), "switching to Türkçe must re-render the tabs")
        openTab(app, tab: "Ayarlar", marker: "Hesabım ve kurtarma")
        app.buttons["Hesabım ve kurtarma"].tap()
        XCTAssertEqual(app.staticTexts["accountIdentifier"].firstMatch.label, accountID, "language switch must keep the same account")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["--uitest-premium"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30), "relaunch must keep the saved English preference without a language override")
        XCTAssertFalse(app.textFields["nameField"].exists, "relaunch must keep the same account")
        openTab(app, tab: "Settings", marker: "My account and recovery")
        app.buttons["My account and recovery"].tap()
        XCTAssertEqual(app.staticTexts["accountIdentifier"].firstMatch.label, accountID, "relaunch must keep the same account")
    }

    func testLargeTextWelcomeRemainsScrollable() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean", "--uitest-premium", "--uitest-language", "en", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        for _ in 0..<6 where !name.isHittable { app.swipeUp() }
        XCTAssertTrue(name.isHittable)
    }
}
