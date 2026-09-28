import XCTest

final class AppStoreScreenshots: XCTestCase {
    private var apiBase: String {
        ProcessInfo.processInfo.environment["TEST_RUNNER_HY_API_URL"]
            ?? ProcessInfo.processInfo.environment["HY_API_URL"]
            ?? "http://127.0.0.1:3100/v1"
    }

    private var seedTokens: [String] = []

    /// Seed accounts can be reused across runs (e.g. two devices, or retries
    /// while the registration rate limit is nearly exhausted). The host sets
    /// HY_SEED_FATMA_AT / HY_SEED_MEHMET_AT (fresh access tokens, via
    /// `simctl spawn ... launchctl setenv`) and optionally HY_SEED_KEEP=1 to
    /// keep the accounts alive for the next run. Pasteboard is not usable:
    /// reading it in the runner blocks forever on the paste-consent flow.
    private var seedKeep: Bool {
        ProcessInfo.processInfo.environment["HY_SEED_KEEP"] == "1"
    }

    private func seedAccounts() async throws -> (fatma: String, mehmet: String) {
        let env = ProcessInfo.processInfo.environment
        if let fatma = env["HY_SEED_FATMA_AT"], let mehmet = env["HY_SEED_MEHMET_AT"],
           !fatma.isEmpty, !mehmet.isEmpty {
            return (fatma, mehmet)
        }
        return (try await createSeedAccount("Fatma"), try await createSeedAccount("Mehmet"))
    }

