import XCTest
import StoreKit
@testable import HerseyYolunda

final class DomainTests: XCTestCase {
    private let iso = ISO8601DateFormatter()
    private func at(_ value: String) -> Date { iso.date(from: value)! }

    private func makeToday(localDate: String = "2026-10-20", state: String = "due", timezone: String? = "Europe/Istanbul",
                           userID: String = "u", serverTime: String = "2026-10-20T06:05:00Z",
                           remindersEnabled: Bool? = true, nextMinute: Int? = 540, nextGrace: Int? = 240,
                           startsAt: String? = "2026-10-19T21:00:00Z", dueAt: String = "2026-10-20T06:00:00Z",
                           deadlineAt: String = "2026-10-20T10:00:00Z", closesAt: String = "2026-10-20T21:00:00Z",
                           nextDueAt: String = "2026-10-21T06:00:00Z", trusted: Int = 1) throws -> Today {
        var json = """
        {"id":"a","user_id":"\(userID)","local_date":"\(localDate)","state":"\(state)","due_at":"\(dueAt)","deadline_at":"\(deadlineAt)","closes_at":"\(closesAt)","next_due_at":"\(nextDueAt)","trusted_contacts":\(trusted),"server_time":"\(serverTime)"
        """
        if let timezone { json += ",\"timezone\":\"\(timezone)\"" }
        if let remindersEnabled { json += ",\"reminders_enabled\":\(remindersEnabled)" }
        if let nextMinute { json += ",\"next_schedule_minute\":\(nextMinute)" }
        if let nextGrace { json += ",\"next_grace_minutes\":\(nextGrace)" }
        if let startsAt { json += ",\"starts_at\":\"\(startsAt)\"" }
        json += "}"
        return try APIClient.decoder().decode(Today.self, from: Data(json.utf8))
    }

