import XCTest
@testable import HerseyYolunda

final class IntentIntegrationTests: XCTestCase {
    @MainActor
    func testWidgetIntentRefreshesYesterdayAndCompletesExactlyOnce() async throws {
        let api = APIClient.shared
        try await api.forgetSession()
        try await api.createAccount(name: "Widget integration test", enabled: true)
        let profile: Profile = try await api.request("GET", "/me")
        addTeardownBlock {
            let _: EmptyResponse = try await api.request("DELETE", "/me", body: ["confirmation": "HESABIMI SİL"], expectedUser: profile.id)
            try await api.forgetSession()
        }
        let today: Today = try await api.request("GET", "/me/checkin/today")
        let yesterday = Today(id: UUID().uuidString, userId: profile.id, localDate: DateText.day(Date().addingTimeInterval(-86400)), state: "completed", dueAt: today.dueAt.addingTimeInterval(-86400), deadlineAt: today.deadlineAt.addingTimeInterval(-86400), closesAt: today.closesAt.addingTimeInterval(-86400), completedAt: Date().addingTimeInterval(-86400), nextDueAt: today.dueAt, trustedContacts: 0, serverTime: Date().addingTimeInterval(-86400))
        SharedStorage.saveSnapshot(profile: profile, today: yesterday)
        XCTAssertFalse(SharedStorage.snapshot()!.today.isCurrent())
        _ = try await CheckInIntent().perform()
        _ = try await CheckInIntent().perform()
        let result: Today = try await api.request("GET", "/me/checkin/today")
        XCTAssertEqual(result.id, today.id)
        XCTAssertEqual(result.state, "completed")
        XCTAssertTrue(SharedStorage.snapshot()!.today.isCurrent())
        let history: Items<HistoryItem> = try await api.request("GET", "/profiles/\(profile.id)/checkins")
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.source, "ios_widget")
    }
}
