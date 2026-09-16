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

    func isCurrent(at date: Date = Date()) -> Bool {
        localDate == DateText.day(date) && date < closesAt
    }
    var title: String {
        guard isCurrent() else { return "Bugünkü durumu yenileyin" }
        switch state {
        case "completed": return "Bugünkü haberiniz kaydedildi"
        case "cancelled": return "Bugün kontrol devre dışı"
        case "overdue", "alerted": return "Bugün henüz haber vermediniz"
        default: return "Bugün bir haber verin"
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
}
struct Receipt: Decodable { let checkinId: String; let status: String; let receivedAt: Date; let alreadyCompleted: Bool }
struct Items<T: Decodable>: Decodable { let items: [T] }
struct Relative: Decodable, Identifiable {
    let profile: Profile
    let today: Today
    var id: String { profile.id }
    var isCompleted: Bool { today.isCurrent() && today.state == "completed" }
    func status(at date: Date = Date()) -> String {
        guard profile.enabled else { return "Günlük program kapalı" }
        guard today.isCurrent(at: date) else { return "Güncel durum için yenileyin" }
        if today.state == "completed" { return "Bugün iyi olduğunu bildirdi" }
        if today.state == "cancelled" { return "Bugün kontrol devre dışı" }
        return "Kontrol bekleniyor"
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
        if type == "completed" { return "\(subjectName) iyi olduğunu bildirdi." }
        if type == "missed" { return "\(subjectName) bugün henüz haber vermedi. Aramak isteyebilirsiniz." }
        return "Bugünkü haberinizi göndermeyi unutmayın."
    }
}
struct ScheduleValue: Decodable { let minute: Int; let grace: Int; let effectiveDate: String }
struct Schedule: Decodable { let current: ScheduleValue; let next: ScheduleValue; let timezone: String }
struct Preferences: Codable { var success: Bool; var missed: Bool; var analytics: Bool }
struct SessionInfo: Decodable, Identifiable { let id: String; let deviceName: String; let current: Bool; let createdAt: Date }
struct EmptyResponse: Decodable {}
struct BackendError: Decodable, LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}
struct LocalError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
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
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d MMMM · HH:mm"
        return formatter.string(from: date)
    }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
