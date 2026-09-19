import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmLogout = false
    var body: some View {
        List {
            Section {
                Label(state.profile?.name ?? "Hesabım", systemImage: "person.crop.circle").font(.title2)
            }
            Section("Günlük rutin") {
                if state.profile?.enabled == false {
                    Button("Ben de günlük haber vermek istiyorum") {
                        Task {
                            await state.perform {
                                let _: Profile = try await state.api.request("PATCH", "/me/profile", body: ["name": state.profile?.name ?? "", "enabled": true])
                                await state.reload()
                                state.tab = 0
                            }
                        }
                    }.frame(minHeight: 56)
                }
                NavigationLink("Kontrol saati") { ScheduleView() }
                NavigationLink("Bildirim tercihleri") { PreferencesView() }
                NavigationLink("Bildirimlerim") { NotificationsView() }
                Button("Bildirim iznini ayarla") { Task { await state.notificationPermission() } }.frame(minHeight: 56)
                NavigationLink("Ana ekrana widget ekle") { WidgetGuideView() }
            }
            Section("Gizlilik ve hesap") {
                NavigationLink("Hesabım ve kurtarma") { AccountAccessView() }
                NavigationLink("Gizlilik ve kullanım sınırları") { PrivacyView() }
                NavigationLink("Açık oturumlar") { SessionsView() }
                NavigationLink("Verilerim ve hesap silme") { DataRightsView() }
                Button("Çıkış yap") { confirmLogout = true }.frame(minHeight: 56)
            }
            Section {
                Text("Herşey Yolunda · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").foregroundStyle(.secondary)
                if APIClient.isLocal { Text("Yerel geliştirme sürümü. Telefon/SMS gerekmez. Canlı push, Apple ile kurtarma ve hukuki metinler henüz hazır değil.").foregroundStyle(Design.amber) }
            }
        }.navigationTitle("Ayarlar")
            .confirmationDialog("Hesabınızdan çıkılsın mı?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Çıkış yap") { Task { await state.logout() } }
            } message: { Text("Bu sürümde Apple ile kurtarma yoktur. Çıkış yaparsanız bu hesaba erişiminizi kaybedebilirsiniz; adınız veya hesap ID’niz hesabı geri açmaz. Günlük programınız sunucuda devam eder. Kalıcı olarak ayrılıyorsanız hesap silme seçeneğini kullanın.") }
    }
}

