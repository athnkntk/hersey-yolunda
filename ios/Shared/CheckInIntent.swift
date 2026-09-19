import AppIntents
import Foundation
import WidgetKit

struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "İyi olduğumu bildir"
    static var description = IntentDescription("Bugünkü haberinizi yetkilendirdiğiniz ailenize kaydeder.")
    static var openAppWhenRun = false
    static var isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult {
        guard let snapshot = SharedStorage.snapshot() else {
            throw LocalError(message: "Bugünkü durumu yenilemek için uygulamayı açın.")
        }
        let profile: Profile = try await APIClient.shared.request("GET", "/me", expectedUser: snapshot.userId)
        let today: Today = try await APIClient.shared.request("GET", "/me/checkin/today", expectedUser: snapshot.userId)
        let updated = try await APIClient.shared.checkIn(profile: profile, today: today, source: "ios_widget")
        await LocalNotifications.sync(today: updated, enabled: profile.enabled)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
