import Foundation
import StoreKit

/// StoreKit purchase data required to attribute a verified subscription.
/// This value is persisted before transmission so known delivery failures can
/// be retried without reconstructing StoreKit state or emitting from restores.
struct VerifiedSubscriptionPurchase: Codable, Equatable, Sendable {
    let transactionID: String
    let productID: String
    let price: Decimal
    let currency: String
    let tier: String
    let source: String
}

enum PurchaseAttributionOutcome: Equatable, Sendable {
    case recorded
    case alreadyRecorded
    case alreadyInProgress
    case deferred(String)
}

protocol PurchaseAttributionEventSending: Sendable {
    func send(event: String, values: [String: String]) async throws
}

protocol PurchaseAttributionPersisting: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct UserDefaultsPurchaseAttributionStore: PurchaseAttributionPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard,
         key: String = "purchase_attribution.storekit_transaction_states.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> Data? { defaults.data(forKey: key) }

    func save(_ data: Data) throws {
        defaults.set(data, forKey: key)
        guard defaults.synchronize() else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// The only authority allowed to emit AppsFlyer subscription purchase events.
///
/// Delivery state is saved after each acknowledged AppsFlyer event. A known
/// send failure leaves the record at its last acknowledged phase, so a later
/// observation of the same verified transaction resumes instead of losing the
/// revenue event. The actor and `inFlight` set serialize direct-purchase and
/// Transaction.updates races.
///
/// AppsFlyer's client API has no atomic "send and persist" operation. A process
/// kill after remote acceptance but before the next local save is therefore an
/// unavoidable uncertain-delivery window. Both events carry the StoreKit
/// transaction ID so downstream reconciliation can identify that edge case.
actor PurchaseAttributionService {
    static let shared = PurchaseAttributionService(
        sender: AppsFlyerPurchaseAttributionSender(),
        persistence: UserDefaultsPurchaseAttributionStore()
    )

    private enum Phase: String, Codable, Sendable {
        case pending
        case subscribeSent
        case completed
    }

    private struct Record: Codable, Sendable {
        let purchase: VerifiedSubscriptionPurchase
        var phase: Phase
    }

    private let sender: any PurchaseAttributionEventSending
    private let persistence: any PurchaseAttributionPersisting
    private var records: [String: Record]
    private var inFlight: Set<String> = []

    init(sender: any PurchaseAttributionEventSending,
         persistence: any PurchaseAttributionPersisting) {
        self.sender = sender
        self.persistence = persistence
        if let data = try? persistence.load(),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func recordVerifiedSubscriptionPurchase(
        transaction: StoreKit.Transaction,
        product: Product,
        tier: String,
        source: String
    ) async -> PurchaseAttributionOutcome {
        await recordVerifiedSubscriptionPurchase(
            VerifiedSubscriptionPurchase(
                transactionID: String(transaction.id),
                productID: product.id,
                price: product.price,
                currency: product.priceFormatStyle.currencyCode,
                tier: tier,
                source: source
            )
        )
    }

    func recordVerifiedSubscriptionPurchase(
        _ purchase: VerifiedSubscriptionPurchase
    ) async -> PurchaseAttributionOutcome {
        let transactionID = purchase.transactionID
        if records[transactionID]?.phase == .completed { return .alreadyRecorded }
        if inFlight.contains(transactionID) { return .alreadyInProgress }

        inFlight.insert(transactionID)
        defer { inFlight.remove(transactionID) }

        if records[transactionID] == nil {
            records[transactionID] = Record(purchase: purchase, phase: .pending)
            do {
                try persist()
            } catch {
                records.removeValue(forKey: transactionID)
                return .deferred("Could not persist pending attribution: \(error.localizedDescription)")
            }
        }

        guard var record = records[transactionID] else {
            return .deferred("Attribution record disappeared before transmission")
        }

        do {
            if record.phase == .pending {
                try await sender.send(event: "af_subscribe", values: eventValues(for: record.purchase))
                record.phase = .subscribeSent
                records[transactionID] = record
                try persist()
            }

            if record.phase == .subscribeSent {
                try await sender.send(event: "af_purchase", values: eventValues(for: record.purchase))
                record.phase = .completed
                records[transactionID] = record
                try persist()
            }

            return .recorded
        } catch {
            return .deferred(error.localizedDescription)
        }
    }

    private func eventValues(for purchase: VerifiedSubscriptionPurchase) -> [String: String] {
        [
            "af_content_id": purchase.productID,
            "af_transaction_id": purchase.transactionID,
            "af_revenue": NSDecimalNumber(decimal: purchase.price).stringValue,
            "af_currency": purchase.currency,
            "subscription_tier": purchase.tier,
            "purchase_source": purchase.source
        ]
    }

    private func persist() throws {
        try persistence.save(JSONEncoder().encode(records))
    }
}

struct AppsFlyerPurchaseAttributionSender: PurchaseAttributionEventSending {
    func send(event: String, values: [String: String]) async throws {
        #if canImport(AppsFlyerLib)
        try await AppsFlyerManager.shared.logEventAcknowledged(event, values: values)
        #else
        throw PurchaseAttributionSenderError.appsFlyerUnavailable
        #endif
    }
}

enum PurchaseAttributionSenderError: LocalizedError {
    case appsFlyerUnavailable
    case appsFlyerNotConfigured

    var errorDescription: String? {
        switch self {
        case .appsFlyerUnavailable: return "AppsFlyer SDK is unavailable"
        case .appsFlyerNotConfigured: return "AppsFlyer SDK is not configured"
        }
    }
}
