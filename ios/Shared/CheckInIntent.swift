import AppIntents
import Foundation
import WidgetKit

struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource { LocalizedStringResource("İyi olduğumu bildir", locale: L10n.locale) }
    static var description: IntentDescription { IntentDescription(LocalizedStringResource("Bugünkü haberinizi yetkilendirdiğiniz ailenize kaydeder.", locale: L10n.locale)) }
    static var openAppWhenRun = false
    static var isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult {
        guard let snapshot = SharedStorage.snapshot() else {
            throw LocalError(message: L10n.text("Bugünkü durumu yenilemek için uygulamayı açın."))
        }
        do {
            let profile: Profile = try await APIClient.shared.request("GET", "/me", expectedUser: snapshot.userId)
            let today: Today = try await APIClient.shared.request("GET", "/me/checkin/today", expectedUser: snapshot.userId)
            let updated = try await APIClient.shared.checkIn(profile: profile, today: today, source: "ios_widget")
            await LocalNotifications.sync(today: updated, enabled: profile.enabled)
            SharedStorage.saveWidgetFailure(nil)
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        } catch {
            let code = (error as? BackendError)?.code ?? "network_error"
            if let current = try? SharedStorage.session(), current.auth.userId == snapshot.userId {
                SharedStorage.saveWidgetFailure(WidgetFailure(userId: snapshot.userId, code: code))
            }
            WidgetCenter.shared.reloadAllTimelines()
            throw LocalError(message: L10n.text("Haber gönderilemedi. Uygulamayı açıp yeniden deneyin."))
        }
    }
}
