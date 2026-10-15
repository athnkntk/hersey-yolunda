import SwiftUI
import UserNotifications

@main
struct HerseyYolundaApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @StateObject private var state = AppState()
    @StateObject private var languageSettings = LanguageSettings()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .id(languageSettings.preference.rawValue)
                .environmentObject(state)
                .environmentObject(languageSettings)
                .environment(\.locale, L10n.locale)
                .tint(Design.green)
                .preferredColorScheme(.light)
                .task { await state.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && state.signedIn { Task { await state.reload() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .init("HYRemoteNotification"))) { _ in
                    if state.signedIn { Task { await state.reload() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .init("HYNotificationOpened"))) { notification in
                    guard state.signedIn else { return }
                    let type = notification.object as? String ?? ""
                    if type.hasPrefix("reminder_") { state.tab = 0 }
                    else if !type.isEmpty { state.tab = 1 }
                    Task { await state.reload() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .init("HYSelfReminder"))) { _ in
                    if state.signedIn { state.tab = 0; Task { await state.reload() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .init("HYNotificationRegistrationFailed"))) { _ in
                    state.message = L10n.text("Cihazınız bildirim servisine kaydedilemedi. Günlük haberlerinizi uygulamadan kontrol edebilirsiniz.")
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
            if !state.signedIn {
                if state.sessionExpired { SessionExpiredView() } else { WelcomeView() }
            } else if let profile = state.profile, profile.name.isEmpty { ProfileSetupView() }
            else {
                TabView(selection: $state.tab) {
                    NavigationStack { HomeView() }.tabItem { Label(L10n.text("Bugün"), systemImage: "sun.max") }.tag(0)
                    NavigationStack { CircleView() }.tabItem { Label(L10n.text("Ailem"), systemImage: "person.2") }.tag(1)
                    NavigationStack { SettingsView() }.tabItem { Label(L10n.text("Ayarlar"), systemImage: "slider.horizontal.3") }.tag(2)
                }
            }
        }
        .font(.system(.body, design: .rounded))
        .foregroundStyle(Design.ink)
        .sheet(isPresented: $state.showNotificationPrompt) {
            NotificationPromptView().presentationDetents([.medium, .large])
        }
        .alert(Text(L10n.text("İşlem tamamlanamadı")), isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button(L10n.text("Tamam"), role: .cancel) { state.error = nil }
        } message: { Text(state.error ?? "") }
        .alert(Text(L10n.text("Bilgilendirme")), isPresented: Binding(get: { state.message != nil }, set: { if !$0 { state.message = nil } })) {
            Button(L10n.text("Tamam"), role: .cancel) { state.message = nil }
        } message: { Text(state.message ?? "") }
    }
}

struct SessionExpiredView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Herşey Yolunda", systemImage: "leaf.fill").font(.title2.bold()).foregroundStyle(Design.green)
                    Text(L10n.text("Oturum kullanılamıyor")).font(.largeTitle.bold())
                    Text(L10n.text("Bu cihazın oturumu artık kullanılamıyor. Adınız veya hesap kimliğiniz eski hesabı geri açmaz. Yeni hesap oluşturursanız aile bağlantılarını yeniden kurmanız gerekir.")).font(.title3)
                    PrimaryButton(title: L10n.text("Yeni hesap oluştur")) { state.sessionExpired = false }
                        .accessibilityIdentifier("sessionExpiredContinue")
                    Link(L10n.text("Destek sayfası"), destination: URL(string: "https://athnkntk.github.io/hersey-yolunda/?lang=\(L10n.language)")!).frame(minHeight: 56)
                }.padding(24)
            }.background(Design.background)
        }
    }
}

