import AppIntents
import SwiftUI
import WidgetKit

struct YolundaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}
struct YolundaProvider: TimelineProvider {
    func placeholder(in context: Context) -> YolundaEntry { YolundaEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (YolundaEntry) -> Void) {
        completion(YolundaEntry(date: .now, snapshot: SharedStorage.snapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<YolundaEntry>) -> Void) {
        let snapshot = SharedStorage.snapshot()
        let now = Date()
        var entries = [YolundaEntry(date: now, snapshot: snapshot)]
        if let snapshot, snapshot.today.closesAt > now { entries.append(YolundaEntry(date: snapshot.today.closesAt, snapshot: snapshot)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}

struct YolundaWidgetView: View {
    let entry: YolundaEntry
    private let green = Color(red: 0.09, green: 0.38, blue: 0.26)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Herşey Yolunda", systemImage: "leaf.fill").font(.headline)
            if let snapshot = entry.snapshot {
                Text(snapshot.name).font(.title2.bold())
                if snapshot.today.isCurrent(at: entry.date) && snapshot.today.state == "completed" {
                    Label("Bugün haber verdiniz", systemImage: "checkmark.circle.fill").font(.title3.bold())
                    if let date = snapshot.today.completedAt { Text(DateText.stamp(date)).font(.callout) }
                } else if snapshot.today.isCurrent(at: entry.date) && snapshot.today.state == "cancelled" {
                    Text("Bugün kontrol devre dışı").font(.title3)
                } else {
                    Button(intent: CheckInIntent()) {
                        Text("BEN İYİYİM").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 60)
                    }.buttonStyle(.borderedProminent).tint(green).foregroundStyle(.white)
                    Text("\(DateText.day(entry.date)) · Aileme haber ver").font(.caption)
                }
            } else {
                Text("Bugün bir haber verin").font(.title2.bold())
                Text("Başlamak veya durumu yenilemek için uygulamayı açın.").font(.callout)
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
            .configurationDisplayName("Ben iyiyim")
            .description("Bir dokunuşla ailenize haber verin. Konum paylaşılmaz.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
