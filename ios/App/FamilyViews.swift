import SwiftUI
import CoreImage.CIFilterBuiltins

struct CircleView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var store = StoreKitManager.shared
    @State private var relatives: [Relative] = []
    @State private var relationships: [Relationship] = []
    @State private var invitations: [Invitation] = []
    @State private var selectedRelation: Relationship?
    @State private var showPaywall = false
    @State private var loadState: LoadState = .idle
    @State private var loadingList = false
    private var hasContent: Bool { !relatives.isEmpty || !invitations.isEmpty || !relationships.isEmpty }
    var body: some View {
        List {
            if case .failed(let message) = loadState, hasContent {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                        Button(L10n.text("Yeniden dene")) { Task { await load() } }
                    }
                }
            }
            Section {
                Text(L10n.text("Takip etmek değil, haber almak.")).font(.title3).listRowBackground(Color.clear)
                NavigationLink { AcceptInvitationView() } label: {
                    Label(L10n.text("Davet kodum var"), systemImage: "envelope.open").frame(minHeight: 56)
                }
            }
            if !store.isPremium {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Aile özellikleri Premium ile açılır")).font(.title3.bold())
                        Text(L10n.text("Yakın davet etme, yakınlarınızın günlük durumunu görme, geçmiş ve bildirimler Premium'dadır. Fiyatı ve varsa deneme seçeneklerini inceleyin."))
                            .foregroundStyle(.secondary)
                        PrimaryButton(title: L10n.text("Premium'u incele")) { showPaywall = true }
                            .accessibilityIdentifier("premiumBanner")
                    }.padding(.vertical, 8)
                }
            }
            if store.isPremium {
            Section {
                NavigationLink { InviteView() } label: {
                    Label(L10n.text("Yakınımı davet et"), systemImage: "person.badge.plus").frame(minHeight: 56)
                }
            }
            }
            if !state.invitationToken.isEmpty {
                Section { NavigationLink(L10n.text("Gelen daveti görüntüle")) { AcceptInvitationView() } }
            }
            if store.isPremium {
                Section(L10n.text("Yakınlarım")) {
                    if relatives.isEmpty {
                        LoadStateView(state: loadState, empty: L10n.text("Henüz bağlı bir yakınınız yok. Davet kabul edilip paylaşım onaylandığında burada görünür."), retry: load)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(relatives) { relative in
                        NavigationLink { RelativeDetailView(relative: relative) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: relative.isCompleted ? "checkmark.circle.fill" : "clock")
                                    .font(.title).foregroundStyle(relative.isCompleted ? Design.green : Design.amber)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(relative.profile.name).font(.title3.bold())
                                    Text(relative.status())
                                    if let date = relative.today.completedAt {
                                        Text(DateText.time(date, timeZone: TimeZone(identifier: relative.profile.timezone) ?? .current)).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(.vertical, 10)
                        }
                    }
                }
                Section(L10n.text("Davetlerim")) {
                    ForEach(invitations) { invitation in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(invitation.recipientName ?? L10n.text("Davetiniz bekleniyor")).font(.headline)
                            if invitation.status == "awaiting_approval" {
                                Text(L10n.text("Bu kişinin günlük haberlerinizi görmesini onaylıyor musunuz?"))
                                Button(L10n.text("Paylaşımı onayla")) {
                                    Task {
                                        await state.perform {
                                            let _: ActionResult = try await state.api.request("POST", "/invitations/\(invitation.id)/approve-sharing")
                                            await load()
                                        }
                                    }
                                }.frame(minHeight: 56)
                            } else { Text(L10n.text("Bağlantı kurulmadan veri paylaşılmaz.")).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section(L10n.text("Benim haberimi alanlar")) {
                let viewers = relationships.filter { $0.subjectId == state.profile?.id }
                if viewers.isEmpty {
                    LoadStateView(state: loadState, empty: L10n.text("Günlük haberinizi şu an kimseyle paylaşmıyorsunuz."), retry: load)
                        .listRowBackground(Color.clear)
                }
                ForEach(viewers) { relation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(relation.viewerName).font(.title3.bold())
                        Button(L10n.text("Paylaşımı durdur"), role: .destructive) { selectedRelation = relation }.frame(minHeight: 56)
                    }
                }
            }
        }
        .navigationTitle(L10n.text("Ailem"))
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task(id: state.refreshGeneration) {
            await store.load()
            await load()
        }
        .refreshable { await load() }
        .onChange(of: store.isPremium) { _, _ in Task { await load() } }
        .confirmationDialog(Text(L10n.text("Bu kişiyle paylaşımı durdur?")), isPresented: Binding(get: { selectedRelation != nil }, set: { if !$0 { selectedRelation = nil } }), titleVisibility: .visible) {
            Button(L10n.text("Paylaşımı durdur"), role: .destructive) {
                guard let relation = selectedRelation else { return }
                Task {
                    await state.perform {
                        let _: EmptyResponse = try await state.api.request("DELETE", "/me/relationships/\(relation.id)")
                        selectedRelation = nil
                        await load()
                        await state.reload()
                    }
                }
            }
        } message: { Text(L10n.text("Yeni haberlerinizi ve geçmişinizi uygulamada artık göremez.")) }
    }
    private func load() async {
        guard !loadingList else { return }
        loadingList = true
        defer { loadingList = false }
        if !hasContent { loadState = .loading }
        do {
            let circle: Items<Relationship> = try await state.api.request("GET", "/me/relationships")
            relationships = circle.items
            if store.isPremium {
                let list: Items<Relative> = try await state.api.request("GET", "/me/relatives")
                let pending: Items<Invitation> = try await state.api.request("GET", "/invitations")
                relatives = list.items
                invitations = pending.items
            }
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            loadState = .failed(ErrorText.message(for: error))
        }
    }
}

enum InvitationQR {
    static func image(_ content: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct InviteView: View {
    @EnvironmentObject var state: AppState
    @State private var direction = "share_mine"
    @State private var label = "Yakınım"
    @State private var invitation: NewInvitation?
    var body: some View {
        Form {
            Section(L10n.text("Ne yapmak istersiniz?")) {
                Picker(selection: $direction) {
                    Text(L10n.text("Ben haber vereceğim")).tag("share_mine")
                    Text(L10n.text("Yakınımdan haber alacağım")).tag("request_theirs")
                } label: { Text(L10n.text("Paylaşım yönü")) }.pickerStyle(.inline)
            }
            Section(L10n.text("Yakınlık")) {
                Picker(selection: $label) {
                    ForEach(["Oğlum", "Kızım", "Eşim", "Kardeşim", "Torunum", "Yakınım", "Diğer"], id: \.self) { Text(L10n.text($0)).tag($0) }
                } label: { Text(L10n.text("İlişki")) }
                Text(L10n.text("Bu etiket yetki vermez. Bilgisini paylaşan kişinin açık onayı gerekir.")).foregroundStyle(.secondary)
                Text(L10n.text("Her kişi günlük haberini en fazla 10 yakınıyla paylaşabilir.")).font(.callout).foregroundStyle(.secondary)
            }
            Section {
                if let invitation {
                    if let link = InvitationInput.link(token: invitation.token) {
                        ShareLink(item: link) {
                            Label(L10n.text("Daveti paylaş"), systemImage: "square.and.arrow.up").frame(minHeight: 56)
                        }
                        if let image = InvitationQR.image(link.absoluteString) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(maxWidth: 240).padding(20).background(.white)
                                .accessibilityLabel(L10n.text("Davet QR kodu; diğer telefondan okutun veya aşağıdaki kodu girin"))
                                .accessibilityIdentifier("invitationQR")
                        }
                    }
                    Text(invitation.code).font(.title2.monospaced().bold()).textSelection(.enabled)
                        .accessibilityIdentifier("invitationCode")
                    Text(L10n.text("Bağlantı ve QR, Herşey Yolunda yüklü telefonda açılır. Olmazsa ‘Davet kodum var’ bölümüne kodu yazın. 48 saat geçerlidir; tek kullanımlıktır. Hesap kimliğiniz giriş veya davet kodu değildir.")).foregroundStyle(.secondary)
                } else {
                    Button(L10n.text("Davet oluştur")) {
                        Task {
                            await state.perform { invitation = try await state.api.request("POST", "/invitations", body: ["direction": direction, "label": label]) }
                        }
                    }.frame(minHeight: 56).disabled(state.loading)
                }
            }
        }.navigationTitle(L10n.text("Yakınını davet et"))
    }
}

struct AcceptInvitationView: View {
    @EnvironmentObject var state: AppState
    @State private var token = ""
    @State private var preview: InvitationPreview?
    @State private var result: String?
    @State private var reviewedCredential: [String: String]?
    var body: some View {
        Form {
            Section(L10n.text("Davet kodu")) {
                TextField(L10n.text("Davet kodu veya bağlantısı"), text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("invitationInput")
                    .onChange(of: token) { _, _ in preview = nil; reviewedCredential = nil; result = nil }
                Button(L10n.text("Daveti görüntüle")) {
                    Task {
                        await state.perform {
                            guard let credential = InvitationInput.credentials(token) else { throw LocalError(message: L10n.text("Size gönderilen 12 karakterli davet kodunu veya bağlantısını girin. Hesap ID’si ile eşleşme yapılmaz.")) }
                            let value: InvitationPreview = try await state.api.request("POST", "/invitations/preview", body: credential)
                            guard InvitationInput.credentials(token) == credential else { return }
                            reviewedCredential = credential
                            preview = value
                        }
                    }
                }.frame(minHeight: 56)
            }
            if let preview, result == nil {
                Section(L10n.format("%@ sizi davet etti", preview.creatorName)) {
                    Text(preview.direction == "request_theirs" ? L10n.text("Kabul ederseniz günlük iyi olduğunuz bilgisi, kontrol saati ve onaydan sonraki geçmişiniz bu kişiyle paylaşılır. Konum paylaşılmaz.") : L10n.text("Bu kişinin günlük haberlerini almayı kabul ediyorsunuz. Veri sahibi ayrıca sizi onaylayana kadar erişim açılmaz."))
                    Text(L10n.text("İsimler kullanıcılar tarafından girilir; kimlik doğrulaması değildir. Daveti tanıdığınız kişiden aldığınızdan emin olun.")).foregroundStyle(.secondary)
                    Button(L10n.text("Kabul ediyorum")) { Task { await respond("accept", preview: preview) } }.frame(minHeight: 56)
                    Button(L10n.text("Reddet"), role: .destructive) { Task { await respond("decline", preview: preview) } }.frame(minHeight: 56)
                }
            }
            if let result { Section { Text(result).font(.title3) } }
        }
        .navigationTitle(L10n.text("Gelen davet"))
        .onAppear { token = state.invitationToken }
    }
    private func respond(_ action: String, preview: InvitationPreview) async {
        await state.perform {
            guard let credential = reviewedCredential, credential == InvitationInput.credentials(token) else { throw LocalError(message: L10n.text("Önce güncel daveti görüntüleyin.")) }
            let response: ActionResult = try await state.api.request("POST", "/invitations/\(preview.id)/\(action)", body: credential)
            result = response.status == "awaiting_approval" ? L10n.text("Kabulünüz alındı. Bilgisini paylaşan kişinin onayı bekleniyor.") : response.status == "declined" ? L10n.text("Davet reddedildi.") : L10n.text("Bağlantınız kuruldu. Paylaşımı istediğiniz zaman durdurabilirsiniz.")
            state.invitationToken = ""
        }
    }
}

struct RelativeDetailView: View {
    @EnvironmentObject var state: AppState
    let relative: Relative
    @State private var current: Relative?
    @State private var loadState: LoadState = .idle
    @State private var loadingDetail = false
    private var subjectZone: TimeZone {
        TimeZone(identifier: current?.profile.timezone ?? relative.profile.timezone) ?? .current
    }
    var body: some View {
        List {
            if let current {
                Section(L10n.text("Bugünkü haber")) {
                    Text(current.status()).font(.title3)
                    if let date = current.today.completedAt { Text(DateText.stamp(date, timeZone: subjectZone)) }
                    Text(L10n.format("Kontrol: %@ · %@", DateText.time(current.today.dueAt, timeZone: subjectZone), subjectZone.identifier))
                    Text(L10n.text("Bu bilgi kişinin kendi beyanıdır; sağlık veya güvenlik doğrulaması değildir.")).foregroundStyle(.secondary)
                }
                NavigationLink(L10n.text("Check-in geçmişi")) { HistoryView(profileID: current.id, subjectName: current.profile.name, timezone: current.profile.timezone) }
            } else {
                LoadStateView(state: loadState, empty: L10n.text("Güncel durum henüz alınamadı. Yenilemek için aşağı çekin."), retry: refresh)
            }
            Text(L10n.text("Haber gelmediğinde yakınınızı normal telefon görüşmesiyle arayabilirsiniz. Bu uygulama acil müdahale hizmeti değildir."))
        }.navigationTitle(relative.profile.name)
            .task(id: state.refreshGeneration) { await refresh() }
            .refreshable { await refresh() }
    }
    private func refresh() async {
        guard !loadingDetail else { return }
        loadingDetail = true
        defer { loadingDetail = false }
        if current == nil { loadState = .loading }
        do {
            current = try await state.api.request("GET", "/profiles/\(relative.id)/status")
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            current = nil
            loadState = .failed(ErrorText.message(for: error))
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    let profileID: String
    let subjectName: String
    var timezone: String? = nil
    @State private var items: [HistoryItem] = []
    @State private var loadState: LoadState = .idle
    @State private var loadingList = false
    private var subjectZone: TimeZone { TimeZone(identifier: timezone ?? "") ?? .current }
    var body: some View {
        List {
            if case .failed(let message) = loadState, !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    Button(L10n.text("Yeniden dene")) { Task { await load() } }
                }
            }
            if items.isEmpty {
                switch loadState {
                case .loaded:
                    ContentUnavailableView {
                        Label(L10n.text("Henüz haber yok"), systemImage: "calendar")
                    } description: {
                        Text(L10n.text("Son 30 gündeki ve paylaşım izniniz kapsamındaki kayıtlar burada görünür."))
                    }
                default:
                    LoadStateView(state: loadState, empty: L10n.text("Henüz haber yok"), retry: load)
                }
            }
            ForEach(items) { item in
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DateText.stamp(item.receivedAt, timeZone: subjectZone)).font(.headline)
                        Text(L10n.text("İyi olduğunu bildirdi")).foregroundStyle(.secondary)
                        Text(L10n.format("%@ · Yetkili yakınlarla paylaşıldı", sourceText(item.source))).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Design.green) }
            }
        }.navigationTitle(L10n.format("%@ · Geçmiş", subjectName))
            .task(id: state.refreshGeneration) { await load() }
            .refreshable { await load() }
    }
    private func load() async {
        guard !loadingList else { return }
        loadingList = true
        defer { loadingList = false }
        if items.isEmpty { loadState = .loading }
        do {
            let response: Items<HistoryItem> = try await state.api.request("GET", "/profiles/\(profileID)/checkins")
            items = response.items
            loadState = .loaded
        } catch {
            if isCancellationError(error) { return }
            loadState = .failed(ErrorText.message(for: error))
        }
    }
}

func sourceText(_ source: String) -> String {
    switch source {
    case "ios_widget": return L10n.text("Widget'tan")
    default: return L10n.text("Uygulamadan")
    }
}
