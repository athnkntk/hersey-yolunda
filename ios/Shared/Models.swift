import Foundation

struct Profile: Codable, Identifiable {
    let id: String
    let name: String
    let timezone: String
    let enabled: Bool
    let scheduleMinute: Int
    let graceMinutes: Int
}

struct Today: Codable, Identifiable {
    let id: String
    let userId: String
    let localDate: String
    let state: String
    let dueAt: Date
    let deadlineAt: Date
    let closesAt: Date
    let completedAt: Date?
    let nextDueAt: Date
    let trustedContacts: Int
    let serverTime: Date
    var remindersEnabled: Bool? = nil
    var timezone: String? = nil
    var startsAt: Date? = nil
    var nextScheduleMinute: Int? = nil
    var nextGraceMinutes: Int? = nil

    var accountZone: TimeZone { TimeZone(identifier: timezone ?? "Europe/Istanbul") ?? .current }
    func isCurrent(at date: Date) -> Bool {
        if let startsAt { return startsAt <= date && date < closesAt }
        return localDate == DateText.day(date, timeZone: accountZone) && date < closesAt
    }
    func isCurrent() -> Bool {
        guard let now = ServerClock.now() else { return false }
        return isCurrent(at: now)
    }
    /// Sunucudan gelen bu durum kayıtlı (önbellekli) durumun yerine geçebilir mi?
    /// Eski bir "bekliyor" yanıtı, onaylanmış bir "tamamlandı" durumunu asla geri alamaz.
    func supersedes(_ cached: Today?) -> Bool {
        guard let cached, cached.userId == userId else { return true }
        if cached.id == id && cached.state == "completed" && state != "completed" { return false }
        return serverTime >= cached.serverTime
    }
    var title: String {
        guard isCurrent() else { return L10n.text("Bugünkü durumu yenileyin") }
        switch state {
        case "completed": return L10n.text("Bugünkü haberiniz kaydedildi")
        case "cancelled": return L10n.text("Bugün kontrol devre dışı")
        case "overdue", "alerted": return L10n.text("Bugün henüz haber vermediniz")
        default: return L10n.text("Bugün bir haber verin")
        }
    }
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let expiresIn: Int
    var savedAt: Date = Date()
    enum CodingKeys: String, CodingKey { case accessToken, refreshToken, userId, expiresIn }
}
struct PendingRegistration: Codable {
    let name: String
    let enabled: Bool
    let secret: String
    let createdAt: Date
    var timezone: String? = nil
}
struct Receipt: Decodable { let checkinId: String; let status: String; let receivedAt: Date; let alreadyCompleted: Bool }
struct Items<T: Decodable>: Decodable { let items: [T] }
struct Relative: Decodable, Identifiable {
    let profile: Profile
    let today: Today
    var id: String { profile.id }
    var isCompleted: Bool { today.isCurrent() && today.state == "completed" }
    func status() -> String { status(at: ServerClock.now() ?? .distantPast) }
    func status(at date: Date) -> String {
        guard profile.enabled else { return L10n.text("Günlük program kapalı") }
        guard today.isCurrent(at: date) else { return L10n.text("Güncel durum için yenileyin") }
        if today.state == "completed" { return L10n.text("Bugün iyi olduğunu bildirdi") }
        if today.state == "cancelled" { return L10n.text("Bugün kontrol devre dışı") }
        return L10n.text("Kontrol bekleniyor")
    }
}
struct Relationship: Decodable, Identifiable {
    let id: String
    let subjectId: String
    let viewerId: String
    let subjectName: String
    let viewerName: String
    let label: String
}
struct Invitation: Decodable, Identifiable { let id: String; let status: String; let label: String; let recipientName: String? }
struct NewInvitation: Decodable { let id: String; let token: String; let code: String }
struct InvitationPreview: Decodable { let id: String; let creatorName: String; let direction: String; let label: String }
struct ActionResult: Decodable { let status: String }
struct HistoryItem: Decodable, Identifiable { let id: String; let receivedAt: Date; let source: String; let localDate: String }
struct Notice: Decodable, Identifiable {
    let id: String
    let type: String
    let status: String
    let createdAt: Date
    let subjectName: String
    var title: String {
        if type == "completed" { return L10n.format("%@ iyi olduğunu bildirdi.", subjectName) }
        if type == "missed" { return L10n.format("%@ bugün henüz haber vermedi. Aramak isteyebilirsiniz.", subjectName) }
        return L10n.text("Bugünkü haberinizi göndermeyi unutmayın.")
    }
}
struct ScheduleValue: Decodable { let minute: Int; let grace: Int; let effectiveDate: String }
struct Schedule: Decodable { let current: ScheduleValue; let next: ScheduleValue; let timezone: String }
extension Schedule {
    static func fitsInDay(minute: Int, grace: Int) -> Bool { minute + grace < 1440 }
}
struct Preferences: Codable { var success: Bool; var missed: Bool; var analytics: Bool }
struct SessionInfo: Decodable, Identifiable { let id: String; let deviceName: String; let current: Bool; let createdAt: Date }
struct EmptyResponse: Decodable {}
struct Health: Decodable { let status: String; let pushConfigured: Bool }
struct BackendError: Decodable, LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { ErrorText.backendMessage(code: code) }
}
struct LocalError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct WidgetFailure: Codable {
    let userId: String
    let code: String
}

/// Backend bildirim durumlarının ham değerlerini göstermeyen yerelleştirilmiş eşlemesi.
enum NotificationStatusText {
    static func message(_ status: String, language: String? = nil) -> String {
        switch status {
        case "queued": return L10n.text("Uygulamada kayıtlı", language: language)
        case "provider_accepted": return L10n.text("İletim servisi kabul etti", language: language)
        case "sending": return L10n.text("Gönderiliyor", language: language)
        case "suppressed": return L10n.text("Gizlendi", language: language)
        case "retryable_failed": return L10n.text("Tekrar deneniyor", language: language)
        case "permanently_failed": return L10n.text("Gönderilemedi", language: language)
        default: return L10n.text("Durum güncelleniyor", language: language)
        }
    }
}

enum ErrorText {
    static func backendMessage(code: String) -> String {
        let text = L10n.text(code)
        return text == code ? L10n.text("internal_error") : text
    }
    static func message(for error: Error) -> String {
        if let backend = error as? BackendError { return backendMessage(code: backend.code) }
        if let local = error as? LocalError { return local.message }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return L10n.text("Bağlantı yok. İnternet bağlantınızı kontrol edip yeniden deneyin.")
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return L10n.text("Sunucuya ulaşılamadı. Biraz sonra yeniden deneyin.")
            default: return L10n.text("internal_error")
            }
        }
        return L10n.text("internal_error")
    }
}

struct PendingCheckIn: Codable {
    let userId: String
    let occurrenceId: String
    let key: String
    let source: String
    let actionAt: Date
}

struct WidgetSnapshot: Codable {
    let userId: String
    let name: String
    let today: Today
}

enum DateText {
    static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(timeZone: timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func time(_ date: Date, timeZone: TimeZone, locale: Locale = L10n.locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
    static func stamp(_ date: Date, timeZone: TimeZone, locale: Locale = L10n.locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    static func headerDay(_ date: Date, timeZone: TimeZone, locale: Locale = L10n.locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func parseISO(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: value)
    }
}
