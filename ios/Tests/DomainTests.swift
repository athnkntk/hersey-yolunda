import XCTest
@testable import HerseyYolunda

final class DomainTests: XCTestCase {
    func testIstanbulDayBoundary() {
        let date = ISO8601DateFormatter().date(from: "2026-09-15T21:01:00Z")!
        XCTAssertEqual(DateText.day(date), "2026-09-16")
    }
    func testPreviousDayNeverLooksCompletedToday() throws {
        let json = """
        {"id":"a","user_id":"u","local_date":"2026-09-15","state":"completed","due_at":"2026-09-15T06:00:00.000Z","deadline_at":"2026-09-15T10:00:00Z","closes_at":"2026-09-15T21:00:00Z","completed_at":"2026-09-15T06:04:00Z","next_due_at":"2026-09-16T06:00:00Z","trusted_contacts":2,"server_time":"2026-09-15T06:04:00Z"}
        """
        let value = try APIClient.decoder().decode(Today.self, from: Data(json.utf8))
        XCTAssertTrue(value.isCurrent(at: ISO8601DateFormatter().date(from: "2026-09-15T10:00:00Z")!))
        XCTAssertFalse(value.isCurrent(at: ISO8601DateFormatter().date(from: "2026-09-15T21:01:00Z")!))
    }
    func testSessionDecodesWithoutPersistingBackendFieldNames() throws {
        let data = Data("{\"access_token\":\"a\",\"refresh_token\":\"b\",\"user_id\":\"u\",\"expires_in\":900}".utf8)
        let auth = try APIClient.decoder().decode(AuthSession.self, from: data)
        let stored = StoredSession(auth: auth, expiresAt: Date().addingTimeInterval(900))
        let restored = try JSONDecoder().decode(StoredSession.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(restored.auth.userId, "u")
        XCTAssertEqual(restored.auth.refreshToken, "b")
    }
    func testPendingRequestPreservesIdempotencyAcrossRetry() throws {
        let pending = PendingCheckIn(userId: "u", occurrenceId: "o", key: UUID().uuidString, source: "ios_widget", actionAt: Date())
        let restored = try JSONDecoder().decode(PendingCheckIn.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(restored.key, pending.key)
        XCTAssertEqual(restored.source, "ios_widget")
    }
}
