import SwiftUI

@main
struct HerseyYolundaApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .tint(Design.green)
                .preferredColorScheme(.light)
                .task { await state.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && state.signedIn { Task { await state.reload() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .init("HYRemoteNotification"))) { _ in
                    if state.signedIn { state.tab = 1; Task { await state.reload() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .init("HYNotificationRegistrationFailed"))) { _ in
                    state.message = "Cihazınız bildirim servisine kaydedilemedi. Günlük haberlerinizi uygulamadan kontrol edebilirsiniz."
                }
                .onOpenURL { url in
                    if url.scheme == "herseyyolunda", url.host == "checkin" {
                        state.tab = 0
                        if state.signedIn { Task { await state.reload() } }
                        return
                    }
                    guard let token = InvitationInput.credentials(url.absoluteString)?["token"] else { return }
                    state.invitationToken = token
                    state.tab = 1
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Group {
            if !state.signedIn { WelcomeView() }
            else if let profile = state.profile, profile.name.isEmpty { ProfileSetupView() }
            else {
                TabView(selection: $state.tab) {
                    NavigationStack { HomeView() }.tabItem { Label("Bugün", systemImage: "sun.max") }.tag(0)
                    NavigationStack { CircleView() }.tabItem { Label("Ailem", systemImage: "person.2") }.tag(1)
                    NavigationStack { SettingsView() }.tabItem { Label("Ayarlar", systemImage: "slider.horizontal.3") }.tag(2)
                }
            }
        }
        .font(.system(.body, design: .rounded))
        .foregroundStyle(Design.ink)
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("Tamam", role: .cancel) { state.error = nil }
        } message: { Text(state.error ?? "") }
        .alert("Bilgilendirme", isPresented: Binding(get: { state.message != nil }, set: { if !$0 { state.message = nil } })) {
            Button("Tamam", role: .cancel) { state.message = nil }
        } message: { Text(state.message ?? "") }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var enabled = true
    @State private var busy = false
    @State private var hasPending = false
    @State private var confirmReset = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Herşey Yolunda", systemImage: "leaf.fill").font(.title2.bold()).foregroundStyle(Design.green)
                    Text("Bir adımla başlayın.").font(.largeTitle.bold())
                    Text("Telefon numarası ve SMS gerekmez. Adınızı yazın; hesabınız bu cihaz için oluşturulsun.").font(.title3)
                    InfoCard {
                        Text("Size nasıl seslenelim?").font(.title2.bold())
                        TextField("Adınız", text: $name).textContentType(.givenName)
                            .font(.title2).padding().background(Design.background, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("nameField")
                        Toggle("Ben de günlük haber vereceğim", isOn: $enabled).font(.title3)
                        Text(enabled ? "Her gün tek dokunuşla ailenize haber verin." : "Yalnızca yakınlarınızdan haber alın; sizin için kontrol başlatılmaz.").foregroundStyle(.secondary)
                        PrimaryButton(title: "Hesabımı oluştur", busy: busy) { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("createAccount")
                    }
                    Text("Adınız şifre değildir. Yeni cihazda aynı adı yazmak eski hesabınızı açmaz. Bu sürümde Apple ile kurtarma henüz yok; telefon veya oturum kaybında yeni hesap ve aile eşleştirmesi gerekir.")
                        .font(.callout).foregroundStyle(.secondary)
                    if hasPending {
                        Button("Bekleyen hesap oluşturma denemesini sıfırla") { confirmReset = true }.frame(minHeight: 56)
                    }
                    NavigationLink("Hesabım ve kurtarma hakkında") { AccountAccessView() }.frame(minHeight: 56)
                    NavigationLink("Gizlilik ve kullanım sınırları") { PrivacyView() }.frame(minHeight: 56)
                    if APIClient.isLocal { Label("Yerel test sürümü · Gerçek push gönderilmez", systemImage: "hammer").foregroundStyle(Design.amber) }
                    Text("Acil yardım veya tıbbi müdahale hizmeti değildir.").font(.callout).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Design.background)
        }
        .task {
            do {
                if let pending = try SharedStorage.registration() {
                    name = pending.name
                    enabled = pending.enabled
                    hasPending = true
                }
            } catch { if !isCancellationError(error) { state.error = error.localizedDescription } }
        }
        .confirmationDialog("Yeni hesap oluşturma denemesi başlatılsın mı?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Yeni deneme başlat") { SharedStorage.clearRegistration(); hasPending = false }
        } message: { Text("Önceki denemede sunucuda hesap oluştuysa bu işlem o hesaba giriş sağlamaz. İlişkili kayıtları silmez; sonraki deneme ayrı bir hesap oluşturur.") }
    }
    private func create() async {
        busy = true
        defer { busy = false }
        do {
            try await state.api.createAccount(name: name, enabled: enabled)
            state.signedIn = true
            await state.reload()
            if !enabled || !state.invitationToken.isEmpty { state.tab = 1 }
        } catch {
            hasPending = (try? SharedStorage.registration()) != nil
            if !isCancellationError(error) { state.error = error.localizedDescription }
        }
    }
}

