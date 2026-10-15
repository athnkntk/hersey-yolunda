import XCTest
@testable import HerseyYolunda

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Yanıt üretilmeden önce arka planda senkron çalışır; testler burada bekleyerek
    /// yanıt sıralamasını deterministik kontrol eder. Teslimat ayrı bir kuyrukta
    /// yapıldığı için bekleyen bir çağrı aynı oturumdaki diğerleri engellemez.
    static var onRequest: ((URLRequest) -> Void)?
    private let stoppedLock = NSLock()
    private var stoppedFlag = false
    private var stopped: Bool {
        get { stoppedLock.lock(); defer { stoppedLock.unlock() }; return stoppedFlag }
        set { stoppedLock.lock(); stoppedFlag = newValue; stoppedLock.unlock() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = self.request
        let handler = Self.handler
        let onRequest = Self.onRequest
        DispatchQueue.global().async {
            onRequest?(request)
            guard !self.stopped else { return }
            guard let handler else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                guard !self.stopped else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard !self.stopped else { return }
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    override func stopLoading() { stopped = true }
}

private func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: 1024)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }
    return data
}

final class TransportTests: XCTestCase {
    override func setUp() async throws {
        StubURLProtocol.handler = nil
        StubURLProtocol.onRequest = nil
        try await APIClient.shared.forgetSession()
        ServerClock.clear()
        SharedStorage.defaults.removeObject(forKey: L10n.preferenceKey)
    }
    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        StubURLProtocol.onRequest = nil
        try await APIClient.shared.forgetSession()
        ServerClock.clear()
        SharedStorage.defaults.removeObject(forKey: L10n.preferenceKey)
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.test/v1")!, session: URLSession(configuration: configuration))
    }
    private func response(_ request: URLRequest, _ status: Int, _ json: String, headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        var fields = ["Content-Type": "application/json"]
        for (key, value) in headers { fields[key] = value }
        return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!, Data(json.utf8))
    }
    private func saveSession(access: String = "a1", refresh: String = "r1", user: String = "u1", expiresIn: Int = 900) throws {
        try SharedStorage.save(AuthSession(accessToken: access, refreshToken: refresh, userId: user, expiresIn: expiresIn))
    }
    private static let profileJSON = "{\"id\":\"u1\",\"name\":\"Test\",\"timezone\":\"Europe/Istanbul\",\"enabled\":true,\"schedule_minute\":540,\"grace_minutes\":240}"
    private static let todayJSON = "{\"id\":\"o1\",\"user_id\":\"u1\",\"local_date\":\"2026-10-20\",\"state\":\"due\",\"due_at\":\"2026-10-20T06:00:00Z\",\"deadline_at\":\"2026-10-20T10:00:00Z\",\"closes_at\":\"2026-10-20T21:00:00Z\",\"completed_at\":null,\"next_due_at\":\"2026-10-21T06:00:00Z\",\"trusted_contacts\":0,\"server_time\":\"2026-10-20T05:00:00Z\",\"reminders_enabled\":true,\"timezone\":\"Europe/Istanbul\",\"starts_at\":\"2026-10-19T21:00:00Z\",\"next_schedule_minute\":540,\"next_grace_minutes\":240}"
    private static let refreshJSON = "{\"access_token\":\"a2\",\"refresh_token\":\"r2\",\"user_id\":\"u1\",\"expires_in\":900}"

    func testServerFailureIsNotSuccess() async {
        StubURLProtocol.handler = { request in self.response(request, 503, "{\"code\":\"unavailable\",\"message\":\"Henüz gönderilemedi\"}") }
        do {
            let _: Receipt = try await client().request("POST", "/me/checkins", authenticated: false)
            XCTFail("A failed request must never return a receipt")
        } catch let error as BackendError { XCTAssertEqual(error.code, "unavailable") }
        catch { XCTFail("Expected a typed backend error: \(error)") }
    }
    func testMalformedSuccessCannotBecomeCheckInReceipt() async {
        StubURLProtocol.handler = { request in self.response(request, 200, "{}") }
        do {
            let _: Receipt = try await client().request("POST", "/me/checkins", authenticated: false)
            XCTFail("Malformed success must not become a receipt")
        } catch { XCTAssertTrue(error is DecodingError) }
    }
    func testNonLocalPlainHTTPIsRejected() async {
        let unsafe = APIClient(baseURL: URL(string: "http://example.test/v1")!)
        do {
            let _: EmptyResponse = try await unsafe.request("GET", "/health", authenticated: false)
            XCTFail("Non-local plaintext is not allowed")
        } catch { XCTAssertTrue(error is LocalError) }
    }

    func testAcceptLanguageAndServerClockHeader() async throws {
        SharedStorage.defaults.set("en", forKey: L10n.preferenceKey)
        var seen: String?
        StubURLProtocol.handler = { request in
            seen = request.value(forHTTPHeaderField: "Accept-Language")
            return self.response(request, 200, "{\"status\":\"ok\",\"mode\":\"development\",\"push_configured\":false,\"sms_configured\":false}", headers: ["X-Server-Time": "2026-10-20T05:00:00Z"])
        }
        let _: Health = try await client().request("GET", "/health", authenticated: false)
        XCTAssertEqual(seen, "en")
        XCTAssertNotNil(ServerClock.now())
    }
    func testCheckInNeverOptimisticOn503OrOffline() async throws {
        SharedStorage.defaults.set("en", forKey: L10n.preferenceKey)
        ServerClock.record(at("2026-10-20T05:00:00Z"), deviceNow: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        try saveSession()
        let api = client()
        let profile: Profile = try APIClient.decoder().decode(Profile.self, from: Data(Self.profileJSON.utf8))
        let today: Today = try APIClient.decoder().decode(Today.self, from: Data(Self.todayJSON.utf8))
        StubURLProtocol.handler = { request in self.response(request, 503, "{\"code\":\"unavailable\",\"message\":\"Henüz gönderilemedi\"}") }
        do {
            _ = try await api.checkIn(profile: profile, today: today, source: "app")
            XCTFail("503 must not produce a completed check-in")
        } catch let error as BackendError { XCTAssertEqual(error.code, "unavailable") }
        catch { XCTFail("Expected backend error: \(error)") }
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await api.checkIn(profile: profile, today: today, source: "app")
            XCTFail("Offline must not produce a completed check-in")
        } catch { XCTAssertTrue(error is URLError || error is BackendError || error is LocalError) }
        XCTAssertNotNil(SharedStorage.pending(), "pending check-in key must be retained for the same retry")
    }
    private func at(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testFailedRefreshRetainsSessionAndRequestIDThenRetriesWithSameID() async throws {
        try saveSession(expiresIn: -60)
        var refreshCalls = 0
        var seenKeys: [String] = []
        var seenTokens: [String] = []
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") {
                refreshCalls += 1
                seenKeys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
                seenTokens.append(body?["refresh_token"] as? String ?? "")
                if refreshCalls == 1 { throw URLError(.timedOut) }
                return self.response(request, 200, Self.refreshJSON)
            }
            return self.response(request, 200, Self.profileJSON)
        }
        let api = client()
        do { let _: Profile = try await api.request("GET", "/me"); XCTFail("timeout should fail") }
        catch { XCTAssertTrue((error as? URLError)?.code == .timedOut || error is URLError) }
        let retained = try XCTUnwrap(try? SharedStorage.session())
        XCTAssertEqual(retained.auth.accessToken, "a1")
        let requestID = try XCTUnwrap(retained.refreshRequestID)
        let profile: Profile = try await api.request("GET", "/me")
        XCTAssertEqual(profile.id, "u1")
        XCTAssertEqual(seenKeys, [requestID, requestID], "retry must reuse the exact persisted request UUID")
        XCTAssertEqual(seenTokens, ["r1", "r1"], "retry must reuse the old refresh token")
        let updated = try XCTUnwrap(try? SharedStorage.session())
        XCTAssertEqual(updated.auth.accessToken, "a2")
        XCTAssertNil(updated.refreshRequestID)
    }
    func testConcurrentRequestsTriggerSingleRefresh() async throws {
        try saveSession(expiresIn: -60)
        var refreshCalls = 0
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") {
                refreshCalls += 1
                return self.response(request, 200, Self.refreshJSON)
            }
            return self.response(request, 200, Self.profileJSON)
        }
        let api = client()
        async let first: Profile = api.request("GET", "/me")
        async let second: Profile = api.request("GET", "/me")
        let results = try await [first, second]
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(refreshCalls, 1, "concurrent requests from the same expired session must refresh exactly once")
    }
    func testUnauthorizedAccessRetriesOnceWithRotatedToken() async throws {
        try saveSession()
        var meCalls = 0
        var refreshCalls = 0
        var seenBearer: [String] = []
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") {
                refreshCalls += 1
                return self.response(request, 200, Self.refreshJSON)
            }
            meCalls += 1
            seenBearer.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            if meCalls == 1 { return self.response(request, 401, "{\"code\":\"unauthorized\",\"message\":\"expired\"}") }
            return self.response(request, 200, Self.profileJSON)
        }
        let profile: Profile = try await client().request("GET", "/me")
        XCTAssertEqual(profile.id, "u1")
        XCTAssertEqual(meCalls, 2)
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(seenBearer.count, 2)
        XCTAssertNotEqual(seenBearer[0], seenBearer[1], "retry must send the rotated access token")
    }
    func testTerminalFailureClearsOnlyMatchingSession() async throws {
        try saveSession()
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") { return self.response(request, 200, Self.refreshJSON) }
            return self.response(request, 401, "{\"code\":\"unauthorized\",\"message\":\"revoked\"}")
        }
        do { let _: Profile = try await client().request("GET", "/me"); XCTFail("terminal unauthorized must fail") }
        catch let error as BackendError { XCTAssertEqual(error.code, "unauthorized") }
        catch { XCTFail("expected backend error") }
        XCTAssertNil(try? SharedStorage.session(), "matching session must be cleared")
    }
    func testOldAccountFailureCannotClearReplacementSession() async throws {
        try saveSession(access: "a1", refresh: "r1", user: "u1", expiresIn: -60)
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") {
                let replacement = AuthSession(accessToken: "b1", refreshToken: "b-r", userId: "u2", expiresIn: 900)
                try? SharedStorage.save(replacement)
                return self.response(request, 401, "{\"code\":\"session_reused\",\"message\":\"reused\"}")
            }
            return self.response(request, 200, Self.profileJSON)
        }
        do { let _: Profile = try await client().request("GET", "/me"); XCTFail("session_reused must fail") }
        catch let error as BackendError { XCTAssertEqual(error.code, "session_reused") }
        catch { XCTFail("expected backend error") }
        let current = try XCTUnwrap(try? SharedStorage.session())
        XCTAssertEqual(current.auth.userId, "u2", "the replacement account's session must survive the old account's failure")
    }

    private static let receiptJSON = "{\"checkin_id\":\"c1\",\"status\":\"completed\",\"received_at\":\"2026-10-20T05:10:00Z\",\"already_completed\":false}"
    func testCheckInSuccessClearsSameAccountWidgetFailureAndPending() async throws {
        ServerClock.record(at("2026-10-20T05:00:00Z"), deviceNow: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        try saveSession()
        let api = client()
        let profile: Profile = try APIClient.decoder().decode(Profile.self, from: Data(Self.profileJSON.utf8))
        let today: Today = try APIClient.decoder().decode(Today.self, from: Data(Self.todayJSON.utf8))
        SharedStorage.saveWidgetFailure(WidgetFailure(userId: "u1", code: "network_error"))
        SharedStorage.savePending(PendingCheckIn(userId: "u1", occurrenceId: "o1", key: "fixed-key", source: "app", actionAt: at("2026-10-20T05:00:00Z")))
        var seenKey: String?
        StubURLProtocol.handler = { request in
            seenKey = request.value(forHTTPHeaderField: "Idempotency-Key")
            return self.response(request, 200, Self.receiptJSON)
        }
        let updated = try await api.checkIn(profile: profile, today: today, source: "app")
        XCTAssertEqual(updated.state, "completed")
        XCTAssertEqual(seenKey, "fixed-key", "check-in must reuse the persisted pending idempotency key")
        XCTAssertNil(SharedStorage.widgetFailure(), "app-side success must clear the same account's widget failure")
        XCTAssertNil(SharedStorage.pending(), "a completed request must clear its matching pending action")
    }
    func testCheckInSuccessLeavesOtherAccountsPending() async throws {
        ServerClock.record(at("2026-10-20T05:00:00Z"), deviceNow: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        try saveSession()
        let api = client()
        let profile: Profile = try APIClient.decoder().decode(Profile.self, from: Data(Self.profileJSON.utf8))
        let today: Today = try APIClient.decoder().decode(Today.self, from: Data(Self.todayJSON.utf8))
        SharedStorage.savePending(PendingCheckIn(userId: "u2", occurrenceId: "o9", key: "other-key", source: "ios_widget", actionAt: Date()))
        StubURLProtocol.handler = { request in self.response(request, 200, Self.receiptJSON) }
        _ = try await api.checkIn(profile: profile, today: today, source: "app")
        XCTAssertEqual(SharedStorage.pending()?.key, "other-key", "a different account's pending action must not be cleared")
    }
    func testFailedCheckInKeepsSnapshotAndWidgetFailure() async throws {
        ServerClock.record(at("2026-10-20T05:00:00Z"), deviceNow: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        try saveSession()
        let api = client()
        let profile: Profile = try APIClient.decoder().decode(Profile.self, from: Data(Self.profileJSON.utf8))
        let today: Today = try APIClient.decoder().decode(Today.self, from: Data(Self.todayJSON.utf8))
        SharedStorage.saveWidgetFailure(WidgetFailure(userId: "u1", code: "network_error"))
        SharedStorage.saveSnapshot(profile: profile, today: today)
        StubURLProtocol.handler = { request in self.response(request, 503, "{\"code\":\"unavailable\",\"message\":\"Henüz gönderilemedi\"}") }
        do {
            _ = try await api.checkIn(profile: profile, today: today, source: "app")
            XCTFail("503 must not succeed")
        } catch let error as BackendError { XCTAssertEqual(error.code, "unavailable") }
        catch { XCTFail("Expected backend error: \(error)") }
        XCTAssertNotNil(SharedStorage.widgetFailure(), "a failed check-in must not clear the widget failure")
        XCTAssertEqual(SharedStorage.snapshot()?.today.state, "due", "a failed check-in must not mark the snapshot completed")
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    override func setUp() async throws {
        StubURLProtocol.handler = nil
        StubURLProtocol.onRequest = nil
        try await APIClient.shared.forgetSession()
        ServerClock.clear()
    }
    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        StubURLProtocol.onRequest = nil
        try await APIClient.shared.forgetSession()
        ServerClock.clear()
    }
    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.test/v1")!, session: URLSession(configuration: configuration))
    }
    private func response(_ request: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "X-Server-Time": "2026-10-20T05:00:00Z"])!, Data(json.utf8))
    }
    private func saveSession(expiresIn: Int = 900) throws {
        try SharedStorage.save(AuthSession(accessToken: "a1", refreshToken: "r1", userId: "u1", expiresIn: expiresIn))
    }
    private static let profileJSON = "{\"id\":\"u1\",\"name\":\"Test\",\"timezone\":\"Europe/Istanbul\",\"enabled\":true,\"schedule_minute\":540,\"grace_minutes\":240}"
    private static let todayJSON = "{\"id\":\"o1\",\"user_id\":\"u1\",\"local_date\":\"2026-10-20\",\"state\":\"due\",\"due_at\":\"2026-10-20T06:00:00Z\",\"deadline_at\":\"2026-10-20T10:00:00Z\",\"closes_at\":\"2026-10-20T21:00:00Z\",\"completed_at\":null,\"next_due_at\":\"2026-10-21T06:00:00Z\",\"trusted_contacts\":0,\"server_time\":\"2026-10-20T05:00:00Z\",\"reminders_enabled\":true,\"timezone\":\"Europe/Istanbul\",\"starts_at\":\"2026-10-19T21:00:00Z\",\"next_schedule_minute\":540,\"next_grace_minutes\":240}"

    func testOverlappingReloadDoesNotDuplicateFetches() async throws {
        try saveSession()
        var meCalls = 0
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/me/checkin/today") { return self.response(request, 200, Self.todayJSON) }
            if request.url!.path.hasSuffix("/me") { meCalls += 1; return self.response(request, 200, Self.profileJSON) }
            return self.response(request, 200, "{}")
        }
        let state = AppState(api: client())
        state.signedIn = true
        async let first: Void = state.reload()
        async let second: Void = state.reload()
        _ = await (first, second)
        XCTAssertEqual(meCalls, 1, "overlapping reload calls must share one fetch")
        XCTAssertTrue(state.online)
        XCTAssertNotNil(state.profile)
    }
    func testFailedReloadKeepsCachedDataAndOfflineState() async throws {
        try saveSession()
        var fail = false
        StubURLProtocol.handler = { request in
            if fail { throw URLError(.notConnectedToInternet) }
            if request.url!.path.hasSuffix("/me/checkin/today") { return self.response(request, 200, Self.todayJSON) }
            if request.url!.path.hasSuffix("/me") { return self.response(request, 200, Self.profileJSON) }
            return self.response(request, 200, "{}")
        }
        let state = AppState(api: client())
        state.signedIn = true
        await state.reload()
        XCTAssertTrue(state.online)
        fail = true
        await state.reload()
        XCTAssertFalse(state.online)
        XCTAssertNotNil(state.profile, "cached profile must survive a failed refresh")
        XCTAssertNotNil(state.refreshFailedMessage)
    }
    func testSessionExpiryClearsStateAndSetsFlag() async throws {
        try saveSession(expiresIn: -60)
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") { return self.response(request, 401, "{\"code\":\"session_reused\",\"message\":\"reused\"}") }
            return self.response(request, 200, Self.profileJSON)
        }
        let state = AppState(api: client())
        state.signedIn = true
        await state.reload()
        for _ in 0..<50 where !state.sessionExpired { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(state.sessionExpired)
        XCTAssertFalse(state.signedIn)
        XCTAssertNil(state.profile)
        XCTAssertNil(try? SharedStorage.session())
    }

    private static let receiptJSON = "{\"checkin_id\":\"c1\",\"status\":\"completed\",\"received_at\":\"2026-10-20T05:10:00Z\",\"already_completed\":false}"
    private static let profileU2JSON = "{\"id\":\"u2\",\"name\":\"Other\",\"timezone\":\"Europe/Istanbul\",\"enabled\":true,\"schedule_minute\":540,\"grace_minutes\":240}"
    private static let todayU2JSON = "{\"id\":\"o2\",\"user_id\":\"u2\",\"local_date\":\"2026-10-20\",\"state\":\"due\",\"due_at\":\"2026-10-20T06:00:00Z\",\"deadline_at\":\"2026-10-20T10:00:00Z\",\"closes_at\":\"2026-10-20T21:00:00Z\",\"completed_at\":null,\"next_due_at\":\"2026-10-21T06:00:00Z\",\"trusted_contacts\":0,\"server_time\":\"2026-10-20T05:00:00Z\",\"reminders_enabled\":true,\"timezone\":\"Europe/Istanbul\",\"starts_at\":\"2026-10-19T21:00:00Z\",\"next_schedule_minute\":540,\"next_grace_minutes\":240}"

    private func defaultHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            if request.url!.path.hasSuffix("/me/checkins") { return self.response(request, 200, Self.receiptJSON) }
            if request.url!.path.hasSuffix("/me/checkin/today") { return self.response(request, 200, Self.todayJSON) }
            if request.url!.path.hasSuffix("/me") { return self.response(request, 200, Self.profileJSON) }
            return self.response(request, 200, "{}")
        }
    }

    func testStaleFetchCannotRevertAcknowledgedCheckIn() async throws {
        try saveSession()
        ServerClock.record(ISO8601DateFormatter().date(from: "2026-10-20T05:00:00Z")!, deviceNow: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let staleFetch = expectation(description: "second today fetch in flight")
        var todayCalls = 0
        StubURLProtocol.onRequest = { request in
            if request.url!.path.hasSuffix("/me/checkin/today") {
                todayCalls += 1
                if todayCalls == 2 { staleFetch.fulfill(); gate.wait() }
            }
        }
        StubURLProtocol.handler = defaultHandler()
        let state = AppState(api: client())
        state.signedIn = true
        await state.reload()
        XCTAssertEqual(state.today?.state, "due")
        let stale = Task { await state.reload() }
        await fulfillment(of: [staleFetch], timeout: 10)
        await state.complete()
        XCTAssertEqual(state.today?.state, "completed")
        gate.signal()
        await stale.value
        XCTAssertEqual(state.today?.state, "completed", "a fetch started before the check-in must not revert the server receipt")
    }

    func testSessionEndDuringCheckInDoesNotRepopulate() async throws {
        try saveSession()
        ServerClock.record(ISO8601DateFormatter().date(from: "2026-10-20T05:00:00Z")!, deviceNow: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let checkInSent = expectation(description: "check-in request in flight")
        StubURLProtocol.onRequest = { request in
            if request.url!.path.hasSuffix("/me/checkins") { checkInSent.fulfill(); gate.wait() }
        }
        StubURLProtocol.handler = defaultHandler()
        let state = AppState(api: client())
        state.signedIn = true
        await state.reload()
        let checkIn = Task { await state.complete() }
        await fulfillment(of: [checkInSent], timeout: 10)
        state.endSession(expired: true)
        gate.signal()
        await checkIn.value
        XCTAssertNil(state.today, "a response landing after session end must not repopulate state")
        XCTAssertNil(state.profile)
        XCTAssertFalse(state.signedIn)
        XCTAssertTrue(state.sessionExpired)
    }

    func testBeginSessionDuringStaleReloadFetchesFreshAccount() async throws {
        try saveSession()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let firstMe = expectation(description: "first /me in flight")
        var meCalls = 0
        StubURLProtocol.onRequest = { request in
            if request.url!.path.hasSuffix("/me") {
                meCalls += 1
                if meCalls == 1 { firstMe.fulfill(); gate.wait() }
            }
        }
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/me/checkin/today") {
                let u2 = request.value(forHTTPHeaderField: "Authorization")?.contains("b1") == true
                return self.response(request, 200, u2 ? Self.todayU2JSON : Self.todayJSON)
            }
            if request.url!.path.hasSuffix("/me") {
                let u2 = request.value(forHTTPHeaderField: "Authorization")?.contains("b1") == true
                return self.response(request, 200, u2 ? Self.profileU2JSON : Self.profileJSON)
            }
            return self.response(request, 200, "{}")
        }
        let state = AppState(api: client())
        state.signedIn = true
        let stale = Task { await state.reload() }
        await fulfillment(of: [firstMe], timeout: 10)
        try SharedStorage.save(AuthSession(accessToken: "b1", refreshToken: "br", userId: "u2", expiresIn: 900))
        await state.beginSession()
        gate.signal()
        await stale.value
        XCTAssertEqual(meCalls, 2, "beginSession must start a fresh fetch instead of joining the discarded one")
        XCTAssertEqual(state.profile?.id, "u2")
        XCTAssertEqual(state.today?.userId, "u2")
    }

    func testDelayedExpiryCannotClearReplacementAccount() async throws {
        try SharedStorage.save(AuthSession(accessToken: "b1", refreshToken: "br", userId: "u2", expiresIn: 900))
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/me/checkin/today") { return self.response(request, 200, Self.todayU2JSON) }
            if request.url!.path.hasSuffix("/me") { return self.response(request, 200, Self.profileU2JSON) }
            return self.response(request, 200, "{}")
        }
        let state = AppState(api: client())
        state.signedIn = true
        await state.reload()
        XCTAssertEqual(state.profile?.id, "u2")
        NotificationCenter.default.post(name: Notification.Name("HYSessionExpired"), object: "u1")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(state.sessionExpired, "a delayed expiry must not evict a live replacement session")
        XCTAssertTrue(state.signedIn)
        XCTAssertEqual(state.profile?.id, "u2")
        SharedStorage.clear()
        NotificationCenter.default.post(name: Notification.Name("HYSessionExpired"), object: "u1")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(state.sessionExpired, "expiry for a different user must not clear the loaded account")
        XCTAssertEqual(state.profile?.id, "u2")
    }
}
