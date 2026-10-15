import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmLogout = false
    var body: some View {
        List {
            Section {
                Label(state.profile?.name ?? L10n.text("Hesabım"), systemImage: "person.crop.circle").font(.title2)
            }
            Section(L10n.text("Dil")) {
                LanguagePicker()
            }
            Section(L10n.text("Günlük rutin")) {
                if state.profile?.enabled == false {
                    Button(L10n.text("Ben de günlük haber vermek istiyorum")) {
                        Task {
                            await state.perform {
                                let _: Profile = try await state.api.request("PATCH", "/me/profile", body: ["name": state.profile?.name ?? "", "enabled": true])
                                await state.reload()
                                state.tab = 0
                            }
                        }
                    }.frame(minHeight: 56)
                }
                NavigationLink(L10n.text("Kontrol saati")) { ScheduleView() }
                NavigationLink(L10n.text("Bildirim tercihleri")) { PreferencesView() }
                NavigationLink(L10n.text("Bildirimlerim")) { NotificationsView() }
                Button(L10n.text("Bildirim iznini ayarla")) { Task { await state.notificationPermission() } }.frame(minHeight: 56)
                NavigationLink(L10n.text("Ana ekrana widget ekle")) { WidgetGuideView() }
            }
            Section(L10n.text("Gizlilik ve hesap")) {
                NavigationLink(L10n.text("Hesabım ve kurtarma")) { AccountAccessView() }
                NavigationLink(L10n.text("Gizlilik ve kullanım sınırları")) { PrivacyView() }
                NavigationLink(L10n.text("Açık oturumlar")) { SessionsView() }
                NavigationLink(L10n.text("Verilerim ve hesap silme")) { DataRightsView() }
                Button(L10n.text("Çıkış yap")) { confirmLogout = true }.frame(minHeight: 56)
            }
            Section {
                Text(L10n.format("Herşey Yolunda · %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")).foregroundStyle(.secondary)
                if APIClient.isLocal { Text(L10n.text("Yerel geliştirme sürümü. Telefon/SMS gerekmez. Canlı push ve hukuki metinler henüz hazır değil.")).foregroundStyle(Design.amber) }
            }
        }.navigationTitle(L10n.text("Ayarlar"))
            .confirmationDialog(Text(L10n.text("Hesabınızdan çıkılsın mı?")), isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(L10n.text("Çıkış yap")) { Task { await state.logout() } }
            } message: { Text(L10n.text("Kaydedilmiş kurtarma anahtarınız olmadan bu hesaba dönemeyebilirsiniz; adınız veya hesap ID’niz hesabı geri açmaz. Günlük programınız sunucuda devam eder. Kalıcı olarak ayrılıyorsanız hesap silme seçeneğini kullanın.")) }
    }
}