struct ScheduleView: View {
    @EnvironmentObject var state: AppState
    @State private var time = Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
    @State private var grace = 240
    @State private var loaded = false
    var body: some View {
        Form {
            Section("Türkiye saati") {
                DatePicker("Hatırlatma", selection: $time, displayedComponents: .hourAndMinute)
                Picker("Bekleme süresi", selection: $grace) {
                    Text("1 saat").tag(60)
                    Text("2 saat").tag(120)
                    Text("4 saat").tag(240)
                    Text("6 saat").tag(360)
                }
                Text("Haberiniz gelmezse bekleme süresi sonunda yakınlarınıza bilgi verilir. Saat ve bekleme süresi aynı güne sığmalıdır.")
            }
            Section {
                Button("Programı kaydet") {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                    Task {
                        await state.perform {
                            let _: EmptyResponse = try await state.api.request("PUT", "/me/checkin-schedule", body: ["minute": (components.hour ?? 9) * 60 + (components.minute ?? 0), "grace": grace])
                            state.message = "Yeni programınız yarından itibaren geçerli. Bugünkü kontrolünüz değişmedi."
                            await state.reload()
                        }
                    }
                }.frame(minHeight: 56).disabled(!loaded || state.loading)
                if !loaded {
                    Text("Mevcut programınız alınamadı. Kaydetmeden önce yeniden yükleyin.").foregroundStyle(Design.amber)
                    Button("Yeniden yükle") { Task { await load() } }.frame(minHeight: 56).disabled(state.loading)
                }
                Text("Değişiklik yarın uygulanır. Telefonunuzun saat dilimi programı otomatik değiştirmez.").foregroundStyle(.secondary)
            }
        }.navigationTitle("Kontrol saati")
            .task { await load() }
    }
    private func load() async {
        do {
            let schedule: Schedule = try await state.api.request("GET", "/me/checkin-schedule")
            time = Calendar.current.date(from: DateComponents(hour: schedule.next.minute / 60, minute: schedule.next.minute % 60)) ?? Date()
            grace = schedule.next.grace
            loaded = true
        } catch { if !isCancellationError(error) { state.error = error.localizedDescription } }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var state: AppState
    @State private var preferences = Preferences(success: true, missed: true, analytics: false)
    @State private var loaded = false
    var body: some View {
        Form {
            Section("Yakınlarımdan gelen haberler") {
                Toggle("İyi olduğunu bildirdiğinde", isOn: $preferences.success)
                Toggle("Günlük haber gelmediğinde", isOn: $preferences.missed)
                if !preferences.missed { Text("Kapalıyken kaçırılan check-in bildirimi almazsınız. Durumu uygulamadan kontrol etmeniz gerekir.").foregroundStyle(Design.amber) }
            }
            Section("İsteğe bağlı analitik") {
                Toggle("Ürünü geliştirmeye yardımcı ol", isOn: $preferences.analytics)
                Text("Adınız, telefonunuz veya aile bilgileriniz analitik olayı olarak gönderilmez. Tercihiniz temel hizmeti etkilemez. Bu sürümde üçüncü taraf analitik SDK'sı yoktur.")
            }
            Button("Tercihleri kaydet") {
                Task {
                    await state.perform {
                        let _: Preferences = try await state.api.request("PATCH", "/me/notification-preferences", body: ["success": preferences.success, "missed": preferences.missed, "analytics": preferences.analytics])
                        state.message = "Tercihleriniz kaydedildi."
                    }
                }
            }.frame(minHeight: 56).disabled(!loaded || state.loading)
            if !loaded {
                Text("Mevcut tercihleriniz alınamadı. Kaydetmeden önce yeniden yükleyin.").foregroundStyle(Design.amber)
                Button("Yeniden yükle") { Task { await load() } }.frame(minHeight: 56).disabled(state.loading)
            }
        }.navigationTitle("Bildirimler")
            .task { await load() }
    }
    private func load() async {
        do { preferences = try await state.api.request("GET", "/me/notification-preferences"); loaded = true }
        catch { if !isCancellationError(error) { state.error = error.localizedDescription } }
    }
}

struct NotificationsView: View {
    @EnvironmentObject var state: AppState
    @State private var items: [Notice] = []
    var body: some View {
        List {
            if items.isEmpty { Text("Henüz bir bildirim yok.") }
            ForEach(items) { notice in
                VStack(alignment: .leading, spacing: 10) {
                    Text(notice.title).font(.headline)
                    Text(DateText.stamp(notice.createdAt)).foregroundStyle(.secondary)
                    Text(notice.status == "queued" ? "Uygulama içi kayıt · Push henüz gönderilmedi" : statusText(notice.status)).font(.callout).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
        }.navigationTitle("Bildirimlerim")
            .task {
                do {
                    let response: Items<Notice> = try await state.api.request("GET", "/me/notifications")
                    items = response.items
                } catch { if !isCancellationError(error) { state.error = error.localizedDescription } }
            }
    }
}

struct SessionsView: View {
    @EnvironmentObject var state: AppState
    @State private var items: [SessionInfo] = []
    var body: some View {
        List(items) { session in
            VStack(alignment: .leading, spacing: 10) {
                Text(session.deviceName).font(.headline)
                Text(session.current ? "Bu oturum" : DateText.stamp(session.createdAt))
                if !session.current {
                    Button("Oturumu kapat", role: .destructive) {
                        Task {
                            await state.perform {
                                let _: EmptyResponse = try await state.api.request("DELETE", "/me/sessions/\(session.id)")
                                items.removeAll { $0.id == session.id }
                            }
                        }
                    }.frame(minHeight: 56)
                }
            }
        }.navigationTitle("Oturumlar")
            .task {
                do { let response: Items<SessionInfo> = try await state.api.request("GET", "/me/sessions"); items = response.items }
                catch { if !isCancellationError(error) { state.error = error.localizedDescription } }
            }
    }
}

struct DataRightsView: View {
    @EnvironmentObject var state: AppState
    @State private var exported = ""
    @State private var confirm = false
    var body: some View {
        List {
            Section("Veri dışa aktarma") {
                Text("Profiliniz ve kendi check-in kayıtlarınız dışa aktarılır. Başkalarının özel hesap bilgileri dahil edilmez.")
                Button("Verilerimi hazırla") {
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
                if !exported.isEmpty { ShareLink("Verilerimi paylaş / kaydet", item: exported).frame(minHeight: 56) }
            }
            Section("Hesap silme") {
                Text("Hesabınız, aile bağlantılarınız ve kayıtlarınız bu sunucudan silinir. İşlem geri alınamaz. Yerel test sürümünde yedek hizmeti yoktur.")
                Button("Hesabımı sil", role: .destructive) { confirm = true }.frame(minHeight: 56)
            }
        }.navigationTitle("Verilerim")
            .confirmationDialog("Hesabınız kalıcı olarak silinsin mi?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Hesabımı kalıcı olarak sil", role: .destructive) {
                    Task {
                        await state.perform {
                            let _: EmptyResponse = try await state.api.request("DELETE", "/me", body: ["confirmation": "HESABIMI SİL"])
                            try await state.api.forgetSession()
                            state.profile = nil
                            state.today = nil
                            state.signedIn = false
                            exported = ""
                        }
                    }
                }
            }
            .onDisappear { exported = "" }
    }
}
func statusText(_ status: String) -> String {
    switch status {
    case "provider_accepted": return "Gönderildi"
    case "suppressed": return "Gizlendi"
    case "retryable_failed": return "Tekrar deneniyor"
    case "permanently_failed": return "Gönderilemedi"
    default: return status
    }
}

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
            Section("Bir dokunuş daha yakın") {
                Label("Ana ekranda boş bir alana basılı tutun.", systemImage: "1.circle")
                Label("Düzenle → Widget Ekle seçeneğini açın.", systemImage: "2.circle")
                Label("Herşey Yolunda'yı bulun ve büyük widget'ı seçin.", systemImage: "3.circle")
                Label("BEN İYİYİM düğmesiyle bilinçli olarak haber verin.", systemImage: "4.circle")
            }
            Section {
                Text("Widget yalnızca sunucu onayından sonra başarılı gösterir. Bağlantı veya oturum sorunu varsa uygulamayı açıp yeniden deneyin.")
                Text("Telefonu açmak otomatik haber göndermez. Widget'taki tarihi kontrol edin.")
            }
        }.navigationTitle("Widget ekleme")
    }
}

