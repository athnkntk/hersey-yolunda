import SwiftUI
import CoreImage.CIFilterBuiltins

struct CircleView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var relatives: [Relative] = []
    @State private var relationships: [Relationship] = []
    @State private var invitations: [Invitation] = []
    @State private var selectedRelation: Relationship?
    var body: some View {
        List {
            Section {
                Text("Takip etmek değil, haber almak.").font(.title3).listRowBackground(Color.clear)
                NavigationLink { InviteView() } label: {
                    Label("Yakınımı davet et", systemImage: "person.badge.plus").frame(minHeight: 56)
                }
                NavigationLink { AcceptInvitationView() } label: {
                    Label("Davet kodum var", systemImage: "envelope.open").frame(minHeight: 56)
                }
            }
            if !state.invitationToken.isEmpty {
                Section { NavigationLink("Gelen daveti görüntüle") { AcceptInvitationView() } }
            }
            Section("Yakınlarım") {
                if relatives.isEmpty { Text("Henüz bağlı bir yakınınız yok. Davet kabul edilip paylaşım onaylandığında burada görünür.").foregroundStyle(.secondary) }
                ForEach(relatives) { relative in
                    NavigationLink { RelativeDetailView(relative: relative) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: relative.isCompleted ? "checkmark.circle.fill" : "clock")
                                .font(.title).foregroundStyle(relative.isCompleted ? Design.green : Design.amber)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(relative.profile.name).font(.title3.bold())
                                Text(relative.status())
                                if let date = relative.today.completedAt { Text(DateText.time(date)).foregroundStyle(.secondary) }
                            }
                        }.padding(.vertical, 10)
                    }
                }
            }
            Section("Benim haberimi alanlar") {
                let viewers = relationships.filter { $0.subjectId == state.profile?.id }
                if viewers.isEmpty { Text("Günlük haberinizi şu an kimseyle paylaşmıyorsunuz.").foregroundStyle(.secondary) }
                ForEach(viewers) { relation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(relation.viewerName).font(.title3.bold())
                        Button("Paylaşımı durdur", role: .destructive) { selectedRelation = relation }.frame(minHeight: 56)
                    }
                }
            }
            Section("Davetlerim") {
                ForEach(invitations) { invitation in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(invitation.recipientName ?? "Davetiniz bekleniyor").font(.headline)
                        if invitation.status == "awaiting_approval" {
                            Text("Bu kişinin günlük haberlerinizi görmesini onaylıyor musunuz?")
                            Button("Paylaşımı onayla") {
                                Task {
                                    await state.perform {
                                        let _: ActionResult = try await state.api.request("POST", "/invitations/\(invitation.id)/approve-sharing")
                                        await load()
                                    }
                                }
                            }.frame(minHeight: 56)
                        } else { Text("Bağlantı kurulmadan veri paylaşılmaz.").foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Ailem")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
        .onReceive(NotificationCenter.default.publisher(for: .init("HYRemoteNotification"))) { _ in Task { await load() } }
        .confirmationDialog("Bu kişiyle paylaşımı durdur?", isPresented: Binding(get: { selectedRelation != nil }, set: { if !$0 { selectedRelation = nil } }), titleVisibility: .visible) {
            Button("Paylaşımı durdur", role: .destructive) {
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
        } message: { Text("Yeni haberlerinizi ve geçmişinizi uygulamada artık göremez.") }
    }
    private func load() async {
        do {
            let list: Items<Relative> = try await state.api.request("GET", "/me/relatives")
            let circle: Items<Relationship> = try await state.api.request("GET", "/me/relationships")
            let pending: Items<Invitation> = try await state.api.request("GET", "/invitations")
            relatives = list.items
            relationships = circle.items
            invitations = pending.items
        } catch { state.error = error.localizedDescription }
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
            Section("Ne yapmak istersiniz?") {
                Picker("Paylaşım yönü", selection: $direction) {
                    Text("Ben haber vereceğim").tag("share_mine")
                    Text("Yakınımdan haber alacağım").tag("request_theirs")
                }.pickerStyle(.inline)
            }
            Section("Yakınlık") {
                Picker("İlişki", selection: $label) {
                    ForEach(["Oğlum", "Kızım", "Eşim", "Kardeşim", "Torunum", "Yakınım", "Diğer"], id: \.self) { Text($0) }
                }
                Text("Bu etiket yetki vermez. Bilgisini paylaşan kişinin açık onayı gerekir.").foregroundStyle(.secondary)
            }
            Section {
                if let invitation {
                    if let link = InvitationInput.link(token: invitation.token) {
                        ShareLink(item: link) {
                            Label("Daveti paylaş", systemImage: "square.and.arrow.up").frame(minHeight: 56)
                        }
                        if let image = InvitationQR.image(link.absoluteString) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(maxWidth: 240).padding(20).background(.white)
                                .accessibilityLabel("Davet QR kodu; diğer telefondan okutun veya aşağıdaki kodu girin")
                                .accessibilityIdentifier("invitationQR")
                        }
                    }
                    Text(invitation.code).font(.title2.monospaced().bold()).textSelection(.enabled)
                        .accessibilityIdentifier("invitationCode")
                    Text("Bağlantı ve QR, Herşey Yolunda yüklü telefonda açılır. Olmazsa ‘Davet kodum var’ bölümüne kodu yazın. 48 saat geçerlidir; tek kullanımlıktır. Hesap kimliğiniz giriş veya davet kodu değildir.").foregroundStyle(.secondary)
                } else {
                    Button("Davet oluştur") {
                        Task {
                            await state.perform { invitation = try await state.api.request("POST", "/invitations", body: ["direction": direction, "label": label]) }
                        }
                    }.frame(minHeight: 56).disabled(state.loading)
                }
            }
        }.navigationTitle("Yakınını davet et")
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
            Section("Davet kodu") {
                TextField("Davet kodu veya bağlantısı", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("invitationInput")
                    .onChange(of: token) { _, _ in preview = nil; reviewedCredential = nil; result = nil }
                Button("Daveti görüntüle") {
                    Task {
                        await state.perform {
                            guard let credential = InvitationInput.credentials(token) else { throw LocalError(message: "Size gönderilen 12 karakterli davet kodunu veya bağlantısını girin. Hesap ID’si ile eşleşme yapılmaz.") }
                            let value: InvitationPreview = try await state.api.request("POST", "/invitations/preview", body: credential)
                            guard InvitationInput.credentials(token) == credential else { return }
                            reviewedCredential = credential
                            preview = value
                        }
                    }
                }.frame(minHeight: 56)
            }
            if let preview, result == nil {
                Section("\(preview.creatorName) sizi davet etti") {
                    Text(preview.direction == "request_theirs" ? "Kabul ederseniz günlük iyi olduğunuz bilgisi, kontrol saati ve onaydan sonraki geçmişiniz bu kişiyle paylaşılır. Konum paylaşılmaz." : "Bu kişinin günlük haberlerini almayı kabul ediyorsunuz. Veri sahibi ayrıca sizi onaylayana kadar erişim açılmaz.")
                    Text("İsimler kullanıcılar tarafından girilir; kimlik doğrulaması değildir. Daveti tanıdığınız kişiden aldığınızdan emin olun.").foregroundStyle(.secondary)
                    Button("Kabul ediyorum") { Task { await respond("accept", preview: preview) } }.frame(minHeight: 56)
                    Button("Reddet", role: .destructive) { Task { await respond("decline", preview: preview) } }.frame(minHeight: 56)
                }
            }
            if let result { Section { Text(result).font(.title3) } }
        }
        .navigationTitle("Gelen davet")
        .onAppear { token = state.invitationToken }
    }
    private func respond(_ action: String, preview: InvitationPreview) async {
        await state.perform {
            guard let credential = reviewedCredential, credential == InvitationInput.credentials(token) else { throw LocalError(message: "Önce güncel daveti görüntüleyin.") }
            let response: ActionResult = try await state.api.request("POST", "/invitations/\(preview.id)/\(action)", body: credential)
            result = response.status == "awaiting_approval" ? "Kabulünüz alındı. Bilgisini paylaşan kişinin onayı bekleniyor." : response.status == "declined" ? "Davet reddedildi." : "Bağlantınız kuruldu. Paylaşımı istediğiniz zaman durdurabilirsiniz."
            state.invitationToken = ""
        }
    }
}