    private func save(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    override func setUp() {
        super.setUp()
        addUIInterruptionMonitor(withDescription: "perm") { alert in
            for title in ["İzin Ver", "Allow", "Allow Once", "Allow While Using App"] {
                let button = alert.buttons[title]
                if button.exists { button.tap(); return true }
            }
            return false
        }
    }

    override func tearDown() async throws {
        // Seeded accounts may live on the production API — remove them unless
        // HY_SEED_KEEP asks to keep them for the next run.
        guard !seedKeep else {
            try await super.tearDown()
            return
        }
        for token in seedTokens {
            for attempt in 0 ..< 3 {
                do {
                    _ = try await api("DELETE", "/me", token: token, body: ["confirmation": "HESABIMI SİL"])
                    break
                } catch {
                    if attempt == 2 {
                        XCTFail("seed account cleanup failed: \(error)")
                    } else {
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                    }
                }
            }
        }
        seedTokens = []
        try await super.tearDown()
    }

    // MARK: - Backend seeding over HTTP

    private struct SeedError: Error, CustomStringConvertible {
        let description: String
    }

    private func api(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil, idempotencyKey: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: apiBase + path)!)
        request.httpMethod = method
        request.timeoutInterval = 60
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200 ..< 300).contains(status) else {
            throw SeedError(description: "\(method) \(path) -> \(status): \(String(decoding: data, as: UTF8.self))")
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func registrationSecret() -> String {
        Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func createSeedAccount(_ name: String) async throws -> String {
        let response = try await api("POST", "/auth/device", body: [
            "name": name,
            "enabled": true,
            "device_name": "Seed",
            "registration_secret": registrationSecret()
        ])
        return try XCTUnwrap(response["access_token"] as? String)
    }

    private func createInvitationCode(label: String, direction: String = "share_mine", token: String) async throws -> String {
        let response = try await api("POST", "/invitations", token: token,
                                   body: ["direction": direction, "label": label])
        return try XCTUnwrap(response["code"] as? String)
    }

    private func checkInToday(token: String) async throws {
        let today = try await api("GET", "/me/checkin/today", token: token)
        let occurrence = try XCTUnwrap(today["id"] as? String)
        _ = try await api("POST", "/me/checkins", token: token,
                          body: [
                              "occurrence_id": occurrence,
                              "source": "app",
                              "client_action_at": ISO8601DateFormatter().string(from: Date())
                          ],
                          idempotencyKey: UUID().uuidString)
    }

    private func approvePendingInvitations(token: String) async throws {
        let list = try await api("GET", "/invitations", token: token)
        for item in (list["items"] as? [[String: Any]]) ?? [] where item["status"] as? String == "awaiting_approval" {
            let id = try XCTUnwrap(item["id"] as? String)
            _ = try await api("POST", "/invitations/\(id)/approve-sharing", token: token)
        }
    }

    // MARK: - UI helpers

    private func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for key in ["return", "Return", "Tamam", "Done", "enter", "Enter", "go", "Go"] {
            let button = keyboard.buttons[key]
            if button.exists { button.tap(); return }
        }
        app.swipeDown()
    }

    /// Dismisses system permission dialogs and in-app info/error alerts.
    /// Only call on tab-root screens: the nudge swipe could pop a pushed view.
    @MainActor
    private func settlePrompts(in app: XCUIApplication, seconds: TimeInterval = 6) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(seconds)
        var quietPasses = 0
        while Date() < deadline, quietPasses < 2 {
            var acted = false
            for title in ["İzin Ver", "Allow", "Allow Once", "Allow While Using App"] {
                for button in [springboard.buttons[title], springboard.alerts.buttons[title]] {
                    if button.exists { button.tap(); acted = true }
                }
            }
            for name in ["Bilgilendirme", "İşlem tamamlanamadı"] {
                for title in ["Tamam", "OK"] {
                    let button = app.alerts[name].buttons[title]
                    if button.exists { button.tap(); acted = true }
                }
            }
            if acted {
                quietPasses = 0
            } else {
                quietPasses += 1
                app.swipeRight()
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        if app.state != .runningForeground { app.activate() }
    }

    private func pullToRefresh(in app: XCUIApplication) {
        let scrollable: XCUIElement = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : (app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app)
        let cell = scrollable.cells.firstMatch
        (cell.exists ? cell : scrollable).swipeDown()
    }

    /// iPadOS renders TabView items as floating bar cells outside `app.tabBars`;
    /// tap whichever element is actually hittable.
    @MainActor
    private func tapTab(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 15) {
        let match = NSPredicate(format: "identifier == %@ OR label == %@", name, name)
        let queries = [app.tabBars.buttons.matching(match),
                       app.buttons.matching(match),
                       app.cells.matching(match)]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in queries {
                for element in query.allElementsBoundByIndex where element.exists && element.isHittable {
                    element.tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("tab '\(name)' not found")
    }

    /// List row links may surface as Button, Cell or Other depending on platform.
    @MainActor
    private func tapLabeled(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let match = NSPredicate(format: "identifier == %@ OR label == %@", label, label)
        let queries = [app.buttons.matching(match),
                       app.cells.matching(match),
                       app.staticTexts.matching(match),
                       app.otherElements.matching(match)]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in queries {
                for element in query.allElementsBoundByIndex where element.exists && element.isHittable {
                    element.tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(queries[0].firstMatch.waitForExistence(timeout: 2), "element '\(label)' not found")
        queries[0].firstMatch.tap()
    }

    @MainActor
    private func acceptInvitation(code: String, resultPrefix: String, in app: XCUIApplication) throws {
        tapLabeled("Davet kodum var", in: app)
        let input = app.textFields["invitationInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText(code)
        dismissKeyboard(in: app)
        let preview = app.buttons["Daveti görüntüle"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        if !preview.isHittable { app.collectionViews.firstMatch.swipeUp() }
        preview.tap()
        let accept = app.buttons["Kabul ediyorum"]
        XCTAssertTrue(accept.waitForExistence(timeout: 30))
        if !accept.isHittable { app.collectionViews.firstMatch.swipeUp() }
        accept.tap()
        let confirmed = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", resultPrefix))
            .firstMatch
        XCTAssertTrue(confirmed.waitForExistence(timeout: 30))
        let back = app.navigationBars.buttons["Ailem"]
        if back.exists { back.tap() }
        else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
    }

    /// invitationCode sits on a selectable Text (not a staticText), so query
    /// any element type; fall back to matching the XXXX-XXXX-XXXX pattern.
    /// The row may be below the fold — scroll the form and retry.
    @MainActor
    private func invitationCodeValue(in app: XCUIApplication) -> String {
        let pattern = #"^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$"#
        for _ in 0 ..< 5 {
            let element = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", "invitationCode"))
                .firstMatch
            if element.exists {
                if !element.label.isEmpty { return element.label }
                if let value = element.value as? String, !value.isEmpty { return value }
            }
            for query in [app.staticTexts, app.textViews] {
                for el in query.allElementsBoundByIndex {
                    let text = el.label.isEmpty ? (el.value as? String ?? "") : el.label
                    if text.range(of: pattern, options: .regularExpression) != nil {
                        return text
                    }
                }
            }
            if app.collectionViews.firstMatch.exists {
                app.collectionViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
            Thread.sleep(forTimeInterval: 0.6)
        }
        return ""
    }

    /// Settings → data rights → delete the signed-in account; back at welcome.
    @MainActor
    private func deleteAccountThroughUI(in app: XCUIApplication) {
        tapTab("Ayarlar", in: app)
        // The Ayarlar tab may still sit on a pushed detail screen — pop to root.
        let navBack = app.navigationBars.buttons["Ayarlar"]
        if navBack.waitForExistence(timeout: 5) { navBack.tap() }
        tapLabeled("Verilerim ve hesap silme", in: app)
        if !app.buttons["Hesabımı sil"].exists {
            app.collectionViews.firstMatch.swipeUp()
        }
        tapLabeled("Hesabımı sil", in: app)
        var confirmDelete = app.buttons["Hesabımı kalıcı olarak sil"]
        if !confirmDelete.waitForExistence(timeout: 10) {
            confirmDelete = app.sheets.buttons["Hesabımı kalıcı olarak sil"]
            XCTAssertTrue(confirmDelete.waitForExistence(timeout: 10))
        }
        confirmDelete.tap()
        XCTAssertTrue(app.textFields["nameField"].waitForExistence(timeout: 30))
    }

    // MARK: - Tests

    @MainActor
    func testCaptureStoreScreenshots() async throws {
        // Seed family data over HTTP before the app launches (reused across
        // runs via HY_SEED_*_AT env vars when available).
        let seeds = try await seedAccounts()
        let fatmaToken = seeds.fatma
        let mehmetToken = seeds.mehmet
        seedTokens = [fatmaToken, mehmetToken]
        let fatmaCode = try await createInvitationCode(label: "Kızım", token: fatmaToken)
        let mehmetCode = try await createInvitationCode(label: "Kardeşim", token: mehmetToken)
        try await checkInToday(token: fatmaToken)

        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean", "--uitest-premium"]
        app.launch()

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        save("01-giris", in: app)

        name.tap()
        name.typeText("Ayşe")
        dismissKeyboard(in: app)
        app.buttons["createAccount"].tap()

        // An alert stalls existence queries — dismiss prompts before waiting.
        settlePrompts(in: app, seconds: 10)
        let checkin = app.buttons["checkInButton"]
        XCTAssertTrue(checkin.waitForExistence(timeout: 60))
        settlePrompts(in: app, seconds: 4)
        XCTAssertTrue(checkin.exists)
        save("02-ana-ekran", in: app)

        tapTab("Ailem", in: app)
        try acceptInvitation(code: fatmaCode, resultPrefix: "Kabulünüz alındı", in: app)
        try acceptInvitation(code: mehmetCode, resultPrefix: "Kabulünüz alındı", in: app)

        try await approvePendingInvitations(token: fatmaToken)
        try await approvePendingInvitations(token: mehmetToken)

        let fatmaRow = app.staticTexts["Fatma"]
        let mehmetRow = app.staticTexts["Mehmet"]
        if !fatmaRow.waitForExistence(timeout: 15) {
            pullToRefresh(in: app)
            _ = fatmaRow.waitForExistence(timeout: 15)
        }
        if !fatmaRow.exists {
            tapTab("Bugün", in: app)
            tapTab("Ailem", in: app)
            pullToRefresh(in: app)
            _ = fatmaRow.waitForExistence(timeout: 15)
        }
        XCTAssertTrue(fatmaRow.exists)
        XCTAssertTrue(mehmetRow.waitForExistence(timeout: 15))

        // Ayşe creates her own share_mine invitation — Fatma accepts it over
        // HTTP, Ayşe approves in UI — so she gains a trusted contact.
        for _ in 0 ..< 3 { app.swipeDown() }
        tapLabeled("Yakınımı davet et", in: app)
        let create = app.buttons["Davet oluştur"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        XCTAssertTrue(app.images["invitationQR"].waitForExistence(timeout: 30))
        if !app.images["invitationQR"].isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        save("05-davet", in: app)
        let ayseCode = invitationCodeValue(in: app)
        XCTAssertFalse(ayseCode.isEmpty, "could not read the invitation code")

        let preview = try await api("POST", "/invitations/preview", token: fatmaToken, body: ["code": ayseCode])
        let ayseInviteId = try XCTUnwrap(preview["id"] as? String)
        _ = try await api("POST", "/invitations/\(ayseInviteId)/accept", token: fatmaToken, body: ["code": ayseCode])

        let back = app.navigationBars.buttons["Ailem"]
        if back.exists { back.tap() }
        pullToRefresh(in: app)
        let approve = app.buttons["Paylaşımı onayla"]
        XCTAssertTrue(approve.waitForExistence(timeout: 30))
        approve.tap()
        for _ in 0 ..< 30 where approve.exists { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertFalse(approve.exists, "invitation approval did not complete")

        // "Benim haberimi alanlar" must now list Fatma (subject = Ayşe).
        pullToRefresh(in: app)
        let viewersHeader = app.staticTexts["Benim haberimi alanlar"]
        let fatmaCells = app.staticTexts.matching(NSPredicate(format: "label == %@", "Fatma"))
        var fatmaCount = 0
        for _ in 0 ..< 6 {
            if viewersHeader.isHittable { fatmaCount = fatmaCells.count }
            if viewersHeader.isHittable, fatmaCount >= 2 { break }
            app.collectionViews.firstMatch.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(viewersHeader.exists)
        XCTAssertGreaterThanOrEqual(fatmaCount, 2,
                                    "Fatma should appear in Yakınlarım and Benim haberimi alanlar")
        save("04-ailem", in: app)

        tapTab("Ayarlar", in: app)
        tapLabeled("Kontrol saati", in: app)
        XCTAssertTrue(app.buttons["Programı kaydet"].waitForExistence(timeout: 15))
        save("06-kontrol-saati", in: app)

        tapTab("Bugün", in: app)
        // Reload today's card so trustedContacts sees the new link — pull to
        // refresh, and background+foreground to force the scenePhase reload.
        pullToRefresh(in: app)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        app.activate()
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(checkin.waitForExistence(timeout: 15))
        checkin.tap()
        XCTAssertTrue(app.staticTexts["Bugün haber verdiniz."].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Aileniz uygulamada iyi olduğunuzu görebilir."].exists)
        save("03-haber-verildi", in: app)

        // Remove Ayşe's synthetic account through the UI — back to welcome.
        deleteAccountThroughUI(in: app)
    }

    @MainActor
    func testCapturePaywall() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-clean", "--uitest-signed-in"]
        app.launch()

        tapTab("Ailem", in: app)
        settlePrompts(in: app, seconds: 5)
        let banner = app.buttons["premiumBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        _ = app.buttons["subscribeButton"].waitForExistence(timeout: 10)
        save("07-premium", in: app)
    }
}