struct AccountAccessView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            if let profile = state.profile {
                Section("Hesap kimliğim") {
                    Text(profile.id).font(.callout.monospaced()).textSelection(.enabled)
                    Text("Bu kimlik şifre veya davet kodu değildir. Başka bir hesap bu kimlikle verilerinize erişemez.")
                }
            }
            Section("Bu cihazdaki hesabınız") {
                Text("Sistem size benzersiz bir hesap kimliği atar. Güvenli oturum anahtarları iPhone’un Keychain alanında tutulur; adınız sadece görünen isimdir.")
                Text("Aynı adı yazmak eski hesabınıza giriş sağlamaz. Telefon değişimi, cihazın sıfırlanması, oturum kaybı veya çıkıştan sonra hesabınıza erişemeyebilirsiniz. Yeniden kurulumda erişimin korunacağı garanti edilmez.")
            }
            Section("Hesabı koruma ve kurtarma") {
                Text("Apple ile hesabı koruma bu sürümde henüz mevcut değildir. Kurtarma bağlantısı olmadan yeni cihazda yeni hesap oluşturup aile eşleştirmelerini tekrar onaylamanız gerekir.")
                Text("Bir yakınınız sizin hesabınızı devralamaz veya adınıza ‘iyiyim’ gönderemez. Davet bağlantıları yalnızca paylaşım ilişkisi kurar; hesabınıza giriş sağlamaz.")
            }
        }.navigationTitle("Hesabım ve kurtarma")
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Kontrol sizde.").font(.largeTitle.bold())
                Text("Yakınınızı takip etmek değil, iyi olduğunu bilmek.").font(.title2)
                privacy("Toplanan bilgiler", "Ad, sistemin atadığı hesap kimliği, günlük beyan zamanı, izin verdiğiniz ilişkiler, güvenli cihaz oturumu ve gerekli bildirim bilgileri. Yeni hesap için telefon veya SMS istenmez. Konum, sağlık ölçümleri, kamera, mikrofon ve rehber toplanmaz. Eski telefonlu hesapların mevcut kayıtları geçiş sırasında korunur; hesap silme kapsamındadır.")
                privacy("Paylaşım", "Günlük haberinizi yalnızca açıkça yetkilendirdiğiniz yakınlar görür. Paylaşımı Ailem ekranından istediğiniz zaman durdurabilirsiniz.")
                privacy("Saklama", "Yerel MVP'de check-in geçmişi 30 günlük temizlik politikasına tabidir. Hesap silme, bu sunucudaki hesabı ve ilişkili kayıtları siler. Üretim saklama ve yedek politikası ayrıca doğrulanacaktır.")
                privacy("Hizmet sınırları", "Bu uygulama acil yardım veya tıbbi müdahale hizmeti değildir. Kullanıcı beyanı, sağlık durumunun doğrulandığı anlamına gelmez. Push bildirimleri gecikebilir veya görülmeyebilir. Acil durumda 112'yi arayın.")
                privacy("Yerel test ve hukuki durum", "Bu sürüm gerçek kişisel verilerle üretim kullanımına hazır değildir. Veri sorumlusu iletişimi, işleme dayanakları, yurt dışı aktarım mekanizması ve nihai aydınlatma metni henüz onaylanmadı. Bu ekran nihai KVKK aydınlatması yerine geçmez.")
            }.padding(24)
        }.background(Design.background).navigationTitle("Gizlilik")
    }
    private func privacy(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.title3.bold()); Text(text).font(.body).lineSpacing(5) }
    }
}
