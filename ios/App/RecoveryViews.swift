import SwiftUI
import UIKit

/// Kurtarma anahtarını paylaşan ortak görünüm parçaları: anahtar metni
/// ekran görüntülerinde gizlenir (privacySensitive) ve panoya yalnızca
/// yerel + 2 dakikalık süreyle kopyalanır.
private struct RecoveryKeyBox: View {
    let key: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(key)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .privacySensitive()
                .accessibilityIdentifier("recoveryKeyValue")
            Button(L10n.text("Kopyala")) {
                UIPasteboard.general.setObjects([key], localOnly: true, expirationDate: Date().addingTimeInterval(120))
            }
            .frame(minHeight: 44)
        }
    }
}

private struct SavedCheckRow: View {
    @Binding var saved: Bool
    var body: some View {
        Button { saved.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: saved ? "checkmark.square.fill" : "square")
                    .foregroundStyle(saved ? Design.green : Color.secondary)
                Text(L10n.text("Anahtarı güvenli bir yere kaydettim")).font(.body.weight(.medium))
                    .foregroundStyle(Design.ink)
                Spacer()
            }.frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recoveryKeySaved")
        .accessibilityValue(saved ? "1" : "0")
    }
}

/// Ayarlar → Hesabım ve kurtarma altında kurtarma anahtarının durumu,
/// oluşturma/yenileme ve kapatma akışı. Sunucu anahtarı asla göstermez;
/// anahtar yalnızca kullanıcı oluştururken bir kez görünür.
struct RecoveryKeySettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var status: RecoveryStatus?
    @State private var loadState: LoadState = .idle
    @State private var pending: PendingRecoverySetup?
    @State private var saved = false
    @State private var busy = false
    @State private var confirmDisable = false
    @State private var errorMessage: String?
    private var userID: String { state.profile?.id ?? "" }

    var body: some View {
        List {
            if !loaded {
                Section { LoadStateView(state: loadState, empty: "", retry: load) }
            }
            if let status {
                Section(L10n.text("Durum")) {
                    Label(status.enabled ? L10n.text("Kurtarma anahtarı etkin") : L10n.text("Kurtarma anahtarı kapalı"),
                          systemImage: status.enabled ? "key.fill" : "key.slash")
                        .accessibilityIdentifier("recoveryStatus")
                    if let updated = status.updatedAt {
                        Text(DateText.stamp(updated, timeZone: .current)).foregroundStyle(.secondary)
                    }
                    Text(L10n.text("Kurtarma anahtarı, cihazınızı veya oturumunuzu kaybederseniz aynı hesabı yeni bir cihazda açmanızı sağlar. Adınız veya hesap kimliğiniz bunun yerine geçmez."))
                        .foregroundStyle(.secondary)
                }
            }
            if let pending {
                Section(L10n.text("Yeni anahtarınız")) {
                    Text(L10n.text("Bu anahtar henüz etkin değil. Güvenli bir yere kaydedip aşağıdan etkinleştirin. Elinde bulunduran herkes hesabınıza erişebilir; anahtar bizde saklanmaz ve sonradan gösterilemez."))
                        .foregroundStyle(Design.amber)
                    if status?.enabled == true {
                        Text(L10n.text("Etkinleştirme mevcut anahtarınızın yerini alır; önceki anahtar artık çalışmaz."))
                            .foregroundStyle(Design.amber)
                    }
                    RecoveryKeyBox(key: pending.key)
                    SavedCheckRow(saved: $saved)
                    Button(L10n.text("Anahtarı etkinleştir")) { Task { await activate() } }
                        .frame(minHeight: 56).disabled(!saved || busy)
                        .accessibilityIdentifier("activateRecoveryKey")
                    Button(L10n.text("Vazgeç"), role: .cancel) { cancelPending() }
                        .frame(minHeight: 56).disabled(busy)
                }
            }
            if loaded, pending == nil {
                Section {
                    Button(status?.enabled == true ? L10n.text("Anahtarı yenile") : L10n.text("Kurtarma anahtarı oluştur")) {
                        Task { await generate() }
                    }.frame(minHeight: 56).disabled(busy)
                    if status?.enabled == true {
                        Button(L10n.text("Kurtarma anahtarını kapat"), role: .destructive) { confirmDisable = true }
                            .frame(minHeight: 56).disabled(busy)
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(L10n.text("Kurtarma anahtarı"))
        .task(id: userID) { if loadState == .idle { await load() } }
        .interactiveDismissDisabled(busy)
        .confirmationDialog(Text(L10n.text("Kurtarma anahtarı kapatılsın mı?")), isPresented: $confirmDisable, titleVisibility: .visible) {
            Button(L10n.text("Anahtarı kapat"), role: .destructive) { Task { await disable() } }
        } message: {
            Text(L10n.text("Kapatırsanız kaydettiğiniz anahtar bu hesabı artık açamaz. Oturum kaybında hesabınıza dönemezsiniz."))
        }
    }

    private var loaded: Bool { loadState == .loaded }

    private func load() async {
        guard !busy else { return }
        if loadState != .loaded { loadState = .loading }
        do {
            status = try await state.api.recoveryStatus(expectedUser: userID)
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            loadState = .failed(L10n.text("Kurtarma durumu alınamadı. Yeniden deneyin."))
        }
    }
    private func generate() async {
        busy = true
        defer { busy = false }
        do {
            pending = try await state.api.prepareRecoveryKey(expectedUser: userID)
            saved = false
        } catch {
            if !isCancellationError(error) { errorMessage = ErrorText.message(for: error) }
        }
    }
    private func activate() async {
        guard let pending else { return }
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            status = try await state.api.activateRecoveryKey(pending)
            if status?.enabled == true {
                self.pending = nil
                state.message = L10n.text("Kurtarma anahtarı etkin. Anahtar artık gösterilmez; kaydettiğiniz kopyayı kullanın.")
            }
        } catch {
            if !isCancellationError(error) { errorMessage = ErrorText.message(for: error) }
        }
    }
    private func cancelPending() {
        SharedStorage.clearRecoverySetup()
        pending = nil
        saved = false
    }
    private func disable() async {
        guard let version = status?.version else { return }
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            status = try await state.api.disableRecoveryKey(expectedUser: userID, version: version)
            if status?.enabled == false {
                state.message = L10n.text("Kurtarma anahtarı kapatıldı.")
            }
        } catch {
            if !isCancellationError(error) { errorMessage = ErrorText.message(for: error) }
        }
    }
}

/// Oturum yokken (hoş geldin / oturum düştü ekranlarından) hesap kurtarma.
/// Önce eski anahtar doğrulanır ve yeni anahtar kaydedilir; ancak bundan sonra
/// ağ isteği yapılır. Başarılı yanıt oturumu açar ve eski oturumları kapatır.
struct RecoverAccountView: View {
    @EnvironmentObject var state: AppState
    @State private var key = ""
    @State private var pending: PendingAccountRecovery?
    @State private var saved = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var resumable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Herşey Yolunda", systemImage: "key.fill").font(.title2.bold()).foregroundStyle(Design.green)
                Text(L10n.text("Hesabınızı kurtarın")).font(.largeTitle.bold())
                if let pending {
                    pendingStep(pending)
                } else {
                    entryStep
                }
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.red)
                }
                if resumable && pending == nil {
                    Button(L10n.text("Yarım kalan kurtarma denemesine devam et")) { resume() }
                        .frame(minHeight: 56).accessibilityIdentifier("recoveryResume")
                }
                Text(L10n.text("Adınız veya hesap kimliğiniz hesabı geri açmaz. Kurtarma yalnızca daha önce oluşturup kaydettiğiniz anahtarla yapılır."))
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(Design.background)
        .navigationTitle(L10n.text("Hesap kurtarma"))
        .interactiveDismissDisabled(busy)
        .task { resumable = (try? SharedStorage.accountRecovery()) != nil }
    }

    private var entryStep: some View {
        InfoCard {
            Text(L10n.text("Kaydettiğiniz kurtarma anahtarını yazın veya yapıştırın. Anahtar “HYR1.” ile başlar.")).font(.title3)
            SecureField(L10n.text("Kurtarma anahtarı"), text: $key)
                .font(.body.monospaced()).padding()
                .background(Design.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("recoveryKeyInput")
            PrimaryButton(title: L10n.text("Devam"), busy: busy) { Task { await prepare() } }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("recoveryContinue")
        }
    }

    private func pendingStep(_ pending: PendingAccountRecovery) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            InfoCard {
                Text(L10n.text("Yeni kurtarma anahtarınız")).font(.title2.bold())
                Text(L10n.text("Kurtarma tamamlanınca eski anahtarınızın yerini bu anahtar alır. Şimdi güvenli bir yere kaydedin; sonradan gösterilmez ve bizden istenemez."))
                RecoveryKeyBox(key: pending.replacementKey)
                SavedCheckRow(saved: $saved)
            }
            Text(L10n.text("Kurtarma sonrası eski anahtarınız değiştirilir ve diğer cihazlardaki oturumlar kapatılır."))
                .font(.callout).foregroundStyle(Design.amber)
            PrimaryButton(title: L10n.text("Hesabımı kurtar"), busy: busy) { Task { await recover(pending) } }
                .disabled(!saved || busy)
                .accessibilityIdentifier("recoverAccount")
            Button(L10n.text("Denemeyi sil ve yeniden başla"), role: .destructive) {
                state.api.discardAccountRecovery()
                self.pending = nil
                self.saved = false
                self.resumable = false
            }.frame(minHeight: 56).disabled(busy)
        }
    }

    private func prepare() async {
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            pending = try await state.api.prepareAccountRecovery(key: key)
        } catch {
            if !isCancellationError(error) { errorMessage = ErrorText.message(for: error) }
        }
    }
    private func resume() {
        if let existing = try? SharedStorage.accountRecovery() {
            pending = existing
            resumable = false
        }
    }
    private func recover(_ pending: PendingAccountRecovery) async {
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            try await state.api.recoverAccount(pending)
            await state.beginSession()
        } catch {
            // Bekleyen anahtar korunur; hata başarıyı asla taklit etmez.
            if !isCancellationError(error) { errorMessage = ErrorText.message(for: error) }
        }
    }
}