struct RelativeDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    let relative: Relative
    @State private var current: Relative?
    var body: some View {
        List {
            if let current {
                Section("Bugünkü haber") {
                    Text(current.status()).font(.title3)
                    if let date = current.today.completedAt { Text(DateText.stamp(date)) }
                    Text("Kontrol: \(DateText.time(current.today.dueAt)) · Türkiye saati")
                    Text("Bu bilgi kişinin kendi beyanıdır; sağlık veya güvenlik doğrulaması değildir.").foregroundStyle(.secondary)
                }
                NavigationLink("Check-in geçmişi") { HistoryView(profileID: current.id) }
            } else { Text("Güncel durum henüz alınamadı. Yenilemek için aşağı çekin.") }
            Text("Haber gelmediğinde yakınınızı normal telefon görüşmesiyle arayabilirsiniz. Bu uygulama acil müdahale hizmeti değildir.")
        }.navigationTitle(relative.profile.name)
            .task { await refresh() }
            .refreshable { await refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
            .onReceive(NotificationCenter.default.publisher(for: .init("HYRemoteNotification"))) { _ in Task { await refresh() } }
    }
    private func refresh() async {
        do { current = try await state.api.request("GET", "/profiles/\(relative.id)/status") }
        catch { current = nil; state.error = error.localizedDescription }
    }
}

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    let profileID: String
    @State private var items: [HistoryItem] = []
    var body: some View {
        List {
            if items.isEmpty { ContentUnavailableView("Henüz haber yok", systemImage: "calendar", description: Text("Son 30 gündeki ve paylaşım izniniz kapsamındaki kayıtlar burada görünür.")) }
            ForEach(items) { item in
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DateText.stamp(item.receivedAt)).font(.headline)
                        Text("İyi olduğunu bildirdi").foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Design.green) }
            }
        }.navigationTitle("Geçmiş")
            .task {
                do {
                    let response: Items<HistoryItem> = try await state.api.request("GET", "/profiles/\(profileID)/checkins")
                    items = response.items
                } catch { state.error = error.localizedDescription }
            }
    }
}