    func testIstanbulDayBoundary() {
        let date = at("2026-09-15T21:01:00Z")
        XCTAssertEqual(DateText.day(date, timeZone: TimeZone(identifier: "Europe/Istanbul")!), "2026-09-16")
    }
    func testDayRangesLosAngelesVersusIstanbul() {
        let instant = at("2026-09-15T21:01:00Z")
        XCTAssertEqual(DateText.day(instant, timeZone: TimeZone(identifier: "Europe/Istanbul")!), "2026-09-16")
        XCTAssertEqual(DateText.day(instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "2026-09-15")
    }
    func testOccurrenceRangeIsStartInclusiveAndEndExclusive() throws {
        let today = try makeToday()
        XCTAssertTrue(today.isCurrent(at: at("2026-10-19T21:00:00Z")))
        XCTAssertFalse(today.isCurrent(at: at("2026-10-19T20:59:59Z")))
        XCTAssertTrue(today.isCurrent(at: at("2026-10-20T20:59:59Z")))
        XCTAssertFalse(today.isCurrent(at: at("2026-10-20T21:00:00Z")))
    }
    func testLegacyTodayDecodesAndUsesLocalDateFallback() throws {
        let json = """
        {"id":"a","user_id":"u","local_date":"2026-09-16","state":"completed","due_at":"2026-09-16T06:00:00.000Z","deadline_at":"2026-09-16T10:00:00Z","closes_at":"2026-09-16T21:00:00Z","completed_at":"2026-09-16T06:04:00Z","next_due_at":"2026-09-17T06:00:00Z","trusted_contacts":2,"server_time":"2026-09-16T06:04:00Z"}
        """
        let value = try APIClient.decoder().decode(Today.self, from: Data(json.utf8))
        XCTAssertNil(value.timezone)
        XCTAssertNil(value.startsAt)
        XCTAssertTrue(value.isCurrent(at: at("2026-09-16T10:00:00Z")))
        XCTAssertFalse(value.isCurrent(at: at("2026-09-15T20:00:00Z")))
        XCTAssertFalse(value.isCurrent(at: at("2026-09-16T21:01:00Z")))
    }
    func testExplicitZoneAndEnglishLocaleFormatting() {
        let instant = at("2026-09-15T21:01:00Z")
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(DateText.time(instant, timeZone: losAngeles, locale: Locale(identifier: "en_US")), "2:01 PM")
        XCTAssertEqual(DateText.time(instant, timeZone: losAngeles, locale: Locale(identifier: "tr_TR")), "14:01")
    }
    func testLANHostAllowsLocalNamesAndPrivateRangesOnly() {
        XCTAssertTrue(APIClient.isLANHost("Atahan-MacBook-Air.local"))
        XCTAssertTrue(APIClient.isLANHost("localhost"))
        XCTAssertTrue(APIClient.isLANHost("127.0.0.1"))
        XCTAssertTrue(APIClient.isLANHost("192.168.1.7"))
        XCTAssertTrue(APIClient.isLANHost("10.23.17.172"))
        XCTAssertFalse(APIClient.isLANHost("example.com"))
        XCTAssertFalse(APIClient.isLANHost("evil.local.attacker.com"))
        XCTAssertFalse(APIClient.isLANHost(nil))
        XCTAssertFalse(APIClient.isLANHost("999.999.999.999"))
    }
    func testSessionDecodesWithoutPersistingBackendFieldNames() throws {
        let data = Data("{\"access_token\":\"a\",\"refresh_token\":\"b\",\"user_id\":\"u\",\"expires_in\":900}".utf8)
        let auth = try APIClient.decoder().decode(AuthSession.self, from: data)
        let stored = StoredSession(auth: auth, expiresAt: Date().addingTimeInterval(900))
        let restored = try JSONDecoder().decode(StoredSession.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(restored.auth.userId, "u")
        XCTAssertEqual(restored.auth.refreshToken, "b")
        XCTAssertNil(restored.refreshRequestID)
    }
    func testPendingRequestPreservesIdempotencyAcrossRetry() throws {
        let pending = PendingCheckIn(userId: "u", occurrenceId: "o", key: UUID().uuidString, source: "ios_widget", actionAt: Date())
        let restored = try JSONDecoder().decode(PendingCheckIn.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(restored.key, pending.key)
        XCTAssertEqual(restored.source, "ios_widget")
    }
    func testHealthDecodesPushConfiguredFlag() throws {
        let on = Data("{\"status\":\"ok\",\"mode\":\"production\",\"push_configured\":true,\"sms_configured\":false}".utf8)
        let off = Data("{\"status\":\"ok\",\"mode\":\"production\",\"push_configured\":false,\"sms_configured\":false}".utf8)
        XCTAssertTrue(try APIClient.decoder().decode(Health.self, from: on).pushConfigured)
        XCTAssertFalse(try APIClient.decoder().decode(Health.self, from: off).pushConfigured)
    }
    func testReminderIdentifiersAreRecognised() {
        XCTAssertTrue(LocalNotifications.isReminder(identifier: LocalNotifications.reminderIDs[3]))
        XCTAssertTrue(LocalNotifications.isReminder(identifier: "hy.reminder.day4.step2"))
        XCTAssertFalse(LocalNotifications.isReminder(identifier: "hy.remote.event"))
    }
    func testScheduleMustFitInsideOneDay() {
        XCTAssertTrue(Schedule.fitsInDay(minute: 540, grace: 240))
        XCTAssertTrue(Schedule.fitsInDay(minute: 1199, grace: 240))
        XCTAssertFalse(Schedule.fitsInDay(minute: 1200, grace: 240))
        XCTAssertFalse(Schedule.fitsInDay(minute: 1380, grace: 240))
    }
    func testReviewPromptTiming() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(completedCount: 0))
        XCTAssertFalse(ReviewPrompt.shouldAsk(completedCount: 2))
        XCTAssertTrue(ReviewPrompt.shouldAsk(completedCount: 3))
        XCTAssertFalse(ReviewPrompt.shouldAsk(completedCount: 4))
        XCTAssertFalse(ReviewPrompt.shouldAsk(completedCount: 24))
        XCTAssertTrue(ReviewPrompt.shouldAsk(completedCount: 25))
        XCTAssertTrue(ReviewPrompt.shouldAsk(completedCount: 50))
    }

    func testLanguageResolution() {
        XCTAssertEqual(L10n.resolvedLanguage(preference: .system, preferredLanguages: ["tr-TR"]), "tr")
        XCTAssertEqual(L10n.resolvedLanguage(preference: .system, preferredLanguages: ["tr_TR"]), "tr")
        XCTAssertEqual(L10n.resolvedLanguage(preference: .system, preferredLanguages: ["en-US"]), "en")
        XCTAssertEqual(L10n.resolvedLanguage(preference: .system, preferredLanguages: ["fr-FR", "tr-TR"]), "tr")
        XCTAssertEqual(L10n.resolvedLanguage(preference: .system, preferredLanguages: ["fr-FR", "de-DE"]), "en")
        XCTAssertEqual(L10n.resolvedLanguage(preference: .system, preferredLanguages: []), "en")
        XCTAssertEqual(L10n.resolvedLanguage(preference: .tr, preferredLanguages: ["en-US"]), "tr")
        XCTAssertEqual(L10n.resolvedLanguage(preference: .en, preferredLanguages: ["tr-TR"]), "en")
    }
    private func catalog(_ language: String) -> [String: String] {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else { return [:] }
        let url = URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String] ?? [:]
    }
    func testCatalogsHaveIdenticalKeySetsAndNonEmptyTranslations() {
        let tr = catalog("tr"), en = catalog("en")
        XCTAssertFalse(tr.isEmpty, "Turkish catalog missing from bundle")
        XCTAssertFalse(en.isEmpty, "English catalog missing from bundle")
        XCTAssertEqual(Set(tr.keys), Set(en.keys))
        for (key, value) in en { XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "Empty English value for \(key)") }
        for (key, value) in tr { XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "Empty Turkish value for \(key)") }
    }
    private func placeholders(_ value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(\\d+\\$)?[@df]")
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
    }
    func testFormatPlaceholderTypesAndCountsMatch() {
        let tr = catalog("tr"), en = catalog("en")
        for key in tr.keys {
            XCTAssertEqual(placeholders(tr[key]!).sorted(), placeholders(en[key]!).sorted(), "Placeholder mismatch for \(key)")
        }
    }
    func testEnglishAnchorsAndTurkishOriginals() {
        XCTAssertEqual(L10n.text("BEN İYİYİM", language: "en"), "I'M OK")
        XCTAssertEqual(L10n.text("Bugün", language: "en"), "Today")
        XCTAssertEqual(L10n.text("Ailem", language: "en"), "Family")
        XCTAssertEqual(L10n.text("Ayarlar", language: "en"), "Settings")
        XCTAssertEqual(L10n.text("Bilgilendirme", language: "en"), "Information")
        XCTAssertEqual(L10n.text("Tamam", language: "en"), "OK")
        XCTAssertEqual(L10n.text("Vazgeç", language: "en"), "Cancel")
        XCTAssertEqual(L10n.text("Yeniden dene", language: "en"), "Try again")
        XCTAssertEqual(L10n.text("Gönderiliyor", language: "en"), "Sending")
        XCTAssertEqual(L10n.text("Bir adımla başlayın.", language: "en"), "Start with one simple step.")
        XCTAssertEqual(L10n.text("Hesabımı oluştur", language: "en"), "Create my account")
        XCTAssertEqual(L10n.text("Kontrol saati", language: "en"), "Check-in schedule")
        XCTAssertEqual(L10n.text("Programı kaydet", language: "en"), "Save schedule")
        XCTAssertEqual(L10n.text("Oğlum", language: "en"), "Son")
        XCTAssertEqual(L10n.text("Yakınım", language: "en"), "Relative")
        XCTAssertEqual(L10n.text("unauthorized", language: "en"), "Your session is no longer available. Open the app to continue.")
        XCTAssertEqual(L10n.text("BEN İYİYİM", language: "tr"), "BEN İYİYİM")
        XCTAssertEqual(L10n.text("Bugün", language: "tr"), "Bugün")
        XCTAssertEqual(L10n.text("Yakınım", language: "tr"), "Yakınım")
        XCTAssertEqual(L10n.text("Bilgilendirme", language: "tr"), "Bilgilendirme")
    }
    func testGreetingUsesDecodedNewlineAndResolvesPerLanguage() {
        let prior = SharedStorage.defaults.string(forKey: L10n.preferenceKey)
        defer {
            if let prior { SharedStorage.defaults.set(prior, forKey: L10n.preferenceKey) }
            else { SharedStorage.defaults.removeObject(forKey: L10n.preferenceKey) }
        }
        SharedStorage.defaults.set("en", forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.format("Merhaba,\n%@", "Sarah"), "Hello,\nSarah")
        SharedStorage.defaults.set("tr", forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.format("Merhaba,\n%@", "Sarah"), "Merhaba,\nSarah")
    }

    func testServerClockAnchorHandlesSkewedDeviceClock() {
        let server = at("2026-10-15T10:00:00Z")
        let skewedDevice = server.addingTimeInterval(3 * 3600)
        ServerClock.record(server, deviceNow: skewedDevice, uptime: 1000)
        defer { ServerClock.clear() }
        let estimate = ServerClock.now(deviceNow: skewedDevice.addingTimeInterval(60), uptime: 1060)
        XCTAssertEqual(estimate?.timeIntervalSince(server) ?? -1, 60, accuracy: 0.001)
    }
    func testServerClockRejectsUnreliableAnchors() {
        let server = at("2026-10-15T10:00:00Z")
        let anchor = ServerTimeAnchor(serverTime: server, recordedAt: server, uptime: 1000)
        XCTAssertNotNil(anchor.estimate(deviceNow: server.addingTimeInterval(30), uptime: 1030))
        XCTAssertNil(anchor.estimate(deviceNow: server.addingTimeInterval(3 * 3600), uptime: 1030), "wall-clock jump must reject")
        XCTAssertNil(anchor.estimate(deviceNow: server.addingTimeInterval(10), uptime: 500), "reboot (uptime decrease) must reject")
        XCTAssertNil(anchor.estimate(deviceNow: server.addingTimeInterval(37 * 3600), uptime: 1000 + 37 * 3600), "anchor older than 36h must reject")
    }

    func testReminderPlanCompletedTodayStillSchedulesTomorrow() throws {
        let now = at("2026-10-20T07:00:00Z")
        for state in ["completed", "cancelled", "overdue"] {
            let today = try makeToday(state: state)
            let plan = LocalNotifications.plan(today: today, enabled: true, now: now)
            XCTAssertFalse(plan.contains { $0.id.contains("day0") }, "state \(state) must not schedule today")
            XCTAssertTrue(plan.contains { $0.id == "hy.reminder.day1.step0" && $0.fireAt == at("2026-10-21T06:00:00Z") })
            XCTAssertLessThanOrEqual(plan.count, 32)
        }
    }
    func testReminderPlanDueTodayAndDisabled() throws {
        let now = at("2026-10-20T05:00:00Z")
        let today = try makeToday(state: "due")
        let plan = LocalNotifications.plan(today: today, enabled: true, now: now)
        XCTAssertTrue(plan.contains { $0.id == "hy.reminder.day0.step0" && $0.fireAt == today.dueAt })
        XCTAssertTrue(plan.contains { $0.id == "hy.reminder.day0.step3" && $0.fireAt == today.deadlineAt })
        XCTAssertLessThanOrEqual(plan.count, 32)
        XCTAssertTrue(LocalNotifications.plan(today: today, enabled: false, now: now).isEmpty)
    }
    func testReminderPlanLateOnboardingSkipsTodayButKeepsFuture() throws {
        let now = at("2026-10-20T05:00:00Z")
        let today = try makeToday(state: "due", remindersEnabled: false)
        let plan = LocalNotifications.plan(today: today, enabled: true, now: now)
        XCTAssertFalse(plan.contains { $0.id.contains("day0") })
        XCTAssertTrue(plan.contains { $0.id == "hy.reminder.day1.step0" })
    }
    func testReminderPlanWithoutNextScheduleOnlyPlansTomorrowDue() throws {
        let now = at("2026-10-20T05:00:00Z")
        let today = try makeToday(state: "completed", nextMinute: nil, nextGrace: nil)
        let plan = LocalNotifications.plan(today: today, enabled: true, now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireAt, at("2026-10-21T06:00:00Z"))
    }
    func testReminderPlanDSTMarchGapAndNovemberRepeat() throws {
        let gap = try makeToday(localDate: "2026-03-06", state: "completed", timezone: "America/New_York",
                                nextMinute: 150, nextGrace: 240, startsAt: "2026-03-06T05:00:00Z",
                                dueAt: "2026-03-06T14:30:00Z", deadlineAt: "2026-03-06T18:30:00Z",
                                closesAt: "2026-03-07T05:00:00Z", nextDueAt: "2026-03-07T15:00:00Z")
        let gapPlan = LocalNotifications.plan(today: gap, enabled: true, now: at("2026-03-06T06:00:00Z"))
        XCTAssertEqual(gapPlan.first { $0.id == "hy.reminder.day2.step0" }?.fireAt, at("2026-03-08T07:30:00Z"), "02:30 gap must resolve to 03:30 EDT")

        let repeated = try makeToday(localDate: "2026-10-30", state: "completed", timezone: "America/New_York",
                                   nextMinute: 90, nextGrace: 240, startsAt: "2026-10-30T04:00:00Z",
                                   dueAt: "2026-10-30T13:30:00Z", deadlineAt: "2026-10-30T17:30:00Z",
                                   closesAt: "2026-10-31T04:00:00Z", nextDueAt: "2026-10-31T14:30:00Z")
        let repeatPlan = LocalNotifications.plan(today: repeated, enabled: true, now: at("2026-10-30T05:00:00Z"))
        XCTAssertEqual(repeatPlan.first { $0.id == "hy.reminder.day2.step0" }?.fireAt, at("2026-11-01T06:30:00Z"), "01:30 repeat must use the second (standard-time) occurrence")
        XCTAssertLessThanOrEqual(repeatPlan.count, 32)
    }

    func testBillingTextSingularAndPlural() {
        XCTAssertEqual(BillingText.duration(value: 1, unit: .month, language: "en"), "1 month")
        XCTAssertEqual(BillingText.duration(value: 3, unit: .week, language: "en"), "3 weeks")
        XCTAssertEqual(BillingText.duration(value: 1, unit: .month, language: "tr"), "1 ay")
        XCTAssertEqual(BillingText.duration(value: 3, unit: .week, language: "tr"), "3 hafta")
    }
    func testBillingTextOfferPeriodCount() {
        XCTAssertEqual(BillingText.offerDuration(value: 1, count: 3, unit: .week, language: "en"), "3 weeks")
        XCTAssertEqual(BillingText.offerDuration(value: 2, count: 1, unit: .month, language: "en"), "2 months")
        XCTAssertEqual(BillingText.offerDuration(value: 1, count: 2, unit: .week, language: "tr"), "2 hafta")
    }
    func testNotificationStatusTextMapping() {
        XCTAssertEqual(NotificationStatusText.message("queued", language: "en"), "Recorded in the app")
        XCTAssertEqual(NotificationStatusText.message("provider_accepted", language: "en"), "Accepted for delivery")
        XCTAssertNotEqual(NotificationStatusText.message("provider_accepted", language: "en"), "Sent", "provider_accepted must not imply confirmed delivery")
        XCTAssertEqual(NotificationStatusText.message("sending", language: "en"), "Sending")
        XCTAssertEqual(NotificationStatusText.message("suppressed", language: "en"), "Hidden")
        XCTAssertEqual(NotificationStatusText.message("retryable_failed", language: "en"), "Retrying")
        XCTAssertEqual(NotificationStatusText.message("permanently_failed", language: "en"), "Could not be sent")
        XCTAssertEqual(NotificationStatusText.message("mystery_value", language: "en"), "Updating status")
        XCTAssertEqual(NotificationStatusText.message("queued", language: "tr"), "Uygulamada kayıtlı")
        XCTAssertEqual(NotificationStatusText.message("provider_accepted", language: "tr"), "İletim servisi kabul etti")
        XCTAssertEqual(NotificationStatusText.message("suppressed", language: "tr"), "Gizlendi")
    }

    func testEvaluationDateProjectsWidgetEntryDates() {
        let server = at("2026-10-15T10:00:00Z")
        let skewedDevice = server.addingTimeInterval(3 * 3600)
        ServerClock.record(server, deviceNow: skewedDevice, uptime: 1000)
        defer { ServerClock.clear() }
        let now = skewedDevice.addingTimeInterval(60)
        let current = ServerClock.evaluationDate(for: now, deviceNow: now, uptime: 1060)
        XCTAssertEqual(current?.timeIntervalSince(server) ?? -1, 60, accuracy: 0.001)
        let future = ServerClock.evaluationDate(for: now.addingTimeInterval(600), deviceNow: now, uptime: 1060)
        XCTAssertEqual(future?.timeIntervalSince(server) ?? -1, 660, accuracy: 0.001)
    }
    func testEvaluationDateRejectsUntrustedClock() {
        ServerClock.clear()
        XCTAssertNil(ServerClock.evaluationDate(for: Date()), "no anchor means no evaluation date")
        let server = at("2026-10-15T10:00:00Z")
        ServerClock.record(server, deviceNow: server, uptime: 1000)
        defer { ServerClock.clear() }
        let jumped = server.addingTimeInterval(40 * 3600)
        XCTAssertNil(ServerClock.evaluationDate(for: jumped.addingTimeInterval(300), deviceNow: jumped, uptime: 1000 + 40 * 3600), "anchors older than 36h must not project widget times")
        let skewed = server.addingTimeInterval(3 * 3600)
        XCTAssertNil(ServerClock.evaluationDate(for: skewed.addingTimeInterval(300), deviceNow: skewed, uptime: 1030), "wall-clock jump must not project widget times")
    }

    func testStalePendingCannotSupersedeCompleted() throws {
        let completed = try makeToday(state: "completed", serverTime: "2026-10-20T06:30:00Z")
        let staleDue = try makeToday(state: "due", serverTime: "2026-10-20T05:00:00Z")
        XCTAssertFalse(staleDue.supersedes(completed), "stale pending must never replace completed")
        let newerDue = try makeToday(state: "due", serverTime: "2026-10-20T08:00:00Z")
        XCTAssertFalse(newerDue.supersedes(completed), "a pending response can never un-complete an occurrence")
        let oldDay = try makeToday(localDate: "2026-10-19", state: "due", serverTime: "2026-10-20T01:00:00Z")
        XCTAssertFalse(oldDay.supersedes(completed), "older-day data must not replace newer data")
        let cancelled = try makeToday(state: "cancelled", serverTime: "2026-10-20T06:00:00Z")
        XCTAssertTrue(newerDue.supersedes(cancelled), "a valid newer resume response may replace cancelled")
        let otherUser = try makeToday(state: "due", userID: "v", serverTime: "2026-10-20T05:00:00Z")
        XCTAssertTrue(otherUser.supersedes(completed), "a different account's data replaces the old account's")
    }
    func testChooseSchedulePrefersNewerSameUserSnapshot() throws {
        SharedStorage.clear()
        try SharedStorage.save(AuthSession(accessToken: "a1", refreshToken: "r1", userId: "u", expiresIn: 900))
        defer { SharedStorage.clear() }
        let profile = try APIClient.decoder().decode(Profile.self, from: Data("{\"id\":\"u\",\"name\":\"T\",\"timezone\":\"Europe/Istanbul\",\"enabled\":true,\"schedule_minute\":540,\"grace_minutes\":240}".utf8))
        let stale = try makeToday(state: "due", serverTime: "2026-10-20T05:00:00Z")
        let completed = try makeToday(state: "completed", serverTime: "2026-10-20T06:30:00Z")
        SharedStorage.saveSnapshot(profile: profile, today: completed)
        let selected = LocalNotifications.chooseSchedule(today: stale, enabled: true, authorized: true, now: Date(), sessionUserID: "u")
        XCTAssertEqual(selected?.today.state, "completed", "the newer cached snapshot wins over a stale incoming response")
        XCTAssertNil(LocalNotifications.chooseSchedule(today: stale, enabled: true, authorized: true, now: Date(), sessionUserID: "v"), "another account's data must not schedule reminders")
        XCTAssertNil(LocalNotifications.chooseSchedule(today: stale, enabled: true, authorized: true, now: Date(), sessionUserID: nil), "no active session means no reminders")
        XCTAssertNil(LocalNotifications.chooseSchedule(today: stale, enabled: true, authorized: false, now: Date(), sessionUserID: "u"), "no notification permission means no reminders")
        XCTAssertNil(LocalNotifications.chooseSchedule(today: stale, enabled: true, authorized: true, now: nil, sessionUserID: "u"), "no trustworthy clock means no reminders")
    }
    func testScheduleRevisionIsMonotonic() {
        let first = LocalNotifications.nextScheduleRevision()
        let second = LocalNotifications.nextScheduleRevision()
        XCTAssertGreaterThan(second, first)
    }

    // --- Kurtarma anahtarı ---------------------------------------------------
    func testRecoveryKeyGeneratorProducesCanonical48CharacterKey() throws {
        let key = try RecoveryKey.generate()
        XCTAssertTrue(key.hasPrefix("HYR1."))
        XCTAssertEqual(key.count, 48)
        XCTAssertTrue(RecoveryKey.isValid(key))
        XCTAssertFalse(try RecoveryKey.generate() == key, "keys must be unique random values")
        // Davet bağlantısı belirteci (43 karakter) kurtarma anahtarı sayılmaz.
        let inviteToken = String(repeating: "a", count: 43)
        XCTAssertFalse(RecoveryKey.isValid(inviteToken))
        XCTAssertFalse(RecoveryKey.isValid("HYR1." + inviteToken.dropLast()), "truncated payload must fail")
        XCTAssertFalse(RecoveryKey.isValid(key.lowercased()), "case must be preserved")
        XCTAssertFalse(RecoveryKey.isValid(" " + key), "leading space inside isValid must fail")
        XCTAssertEqual(RecoveryKey.normalized("  \(key)\n"), key, "outer whitespace is trimmed")
        XCTAssertNil(RecoveryKey.normalized("AYŞE-1234"), "names are never recovery credentials")
        XCTAssertNil(RecoveryKey.normalized("HYR1." + String(repeating: "=", count: 43)), "padding characters are not valid payload")
    }
    func testPendingRecoveryRecordsPersistInKeychainNotDefaults() throws {
        SharedStorage.clearAccountRecovery()
        SharedStorage.clearRecoverySetup()
        defer { SharedStorage.clearAccountRecovery(); SharedStorage.clearRecoverySetup() }
        let recovery = PendingAccountRecovery(key: "HYR1." + String(repeating: "a", count: 43),
            replacementKey: "HYR1." + String(repeating: "b", count: 43), requestID: "req-1", deviceName: "iPhone / iPad")
        try SharedStorage.saveAccountRecovery(recovery)
        XCTAssertEqual(try SharedStorage.accountRecovery(), recovery, "pending recovery must round-trip through Keychain")
        XCTAssertNil(SharedStorage.defaults.data(forKey: "pending-account-recovery"), "recovery record must not live in UserDefaults")
        let setup = PendingRecoverySetup(userId: "u1", key: recovery.replacementKey, expectedVersion: 2)
        try SharedStorage.saveRecoverySetup(setup)
        XCTAssertEqual(try SharedStorage.recoverySetup(), setup)
        XCTAssertNil(SharedStorage.defaults.data(forKey: "pending-recovery-setup"))
    }
    func testRecoveryStatusDecodes() throws {
        let enabled = try APIClient.decoder().decode(RecoveryStatus.self, from: Data("{\"enabled\":true,\"version\":3,\"updated_at\":\"2026-10-20T05:00:00Z\"}".utf8))
        XCTAssertTrue(enabled.enabled)
        XCTAssertEqual(enabled.version, 3)
        XCTAssertNotNil(enabled.updatedAt)
        let disabled = try APIClient.decoder().decode(RecoveryStatus.self, from: Data("{\"enabled\":false,\"version\":0,\"updated_at\":null}".utf8))
        XCTAssertFalse(disabled.enabled)
        XCTAssertNil(disabled.updatedAt)
    }
}