struct ScheduleView: View {
    @EnvironmentObject var state: AppState
    @State private var time = Date()
    @State private var grace = 240
    @State private var loadState: LoadState = .idle
    @State private var loading = false
    @State private var timezone = ""
    private var accountZone: TimeZone {
        TimeZone(identifier: timezone.isEmpty ? (state.profile?.timezone ?? "") : timezone) ?? .current
    }
    private var accountCalendar: Calendar { DateText.calendar(timeZone: accountZone) }
    private var minuteOfDay: Int {
        let components = accountCalendar.dateComponents([.hour, .minute], from: time)
        return (components.hour ?? 9) * 60 + (components.minute ?? 0)
    }
    private var loaded: Bool { loadState == .loaded }
    private var fitsInDay: Bool { Schedule.fitsInDay(minute: minuteOfDay, grace: grace) }
    var body: some View {
        Form {
            if !loaded {
                Section { LoadStateView(state: loadState, empty: "", retry: load) }
            }
            Section(L10n.format("Hesap saat dilimi: %@", accountZone.identifier)) {
                DatePicker(L10n.text("Hatırlatma"), selection: $time, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, accountZone)
                    .disabled(!loaded)
                Picker(selection: $grace) {
                    Text(L10n.text("1 saat")).tag(60)
                    Text(L10n.text("2 saat")).tag(120)
                    Text(L10n.text("4 saat")).tag(240)
                    Text(L10n.text("6 saat")).tag(360)
                } label: { Text(L10n.text("Bekleme süresi")) }
                .disabled(!loaded)
                Text(L10n.text("Haberiniz gelmezse bekleme süresi sonunda yakınlarınız bunu uygulamada görebilir. Saat ve bekleme süresi aynı güne sığmalıdır."))
                if loaded && !fitsInDay {
                    Text(L10n.text("Bu saat ve bekleme süresi aynı güne sığmıyor. Daha erken bir saat veya daha kısa bekleme süresi seçin.")).foregroundStyle(Design.amber)
                }
            }
            Section {
                Button(L10n.text("Programı kaydet")) {
                    Task {
                        await state.perform {
                            let _: EmptyResponse = try await state.api.request("PUT", "/me/checkin-schedule", body: ["minute": minuteOfDay, "grace": grace])
                            state.message = L10n.text("Yeni programınız yarından itibaren geçerli. Bugünkü kontrolünüz değişmedi.")
                            await state.reload()
                        }
                    }
                }.frame(minHeight: 56).disabled(!loaded || state.loading || !fitsInDay)
                    .accessibilityIdentifier("scheduleSave")
                if case .failed = loadState {
                    Button(L10n.text("Yeniden yükle")) { Task { await load() } }.frame(minHeight: 56).disabled(state.loading)
                }
                Text(L10n.text("Değişiklik yarın uygulanır. Telefonunuzun saat dilimi programı otomatik değiştirmez.")).foregroundStyle(.secondary)
            }
        }.navigationTitle(L10n.text("Kontrol saati"))
            .task(id: state.profile?.id) { if loadState == .idle { await load() } }
    }
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if loadState != .loaded { loadState = .loading }
        do {
            let schedule: Schedule = try await state.api.request("GET", "/me/checkin-schedule")
            timezone = schedule.timezone
            time = accountCalendar.date(from: DateComponents(hour: schedule.next.minute / 60, minute: schedule.next.minute % 60)) ?? Date()
            grace = schedule.next.grace
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            loadState = .failed(L10n.text("Mevcut programınız alınamadı. Kaydetmeden önce yeniden yükleyin."))
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var state: AppState
    @State private var preferences = Preferences(success: true, missed: true, analytics: false)
    @State private var loadState: LoadState = .idle
    @State private var loading = false
    private var loaded: Bool { loadState == .loaded }
    var body: some View {
        Form {
            if !loaded {
                Section { LoadStateView(state: loadState, empty: "", retry: load) }
            }
            Section(L10n.text("Yakınlarımdan gelen haberler")) {
                Toggle(L10n.text("İyi olduğunu bildirdiğinde"), isOn: $preferences.success)
                    .disabled(!loaded)
                Toggle(L10n.text("Günlük haber gelmediğinde"), isOn: $preferences.missed)
                    .disabled(!loaded)
                if loaded && !preferences.missed { Text(L10n.text("Kapalıyken kaçırılan check-in bildirimi almazsınız. Durumu uygulamadan kontrol etmeniz gerekir.")).foregroundStyle(Design.amber) }
            }
            Section(L10n.text("İsteğe bağlı analitik")) {
                Toggle(L10n.text("Ürünü geliştirmeye yardımcı ol"), isOn: $preferences.analytics)
                    .disabled(!loaded)
                Text(L10n.text("Adınız, telefonunuz veya aile bilgileriniz analitik olayı olarak gönderilmez. Tercihiniz temel hizmeti etkilemez. Bu sürümde üçüncü taraf analitik SDK'sı yoktur."))
            }
            Button(L10n.text("Tercihleri kaydet")) {
                Task {
                    await state.perform {
                        let _: Preferences = try await state.api.request("PATCH", "/me/notification-preferences", body: ["success": preferences.success, "missed": preferences.missed, "analytics": preferences.analytics])
                        state.message = L10n.text("Tercihleriniz kaydedildi.")
                    }
                }
            }.frame(minHeight: 56).disabled(!loaded || state.loading)
            if case .failed = loadState {
                Button(L10n.text("Yeniden yükle")) { Task { await load() } }.frame(minHeight: 56).disabled(state.loading)
            }
        }.navigationTitle(L10n.text("Bildirimler"))
            .task(id: state.profile?.id) { if loadState == .idle { await load() } }
    }
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if loadState != .loaded { loadState = .loading }
        do {
            preferences = try await state.api.request("GET", "/me/notification-preferences")
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            loadState = .failed(L10n.text("Mevcut tercihleriniz alınamadı. Kaydetmeden önce yeniden yükleyin."))
        }
    }
}

