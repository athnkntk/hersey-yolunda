import Foundation

struct ServerTimeAnchor: Codable {
    let serverTime: Date
    let recordedAt: Date
    let uptime: TimeInterval
    func estimate(deviceNow: Date, uptime currentUptime: TimeInterval) -> Date? {
        let elapsed = currentUptime - uptime
        guard elapsed >= 0, elapsed <= 36 * 3600,
              abs(deviceNow.timeIntervalSince(recordedAt) - elapsed) < 120 else { return nil }
        return serverTime.addingTimeInterval(elapsed)
    }
}
enum ServerClock {
    private static let key = "serverClock"
    static func record(_ serverTime: Date, deviceNow: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let anchor = ServerTimeAnchor(serverTime: serverTime, recordedAt: deviceNow, uptime: uptime)
        SharedStorage.defaults.set(try? JSONEncoder().encode(anchor), forKey: key)
    }
    static func now(deviceNow: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Date? {
        guard let data = SharedStorage.defaults.data(forKey: key),
              let anchor = try? JSONDecoder().decode(ServerTimeAnchor.self, from: data) else { return nil }
        return anchor.estimate(deviceNow: deviceNow, uptime: uptime)
    }
    static func deviceDate(for serverDate: Date) -> Date? {
        let local = Date()
        guard let server = now(deviceNow: local) else { return nil }
        return local.addingTimeInterval(serverDate.timeIntervalSince(server))
    }
    /// Bir widget zaman çizelgesi girdisini güvenilir sunucu saati eksenine çevirir.
    /// Cihaz saati kaymış olsa bile girdi anına karşılık gelen sunucu zamanını verir;
    /// güvenilir bir çapa yoksa nil döner (karar verilemez).
    static func evaluationDate(for entryDate: Date, deviceNow: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Date? {
        guard let serverNow = now(deviceNow: deviceNow, uptime: uptime) else { return nil }
        return serverNow.addingTimeInterval(max(0, entryDate.timeIntervalSince(deviceNow)))
    }
    static func clear() { SharedStorage.defaults.removeObject(forKey: key) }
}