struct NotificationPromptView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
            Label("Herşey Yolunda", systemImage: "bell.badge.fill").font(.title2.bold()).foregroundStyle(Design.green)
            Text(L10n.text("Hatırlatmaları açmak ister misiniz?")).font(.largeTitle.bold())
            Text(L10n.text("Günlük haber saatinizde hatırlatma alabilir ve yakınlarınızdan haberler alabilirsiniz. İzni daha sonra Ayarlar'dan da açabilirsiniz.")).font(.title3)
            PrimaryButton(title: L10n.text("Bildirimlere izin ver")) {
                Task {
                    state.showNotificationPrompt = false
                    await state.notificationPermission()
                }
            }.accessibilityIdentifier("notificationAllow")
            Button(L10n.text("Şimdi değil")) {
                state.showNotificationPrompt = false
                Task { await state.syncNotificationRegistration() }
            }.frame(maxWidth: .infinity, minHeight: 56).accessibilityIdentifier("notificationLater")
            }.padding(28)
        }
        .background(Design.background)
    }
}

struct LanguagePicker: View {
    @EnvironmentObject var settings: LanguageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
    private var picker: some View {
        Picker(selection: $settings.preference) {
            Text(L10n.text("Sistem")).tag(LanguagePreference.system)
            Text("Türkçe").tag(LanguagePreference.tr)
            Text("English").tag(LanguagePreference.en)
        } label: {
            Text(L10n.text("Dil"))
        }
        .accessibilityIdentifier("languagePicker")
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
                    HStack {
                        Label("Herşey Yolunda", systemImage: "leaf.fill").font(.title2.bold()).foregroundStyle(Design.green)
                        Spacer()
                    }
                    LanguagePicker()
                    Text(L10n.text("Bir adımla başlayın.")).font(.largeTitle.bold())
                    Text(L10n.text("Telefon numarası ve SMS gerekmez. Adınızı yazın; hesabınız bu cihaz için oluşturulsun.")).font(.title3)
                    InfoCard {
                        Text(L10n.text("Size nasıl seslenelim?")).font(.title2.bold())
                        TextField(L10n.text("Adınız"), text: $name).textContentType(.givenName)
                            .font(.title2).padding().background(Design.background, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("nameField")
                        Toggle(L10n.text("Ben de günlük haber vereceğim"), isOn: $enabled).font(.title3)
                        Text(enabled ? L10n.text("Her gün tek dokunuşla ailenize haber verin.") : L10n.text("Yalnızca yakınlarınızdan haber alın; sizin için kontrol başlatılmaz.")).foregroundStyle(.secondary)
                        Text(L10n.format("Bu cihazın saat dilimi: %@", TimeZone.current.identifier)).font(.callout).foregroundStyle(.secondary)
                        PrimaryButton(title: L10n.text("Hesabımı oluştur"), busy: busy) { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("createAccount")
                    }
                    Text(L10n.text("Adınız şifre değildir. Yeni cihazda aynı adı yazmak eski hesabınızı açmaz. Bu sürümde Apple ile kurtarma henüz yok; telefon veya oturum kaybında yeni hesap ve aile eşleştirmesi gerekir."))
                        .font(.callout).foregroundStyle(.secondary)
                    if hasPending {
                        Button(L10n.text("Bekleyen hesap oluşturma denemesini sıfırla")) { confirmReset = true }.frame(minHeight: 56)
                    }
                    NavigationLink(L10n.text("Hesabım ve kurtarma hakkında")) { AccountAccessView() }.frame(minHeight: 56)
                    NavigationLink(L10n.text("Gizlilik ve kullanım sınırları")) { PrivacyView() }.frame(minHeight: 56)
                    if APIClient.isLocal { Label(L10n.text("Yerel test sürümü · Gerçek push gönderilmez"), systemImage: "hammer").foregroundStyle(Design.amber) }
                    Text(L10n.text("Acil yardım veya tıbbi müdahale hizmeti değildir.")).font(.callout).foregroundStyle(.secondary)
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
            } catch { if !isCancellationError(error) { state.error = ErrorText.message(for: error) } }
        }
        .confirmationDialog(Text(L10n.text("Yeni hesap oluşturma denemesi başlatılsın mı?")), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L10n.text("Yeni deneme başlat")) { SharedStorage.clearRegistration(); hasPending = false }
        } message: { Text(L10n.text("Önceki denemede sunucuda hesap oluştuysa bu işlem o hesaba giriş sağlamaz. İlişkili kayıtları silmez; sonraki deneme ayrı bir hesap oluşturur.")) }
    }
    private func create() async {
        busy = true
        defer { busy = false }
        do {
            try await state.api.createAccount(name: name, enabled: enabled)
            await state.beginSession()
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .notDetermined { state.showNotificationPrompt = true }
            else { await state.syncNotificationRegistration() }
            if !enabled || !state.invitationToken.isEmpty { state.tab = 1 }
        } catch {
            hasPending = (try? SharedStorage.registration()) != nil
            if !isCancellationError(error) { state.error = ErrorText.message(for: error) }
        }
    }
}

