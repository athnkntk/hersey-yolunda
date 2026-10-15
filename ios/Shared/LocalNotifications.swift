import Foundation
import UserNotifications

struct PlannedReminder {
    let id: String
    let fireAt: Date
    let title: String
    let body: String
}

/// Sunucudan bağımsız, cihaz üzerinde zamanlanan günlük hatırlatmalar.
/// APNs yapılandırılana kadar kullanıcının kendi hatırlatmaları bu kanaldan çalışır;
/// aileye giden "missed/completed" bildirimleri yine backend push'una bağlıdır.
enum LocalNotifications {
    static let reminderPrefix = "hy.reminder."
    static let legacyReminderIDs = (0...3).map { "\(reminderPrefix)\($0)" }
    static func reminderID(day: Int, step: Int) -> String { "\(reminderPrefix)day\(day).step\(step)" }
    static var reminderIDs: [String] {
        legacyReminderIDs + (0...7).flatMap { day in (0...3).map { reminderID(day: day, step: $0) } }
    }

    static func isReminder(identifier: String) -> Bool { identifier.hasPrefix(reminderPrefix) }

    /// Kuyruklanmış sync çağrılarının sıralanması: yalnızca en son revizyon zamanlayabilir.
    /// Böylece eski bir çağrı, daha yeni bir tamamlanmış check-in'den sonra bugünün
    /// hatırlatmalarını yeniden kuramaz.
    private static let scheduleLock = NSLock()
    static private(set) var scheduleRevision = 0
    static func nextScheduleRevision() -> Int {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        scheduleRevision += 1
        return scheduleRevision
    }
    static func isLatestSchedule(revision: Int) -> Bool {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        return revision == scheduleRevision
    }

