import XCTest
@testable import SacredBillTracker

final class PurchaseAttributionServiceTests: XCTestCase {
    private actor Sender: PurchaseAttributionEventSending {
        struct Sent: Equatable { let name: String; let values: PurchaseAttributionEventValues }
        private(set) var events: [Sent] = []
        var delayNanoseconds: UInt64 = 0
        var failuresRemaining = 0

        func send(event: String, values: PurchaseAttributionEventValues) async throws {
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw TestError.rejected
            }
            events.append(Sent(name: event, values: values))
        }

        func snapshot() -> [Sent] { events }
        func setDelay(_ value: UInt64) { delayNanoseconds = value }
        func failNextSend() { failuresRemaining += 1 }
    }

    private final class MemoryStore: PurchaseAttributionPersisting, @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?

        init(data: Data? = nil) { self.data = data }

        func load() throws -> Data? { lock.withLock { data } }
        func save(_ data: Data) throws { lock.withLock { self.data = data } }
    }

    private struct FailingSaveStore: PurchaseAttributionPersisting {
        func load() throws -> Data? { nil }
        func save(_ data: Data) throws { throw TestError.rejected }
    }

    private enum TestError: Error { case rejected }

    private struct LegacyRecord: Codable {
        let purchase: VerifiedSubscriptionPurchase
        let phase: String
    }

    private struct VersionedRecord: Codable {
        let purchase: VerifiedSubscriptionPurchase
        let phase: String
        let contractVersion: Int
    }

    private func purchase(
        id: String = "1000000123456789",
        productID: String,
        price: String,
        currency: String = "USD",
        tier: String
    ) -> VerifiedSubscriptionPurchase {
        VerifiedSubscriptionPurchase(
            transactionID: id,
            productID: productID,
            price: Decimal(string: price)!,
            currency: currency,
            tier: tier,
            source: "three_tier_paywall"
        )
    }

    private func assertSingleRevenueEvent(
        tier: String,
        productID: String,
        price: String,
        currency: String = "USD",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let item = purchase(productID: productID, price: price, currency: currency, tier: tier)

        let outcome = await service.recordVerifiedSubscriptionPurchase(item)
        XCTAssertEqual(outcome, .recorded, file: file, line: line)
        let events = await sender.snapshot()
        XCTAssertEqual(events.map(\.name), ["af_purchase"], file: file, line: line)
        XCTAssertEqual(events[0].values.transactionID, item.transactionID, file: file, line: line)
        XCTAssertEqual(events[0].values.revenue, Decimal(string: price), file: file, line: line)
        XCTAssertEqual(events[0].values.currency, currency, file: file, line: line)
        XCTAssertEqual(events[0].values.productID, productID, file: file, line: line)
        XCTAssertEqual(events[0].values.tier, tier, file: file, line: line)
        XCTAssertEqual(events[0].values.source, "three_tier_paywall", file: file, line: line)
        XCTAssertTrue(events[0].values.appsFlyerDictionary["af_revenue"] is NSDecimalNumber, file: file, line: line)
    }

    func test_verifiedEssential_emitsExactlyOneRevenueEvent() async {
        await assertSingleRevenueEvent(tier: "essential", productID: ProductID.essentialMonthly, price: "4.99")
    }

    func test_verifiedBusiness_emitsExactlyOneRevenueEvent() async {
        await assertSingleRevenueEvent(tier: "business", productID: ProductID.businessMonthly, price: "9.99")
    }

    func test_verifiedUnlimited_emitsExactlyOneRevenueEvent() async {
        await assertSingleRevenueEvent(tier: "unlimited", productID: ProductID.unlimitedMonthly, price: "14.99", currency: "CAD")
    }

    func test_reprocessingSameTransaction_emitsNoDuplicate() async {
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")

        let first = await service.recordVerifiedSubscriptionPurchase(item)
        let second = await service.recordVerifiedSubscriptionPurchase(item)
        let count = await sender.snapshot().count
        XCTAssertEqual(first, .recorded)
        XCTAssertEqual(second, .alreadyRecorded)
        XCTAssertEqual(count, 1)
    }

    func test_concurrentProcessingSameTransaction_emitsOneRevenueEvent() async {
        let sender = Sender()
        await sender.setDelay(30_000_000)
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let item = purchase(productID: ProductID.unlimitedMonthly, price: "14.99", tier: "unlimited")

        async let first = service.recordVerifiedSubscriptionPurchase(item)
        async let second = service.recordVerifiedSubscriptionPurchase(item)
        _ = await [first, second]

        let names = await sender.snapshot().map(\.name)
        XCTAssertEqual(names, ["af_purchase"])
    }

    func test_relaunchWithPersistedTransaction_emitsNoDuplicate() async {
        let persistence = MemoryStore()
        let firstSender = Sender()
        let item = purchase(productID: ProductID.essentialMonthly, price: "4.99", tier: "essential")
        let firstService = PurchaseAttributionService(sender: firstSender, persistence: persistence)
        let firstOutcome = await firstService.recordVerifiedSubscriptionPurchase(item)
        XCTAssertEqual(firstOutcome, .recorded)

        let relaunchedSender = Sender()
        let relaunchedService = PurchaseAttributionService(sender: relaunchedSender, persistence: persistence)
        let relaunchOutcome = await relaunchedService.recordVerifiedSubscriptionPurchase(item)
        let relaunchedEvents = await relaunchedSender.snapshot()
        XCTAssertEqual(relaunchOutcome, .alreadyRecorded)
        XCTAssertTrue(relaunchedEvents.isEmpty)
    }

    func test_preparedBeforeFinish_survivesRelaunchAndDeliversOnce() async {
        let persistence = MemoryStore()
        let firstSender = Sender()
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")
        let firstService = PurchaseAttributionService(sender: firstSender, persistence: persistence)

        let preparation = await firstService.prepareVerifiedSubscriptionPurchase(item)
        XCTAssertEqual(preparation, .prepared)
        let eventsBeforeRelaunch = await firstSender.snapshot()
        XCTAssertTrue(eventsBeforeRelaunch.isEmpty)

        let relaunchedSender = Sender()
        let relaunchedService = PurchaseAttributionService(sender: relaunchedSender, persistence: persistence)
        let outcome = await relaunchedService.deliverPreparedPurchase(transactionID: item.transactionID)
        XCTAssertEqual(outcome, .recorded)
        let relaunchedEvents = await relaunchedSender.snapshot()
        XCTAssertEqual(relaunchedEvents.map(\.name), ["af_purchase"])

        let secondOutcome = await relaunchedService.deliverPreparedPurchase(transactionID: item.transactionID)
        XCTAssertEqual(secondOutcome, .alreadyRecorded)
        let finalEventCount = await relaunchedSender.snapshot().count
        XCTAssertEqual(finalEventCount, 1)
    }

    func test_onlyDurableOrTerminalPreparationPermitsStoreKitFinish() {
        XCTAssertTrue(PurchaseAttributionPreparationOutcome.prepared.permitsStoreKitFinish)
        XCTAssertTrue(PurchaseAttributionPreparationOutcome.alreadyRecorded.permitsStoreKitFinish)
        XCTAssertTrue(PurchaseAttributionPreparationOutcome.ineligible("not revenue").permitsStoreKitFinish)
        XCTAssertFalse(PurchaseAttributionPreparationOutcome.deferred("not durable").permitsStoreKitFinish)
    }

    func test_sameTransactionFromDifferentListeners_usesOnePreparedRevenueIdentity() async {
        let persistence = MemoryStore()
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: persistence)
        let direct = purchase(productID: ProductID.essentialMonthly, price: "4.99", tier: "essential")
        let listener = VerifiedSubscriptionPurchase(
            transactionID: direct.transactionID,
            productID: direct.productID,
            price: direct.price,
            currency: direct.currency,
            tier: direct.tier,
            source: "transaction_listener"
        )

        let firstPreparation = await service.prepareVerifiedSubscriptionPurchase(direct)
        let secondPreparation = await service.prepareVerifiedSubscriptionPurchase(listener)
        XCTAssertEqual(firstPreparation, .prepared)
        XCTAssertEqual(secondPreparation, .prepared)

        _ = await service.deliverPreparedPurchase(transactionID: direct.transactionID)
        _ = await service.deliverPreparedPurchase(transactionID: direct.transactionID)
        let events = await sender.snapshot()
        XCTAssertEqual(events.map(\.name), ["af_purchase"])
        XCTAssertEqual(events[0].values.source, "three_tier_paywall")
    }

    func test_differentTransactionsEmitSeparateLegitimateRevenueEvents() async {
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let first = purchase(id: "initial-transaction", productID: ProductID.businessMonthly, price: "9.99", tier: "business")
        let second = purchase(id: "different-transaction", productID: ProductID.businessMonthly, price: "9.99", tier: "business")

        let firstOutcome = await service.recordVerifiedSubscriptionPurchase(first)
        let secondOutcome = await service.recordVerifiedSubscriptionPurchase(second)
        XCTAssertEqual(firstOutcome, .recorded)
        XCTAssertEqual(secondOutcome, .recorded)

        let events = await sender.snapshot()
        XCTAssertEqual(events.map(\.name), ["af_purchase", "af_purchase"])
        XCTAssertEqual(events.map(\.values.transactionID), [first.transactionID, second.transactionID])
    }

    func test_renewalWithNewAppleTransactionIDEmitsNewRevenueEvent() async {
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let initial = purchase(id: "apple-initial-id", productID: ProductID.essentialMonthly, price: "4.99", tier: "essential")
        let renewal = purchase(id: "apple-renewal-id", productID: ProductID.essentialMonthly, price: "4.99", tier: "essential")

        _ = await service.recordVerifiedSubscriptionPurchase(initial)
        _ = await service.recordVerifiedSubscriptionPurchase(renewal)

        let transactionIDs = await sender.snapshot().map(\.values.transactionID)
        XCTAssertEqual(transactionIDs, ["apple-initial-id", "apple-renewal-id"])
    }

    func test_legacySubscribeSentRecordCompletesWithoutSecondRevenueEvent() async throws {
        let item = purchase(productID: ProductID.unlimitedMonthly, price: "14.99", tier: "unlimited")
        let encoded = try JSONEncoder().encode([
            item.transactionID: LegacyRecord(purchase: item, phase: "subscribeSent")
        ])
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore(data: encoded))

        let outcome = await service.recordVerifiedSubscriptionPurchase(item)
        let events = await sender.snapshot()
        XCTAssertEqual(outcome, .alreadyRecorded)
        XCTAssertTrue(events.isEmpty)
    }

    func test_legacyPendingRecordIsQuarantinedWithoutRevenueEvent() async throws {
        let item = purchase(productID: ProductID.essentialMonthly, price: "4.99", tier: "essential")
        let encoded = try JSONEncoder().encode([
            item.transactionID: LegacyRecord(purchase: item, phase: "pending")
        ])
        let sender = Sender()
        let persistence = MemoryStore(data: encoded)
        let service = PurchaseAttributionService(sender: sender, persistence: persistence)

        guard case .deferred(let reason) = await service.recordVerifiedSubscriptionPurchase(item) else {
            return XCTFail("Ambiguous legacy pending state must be quarantined")
        }
        let initialEvents = await sender.snapshot()
        XCTAssertTrue(reason.contains("quarantined"))
        XCTAssertTrue(initialEvents.isEmpty)

        let relaunchedSender = Sender()
        let relaunched = PurchaseAttributionService(sender: relaunchedSender, persistence: persistence)
        _ = await relaunched.retryPendingPurchases()
        let relaunchedEvents = await relaunchedSender.snapshot()
        XCTAssertTrue(relaunchedEvents.isEmpty)
    }

    func test_relaunchAutomaticallyRetriesVersionedPendingPurchase() async {
        let persistence = MemoryStore()
        let initialSender = Sender()
        await initialSender.failNextSend()
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")
        let initialService = PurchaseAttributionService(sender: initialSender, persistence: persistence)
        guard case .deferred = await initialService.recordVerifiedSubscriptionPurchase(item) else {
            return XCTFail("Initial failed send must remain pending")
        }

        let relaunchedSender = Sender()
        let relaunched = PurchaseAttributionService(sender: relaunchedSender, persistence: persistence)
        let outcomes = await relaunched.retryPendingPurchases()
        let events = await relaunchedSender.snapshot()
        XCTAssertEqual(outcomes[item.transactionID], .recorded)
        XCTAssertEqual(events.map(\.name), ["af_purchase"])
        XCTAssertEqual(events.map(\.values.transactionID), [item.transactionID])

        let secondDrain = await relaunched.retryPendingPurchases()
        XCTAssertTrue(secondDrain.isEmpty)
    }

    func test_corruptLedgerFailsClosedWithoutSendingRevenue() async {
        let sender = Sender()
        let persistence = MemoryStore(data: Data("not-json".utf8))
        let item = purchase(productID: ProductID.unlimitedMonthly, price: "14.99", tier: "unlimited")
        let service = PurchaseAttributionService(sender: sender, persistence: persistence)

        guard case .deferred(let reason) = await service.recordVerifiedSubscriptionPurchase(item) else {
            return XCTFail("Corrupt ledger must fail closed")
        }
        let events = await sender.snapshot()
        XCTAssertTrue(reason.contains("could not be loaded"))
        XCTAssertTrue(events.isEmpty)
    }

    func test_initialPersistenceFailureDefersWithoutSendingOrPermittingFinish() async {
        let sender = Sender()
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")
        let service = PurchaseAttributionService(sender: sender, persistence: FailingSaveStore())

        let preparation = await service.prepareVerifiedSubscriptionPurchase(item)
        guard case .deferred(let reason) = preparation else {
            return XCTFail("A non-durable transaction must be deferred")
        }
        let events = await sender.snapshot()
        XCTAssertTrue(reason.contains("Could not persist pending attribution"))
        XCTAssertFalse(preparation.permitsStoreKitFinish)
        XCTAssertTrue(events.isEmpty)
    }

    func test_futureContractVersionFailsClosedWithoutSendingRevenue() async throws {
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")
        let encoded = try JSONEncoder().encode([
            item.transactionID: VersionedRecord(
                purchase: item,
                phase: "pending",
                contractVersion: 999
            )
        ])
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore(data: encoded))

        guard case .deferred(let reason) = await service.recordVerifiedSubscriptionPurchase(item) else {
            return XCTFail("Future contract version must fail closed")
        }
        let events = await sender.snapshot()
        XCTAssertTrue(reason.contains("unsupported"))
        XCTAssertTrue(events.isEmpty)
    }

    func test_failedDeliveryStaysPendingAndRetryEmitsOneRevenueEvent() async {
        let sender = Sender()
        await sender.failNextSend()
        let persistence = MemoryStore()
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")
        let service = PurchaseAttributionService(sender: sender, persistence: persistence)

        guard case .deferred = await service.recordVerifiedSubscriptionPurchase(item) else {
            return XCTFail("Failed send must remain deferred")
        }
        let retryOutcome = await service.recordVerifiedSubscriptionPurchase(item)
        let eventNames = await sender.snapshot().map(\.name)
        XCTAssertEqual(retryOutcome, .recorded)
        XCTAssertEqual(eventNames, ["af_purchase"])
    }

    func test_nonSuccessStoreKitOutcomesHaveNoAttributionCallSite() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("SacredBillTracker/Services/StoreKit/TierEntitlementManager.swift"))
        let cancelled = source.range(of: "case .userCancelled:")!
        let pending = source.range(of: "case .pending:")!
        let unknown = source.range(of: "@unknown default:")!
        XCTAssertFalse(source[cancelled.lowerBound..<pending.lowerBound].contains("preparePurchaseAttribution"))
        XCTAssertFalse(source[pending.lowerBound..<unknown.lowerBound].contains("preparePurchaseAttribution"))
    }

    func test_unverifiedStoreKitResultsCannotReachPurchaseAttribution() throws {
        let subscriptionSource = try String(contentsOf: sourceRoot().appendingPathComponent("SacredBillTracker/Services/StoreKit/SubscriptionManager.swift"))
        XCTAssertTrue(subscriptionSource.contains("case .unverified(_, let error):\n            throw error"))
        XCTAssertTrue(subscriptionSource.contains("let transaction = try checkVerified(verification)"))

        let tierSource = try String(contentsOf: sourceRoot().appendingPathComponent("SacredBillTracker/Services/StoreKit/TierEntitlementManager.swift"))
        XCTAssertTrue(tierSource.contains("if case .verified(let txn) = verification"))
        XCTAssertTrue(tierSource.contains("guard case .verified(let txn) = update else { continue }"))
    }

    func test_restoreAndEntitlementRefreshDoNotEmitPurchaseAttribution() throws {
        for relativePath in [
            "SacredBillTracker/Services/StoreKit/TierEntitlementManager.swift",
            "SacredBillTracker/Services/StoreKit/SubscriptionManager.swift"
        ] {
            let source = try String(contentsOf: sourceRoot().appendingPathComponent(relativePath))
            for functionName in ["func restore(", "func restorePurchases(", "func refreshFromStoreKit(", "func refreshEntitlements("] {
                guard let start = source.range(of: functionName) else { continue }
                let tail = source[start.lowerBound...]
                let end = tail.dropFirst().firstIndex(of: "}") ?? tail.endIndex
                XCTAssertFalse(tail[..<end].contains("preparePurchaseAttribution"), "\(functionName) must not attribute")
                XCTAssertFalse(tail[..<end].contains("schedulePurchaseAttributionDelivery"), "\(functionName) must not deliver attribution")
            }
        }
    }

    func test_purchaseCallSitesPrepareDurablyBeforeFinishingStoreKitTransaction() throws {
        for relativePath in [
            "SacredBillTracker/Services/StoreKit/TierEntitlementManager.swift",
            "SacredBillTracker/Services/StoreKit/SubscriptionManager.swift"
        ] {
            let source = try String(contentsOf: sourceRoot().appendingPathComponent(relativePath))
            let purchasePreparation = source.range(of: "let attributionPreparation = await preparePurchaseAttribution")
            let finish = source.range(of: "await transaction.finish()") ?? source.range(of: "await txn.finish()")
            XCTAssertNotNil(purchasePreparation, "\(relativePath) must prepare attribution")
            XCTAssertNotNil(finish, "\(relativePath) must finish StoreKit transactions")
            if let purchasePreparation, let finish {
                XCTAssertLessThan(purchasePreparation.lowerBound, finish.lowerBound)
            }
            XCTAssertEqual(
                source.components(separatedBy: "if attributionPreparation.permitsStoreKitFinish").count - 1,
                2,
                "Every direct and listener finish in \(relativePath) must be gated by durable preparation"
            )
        }
    }

    func test_transactionPayloadUsesPaidTransactionValuesAndRejectsFalseRevenueStates() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("SacredBillTracker/Services/StoreKit/PurchaseAttributionService.swift"))
        XCTAssertTrue(source.contains("transaction.revocationDate == nil"))
        XCTAssertTrue(source.contains("!transaction.isUpgraded"))
        XCTAssertTrue(source.contains("transaction.ownershipType == .purchased"))
        XCTAssertTrue(source.contains("transaction.reason == .purchase || transaction.reason == .renewal"))
        XCTAssertTrue(source.contains("let price = transaction.price, price > 0"))
        XCTAssertTrue(source.contains("transaction.currency?.identifier"))
        XCTAssertTrue(source.contains("StoreKit.Transaction.unfinished"))
    }

    func test_metaSDKIsNotLinkedAsSecondPurchasePath() {
        XCTAssertNil(NSClassFromString("FBSDKAppEvents"))
    }

    func test_appStartsAppsFlyerForEachActiveSessionAndDrainsPendingPurchases() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("SacredBillTracker/SacredBillTrackerApp.swift"))
        XCTAssertFalse(source.contains("private var didStart"))
        XCTAssertTrue(source.contains(".onChange(of: scenePhase, initial: true)"))
        XCTAssertTrue(source.contains("AppsFlyerLib.shared().start()"))
        XCTAssertTrue(source.contains("PurchaseAttributionService.shared.recoverUnfinishedTransactions()"))
        XCTAssertTrue(source.contains("PurchaseAttributionService.shared.retryPendingPurchases()"))
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
