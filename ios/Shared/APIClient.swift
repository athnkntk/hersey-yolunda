import Foundation
import Security
import WidgetKit
import Darwin

struct StoredSession: Codable {
    let auth: AuthSession
    let expiresAt: Date
    var refreshRequestID: String? = nil
}

enum SharedStorage {
    static let group = "group.com.herseyyolunda.shared"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static var keychainQuery: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "herseyyolunda.session", kSecAttrAccount as String: "active"]
        if let group = Bundle.main.object(forInfoDictionaryKey: "HYKeychainGroup") as? String, !group.contains("$(") {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
    static func session() throws -> StoredSession? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LocalError(message: L10n.text("Güvenli oturum açılamadı. Uygulamayı açıp yeniden deneyin.")) }
        return try JSONDecoder().decode(StoredSession.self, from: data)
    }
    static func saveStored(_ value: StoredSession) throws {
        let data = try JSONEncoder().encode(value)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(keychainQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw LocalError(message: L10n.text("Oturum güvenli biçimde kaydedilemedi.")) }
        } else if status != errSecSuccess { throw LocalError(message: L10n.text("Oturum yenilenemedi.")) }
    }
    static func save(_ session: AuthSession) throws {
        try saveStored(StoredSession(auth: session, expiresAt: Date().addingTimeInterval(TimeInterval(session.expiresIn))))
    }
    static var registrationQuery: [String: Any] {
        var query = keychainQuery
        query[kSecAttrAccount as String] = "pending-registration"
        return query
    }
    static func registration() throws -> PendingRegistration? {
        var query = registrationQuery
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LocalError(message: L10n.text("Bekleyen hesap kaydı güvenli alandan okunamadı.")) }
        return try JSONDecoder().decode(PendingRegistration.self, from: data)
    }
    static func saveRegistration(_ registration: PendingRegistration) throws {
        let data = try JSONEncoder().encode(registration)
        let status = SecItemUpdate(registrationQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = registrationQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw LocalError(message: L10n.text("Hesap anahtarı güvenli biçimde kaydedilemedi.")) }
        } else if status != errSecSuccess { throw LocalError(message: L10n.text("Bekleyen hesap kaydı güncellenemedi.")) }
    }
    static func clearRegistration() { SecItemDelete(registrationQuery as CFDictionary) }
    static func clear() {
        SecItemDelete(keychainQuery as CFDictionary)
        clearRegistration()
        defaults.removeObject(forKey: "snapshot")
        defaults.removeObject(forKey: "pending")
        defaults.removeObject(forKey: "profile")
        defaults.removeObject(forKey: "widgetFailure")
        ServerClock.clear()
        LocalNotifications.cancelReminders()
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func snapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    static func saveWidgetFailure(_ failure: WidgetFailure?) {
        if let failure { defaults.set(try? JSONEncoder().encode(failure), forKey: "widgetFailure") }
        else { defaults.removeObject(forKey: "widgetFailure") }
    }
    static func widgetFailure() -> WidgetFailure? {
        guard let data = defaults.data(forKey: "widgetFailure") else { return nil }
        return try? JSONDecoder().decode(WidgetFailure.self, from: data)
    }
    static func cachedProfile() -> Profile? {
        guard let data = defaults.data(forKey: "profile") else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }
    static func saveSnapshot(profile: Profile, today: Today) {
        guard let current = try? session(), current.auth.userId == profile.id else { return }
        defaults.set(try? JSONEncoder().encode(profile), forKey: "profile")
        guard profile.enabled else {
            defaults.removeObject(forKey: "snapshot")
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        guard today.supersedes(snapshot()?.today) else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        defaults.set(try? JSONEncoder().encode(WidgetSnapshot(userId: profile.id, name: profile.name, today: today)), forKey: "snapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func pending() -> PendingCheckIn? {
        guard let data = defaults.data(forKey: "pending") else { return nil }
        return try? JSONDecoder().decode(PendingCheckIn.self, from: data)
    }
    static func savePending(_ value: PendingCheckIn?) {
        if let value { defaults.set(try? JSONEncoder().encode(value), forKey: "pending") }
        else { defaults.removeObject(forKey: "pending") }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let urlSession: URLSession
    private let baseURL: URL?
    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? (Bundle.main.object(forInfoDictionaryKey: "HYAPIURL") as? String).flatMap(URL.init(string:))
        self.urlSession = session
    }
    static var isLocal: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    static func isLANHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 127 { return true }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        return false
    }
    private func lock() async throws -> Int32 {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStorage.group) else {
            throw LocalError(message: L10n.text("Paylaşılan güvenli alan açılamadı. Uygulamayı açın."))
        }
        let descriptor = open(container.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LocalError(message: L10n.text("Oturum kilidi açılamadı.")) }
        for _ in 0..<450 {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { close(descriptor); throw error }
        }
        close(descriptor)
        throw LocalError(message: L10n.text("Başka bir işlem sürüyor. Yeniden deneyin."))
    }
    private func unlock(_ descriptor: Int32) { flock(descriptor, LOCK_UN); close(descriptor) }

    private func credential(expectedUser: String? = nil, replacing rejectedAccess: String? = nil) async throws -> (token: String, userID: String) {
        let descriptor = try await lock()
        defer { unlock(descriptor) }
        guard let stored = try SharedStorage.session() else {
            throw BackendError(code: "session_expired", message: "")
        }
        if let expectedUser, stored.auth.userId != expectedUser {
            throw LocalError(message: L10n.text("Aktif hesap değişti. Ekranı yenileyin."))
        }
        if stored.expiresAt > Date().addingTimeInterval(60), stored.refreshRequestID == nil,
           rejectedAccess == nil || stored.auth.accessToken != rejectedAccess {
            return (stored.auth.accessToken, stored.auth.userId)
        }
        var working = stored
        if working.refreshRequestID == nil {
            working.refreshRequestID = UUID().uuidString
            try SharedStorage.saveStored(working)
        }
        let refreshed: AuthSession = try await send("POST", "/auth/refresh", body: ["refresh_token": working.auth.refreshToken], token: nil, key: working.refreshRequestID)
        guard refreshed.userId == stored.auth.userId else {
            throw LocalError(message: L10n.text("Aktif hesap değişti. Ekranı yenileyin."))
        }
        try SharedStorage.save(refreshed)
        return (refreshed.accessToken, refreshed.userId)
    }
    func createAccount(name: String, enabled: Bool) async throws {
        let descriptor = try await lock()
        defer { unlock(descriptor) }
        guard try SharedStorage.session() == nil else { throw LocalError(message: L10n.text("Bu cihazda zaten bir hesap açık. Önce mevcut hesabınızı kontrol edin.")) }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let registration: PendingRegistration
        if let pending = try SharedStorage.registration() {
            guard pending.name == normalizedName, pending.enabled == enabled else { throw LocalError(message: L10n.text("Bekleyen kayıt için önceki ad ve tercihle yeniden deneyin veya denemeyi sıfırlayın.")) }
            registration = pending
        } else {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LocalError(message: L10n.text("Güvenli hesap anahtarı oluşturulamadı.")) }
            let secret = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            registration = PendingRegistration(name: normalizedName, enabled: enabled, secret: secret, createdAt: Date(), timezone: TimeZone.current.identifier)
            try SharedStorage.saveRegistration(registration)
        }
        var body: [String: Any] = ["name": registration.name, "enabled": registration.enabled, "device_name": "iPhone / iPad", "registration_secret": registration.secret]
        if let timezone = registration.timezone { body["timezone"] = timezone }
        let auth: AuthSession = try await send("POST", "/auth/device", body: body, token: nil)
        try SharedStorage.save(auth)
        SharedStorage.clearRegistration()
        SharedStorage.defaults.removeObject(forKey: "snapshot")
        SharedStorage.defaults.removeObject(forKey: "pending")
        SharedStorage.defaults.removeObject(forKey: "profile")
        SharedStorage.saveWidgetFailure(nil)
        WidgetCenter.shared.reloadAllTimelines()
    }
    func logout(expectedUser: String? = nil) async throws {
        let _: EmptyResponse = try await request("POST", "/auth/logout", expectedUser: expectedUser)
        let descriptor = try await lock()
        defer { unlock(descriptor) }
        if let expectedUser, let current = try SharedStorage.session(), current.auth.userId != expectedUser { return }
        SharedStorage.clear()
    }
    func forgetSession() async throws {
        let descriptor = try await lock()
        defer { unlock(descriptor) }
        SharedStorage.clear()
    }
    private func invalidateSession(expectedUser: String?, expectedAccess: String?) async {
        guard let descriptor = try? await lock() else { return }
        defer { unlock(descriptor) }
        let current: StoredSession?
        do { current = try SharedStorage.session() }
        catch { return }
        guard let current else {
            await MainActor.run { NotificationCenter.default.post(name: .init("HYSessionExpired"), object: expectedUser) }
            return
        }
        if let expectedUser, current.auth.userId != expectedUser { return }
        if let expectedAccess, current.auth.accessToken != expectedAccess { return }
        SharedStorage.clear()
        await MainActor.run { NotificationCenter.default.post(name: .init("HYSessionExpired"), object: expectedUser) }
    }
    func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil, authenticated: Bool = true, key: String? = nil, expectedUser: String? = nil) async throws -> T {
        let captured = authenticated ? (try? SharedStorage.session()) : nil
        let capturedUser = expectedUser ?? captured?.auth.userId
        var attemptedAccess: String? = nil
        do {
            if !authenticated {
                return try await send(method, path, body: body, token: nil, key: key)
            }
            let access = try await credential(expectedUser: capturedUser)
            attemptedAccess = access.token
            do {
                return try await send(method, path, body: body, token: access.token, key: key)
            } catch let error as BackendError where error.code == "unauthorized" {
                let retry = try await credential(expectedUser: capturedUser, replacing: access.token)
                attemptedAccess = retry.token
                return try await send(method, path, body: body, token: retry.token, key: key)
            }
        } catch let error as BackendError {
            if authenticated && ["unauthorized", "session_expired", "session_reused"].contains(error.code) {
                await invalidateSession(expectedUser: capturedUser, expectedAccess: attemptedAccess ?? captured?.auth.accessToken)
            }
            throw error
        }
    }
    private func recordServerTime(_ http: HTTPURLResponse, data: Data) {
        var server: Date? = nil
        if let object = try? JSONSerialization.jsonObject(with: data), let map = object as? [String: Any],
           let value = map["server_time"] as? String {
            server = DateText.parseISO(value)
        }
        if server == nil, let value = http.value(forHTTPHeaderField: "X-Server-Time") {
            server = DateText.parseISO(value)
        }
        if server == nil, let value = http.value(forHTTPHeaderField: "Date") {
            server = DateText.httpDate(value)
        }
        if let server { ServerClock.record(server) }
    }
    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]?, token: String?, key: String? = nil) async throws -> T {
        guard let baseURL, let url = URL(string: baseURL.absoluteString + path),
              url.scheme == "https" || (Self.isLocal && Self.isLANHost(url.host)) else {
            throw LocalError(message: L10n.text("Sunucu henüz yapılandırılmadı. Bu sürüm üretim kullanımına hazır değil."))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(L10n.language, forHTTPHeaderField: "Accept-Language")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await urlSession.data(for: request)
        let decoder = Self.decoder()
        guard let http = response as? HTTPURLResponse else { throw LocalError(message: L10n.text("Sunucudan yanıt alınamadı.")) }
        recordServerTime(http, data: data)
        guard (200..<300).contains(http.statusCode) else {
            throw (try? decoder.decode(BackendError.self, from: data)) ?? BackendError(code: "network_error", message: "")
        }
        return try decoder.decode(T.self, from: data)
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw LocalError(message: L10n.text("Sunucunun tarih biçimi okunamadı."))
        }
        return decoder
    }
    func checkIn(profile: Profile, today: Today, source: String) async throws -> Today {
        guard let serverNow = ServerClock.now() else {
            throw LocalError(message: L10n.text("Sunucu saati doğrulanamadı. Bağlanıp yeniden deneyin."))
        }
        guard today.isCurrent(at: serverNow) else { throw LocalError(message: L10n.text("Günlük ekranı yenileyip yeniden dokunun.")) }
        let old = SharedStorage.pending()
        let pending: PendingCheckIn
        if let old, old.userId == profile.id, old.occurrenceId == today.id,
           serverNow.timeIntervalSince(old.actionAt) >= 0, serverNow.timeIntervalSince(old.actionAt) < 300 {
            pending = old
        } else {
            pending = PendingCheckIn(userId: profile.id, occurrenceId: today.id, key: UUID().uuidString, source: source, actionAt: serverNow)
            // Başka bir hesaba ait bekleyen eylemi ezmeyin; yalnızca aynı hesap
            // (veya boş alan) için yeni anahtarı saklayın.
            if old == nil || old?.userId == profile.id {
                SharedStorage.savePending(pending)
            }
        }
        let receipt: Receipt = try await request("POST", "/me/checkins", body: ["occurrence_id": pending.occurrenceId, "source": pending.source, "client_action_at": DateText.iso(pending.actionAt)], key: pending.key, expectedUser: profile.id)
        if let stored = SharedStorage.pending(), stored.userId == profile.id, stored.key == pending.key {
            SharedStorage.savePending(nil)
        }
        let updated = Today(id: today.id, userId: profile.id, localDate: today.localDate, state: receipt.status, dueAt: today.dueAt, deadlineAt: today.deadlineAt, closesAt: today.closesAt, completedAt: receipt.receivedAt, nextDueAt: today.nextDueAt, trustedContacts: today.trustedContacts, serverTime: ServerClock.now() ?? receipt.receivedAt, remindersEnabled: today.remindersEnabled, timezone: today.timezone, startsAt: today.startsAt, nextScheduleMinute: today.nextScheduleMinute, nextGraceMinutes: today.nextGraceMinutes)
        SharedStorage.saveSnapshot(profile: profile, today: updated)
        if SharedStorage.widgetFailure()?.userId == profile.id {
            SharedStorage.saveWidgetFailure(nil)
            WidgetCenter.shared.reloadAllTimelines()
        }
        return updated
    }
}