    static func cancelReminders() {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        scheduleRevision += 1
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: reminderIDs)
    }

    /// Kilitli blok içinde çağrılan saf seçim: aynı hesaba ait en yeni anlık görüntüyü
    /// ve eşleşen profilin enabled değerini döndürür; aksi halde nil (zamanlama yok).
    static func chooseSchedule(today: Today?, enabled: Bool, authorized: Bool, now: Date?, sessionUserID: String?) -> (today: Today, enabled: Bool, now: Date)? {
        guard authorized, let now, let today, today.userId == sessionUserID else { return nil }
        var effectiveToday = today
        if let cached = SharedStorage.snapshot()?.today, cached.userId == today.userId, !today.supersedes(cached) {
            effectiveToday = cached
        }
        var resolvedEnabled = enabled
        if let cached = SharedStorage.cachedProfile(), cached.id == today.userId { resolvedEnabled = cached.enabled }
        return (effectiveToday, resolvedEnabled, now)
    }

    private static let closedStates = ["completed", "cancelled", "alerted", "overdue"]

    private static func steps(day: Int, due: Date, deadline: Date, trustedContacts: Int, now: Date, timeZone: TimeZone) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        let candidates: [(Int, Date, String, String)] = [
            (0, due, L10n.text("Bugünkü haberinizi göndermeyi unutmayın"), L10n.text("Tek dokunuşla ailenize iyi olduğunuzu bildirin.")),
            (1, due.addingTimeInterval(3600), L10n.text("Aileniz sizi merak ediyor olabilir"), L10n.text("Henüz haber vermediniz. Kısa bir dokunuş yeterli.")),
            (2, due.addingTimeInterval(10800), L10n.text("Kontrol süreniz dolmak üzere"),
             L10n.format("%@ · Yakınlarınız haber vermediğinizi uygulamada görebilir. Hâlâ haber gönderebilirsiniz.", DateText.time(deadline, timeZone: timeZone)))
        ]
        for (step, date, title, body) in candidates where date > now && date < deadline {
            planned.append(PlannedReminder(id: reminderID(day: day, step: step), fireAt: date, title: title, body: body))
        }
        if trustedContacts > 0, deadline > now {
            planned.append(PlannedReminder(id: reminderID(day: day, step: 3), fireAt: deadline,
                title: L10n.text("Haber verme süreniz doldu"),
                body: L10n.text("Yakınlarınız uygulamada henüz haber vermediğinizi görebilir. İsterseniz şimdi de haber verebilirsiniz.")))
        }
        return planned
    }

    /// Planlanan hatırlatmaların saf hali: test edilebilir, UserNotifications'a dokunmaz.
    /// `now` güvenilir sunucu saati tahmini olmalı; bugün + gelecek 7 gün en fazla 32 bildirim.
    static func plan(today: Today, enabled: Bool, now: Date) -> [PlannedReminder] {
        guard enabled else { return [] }
        let timeZone = today.accountZone
        var planned: [PlannedReminder] = []
        if today.isCurrent(at: now), today.remindersEnabled != false, !closedStates.contains(today.state) {
            planned += steps(day: 0, due: today.dueAt, deadline: today.deadlineAt, trustedContacts: today.trustedContacts, now: now, timeZone: timeZone)
        }
        guard let minute = today.nextScheduleMinute, let grace = today.nextGraceMinutes else {
            if today.nextDueAt > now {
                planned.append(PlannedReminder(id: reminderID(day: 1, step: 0), fireAt: today.nextDueAt,
                    title: L10n.text("Bugünkü haberinizi göndermeyi unutmayın"),
                    body: L10n.text("Tek dokunuşla ailenize iyi olduğunuzu bildirin.")))
            }
            return Array(planned.prefix(32))
        }
        let calendar = DateText.calendar(timeZone: timeZone)
        let startOfToday = today.startsAt ?? calendar.startOfDay(for: now)
        let matching = DateComponents(hour: minute / 60, minute: minute % 60)
        for day in 1...7 {
            guard let dayStart = calendar.date(byAdding: .day, value: day, to: startOfToday),
                  let nextDayStart = calendar.date(byAdding: .day, value: day + 1, to: startOfToday) else { continue }
            let due: Date
            if day == 1 {
                due = today.nextDueAt
            } else {
                guard let resolved = calendar.nextDate(after: dayStart.addingTimeInterval(-1), matching: matching,
                        matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .last, direction: .forward),
                      resolved < nextDayStart else { continue }
                due = resolved
            }
            let deadline = min(due.addingTimeInterval(TimeInterval(grace * 60)), nextDayStart.addingTimeInterval(-0.001))
            planned += steps(day: day, due: due, deadline: deadline, trustedContacts: today.trustedContacts, now: now, timeZone: timeZone)
        }
        return Array(planned.prefix(32))
    }

    /// Sunucu saati tahminine göre hatırlatmaları yeniden kurar.
    /// Eşzamanlı çağrılar arasında yalnızca en yenisi zamanlar; güvenilir saat,
    /// izin veya eşleşen hesap yoksa son çağrı temizleyip hiçbir şey eklemez.
    static func sync(today: Today?, enabled: Bool) async {
        let revision = nextScheduleRevision()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let now = ServerClock.now()
        applySchedule(revision: revision, today: today, enabled: enabled, authorized: authorized, now: now)
    }

    /// Kilitli tek blok: revizyon kontrolü, hesap eşleşmesi, eski isteklerin
    /// kaldırılması ve yeni planın eklenmesi. await içermez.
    private static func applySchedule(revision: Int, today: Today?, enabled: Bool, authorized: Bool, now: Date?) {
        let center = UNUserNotificationCenter.current()
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        guard revision == scheduleRevision else { return }
        let session = try? SharedStorage.session()
        if let today, today.userId != session?.auth.userId { return }
        center.removePendingNotificationRequests(withIdentifiers: reminderIDs)
        guard let choice = chooseSchedule(today: today, enabled: enabled, authorized: authorized, now: now, sessionUserID: session?.auth.userId) else { return }
        for reminder in plan(today: choice.today, enabled: choice.enabled, now: choice.now) {
            schedule(center: center, reminder: reminder, now: choice.now)
        }
    }

    private static func schedule(center: UNUserNotificationCenter, reminder: PlannedReminder, now: Date) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.fireAt.timeIntervalSince(now)), repeats: false)
        center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }
}