struct NotificationsView: View {
    @EnvironmentObject var state: AppState
    @State private var items: [Notice] = []
    @State private var loadState: LoadState = .idle
    @State private var loadingList = false
    private var accountZone: TimeZone { TimeZone(identifier: state.profile?.timezone ?? "") ?? .current }
    var body: some View {
        List {
            if case .failed(let message) = loadState, !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    Button(L10n.text("Yeniden dene")) { Task { await load() } }
                }
            }
            if items.isEmpty {
                LoadStateView(state: loadState, empty: L10n.text("Henüz bir bildirim yok."), retry: load)
            }
            ForEach(items) { notice in
                VStack(alignment: .leading, spacing: 10) {
                    Text(notice.title).font(.headline)
                    Text(DateText.stamp(notice.createdAt, timeZone: accountZone)).foregroundStyle(.secondary)
                    Text(NotificationStatusText.message(notice.status)).font(.callout).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
        }.navigationTitle(L10n.text("Bildirimlerim"))
            .task(id: state.refreshGeneration) { await load() }
            .refreshable { await load() }
    }
    private func load() async {
        guard !loadingList else { return }
        loadingList = true
        defer { loadingList = false }
        if items.isEmpty { loadState = .loading }
        do {
            let response: Items<Notice> = try await state.api.request("GET", "/me/notifications")
            items = response.items
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            loadState = .failed(ErrorText.message(for: error))
        }
    }
}

struct SessionsView: View {
    @EnvironmentObject var state: AppState
    @State private var items: [SessionInfo] = []
    @State private var loadState: LoadState = .idle
    @State private var loadingList = false
    private var accountZone: TimeZone { TimeZone(identifier: state.profile?.timezone ?? "") ?? .current }
    var body: some View {
        List {
            if case .failed(let message) = loadState, !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    Button(L10n.text("Yeniden dene")) { Task { await load() } }
                }
            }
            if items.isEmpty {
                LoadStateView(state: loadState, empty: L10n.text("Henüz bir oturum yok."), retry: load)
            }
            ForEach(items) { session in
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.deviceName).font(.headline)
                    Text(session.current ? L10n.text("Bu oturum") : DateText.stamp(session.createdAt, timeZone: accountZone))
                    if !session.current {
                        Button(L10n.text("Oturumu kapat"), role: .destructive) {
                            Task {
                                await state.perform {
                                    let _: EmptyResponse = try await state.api.request("DELETE", "/me/sessions/\(session.id)")
                                    items.removeAll { $0.id == session.id }
                                }
                            }
                        }.frame(minHeight: 56)
                    }
                }
            }
        }.navigationTitle(L10n.text("Oturumlar"))
            .task(id: state.refreshGeneration) { await load() }
            .refreshable { await load() }
    }
    private func load() async {
        guard !loadingList else { return }
        loadingList = true
        defer { loadingList = false }
        if items.isEmpty { loadState = .loading }
        do {
            let response: Items<SessionInfo> = try await state.api.request("GET", "/me/sessions")
            items = response.items
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            loadState = .failed(ErrorText.message(for: error))
        }
    }
}

