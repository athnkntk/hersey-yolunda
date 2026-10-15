import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    static let productID = "premium_monthly"

    @Published var product: Product?
    @Published var isPremium = false
    @Published var purchasing = false
    @Published var trialEligible = false
    @Published var error: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        if ProcessInfo.processInfo.arguments.contains("--uitest-premium") {
            isPremium = true
        } else {
            updatesTask = observeTransactions()
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        if ProcessInfo.processInfo.arguments.contains("--uitest-premium") { return }
        error = nil
        if product == nil {
            do {
                product = try await Product.products(for: [Self.productID]).first
                if product == nil { error = L10n.text("Abonelik bilgisi yüklenemedi. Lütfen yeniden deneyin.") }
            } catch {
                if !isCancellationError(error) { self.error = L10n.text("Mağazaya ulaşılamadı. Bağlantınızı kontrol edin.") }
            }
        }
        await refreshTrialEligibility()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var premium = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                premium = true
            }
        }
        isPremium = premium
    }

    @discardableResult
    func purchase() async -> Bool {
        error = nil
        guard let product else {
            await load()
            guard product != nil else { return false }
            return await purchase()
        }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    error = L10n.text("Satın alma doğrulanamadı. Ücret alınmadıysa yeniden deneyin.")
                    return false
                }
                await transaction.finish()
                isPremium = true
                return true
            case .userCancelled:
                return false
            case .pending:
                error = L10n.text("Satın alma onay bekliyor. Onaylandığında Premium otomatik açılır.")
                return false
            @unknown default:
                return false
            }
        } catch {
            if !isCancellationError(error) { self.error = L10n.text("Satın alma tamamlanamadı. Ücret alınmadıysa yeniden deneyin.") }
            return false
        }
    }

    func restore() async {
        error = nil
        purchasing = true
        defer { purchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isPremium { self.error = L10n.text("Bu Apple hesabında etkin abonelik bulunamadı.") }
        } catch {
            if !isCancellationError(error) { self.error = L10n.text("Geri yükleme başarısız. Apple hesabınızı kontrol edin.") }
        }
    }

    private func refreshTrialEligibility() async {
        guard let subscription = product?.subscription, subscription.introductoryOffer?.paymentMode == .freeTrial else { trialEligible = false; return }
        trialEligible = await subscription.isEligibleForIntroOffer
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}

enum BillingText {
    static func duration(value: Int, unit: Product.SubscriptionPeriod.Unit, language: String = L10n.language) -> String {
        let base: String
        switch unit {
        case .day: base = "duration.day"
        case .week: base = "duration.week"
        case .month: base = "duration.month"
        case .year: base = "duration.year"
        @unknown default: base = "duration.month"
        }
        let key = value == 1 ? "\(base).one" : "\(base).many"
        return String(format: L10n.text(key, language: language), locale: L10n.locale, value)
    }
    /// StoreKit introductoryOffer'ın toplam süresi (period.value × periodCount).
    static func offerDuration(value: Int, count: Int, unit: Product.SubscriptionPeriod.Unit, language: String = L10n.language) -> String {
        duration(value: value * count, unit: unit, language: language)
    }
}
