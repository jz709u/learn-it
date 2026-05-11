import Foundation
import StoreKit

struct CreditCatalogItem: Identifiable, Hashable {
    let productID: String
    let title: String
    let creditAmount: Int
    let fallbackPriceLabel: String
    let badge: String?

    var id: String { productID }

    static let all: [CreditCatalogItem] = [
        CreditCatalogItem(
            productID: "com.learnit.imports.10",
            title: "10 Imports",
            creditAmount: 10,
            fallbackPriceLabel: "$2.99",
            badge: nil
        ),
        CreditCatalogItem(
            productID: "com.learnit.imports.25",
            title: "25 Imports",
            creditAmount: 25,
            fallbackPriceLabel: "$5.99",
            badge: nil
        ),
        CreditCatalogItem(
            productID: "com.learnit.imports.50",
            title: "50 Imports",
            creditAmount: 50,
            fallbackPriceLabel: "$9.99",
            badge: "Best Value"
        )
    ]
}

struct CreditPurchaseRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let transactionID: UInt64
    let productID: String
    let creditAmount: Int
    let purchasedAt: Date
}

struct CreditConsumptionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let amount: Int
    let reason: String
    let consumedAt: Date
}

@MainActor
final class ImportCreditStore: ObservableObject {
    @Published private(set) var balance: Int = 0
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseHistory: [CreditPurchaseRecord] = []
    @Published private(set) var consumptionHistory: [CreditConsumptionRecord] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private var updatesTask: Task<Void, Never>?

    init() {
        loadPersistedState()
        updatesTask = observeTransactionUpdates()

        Task {
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: CreditCatalogItem.all.map(\.productID))
            products = loaded.sorted { lhs, rhs in
                catalogItem(for: lhs.id)?.creditAmount ?? 0 < catalogItem(for: rhs.id)?.creditAmount ?? 0
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not load import credit options."
        }
    }

    func purchase(_ catalogItem: CreditCatalogItem) async {
        guard !isPurchasing else { return }
        guard let product = products.first(where: { $0.id == catalogItem.productID }) else {
            errorMessage = "The App Store product is unavailable right now."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                applyPurchaseIfNeeded(transactionID: transaction.id, productID: transaction.productID)
                await transaction.finish()
                errorMessage = nil
            case .userCancelled, .pending:
                break
            @unknown default:
                errorMessage = "The purchase could not be completed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func consumeCredit(reason: String) throws {
        guard balance > 0 else {
            throw NSError(
                domain: "ImportCreditStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "You need an AI import credit to use OpenAI mode."]
            )
        }

        let record = CreditConsumptionRecord(
            id: UUID(),
            amount: 1,
            reason: reason,
            consumedAt: .now
        )
        consumptionHistory.insert(record, at: 0)
        persistState()
    }

    func canAffordOpenAIImport() -> Bool {
        balance > 0
    }

    func displayPrice(for item: CreditCatalogItem) -> String {
        products.first(where: { $0.id == item.productID })?.displayPrice ?? item.fallbackPriceLabel
    }

    func dismissError() {
        errorMessage = nil
    }

    private func applyPurchaseIfNeeded(transactionID: UInt64, productID: String) {
        guard !purchaseHistory.contains(where: { $0.transactionID == transactionID }) else { return }
        guard let item = catalogItem(for: productID) else { return }

        let record = CreditPurchaseRecord(
            id: UUID(),
            transactionID: transactionID,
            productID: productID,
            creditAmount: item.creditAmount,
            purchasedAt: .now
        )
        purchaseHistory.insert(record, at: 0)
        persistState()
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw NSError(
                domain: "ImportCreditStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The App Store could not verify this purchase."]
            )
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try verifiedTransaction(from: result)
                    applyPurchaseIfNeeded(transactionID: transaction.id, productID: transaction.productID)
                    await transaction.finish()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadPersistedState() {
        purchaseHistory = decode([CreditPurchaseRecord].self, forKey: purchaseHistoryKey) ?? []
        consumptionHistory = decode([CreditConsumptionRecord].self, forKey: consumptionHistoryKey) ?? []
        recalculateBalance()
    }

    private func persistState() {
        encode(purchaseHistory, forKey: purchaseHistoryKey)
        encode(consumptionHistory, forKey: consumptionHistoryKey)
        recalculateBalance()
    }

    private func recalculateBalance() {
        let purchased = purchaseHistory.reduce(0) { $0 + $1.creditAmount }
        let consumed = consumptionHistory.reduce(0) { $0 + $1.amount }
        balance = max(0, purchased - consumed)
    }

    private func catalogItem(for productID: String) -> CreditCatalogItem? {
        CreditCatalogItem.all.first(where: { $0.productID == productID })
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private var purchaseHistoryKey: String { "import-credits.purchases" }
    private var consumptionHistoryKey: String { "import-credits.consumptions" }
}
