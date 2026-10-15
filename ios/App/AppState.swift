import SwiftUI
import StoreKit
import UserNotifications
import Combine

enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

struct LoadStateView: View {
    let state: LoadState
    let empty: String
    let retry: () async -> Void
    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity).padding(24)
        case .loaded:
            Text(empty).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(24)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button(L10n.text("Yeniden dene")) { Task { await retry() } }
                    .font(.callout.weight(.semibold)).foregroundStyle(Design.green)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var profile: Profile?
    @Published var today: Today?
    @Published var signedIn = false
    @Published private(set) var loading = false
    @Published var sending = false
    @Published var error: String?
    @Published var message: String?
    @Published var tab = 0
    @Published var invitationToken = ""
    @Published var online = false
    @Published var refreshGeneration = 0
    @Published var sessionExpired = false
    @Published var showNotificationPrompt = false
    let api: APIClient
    private var sessionObserver: AnyCancellable?
    private var languageObserver: AnyCancellable?
    private var operations = 0
    private var sessionGeneration = 0
    private var mutationRevision = 0
    private var reloadTask: Task<Void, Never>?
    private var reloadID: UUID?
    private var restored = false

    init(api: APIClient = .shared) {
        self.api = api
        sessionObserver = NotificationCenter.default.publisher(for: .init("HYSessionExpired"))
            .receive(on: RunLoop.main).sink { [weak self] notification in
                self?.handleSessionExpired(failedUser: notification.object as? String)
            }
        languageObserver = NotificationCenter.default.publisher(for: .init("HYLanguageChanged"))
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    if let today = self.today {
                        await LocalNotifications.sync(today: today, enabled: self.profile?.enabled ?? false)
                    }
                    await self.syncNotificationRegistration()
                }
            }
    }

    private func begin() { operations += 1; loading = true }
    private func end() { operations = max(0, operations - 1); loading = operations > 0 }

    private func handleSessionExpired(failedUser: String?) {
        if (try? SharedStorage.session()) != nil { return }
        if let failedUser, let loaded = profile, loaded.id != failedUser { return }
        endSession(expired: true)
    }

    /// Oturum sonlandığında ortak sıfırlama: devam eden yenileme iptal edilir,
    /// eski hesaba ait tüm bellek içi durum temizlenir.
    func endSession(expired: Bool) {
        sessionGeneration += 1
        mutationRevision += 1
        reloadTask?.cancel()
        reloadTask = nil
        reloadID = nil
        profile = nil
        today = nil
        signedIn = false
        online = false
        sending = false
        error = nil
        message = nil
        showNotificationPrompt = false
        sessionExpired = expired
        LocalNotifications.cancelReminders()
    }

    func beginSession() async {
        endSession(expired: false)
        sessionExpired = false
        restored = true
        signedIn = true
        await reload()
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        if ProcessInfo.processInfo.arguments.contains("--uitest-clean") {
            try? await api.forgetSession()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-signed-in") {
            signedIn = true
            return
        }
        signedIn = (try? SharedStorage.session()) != nil
        if signedIn {
            if profile == nil { profile = SharedStorage.cachedProfile() }
            if today == nil { today = SharedStorage.snapshot()?.today }
            await reload()
        }
    }
    func reload() async {
        if let reloadTask { await reloadTask.value; return }
        guard signedIn else { return }
        let user = profile?.id ?? (try? SharedStorage.session())?.auth.userId
        let generation = sessionGeneration
        let revision = mutationRevision
        let id = UUID()
        reloadID = id
        let task = Task { @MainActor in await self.fetch(generation: generation, revision: revision, expectedUser: user) }
        reloadTask = task
        await task.value
        if reloadID == id {
            reloadTask = nil
            reloadID = nil
        }
    }
    private func fetch(generation: Int, revision: Int, expectedUser: String?) async {
        begin()
        defer { end() }
        do {
            let user: Profile = try await api.request("GET", "/me", expectedUser: expectedUser)
            guard !Task.isCancelled, generation == sessionGeneration, signedIn, revision == mutationRevision,
                  expectedUser == nil || user.id == expectedUser else { return }
            let status: Today = try await api.request("GET", "/me/checkin/today", expectedUser: user.id)
            guard !Task.isCancelled, generation == sessionGeneration, signedIn, revision == mutationRevision,
                  status.userId == user.id else { return }
            profile = user
            if status.supersedes(today) { today = status }
            online = true
            refreshGeneration += 1
            SharedStorage.saveSnapshot(profile: user, today: status)
            await LocalNotifications.sync(today: status, enabled: user.enabled)
            await syncNotificationRegistration()
        } catch {
            if isCancellationError(error) { return }
            guard generation == sessionGeneration else { return }
            online = false
            if profile == nil { self.error = ErrorText.message(for: error) }
        }
    }
    /// Önbellekteki veri dururken yenileme başarısız olduğunda gösterilen dürüst durum mesajı.
    var refreshFailedMessage: String? {
        online || profile == nil ? nil : L10n.text("Son durum yenilenemedi. Gösterilen bilgiler güncel olmayabilir.")
    }
    func complete() async {
        guard !sending, let profile, let today else { return }
        let generation = sessionGeneration
        mutationRevision += 1
        let revision = mutationRevision
        sending = true
        error = nil
        defer { if generation == sessionGeneration { sending = false } }
        do {
            let result = try await api.checkIn(profile: profile, today: today, source: "app")
            guard generation == sessionGeneration, revision == mutationRevision, signedIn else { return }
            self.today = result
            online = true
            refreshGeneration += 1
            await LocalNotifications.sync(today: result, enabled: profile.enabled)
            ReviewPrompt.checkInCompleted()
        } catch {
            if isCancellationError(error) { return }
            guard generation == sessionGeneration, revision == mutationRevision else { return }
            self.error = ErrorText.message(for: error)
        }
    }
    func pause(_ value: Bool) async {
        guard let userID = profile?.id else { return }
        let generation = sessionGeneration
        mutationRevision += 1
        let revision = mutationRevision
        begin()
        defer { end() }
        do {
            let result: Today = try await self.api.request("POST", value ? "/me/checkin/today/pause" : "/me/checkin/today/resume", expectedUser: userID)
            guard generation == sessionGeneration, revision == mutationRevision, signedIn else { return }
            self.today = result
            refreshGeneration += 1
            if let profile = self.profile {
                SharedStorage.saveSnapshot(profile: profile, today: result)
                await LocalNotifications.sync(today: result, enabled: profile.enabled)
            }
        } catch {
            if isCancellationError(error) { return }
            guard generation == sessionGeneration, revision == mutationRevision else { return }
            self.error = ErrorText.message(for: error)
        }
    }
    func perform(_ work: () async throws -> Void) async {
        let generation = sessionGeneration
        begin()
        defer { end() }
        do { try await work() } catch {
            if isCancellationError(error) { return }
            guard generation == sessionGeneration else { return }
            self.error = ErrorText.message(for: error)
        }
    }
    func logout() async {
        let userID = profile?.id ?? (try? SharedStorage.session())?.auth.userId
        await perform {
            try await self.api.logout(expectedUser: userID)
            if self.profile == nil || self.profile?.id == userID { self.endSession(expired: false) }
        }
    }


    /// Kullanıcıya sormadan cihaz kaydını eşitler; hatırlatma zamanlaması
    /// fetch/izin akışlarında ayrıca yapılır.
    func syncNotificationRegistration() async {
        guard let userID = profile?.id else { return }
        let generation = sessionGeneration
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard generation == sessionGeneration, profile?.id == userID else { return }
        let permission: String
        switch status {
        case .authorized, .provisional: permission = "authorized"
        case .denied: permission = "denied"
        default: permission = "not_determined"
        }
        let defaults = UserDefaults.standard
        let key = "deviceID.\(userID)"
        let device = defaults.string(forKey: key) ?? UUID().uuidString
        defaults.set(device, forKey: key)
        do {
            let _: EmptyResponse = try await api.request("POST", "/me/devices", body: ["id": device, "permission": permission, "locale": L10n.language], expectedUser: userID)
        } catch { return }
        guard generation == sessionGeneration, profile?.id == userID else { return }
        guard permission == "authorized" else { return }
        let pushReady = (try? await api.request("GET", "/health", authenticated: false) as Health)?.pushConfigured ?? false
        guard generation == sessionGeneration, profile?.id == userID else { return }
        if pushReady && !APIClient.isLocal { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Kullanıcının açık eylemiyle sistem izni ister; sonra cihaz kaydını eşitler.
    func notificationPermission() async {
        await perform {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if status == .denied {
                self.message = L10n.text("Bildirim izni kapalı. Açılan Ayarlar ekranında Bildirimler'i açın; günlük hatırlatmalar ancak böyle çalışır.")
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
                return
            }
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            await self.syncNotificationRegistration()
            let updated = await center.notificationSettings().authorizationStatus
            guard updated == .authorized || updated == .provisional else { return }
            if let today = self.today {
                await LocalNotifications.sync(today: today, enabled: self.profile?.enabled ?? false)
            }
            let pushReady = (try? await self.api.request("GET", "/health", authenticated: false) as Health)?.pushConfigured ?? false
            self.message = pushReady && !APIClient.isLocal
                ? L10n.text("Bildirim izni açık. Cihaz kaydı tamamlanınca bildirim alabilirsiniz.")
                : L10n.text("Bildirim izni açık. Günlük hatırlatmalarınız cihazınızda zamanlanır.")
        }
    }
}

func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? URLError)?.code == .cancelled
}

/// App Store değerlendirme istemi: yalnızca gerçekten başarılı check-in sayısına bakar.
enum ReviewPrompt {
    static func shouldAsk(completedCount: Int) -> Bool {
        completedCount == 3 || (completedCount > 3 && completedCount % 25 == 0)
    }
    @MainActor
    static func checkInCompleted() {
        let key = "review.completedCount"
        let count = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(count, forKey: key)
        guard shouldAsk(completedCount: count),
              let scene = UIApplication.shared.connectedScenes
                  .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        AppStore.requestReview(in: scene)
    }
}

enum Design {
    static let green = Color(red: 0.09, green: 0.38, blue: 0.26)
    static let ink = Color(red: 0.09, green: 0.15, blue: 0.12)
    static let background = Color(red: 0.98, green: 0.98, blue: 0.96)
    static let amber = Color(red: 0.48, green: 0.32, blue: 0.07)
}

struct PrimaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if busy { ProgressView().tint(.white) }
                Text(title).font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Design.green, in: RoundedRectangle(cornerRadius: 20))
        .opacity(isEnabled || busy ? 1 : 0.5)
        .disabled(busy)
    }
}

struct InfoCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
}
