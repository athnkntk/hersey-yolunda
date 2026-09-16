import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        UserDefaults.standard.set(fcmToken, forKey: "fcmToken")
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            guard let session = try? SharedStorage.session() else { return }
            let key = "deviceID.\(session.auth.userId)"
            let identifier = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
            UserDefaults.standard.set(identifier, forKey: key)
            do {
                let _: EmptyResponse = try await APIClient.shared.request("POST", "/me/devices", body: ["id": identifier, "token": token, "permission": "authorized"], expectedUser: session.auth.userId)
            } catch {
                NotificationCenter.default.post(name: .init("HYNotificationRegistrationFailed"), object: nil)
            }
        }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .init("HYNotificationRegistrationFailed"), object: nil)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { NotificationCenter.default.post(name: .init("HYRemoteNotification"), object: nil) }
        return [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let event = response.notification.request.content.userInfo["event_id"] as? String,
           UUID(uuidString: event) != nil {
            let _: EmptyResponse? = try? await APIClient.shared.request("POST", "/me/notifications/\(event)/opened")
        }
        await MainActor.run { NotificationCenter.default.post(name: .init("HYRemoteNotification"), object: nil) }
    }
}
