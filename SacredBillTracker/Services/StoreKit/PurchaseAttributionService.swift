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

enum PurchaseAttributionPreparationOutcome: Equatable, Sendable {
    case prepared
    case alreadyRecorded
    case ineligible(String)
    case deferred(String)

    /// A deferred result means no durable attribution decision exists yet.
    /// Keep the verified StoreKit transaction unfinished so foreground
    /// recovery can retry without losing the transaction payload.
    var permitsStoreKitFinish: Bool {
        switch self {
        case .prepared, .alreadyRecorded, .ineligible:
            return true
        case .deferred:
            return false
        }
    }
}

protocol PurchaseAttributionEventSending: Sendable {
    func send(event: String, values: PurchaseAttributionEventValues) async throws
}

/// Strongly typed purchase values keep revenue numeric until the final SDK
/// bridge instead of representing money as a formatted string.
struct PurchaseAttributionEventValues: Equatable, Sendable {
    let productID: String
    let transactionID: String
    let revenue: Decimal
    let currency: String
    let tier: String
    let source: String

    var appsFlyerDictionary: [String: Any] {
        [
            "af_content_id": productID,
            "af_transaction_id": transactionID,
            "af_revenue": NSDecimalNumber(decimal: revenue),
            "af_currency": currency,
            "subscription_tier": tier,
            "purchase_source": source
        ]
    }
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

/// The only authority allowed to emit AppsFlyer subscription revenue events.
///
/// Delivery state is saved after each acknowledged AppsFlyer event. A known
/// send failure leaves the record at its last acknowledged phase, so a later
/// observation of the same verified transaction resumes instead of losing the
/// revenue event. The actor and `inFlight` set serialize direct-purchase and
/// Transaction.updates races.
///
/// AppsFlyer's client API has no atomic "send and persist" operation. A process
/// kill after remote acceptance but before the next local save is therefore an
/// unavoidable uncertain-delivery window. The single revenue event carries the
/// StoreKit transaction ID so downstream reconciliation can identify that edge
/// case.
actor PurchaseAttributionService {
    private static let currentContractVersion = 2

    static let shared = PurchaseAttributionService(
        sender: AppsFlyerPurchaseAttributionSender(),
        persistence: UserDefaultsPurchaseAttributionStore()
    )

    private enum Phase: String, Codable, Sendable {
        case pending
        // Decode-only migration state written by builds that sent a
        // revenue-bearing af_subscribe before af_purchase. That acknowledged
        // legacy event already credited revenue, so it must be completed
        // without transmitting another revenue event.
        case subscribeSent
        case legacyPendingQuarantined
        case completed
    }

    private struct Record: Codable, Sendable {
        let purchase: VerifiedSubscriptionPurchase
        var phase: Phase
        var contractVersion: Int?
    }

    private let sender: any PurchaseAttributionEventSending
    private let persistence: any PurchaseAttributionPersisting
    private let ledgerLoadFailure: String?
    private var records: [String: Record]
    private var inFlight: Set<String> = []

    init(sender: any PurchaseAttributionEventSending,
         persistence: any PurchaseAttributionPersisting) {
        self.sender = sender
        self.persistence = persistence
        do {
            if let data = try persistence.load() {
                records = try JSONDecoder().decode([String: Record].self, from: data)
            } else {
                records = [:]
            }
            ledgerLoadFailure = nil
        } catch {
            records = [:]
            ledgerLoadFailure = error.localizedDescription
        }
    }

    /// Persists a verified transaction before StoreKit `finish()` is called.
    /// Delivery is deliberately separate so attribution network latency never
    /// blocks entitlement delivery, while a crash after `finish()` can still
    /// be recovered from the durable pending record.
    func prepareVerifiedSubscriptionPurchase(
        transaction: StoreKit.Transaction,
        tier: String,
        source: String
    ) -> PurchaseAttributionPreparationOutcome {
        guard ProductID.all.contains(transaction.productID) else {
            return .ineligible("Transaction is not a Sacred Bill Tracker subscription")
        }
        guard transaction.revocationDate == nil else {
            return .ineligible("Revoked transactions cannot create positive revenue")
        }
        guard !transaction.isUpgraded else {
            return .ineligible("Superseded upgrade transactions cannot create positive revenue")
        }
        guard transaction.ownershipType == .purchased else {
            return .ineligible("Family-shared transactions cannot create purchaser revenue")
        }
        guard transaction.reason == .purchase || transaction.reason == .renewal else {
            return .ineligible("Transaction is not a purchase or renewal")
        }
        guard let price = transaction.price, price > 0 else {
            return .deferred("Verified transaction has no positive paid amount")
        }
        guard let currency = transaction.currency?.identifier,
              !currency.isEmpty else {
            return .deferred("Verified transaction has no ISO currency")
        }

        return prepareVerifiedSubscriptionPurchase(
            VerifiedSubscriptionPurchase(
                transactionID: String(transaction.id),
                productID: transaction.productID,
                price: price,
                currency: currency,
                tier: tier,
                source: source
            )
        )
    }

    func prepareVerifiedSubscriptionPurchase(
        _ purchase: VerifiedSubscriptionPurchase
    ) -> PurchaseAttributionPreparationOutcome {
        let transactionID = purchase.transactionID
        guard ledgerLoadFailure == nil else {
            return .deferred("Attribution ledger could not be loaded; refusing to send")
        }
        guard !transactionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .deferred("Verified purchase is missing a transaction ID")
        }
        if var existing = records[transactionID] {
            if let version = existing.contractVersion,
               version > Self.currentContractVersion {
                return .deferred("Attribution record uses an unsupported contract version")
            }
            if existing.phase == .completed { return .alreadyRecorded }

            // Version 1 records were written by the two-revenue-event build.
            // Acknowledged subscribe and completed phases are terminal; an
            // ambiguous pending phase is quarantined rather than risk a second
            // revenue credit.
            if existing.contractVersion == nil {
                switch existing.phase {
                case .subscribeSent:
                    existing.phase = .completed
                    existing.contractVersion = Self.currentContractVersion
                    records[transactionID] = existing
                    do {
                        try persist()
                        return .alreadyRecorded
                    } catch {
                        return .deferred("Could not persist legacy migration: \(error.localizedDescription)")
                    }
                case .pending:
                    existing.phase = .legacyPendingQuarantined
                    existing.contractVersion = Self.currentContractVersion
                    records[transactionID] = existing
                    do {
                        try persist()
                        return .deferred("Legacy pending revenue is quarantined for reconciliation")
                    } catch {
                        return .deferred("Could not persist legacy quarantine: \(error.localizedDescription)")
                    }
                case .completed:
                    return .alreadyRecorded
                case .legacyPendingQuarantined:
                    return .deferred("Legacy pending revenue is quarantined for reconciliation")
                }
            }

            if existing.phase == .legacyPendingQuarantined {
                return .deferred("Legacy pending revenue is quarantined for reconciliation")
            }
            guard existing.purchase.hasSameRevenueIdentity(as: purchase) else {
                return .deferred("Transaction ID already exists with different revenue values")
            }
            return .prepared
        } else {
            records[transactionID] = Record(
                purchase: purchase,
                phase: .pending,
                contractVersion: Self.currentContractVersion
            )
            do {
                try persist()
            } catch {
                records.removeValue(forKey: transactionID)
                return .deferred("Could not persist pending attribution: \(error.localizedDescription)")
            }
        }

        return .prepared
    }

