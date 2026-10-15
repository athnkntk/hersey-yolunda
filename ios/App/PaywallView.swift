import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var store = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false

    private var periodText: String {
        guard let period = store.product?.subscription?.subscriptionPeriod else { return "" }
        return BillingText.duration(value: period.value, unit: period.unit)
    }
    private var trialPeriodText: String? {
        guard store.trialEligible, let offer = store.product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return BillingText.offerDuration(value: offer.period.value, count: offer.periodCount, unit: offer.period.unit)
    }
    private var priceText: String { store.product?.displayPrice ?? L10n.text("Yükleniyor...") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Herşey Yolunda Premium", systemImage: "heart.circle.fill")
                        .font(.title2.bold()).foregroundStyle(Design.green)
                    Text(L10n.text("Ailenizin yanında olun.")).font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 14) {
                        feature(L10n.text("Yakınlarınızı davet edin"), "person.2.fill")
                        feature(L10n.text("Yakınlarınızın günlük durumunu görün"), "checkmark.circle.fill")
                        feature(L10n.text("Check-in geçmişine ulaşın"), "calendar")
                        feature(L10n.text("Haber gelmediğinde durumu görün"), "bell.badge.fill")
                    }
                    if store.product != nil {
                        InfoCard {
                            Text(periodText.isEmpty ? priceText : L10n.format("%@ / %@", priceText, periodText)).font(.title.bold())
                            if let trial = trialPeriodText {
                                Text(L10n.format("%@ ücretsiz deneme dahildir.", trial)).font(.title3).foregroundStyle(Design.green)
                                Text(L10n.format("Deneme bitiminde abonelik %1$@ karşılığında %2$@ yenilenir. İstediğiniz zaman App Store hesabınızdan iptal edebilirsiniz; iptal, dönem sonuna kadar erişimi korur.", priceText, periodText))
                                    .font(.callout).foregroundStyle(.secondary)
                            } else {
                                Text(L10n.format("Abonelik %1$@ karşılığında %2$@ yenilenir. İstediğiniz zaman App Store hesabınızdan iptal edebilirsiniz; iptal, dönem sonuna kadar erişimi korur.", priceText, periodText))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    } else if let loadError = store.error {
                        InfoCard {
                            Text(loadError).font(.callout).foregroundStyle(.secondary)
                            Button(L10n.text("Yeniden dene")) { Task { await store.load() } }
                                .font(.callout.weight(.semibold)).foregroundStyle(Design.green)
                        }
                    } else {
                        InfoCard {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text(L10n.text("Abonelik bilgisi yükleniyor...")).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    PrimaryButton(title: store.purchasing ? L10n.text("İşleniyor") : (trialPeriodText != nil ? L10n.format("%@ ücretsiz başla", trialPeriodText!) : L10n.text("Abone ol")), busy: store.purchasing) {
                        Task {
                            if await store.purchase() { dismiss() }
                            else if store.error != nil { showError = true }
                        }
                    }.disabled(store.purchasing || store.product == nil)
                        .accessibilityIdentifier("subscribeButton")
                    Button(L10n.text("Satın almayı geri yükle")) {
                        Task {
                            await store.restore()
                            if store.isPremium { dismiss() }
                            else if store.error != nil { showError = true }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 56).disabled(store.purchasing)
                    HStack(spacing: 20) {
                        Link(L10n.text("Gizlilik Politikası"), destination: URL(string: "https://athnkntk.github.io/hersey-yolunda/privacy.html?lang=\(L10n.language)")!)
                        Link(L10n.text("Kullanım Koşulları"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }.font(.callout).frame(maxWidth: .infinity)
                    Text(L10n.text("Abonelik Apple hesabınıza bağlıdır; ödeme Apple tarafından tahsil edilir.")).font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(Design.background)
            .navigationTitle(L10n.text("Premium"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Kapat")) { dismiss() }
                }
            }
            .task { await store.load() }
            .alert(Text(L10n.text("İşlem tamamlanamadı")), isPresented: $showError) {
                Button(L10n.text("Tamam"), role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }

    private func feature(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.title3)
    }
}