struct ProfileSetupView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var enabled = true
    private var firstReminderText: String {
        let zone = TimeZone(identifier: state.profile?.timezone ?? "") ?? .current
        let calendar = DateText.calendar(timeZone: zone)
        let at9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        return DateText.time(at9, timeZone: zone)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "hand.wave").font(.system(size: 52)).foregroundStyle(Design.green)
                Text(L10n.text("Size nasıl seslenelim?")).font(.largeTitle.bold())
                Text(L10n.text("Sadece adınız yeterli. Bunu izin verdiğiniz yakınlarınız görecek.")).font(.title3)
                TextField(L10n.text("Adınız"), text: $name).textContentType(.givenName).font(.title2).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("nameField")
                Toggle(L10n.text("Ben de günlük haber vereceğim"), isOn: $enabled).font(.title3)
                Text(enabled ? L10n.text("Her gün tek dokunuşla ailenize haber verebilirsiniz.") : L10n.text("Yalnızca yakınlarınızdan haber alacaksınız. Kendiniz için günlük kontrol başlatılmaz.")).foregroundStyle(.secondary)
                PrimaryButton(title: L10n.text("Başlayalım"), busy: state.loading) {
                    Task {
                        await state.perform {
                            let _: Profile = try await state.api.request("PATCH", "/me/profile", body: ["name": name, "enabled": enabled])
                            await state.reload()
                            if !enabled { state.tab = 1 }
                        }
                    }
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("saveProfile")
                Text(L10n.format("İlk hatırlatma saatiniz %@. Ayarlardan değiştirebilirsiniz. Ailenizi eklemeden kimseye bilgi paylaşılmaz.", firstReminderText))
                    .foregroundStyle(.secondary)
            }.padding(28).padding(.top, 50)
        }.background(Design.background)
    }
}

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmPause = false
    private var accountZone: TimeZone {
        TimeZone(identifier: state.today?.timezone ?? state.profile?.timezone ?? "") ?? .current
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("HERŞEY YOLUNDA", systemImage: "leaf.fill").font(.caption.weight(.bold)).tracking(1.5)
                    Spacer()
                    Text(DateText.headerDay(ServerClock.now() ?? Date(), timeZone: accountZone)).font(.subheadline)
                }.foregroundStyle(Design.green)
                Text(L10n.format("Merhaba,\n%@", state.profile?.name ?? "")).font(.system(.largeTitle, design: .rounded, weight: .bold))
                if let stale = state.refreshFailedMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(stale).font(.callout)
                        Spacer()
                        Button(L10n.text("Yeniden dene")) { Task { await state.reload() } }
                            .font(.callout.weight(.semibold))
                    }
                    .padding(14)
                    .background(Design.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(Design.ink)
                }
                if state.profile?.enabled == false {
                    InfoCard {
                        Label(L10n.text("Ailenizden bir haber"), systemImage: "person.2.fill").font(.title2.bold())
                        Text(L10n.text("Sizin için günlük kontrol açık değil. Yakınlarınızın haberlerini Ailem ekranında görebilirsiniz.")).font(.title3)
                        PrimaryButton(title: L10n.text("Aileme git")) { state.tab = 1 }
                    }
                } else if let today = state.today, today.isCurrent() {
                    Text(today.title).font(.title3).accessibilityIdentifier("todayStatus")
                    if today.state == "completed" {
                        InfoCard {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Design.green)
                            Text(L10n.text("Bugün haber verdiniz.")).font(.title.bold())
                            if let date = today.completedAt { Text(DateText.time(date, timeZone: accountZone)).font(.title2.monospacedDigit()) }
                            Text(today.trustedContacts > 0 ? L10n.text("Aileniz uygulamada iyi olduğunuzu görebilir.") : L10n.text("Haberiniz kaydedildi. Ailenize haber vermek için bir yakınınızı ekleyin."))
                                .font(.title3)
                        }.accessibilityElement(children: .contain)
                        .accessibilityIdentifier("completedCard")
                    } else if today.state == "cancelled" {
                        InfoCard {
                            Label(L10n.text("Bugün ara verdiniz"), systemImage: "pause.circle").font(.title2.bold())
                            Text(L10n.text("Aileniz kontrolün devre dışı olduğunu görür. Yarın otomatik devam eder."))
                            PrimaryButton(title: L10n.text("Bugün yeniden etkinleştir"), busy: state.loading) { Task { await state.pause(false) } }
                        }
                    } else {
                        Button { Task { await state.complete() } } label: {
                            VStack(spacing: 16) {
                                if state.sending { ProgressView().tint(.white).scaleEffect(1.5) }
                                else { Image(systemName: "checkmark").font(.system(size: 44, weight: .medium)) }
                                Text(L10n.text(state.sending ? "Gönderiliyor" : "BEN İYİYİM")).font(.largeTitle.bold())
                                Text(L10n.text("Aileme haber ver")).font(.title3)
                            }.frame(maxWidth: .infinity, minHeight: 210).padding(12)
                        }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .background(Design.green, in: RoundedRectangle(cornerRadius: 32))
                        .disabled(state.sending)
                        .accessibilityLabel(L10n.text("Bugün iyi olduğumu bildir")).accessibilityIdentifier("checkInButton")
                    }
                    InfoCard {
                        let closed = ["completed", "cancelled"].contains(today.state)
                        let tomorrow = closed || today.remindersEnabled == false
                        Label(L10n.text(tomorrow ? "Bir sonraki hatırlatma" : "Günlük hatırlatma"), systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Text(L10n.format(tomorrow ? "Yarın, %@" : "Bugün, %@", DateText.time(tomorrow ? today.nextDueAt : today.dueAt, timeZone: accountZone)))
                            .font(.title2.bold())
                        if today.remindersEnabled == false { Text(L10n.text("Bugün isterseniz haber verebilirsiniz. Hatırlatma rutininiz yarın başlar.")).font(.callout) }
                        else if !closed { Text(L10n.format("%@ itibarıyla yakınlarınız haber vermediğinizi uygulamada görebilir", DateText.time(today.deadlineAt, timeZone: accountZone))).font(.callout) }
                    }
                    NavigationLink { HistoryView(profileID: state.profile?.id ?? "", subjectName: state.profile?.name ?? "", timezone: state.profile?.timezone) } label: {
                        Label(L10n.text("Geçmiş haberlerim"), systemImage: "calendar").font(.title3).frame(minHeight: 56)
                    }
                    if !["completed", "cancelled"].contains(today.state) {
                        Button(L10n.text("Bugün hatırlatmaları durdur")) { confirmPause = true }.frame(minHeight: 56)
                    }
                } else {
                    InfoCard {
                        Text(L10n.text("Güncel durum henüz alınamadı.")).font(.title2)
                        PrimaryButton(title: L10n.text("Yeniden dene"), busy: state.loading) { Task { await state.reload() } }
                    }
                }
                if APIClient.isLocal { Label(L10n.text("Yerel test · Gerçek SMS / push gönderilmez"), systemImage: "hammer").font(.callout).foregroundStyle(Design.amber) }
            }.padding(24)
        }
        .background(Design.background)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await state.reload() }
        .confirmationDialog(Text(L10n.text("Bugün kontrol devre dışı bırakılsın mı?")), isPresented: $confirmPause, titleVisibility: .visible) {
            Button(L10n.text("Bugün durdur")) { Task { await state.pause(true) } }
            Button(L10n.text("Vazgeç"), role: .cancel) {}
        } message: { Text(L10n.text("Aileniz kontrolün kapalı olduğunu görecek. Yarın otomatik devam eder.")) }
    }
}
