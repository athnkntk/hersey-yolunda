import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    static let productID = "premium_monthly"

    @Published var product: Product?
    @Published var isPremium = false
    @Published var purchasing = false
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
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil { error = "Abonelik bilgisi yüklenemedi. Lütfen yeniden deneyin." }
        } catch {
            self.error = "Mağazaya ulaşılamadı. Bağlantınızı kontrol edin."
        }
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var premium = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                premium = true
            }
        }
        isPremium = premium
    }

    @discardableResult
    func purchase() async -> Bool {
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
                    error = "Satın alma doğrulanamadı. Ücret alınmadıysa yeniden deneyin."
                    return false
                }
                await transaction.finish()
                isPremium = true
                return true
            case .userCancelled:
                return false
            case .pending:
                error = "Satın alma onay bekliyor. Onaylandığında Premium otomatik açılır."
                return false
            @unknown default:
                return false
            }
        } catch {
            self.error = "Satın alma tamamlanamadı. Ücret alınmadıysa yeniden deneyin."
            return false
        }
    }

    func restore() async {
        purchasing = true
        defer { purchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isPremium { self.error = "Bu Apple hesabında etkin abonelik bulunamadı." }
        } catch {
            self.error = "Geri yükleme başarısız. Apple hesabınızı kontrol edin."
        }
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
