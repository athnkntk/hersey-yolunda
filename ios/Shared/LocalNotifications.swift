import Foundation
import UserNotifications

/// Sunucudan bağımsız, cihaz üzerinde zamanlanan günlük hatırlatmalar.
/// APNs yapılandırılana kadar kullanıcının kendi hatırlatmaları bu kanaldan çalışır;
/// aileye giden "missed/completed" bildirimleri yine backend push'una bağlıdır.
enum LocalNotifications {
    static let reminderIDs = (0...3).map { "hy.reminder.\($0)" }

    static func cancelReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: reminderIDs)
    }

    /// Bugünkü occurrence'a göre hatırlatmaları yeniden kurar.
    /// Her çağrıda önce temizler; izin yoksa veya gün kapalıysa hiçbir şey zamanlanmaz.
    static func sync(today: Today?, enabled: Bool) async {
        cancelReminders()
        guard let today, enabled, today.isCurrent() else { return }
        guard !["completed", "cancelled", "alerted", "overdue"].contains(today.state) else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let now = Date()
        let reminders: [(Int, Date, String, String)] = [
            (0, today.dueAt, "Bugünkü haberinizi göndermeyi unutmayın", "Tek dokunuşla ailenize iyi olduğunuzu bildirin."),
            (1, today.dueAt.addingTimeInterval(3600), "Aileniz sizi merak ediyor olabilir", "Henüz haber vermediniz. Kısa bir dokunuş yeterli."),
            (2, today.dueAt.addingTimeInterval(10800), "Kontrol süreniz dolmak üzere", "\(DateText.time(today.deadlineAt)) itibarıyla ailenize bilgi verilecek. Hâlâ haber gönderebilirsiniz.")
        ]
        for (step, date, title, body) in reminders where date > now && date < today.deadlineAt {
            schedule(center: center, id: reminderIDs[step], at: date, title: title, body: body)
        }
        if today.trustedContacts > 0, today.deadlineAt > now {
            schedule(center: center, id: reminderIDs[3], at: today.deadlineAt,
                     title: "Haber verme süreniz doldu",
                     body: "Yakınlarınıza durum bilgisi iletildi. İsterseniz şimdi de haber verebilirsiniz.")
        }
    }

    private static func schedule(center: UNUserNotificationCenter, id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
