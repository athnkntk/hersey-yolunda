import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var store = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false

    private var priceText: String {
        store.product?.displayPrice ?? "199,99 TL"
    }

    private var trialText: String {
        if store.product?.subscription?.introductoryOffer != nil {
            return "İlk 1 ay ücretsiz deneme dahildir."
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Herşey Yolunda Premium", systemImage: "heart.circle.fill")
                        .font(.title2.bold()).foregroundStyle(Design.green)
                    Text("Ailenizin yanında olun.").font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 14) {
                        feature("Sınırsız aile üyesi ekleyin", "person.2.fill")
                        feature("Yakınlarınızın günlük durumunu görün", "checkmark.circle.fill")
                        feature("Check-in geçmişine ulaşın", "calendar")
                        feature("Haber gelmediğinde bildirim alın", "bell.badge.fill")
                    }
                    InfoCard {
                        Text(priceText + " / ay").font(.title.bold())
                        if !trialText.isEmpty {
                            Text(trialText).font(.title3).foregroundStyle(Design.green)
                        }
                        Text("Deneme bitiminde aylık \(priceText) otomatik yenilenir. İstediğiniz zaman App Store hesabınızdan iptal edebilirsiniz; iptal, dönem sonuna kadar erişimi korur.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    PrimaryButton(title: store.purchasing ? "İşleniyor" : "1 Ay Ücretsiz Başla", busy: store.purchasing) {
                        Task {
                            if await store.purchase() { dismiss() }
                            else if store.error != nil { showError = true }
                        }
                    }.disabled(store.purchasing)
                        .accessibilityIdentifier("subscribeButton")
                    Button("Satın almayı geri yükle") {
                        Task {
                            await store.restore()
                            if store.isPremium { dismiss() }
                            else if store.error != nil { showError = true }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 56).disabled(store.purchasing)
                    HStack(spacing: 20) {
                        Link("Gizlilik Politikası", destination: URL(string: "https://athnkntk.github.io/hersey-yolunda/privacy.html")!)
                        Link("Kullanım Koşulları", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }.font(.callout).frame(maxWidth: .infinity)
                    Text("Abonelik Apple hesabınıza bağlıdır; ödeme Apple tarafından tahsil edilir.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(Design.background)
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
            .task { await store.load() }
            .alert("İşlem tamamlanamadı", isPresented: $showError) {
                Button("Tamam", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }

    private func feature(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.title3)
    }
}