struct ProfileSetupView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var enabled = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "hand.wave").font(.system(size: 52)).foregroundStyle(Design.green)
                Text("Size nasıl seslenelim?").font(.largeTitle.bold())
                Text("Sadece adınız yeterli. Bunu izin verdiğiniz yakınlarınız görecek.").font(.title3)
                TextField("Adınız", text: $name).textContentType(.givenName).font(.title2).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("nameField")
                Toggle("Ben de günlük haber vereceğim", isOn: $enabled).font(.title3)
                Text(enabled ? "Her gün tek dokunuşla ailenize haber verebilirsiniz." : "Yalnızca yakınlarınızdan haber alacaksınız. Kendiniz için günlük kontrol başlatılmaz.").foregroundStyle(.secondary)
                PrimaryButton(title: "Başlayalım", busy: state.loading) {
                    Task {
                        await state.perform {
                            let _: Profile = try await state.api.request("PATCH", "/me/profile", body: ["name": name, "enabled": enabled])
                            await state.reload()
                            if !enabled { state.tab = 1 }
                        }
                    }
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("saveProfile")
                Text("İlk hatırlatma saatiniz 09.00. Ayarlardan değiştirebilirsiniz. Ailenizi eklemeden kimseye bilgi paylaşılmaz.")
                    .foregroundStyle(.secondary)
            }.padding(28).padding(.top, 50)
        }.background(Design.background)
    }
}

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmPause = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("HERŞEY YOLUNDA", systemImage: "leaf.fill").font(.caption.weight(.bold)).tracking(1.5)
                    Spacer()
                    Text(Date.now.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR")))).font(.subheadline)
                }.foregroundStyle(Design.green)
                Text("Merhaba,\n\(state.profile?.name ?? "")").font(.system(.largeTitle, design: .rounded, weight: .bold))
                if state.profile?.enabled == false {
                    InfoCard {
                        Label("Ailenizden bir haber", systemImage: "person.2.fill").font(.title2.bold())
                        Text("Sizin için günlük kontrol açık değil. Yakınlarınızın haberlerini Ailem ekranında görebilirsiniz.").font(.title3)
                        PrimaryButton(title: "Aileme git") { state.tab = 1 }
                    }
                } else if let today = state.today, today.isCurrent() {
                    Text(today.title).font(.title3).accessibilityIdentifier("todayStatus")
                    if today.state == "completed" {
                        InfoCard {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Design.green)
                            Text("Bugün haber verdiniz.").font(.title.bold())
                            if let date = today.completedAt { Text(DateText.time(date)).font(.title2.monospacedDigit()) }
                            Text(today.trustedContacts > 0 ? "Aileniz uygulamada iyi olduğunuzu görebilir." : "Haberiniz kaydedildi. Ailenize haber vermek için bir yakınınızı ekleyin.")
                                .font(.title3)
                        }.accessibilityIdentifier("completedCard")
                    } else if today.state == "cancelled" {
                        InfoCard {
                            Label("Bugün ara verdiniz", systemImage: "pause.circle").font(.title2.bold())
                            Text("Aileniz kontrolün devre dışı olduğunu görür. Yarın otomatik devam eder.")
                            PrimaryButton(title: "Bugün yeniden etkinleştir", busy: state.loading) { Task { await state.pause(false) } }
                        }
                    } else {
                        Button { Task { await state.complete() } } label: {
                            VStack(spacing: 16) {
                                if state.sending { ProgressView().tint(.white).scaleEffect(1.5) }
                                else { Image(systemName: "checkmark").font(.system(size: 44, weight: .medium)) }
                                Text(state.sending ? "Gönderiliyor" : "BEN İYİYİM").font(.largeTitle.bold())
                                Text("Aileme haber ver").font(.title3)
                            }.frame(maxWidth: .infinity, minHeight: 210).padding(12)
                        }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .background(Design.green, in: RoundedRectangle(cornerRadius: 32))
                        .disabled(state.sending || state.loading)
                        .accessibilityLabel("Bugün iyi olduğumu bildir").accessibilityIdentifier("checkInButton")
                    }
                    InfoCard {
                        let tomorrow = today.state == "completed" || today.remindersEnabled == false
                        Label(tomorrow ? "Bir sonraki hatırlatma" : "Günlük hatırlatma", systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Text("\(tomorrow ? "Yarın" : "Bugün"), \(DateText.time(tomorrow ? today.nextDueAt : today.dueAt))")
                            .font(.title2.bold())
                        if today.remindersEnabled == false { Text("Bugün isterseniz haber verebilirsiniz. Hatırlatma rutininiz yarın başlar.").font(.callout) }
                        else if today.state != "completed" { Text("Haber gelmezse ailenize bilgi: \(DateText.time(today.deadlineAt))").font(.callout) }
                    }
                    NavigationLink { HistoryView(profileID: state.profile?.id ?? "", subjectName: state.profile?.name ?? "") } label: {
                        Label("Geçmiş haberlerim", systemImage: "calendar").font(.title3).frame(minHeight: 56)
                    }
                    if !["completed", "cancelled"].contains(today.state) {
                        Button("Bugün hatırlatmaları durdur") { confirmPause = true }.frame(minHeight: 56)
                    }
                } else {
                    InfoCard {
                        Text("Güncel durum henüz alınamadı.").font(.title2)
                        PrimaryButton(title: "Yeniden dene", busy: state.loading) { Task { await state.reload() } }
                    }
                }
                if APIClient.isLocal { Label("Yerel test · Gerçek SMS / push gönderilmez", systemImage: "hammer").font(.callout).foregroundStyle(Design.amber) }
            }.padding(24)
        }
        .background(Design.background)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await state.reload() }
        .confirmationDialog("Bugün kontrol devre dışı bırakılsın mı?", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("Bugün durdur") { Task { await state.pause(true) } }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("Aileniz kontrolün kapalı olduğunu görecek. Yarın otomatik devam eder.") }
    }
}