struct DataRightsView: View {
    @EnvironmentObject var state: AppState
    @State private var exported = ""
    @State private var confirm = false
    var body: some View {
        List {
            Section(L10n.text("Veri dışa aktarma")) {
                Text(L10n.text("Profiliniz ve kendi check-in kayıtlarınız dışa aktarılır. Başkalarının özel hesap bilgileri dahil edilmez."))
                Button(L10n.text("Verilerimi hazırla")) {
                    Task {
                        await state.perform {
                            let data: ExportData = try await state.api.request("POST", "/me/exports")
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            encoder.dateEncodingStrategy = .iso8601
                            exported = String(decoding: try encoder.encode(data), as: UTF8.self)
                        }
                    }
                }.frame(minHeight: 56)
                if !exported.isEmpty { ShareLink(L10n.text("Verilerimi paylaş / kaydet"), item: exported).frame(minHeight: 56) }
            }
            Section(L10n.text("Hesap silme")) {
                Text(L10n.text("Hesabınız, aile bağlantılarınız ve kayıtlarınız bu sunucudan silinir. İşlem geri alınamaz."))
                Text(L10n.text("Hesabınızı silmek App Store aboneliğinizi iptal etmez. Aboneliğinizi App Store üzerinden ayrıca yönetin."))
                Link(L10n.text("Aboneliği yönet"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!).frame(minHeight: 56)
                Button(L10n.text("Hesabımı sil"), role: .destructive) { confirm = true }.frame(minHeight: 56)
            }
        }.navigationTitle(L10n.text("Verilerim"))
            .confirmationDialog(Text(L10n.text("Hesabınız kalıcı olarak silinsin mi?")), isPresented: $confirm, titleVisibility: .visible) {
                Button(L10n.text("Hesabımı kalıcı olarak sil"), role: .destructive) {
                    Task {
                        await state.perform {
                            let _: EmptyResponse = try await state.api.request("DELETE", "/me", body: ["confirmation": "HESABIMI SİL"], expectedUser: state.profile?.id)
                            try await state.api.forgetSession()
                            state.endSession(expired: false)
                            exported = ""
                        }
                    }
                }
            }
            .onDisappear { exported = "" }
    }
}
func statusText(_ status: String) -> String { NotificationStatusText.message(status) }

struct ExportData: Codable {
    let profile: Profile
    let checkins: [ExportCheckIn]
    let consents: [ExportConsent]
}
struct ExportCheckIn: Codable { let source: String; let receivedAt: Date }
struct ExportConsent: Codable { let purpose: String; let version: String; let granted: Bool; let createdAt: Date }

struct WidgetGuideView: View {
    var body: some View {
        List {
            Section(L10n.text("Bir dokunuş daha yakın")) {
                Label(L10n.text("Ana ekranda boş bir alana basılı tutun."), systemImage: "1.circle")
                Label(L10n.text("Düzenle → Widget Ekle seçeneğini açın."), systemImage: "2.circle")
                Label(L10n.text("Herşey Yolunda'yı bulun ve büyük widget'ı seçin."), systemImage: "3.circle")
                Label(L10n.text("BEN İYİYİM düğmesiyle bilinçli olarak haber verin."), systemImage: "4.circle")
            }
            Section {
                Text(L10n.text("Widget yalnızca sunucu onayından sonra başarılı gösterir. Bağlantı veya oturum sorunu varsa uygulamayı açıp yeniden deneyin."))
                Text(L10n.text("Telefonu açmak otomatik haber göndermez. Widget'taki tarihi kontrol edin."))
            }
        }.navigationTitle(L10n.text("Widget ekleme"))
    }
}

struct AccountAccessView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            if let profile = state.profile {
                Section(L10n.text("Hesap kimliğim")) {
                    Text(profile.id).font(.callout.monospaced()).textSelection(.enabled)
                        .accessibilityIdentifier("accountIdentifier")
                    Text(L10n.text("Bu kimlik şifre veya davet kodu değildir. Başka bir hesap bu kimlikle verilerinize erişemez."))
                }
            }
            Section(L10n.text("Bu cihazdaki hesabınız")) {
                Text(L10n.text("Sistem size benzersiz bir hesap kimliği atar. Güvenli oturum anahtarları iPhone’un Keychain alanında tutulur; adınız sadece görünen isimdir."))
                Text(L10n.text("Aynı adı yazmak eski hesabınıza giriş sağlamaz. Telefon değişimi, cihazın sıfırlanması, oturum kaybı veya çıkıştan sonra hesabınıza erişemeyebilirsiniz. Yeniden kurulumda erişimin korunacağı garanti edilmez."))
            }
            Section(L10n.text("Hesabı koruma ve kurtarma")) {
                NavigationLink(L10n.text("Kurtarma anahtarı")) { RecoveryKeySettingsView() }
                    .frame(minHeight: 56).accessibilityIdentifier("recoveryKeySettings")
                Text(L10n.text("Kurtarma anahtarını etkinleştirip güvenli bir yere kaydettiyseniz aynı hesabı yeni bir cihazda açabilirsiniz. Kurtarma anahtarınız yoksa veya onu kaybettiyseniz yeni hesap oluşturup aile eşleştirmelerini tekrar onaylatmanız gerekir. Apple ile giriş kullanılmaz."))
                Text(L10n.text("Bir yakınınız sizin hesabınızı devralamaz veya adınıza ‘iyiyim’ gönderemez. Davet bağlantıları yalnızca paylaşım ilişkisi kurar; hesabınıza giriş sağlamaz."))
            }
        }.navigationTitle(L10n.text("Hesabım ve kurtarma"))
    }
}

