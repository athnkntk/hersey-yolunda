import SwiftUI
import UserNotifications
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var profile: Profile?
    @Published var today: Today?
    @Published var signedIn = false
    @Published var loading = false
    @Published var sending = false
    @Published var error: String?
    @Published var message: String?
    @Published var tab = 0
    @Published var invitationToken = ""
    @Published var online = false
    let api = APIClient.shared
    private var sessionObserver: AnyCancellable?

    init() {
        sessionObserver = NotificationCenter.default.publisher(for: .init("HYSessionExpired"))
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.signedIn = false
                self?.profile = nil
                self?.today = nil
            }
    }

    func restore() async {
        if ProcessInfo.processInfo.arguments.contains("--uitest-clean") {
            try? await api.forgetSession()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-signed-in") {
            signedIn = true
            return
        }
        signedIn = (try? SharedStorage.session()) != nil
        if signedIn { await reload() }
    }
    func reload() async {
        loading = true
        defer { loading = false }
        do {
            let user: Profile = try await api.request("GET", "/me")
            let status: Today = try await api.request("GET", "/me/checkin/today")
            profile = user
            today = status
            online = true
            SharedStorage.saveSnapshot(profile: user, today: status)
        } catch {
            if isCancellationError(error) { return }
            online = false
            self.error = error.localizedDescription
        }
    }
    func complete() async {
        guard !sending, let profile, let today else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            self.today = try await api.checkIn(profile: profile, today: today, source: "app")
            online = true
        } catch { if !isCancellationError(error) { self.error = error.localizedDescription } }
    }
    func pause(_ value: Bool) async {
        await perform {
            let result: Today = try await self.api.request("POST", value ? "/me/checkin/today/pause" : "/me/checkin/today/resume")
            self.today = result
            if let profile = self.profile { SharedStorage.saveSnapshot(profile: profile, today: result) }
        }
    }
    func perform(_ work: () async throws -> Void) async {
        loading = true
        defer { loading = false }
        do { try await work() } catch { if !isCancellationError(error) { self.error = error.localizedDescription } }
    }
    func logout() async {
        await perform {
            try await self.api.logout()
            self.signedIn = false
            self.profile = nil
            self.today = nil
        }
    }


    func notificationPermission() async {
        await perform {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            let defaults = UserDefaults.standard
            guard let userID = self.profile?.id else { return }
            let key = "deviceID.\(userID)"
            let device = defaults.string(forKey: key) ?? UUID().uuidString
            defaults.set(device, forKey: key)
            let _: EmptyResponse = try await self.api.request("POST", "/me/devices", body: ["id": device, "permission": allowed ? "authorized" : "denied"])
            struct Health: Decodable { let push_configured: Bool }
            let pushReady = (try? await self.api.request("GET", "/health", authenticated: false) as Health)?.push_configured ?? false
            if allowed && pushReady && !APIClient.isLocal { UIApplication.shared.registerForRemoteNotifications() }
            self.message = allowed
                ? (pushReady && !APIClient.isLocal
                    ? "Bildirim izni açık. Cihaz kaydı tamamlanınca bildirim alabilirsiniz."
                    : "Bildirim izni açık. Anlık bildirim servisi henüz etkinleştirilmedi; durumları uygulamadan takip edebilirsiniz.")
                : "Bildirim izni kapalı. Günlük durumunuzu uygulamada görebilirsiniz."
        }
    }
}

func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? URLError)?.code == .cancelled
}

enum Design {
    static let green = Color(red: 0.09, green: 0.38, blue: 0.26)
    static let ink = Color(red: 0.09, green: 0.15, blue: 0.12)
    static let background = Color(red: 0.98, green: 0.98, blue: 0.96)
    static let amber = Color(red: 0.48, green: 0.32, blue: 0.07)
}

struct PrimaryButton: View {
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