    func deliverPreparedPurchase(transactionID: String) async -> PurchaseAttributionOutcome {
        guard ledgerLoadFailure == nil else {
            return .deferred("Attribution ledger could not be loaded; refusing to send")
        }
        guard var record = records[transactionID] else {
            return .deferred("No prepared attribution exists for this transaction")
        }
        if let version = record.contractVersion,
           version > Self.currentContractVersion {
            return .deferred("Attribution record uses an unsupported contract version")
        }
        if record.phase == .completed { return .alreadyRecorded }
        if record.phase == .legacyPendingQuarantined || record.contractVersion == nil {
            return .deferred("Legacy pending revenue is quarantined for reconciliation")
        }
        if inFlight.contains(transactionID) { return .alreadyInProgress }

        inFlight.insert(transactionID)
        defer { inFlight.remove(transactionID) }

        do {
            if record.phase == .pending {
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

    func recordVerifiedSubscriptionPurchase(
        _ purchase: VerifiedSubscriptionPurchase
    ) async -> PurchaseAttributionOutcome {
        switch prepareVerifiedSubscriptionPurchase(purchase) {
        case .prepared:
            return await deliverPreparedPurchase(transactionID: purchase.transactionID)
        case .alreadyRecorded:
            return .alreadyRecorded
        case .ineligible(let reason), .deferred(let reason):
            return .deferred(reason)
        }
    }

    /// Completes and attributes transactions left unfinished by a crash only
    /// after the revenue payload has been durably prepared. Unknown products
    /// and unverified transactions remain untouched for their owning code.
    func recoverUnfinishedTransactions() async -> [String: PurchaseAttributionOutcome] {
        var outcomes: [String: PurchaseAttributionOutcome] = [:]
        for await verification in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = verification,
                  ProductID.all.contains(transaction.productID) else { continue }

            let transactionID = String(transaction.id)
            let preparation = prepareVerifiedSubscriptionPurchase(
                transaction: transaction,
                tier: Self.attributionTier(for: transaction.productID),
                source: "unfinished_transaction_recovery"
            )

            switch preparation {
            case .prepared:
                await transaction.finish()
                outcomes[transactionID] = await deliverPreparedPurchase(transactionID: transactionID)
            case .alreadyRecorded:
                await transaction.finish()
                outcomes[transactionID] = .alreadyRecorded
            case .ineligible(let reason):
                await transaction.finish()
                outcomes[transactionID] = .deferred(reason)
            case .deferred(let reason):
                // Keep the StoreKit transaction unfinished until its payload
                // can be persisted safely on a later foreground transition.
                outcomes[transactionID] = .deferred(reason)
            }
        }
        return outcomes
    }

    /// Replays only versioned pending purchases already stored on disk. Legacy
    /// ambiguous records are never sent automatically.
    func retryPendingPurchases() async -> [String: PurchaseAttributionOutcome] {
        guard ledgerLoadFailure == nil else {
            return ["ledger": .deferred("Attribution ledger could not be loaded; refusing to send")]
        }
        let pendingTransactionIDs = records.values
            .filter {
                $0.phase == .pending &&
                $0.contractVersion == Self.currentContractVersion
            }
            .map(\.purchase.transactionID)

        var outcomes: [String: PurchaseAttributionOutcome] = [:]
        for transactionID in pendingTransactionIDs {
            outcomes[transactionID] = await deliverPreparedPurchase(transactionID: transactionID)
        }
        return outcomes
    }

    private func eventValues(for purchase: VerifiedSubscriptionPurchase) -> PurchaseAttributionEventValues {
        PurchaseAttributionEventValues(
            productID: purchase.productID,
            transactionID: purchase.transactionID,
            revenue: purchase.price,
            currency: purchase.currency,
            tier: purchase.tier,
            source: purchase.source
        )
    }

    private func persist() throws {
        try persistence.save(JSONEncoder().encode(records))
    }

    private static func attributionTier(for productID: String) -> String {
        switch productID {
        case ProductID.essentialMonthly: return "essential"
        case ProductID.businessMonthly: return "business"
        case ProductID.unlimitedMonthly: return "unlimited"
        case ProductID.proMonthly, ProductID.proYearly: return "pro"
        case ProductID.focusPlusMonthly: return "focus_plus"
        case ProductID.autoTrackMonthly, ProductID.autoTrackYearly: return "autotrack"
        default: return "subscription"
        }
    }
}

private extension VerifiedSubscriptionPurchase {
    func hasSameRevenueIdentity(as other: VerifiedSubscriptionPurchase) -> Bool {
        transactionID == other.transactionID &&
        productID == other.productID &&
        price == other.price &&
        currency == other.currency &&
        tier == other.tier
    }
}

struct AppsFlyerPurchaseAttributionSender: PurchaseAttributionEventSending {
    func send(event: String, values: PurchaseAttributionEventValues) async throws {
        #if canImport(AppsFlyerLib)
        try await AppsFlyerManager.shared.logEventAcknowledged(
            event,
            values: values.appsFlyerDictionary
        )
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
