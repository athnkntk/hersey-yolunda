import AppIntents
import SwiftUI
import WidgetKit

struct YolundaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let failure: WidgetFailure?
}
struct YolundaProvider: TimelineProvider {
    func placeholder(in context: Context) -> YolundaEntry { YolundaEntry(date: .now, snapshot: nil, failure: nil) }
    func getSnapshot(in context: Context, completion: @escaping (YolundaEntry) -> Void) {
        completion(YolundaEntry(date: .now, snapshot: SharedStorage.snapshot(), failure: SharedStorage.widgetFailure()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<YolundaEntry>) -> Void) {
        let snapshot = SharedStorage.snapshot()
        let failure = SharedStorage.widgetFailure()
        let now = Date()
        var entries = [YolundaEntry(date: now, snapshot: snapshot, failure: failure)]
        if let snapshot, let rollover = ServerClock.deviceDate(for: snapshot.today.closesAt), rollover > now {
            entries.append(YolundaEntry(date: rollover, snapshot: snapshot, failure: failure))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}

struct YolundaWidgetView: View {
    let entry: YolundaEntry
    private let green = Color(red: 0.09, green: 0.38, blue: 0.26)
    private var openApp: some View {
        Link(destination: URL(string: "herseyyolunda://checkin")!) {
            Text(L10n.text("Uygulamayı aç")).font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.borderedProminent).tint(green).foregroundStyle(.white)
    }
    private var snapshotZone: TimeZone {
        TimeZone(identifier: entry.snapshot?.today.timezone ?? "") ?? .current
    }
    var body: some View {
        let evaluation = ServerClock.evaluationDate(for: entry.date)
        VStack(alignment: .leading, spacing: 12) {
            Label("Herşey Yolunda", systemImage: "leaf.fill").font(.headline)
            if let failure = entry.failure, failure.userId == entry.snapshot?.userId {
                Text(L10n.text("Haber gönderilemedi.")).font(.title3.bold())
                Text(ErrorText.backendMessage(code: failure.code)).font(.callout)
                openApp
            } else if let snapshot = entry.snapshot, let evaluation {
                Text(snapshot.name).font(.title2.bold())
                if snapshot.today.isCurrent(at: evaluation) && snapshot.today.state == "completed" {
                    Label(L10n.text("Bugün haber verdiniz"), systemImage: "checkmark.circle.fill").font(.title3.bold())
                    if let date = snapshot.today.completedAt { Text(DateText.stamp(date, timeZone: snapshotZone)).font(.callout) }
                } else if snapshot.today.isCurrent(at: evaluation) && snapshot.today.state == "cancelled" {
                    Text(L10n.text("Bugün kontrol devre dışı")).font(.title3)
                } else if snapshot.today.isCurrent(at: evaluation) {
                    Button(intent: CheckInIntent()) {
                        Text(L10n.text("BEN İYİYİM")).font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 60)
                    }.buttonStyle(.borderedProminent).tint(green).foregroundStyle(.white)
                    Text(L10n.format("%@ · Aileme haber ver", DateText.day(evaluation, timeZone: snapshotZone))).font(.caption)
                } else {
                    Text(L10n.text("Bugünkü durum için uygulamayı açın")).font(.title3)
                    openApp
                }
            } else if entry.snapshot != nil {
                Text(entry.snapshot?.name ?? "").font(.title2.bold())
                Text(L10n.text("Bugünkü durum için uygulamayı açın")).font(.title3)
                openApp
            } else {
                Text(L10n.text("Bugün bir haber verin")).font(.title2.bold())
                Text(L10n.text("Başlamak veya durumu yenilemek için uygulamayı açın.")).font(.callout)
            }
        }
        .foregroundStyle(green)
        .containerBackground(Color(red: 0.96, green: 0.98, blue: 0.94), for: .widget)
        .widgetURL(URL(string: "herseyyolunda://checkin"))
    }
}

@main
struct YolundaWidget: Widget {
    let kind = "YolundaDailyCheckIn"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YolundaProvider()) { entry in YolundaWidgetView(entry: entry) }
            .configurationDisplayName(L10n.text("Ben iyiyim"))
            .description(L10n.text("Bir dokunuşla ailenize haber verin. Konum paylaşılmaz."))
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
