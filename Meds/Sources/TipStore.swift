import StoreKit

enum TipStore {
    static let productIDs: Set<String> = [
        "com.christoforakis.Meds.tip.small",
        "com.christoforakis.Meds.tip.medium",
        "com.christoforakis.Meds.tip.large"
    ]

    static let displayNames = [
        "com.christoforakis.Meds.tip.small": "Small Tip",
        "com.christoforakis.Meds.tip.medium": "Medium Tip",
        "com.christoforakis.Meds.tip.large": "Large Tip"
    ]

    static func availableProducts() async -> [Product] {
        guard let products = try? await Product.products(for: productIDs) else { return [] }
        return products
            .filter { $0.type == .consumable && productIDs.contains($0.id) }
            .sorted { $0.price < $1.price }
    }

    static func observeTransactions() async {
        for await result in Transaction.unfinished {
            await finishVerifiedTip(result)
        }
        for await result in Transaction.updates {
            await finishVerifiedTip(result)
        }
    }

    private static func finishVerifiedTip(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              productIDs.contains(transaction.productID) else { return }
        await transaction.finish()
    }
}