struct PrivacyView: View {
    private var page: URL { URL(string: "https://athnkntk.github.io/hersey-yolunda/privacy.html?lang=\(L10n.language)")! }
    private var support: URL { URL(string: "https://athnkntk.github.io/hersey-yolunda/?lang=\(L10n.language)")! }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.text("Kontrol sizde.")).font(.largeTitle.bold())
                Text(L10n.text("Yakınınızı takip etmek değil, iyi olduğunu bilmek.")).font(.title2)
                privacy(L10n.text("Toplanan bilgiler"), L10n.text("Ad, sistemin atadığı hesap kimliği, günlük beyan zamanı, izin verdiğiniz ilişkiler, güvenli cihaz oturumu ve gerekli bildirim bilgileri. Yeni hesap için telefon veya SMS istenmez. Konum, sağlık ölçümleri, kamera, mikrofon ve rehber toplanmaz."))
                privacy(L10n.text("Paylaşım"), L10n.text("Günlük haberinizi yalnızca açıkça yetkilendirdiğiniz yakınlar görür. Paylaşımı Ailem ekranından istediğiniz zaman durdurabilirsiniz."))
                privacy(L10n.text("Saklama"), L10n.text("Check-in geçmişi 30 günlük temizlik politikasına tabidir. Hesap silme, bu sunucudaki hesabı ve ilişkili kayıtları siler."))
                privacy(L10n.text("Hesap ve oturum"), L10n.text("Adınız bir kimlik bilgisi değildir; yeni bir cihazda aynı adı yazmak eski hesabınızı açmaz. Hesabınıza dönmek için önceden oluşturup kaydettiğiniz kurtarma anahtarı gerekir; anahtar yoksa oturum kaybında yeni hesap ve aile eşleştirmesi gerekir."))
                privacy(L10n.text("Hizmet sınırları"), L10n.text("Bu uygulama acil yardım veya tıbbi müdahale hizmeti değildir. Kullanıcı beyanı, sağlık durumunun doğrulandığı anlamına gelmez. Push bildirimleri gecikebilir veya görülmeyebilir. Acil durumda bulunduğunuz ülkedeki acil yardım numarasını arayın."))
                Link(L10n.text("Tam gizlilik metni"), destination: page)
                Link(L10n.text("Destek"), destination: support)
            }.padding(24)
        }.background(Design.background).navigationTitle(L10n.text("Gizlilik"))
    }
    private func privacy(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.title3.bold()); Text(text).font(.body).lineSpacing(5) }
    }
}
