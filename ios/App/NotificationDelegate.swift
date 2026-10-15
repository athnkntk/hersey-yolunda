import UIKit
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            guard let session = try? SharedStorage.session() else { return }
            let key = "deviceID.\(session.auth.userId)"
            let identifier = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
            UserDefaults.standard.set(identifier, forKey: key)
            do {
                let _: EmptyResponse = try await APIClient.shared.request("POST", "/me/devices", body: ["id": identifier, "token": token, "permission": "authorized", "locale": L10n.language], expectedUser: session.auth.userId)
            } catch {
                NotificationCenter.default.post(name: .init("HYNotificationRegistrationFailed"), object: nil)
            }
        }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .init("HYNotificationRegistrationFailed"), object: nil)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if LocalNotifications.isReminder(identifier: notification.request.identifier) { return [.banner, .sound] }
        await MainActor.run { NotificationCenter.default.post(name: .init("HYRemoteNotification"), object: nil) }
        return [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if LocalNotifications.isReminder(identifier: response.notification.request.identifier) {
            await MainActor.run { NotificationCenter.default.post(name: .init("HYSelfReminder"), object: nil) }
            return
        }
        let info = response.notification.request.content.userInfo
        var type = ""
        if let event = info["event_id"] as? String, UUID(uuidString: event) != nil {
            let _: EmptyResponse? = try? await APIClient.shared.request("POST", "/me/notifications/\(event)/opened")
            if let raw = info["event_type"] as? String,
               raw == "completed" || raw == "missed" || (raw.hasPrefix("reminder_") && raw.dropFirst("reminder_".count).allSatisfy { $0.isNumber }) {
                type = raw
            }
        }
        await MainActor.run { NotificationCenter.default.post(name: .init("HYNotificationOpened"), object: type) }
    }
}
