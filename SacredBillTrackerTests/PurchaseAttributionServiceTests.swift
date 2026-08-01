import XCTest
@testable import SacredBillTracker

final class PurchaseAttributionServiceTests: XCTestCase {
    private actor Sender: PurchaseAttributionEventSending {
        struct Sent: Equatable {
            let name: String
            let values: [String: PurchaseAttributionValue]
        }

        private(set) var events: [Sent] = []
        var delayNanoseconds: UInt64 = 0

        func send(event: String, values: [String: PurchaseAttributionValue]) async throws {
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            events.append(Sent(name: event, values: values))
        }

        func snapshot() -> [Sent] { events }
        func setDelay(_ value: UInt64) { delayNanoseconds = value }
    }

    private final class MemoryStore: PurchaseAttributionPersisting, @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?

        func load() throws -> Data? { lock.withLock { data } }
        func save(_ data: Data) throws { lock.withLock { self.data = data } }
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

    func test_subscribeIsLifecycleOnlyAndPurchaseCarriesRevenue() async {
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")

        let outcome = await service.recordVerifiedSubscriptionPurchase(item)
        let events = await sender.snapshot()

        XCTAssertEqual(outcome, .recorded)
        XCTAssertEqual(events.map(\.name), ["af_subscribe", "af_purchase"])
        XCTAssertEqual(events[0].values["af_content_id"], .string(ProductID.businessMonthly))
        XCTAssertEqual(events[0].values["af_transaction_id"], .string(item.transactionID))
        XCTAssertNil(events[0].values["af_revenue"])
        XCTAssertNil(events[0].values["af_currency"])
        XCTAssertEqual(events[1].values["af_content_id"], .string(ProductID.businessMonthly))
        XCTAssertEqual(events[1].values["af_revenue"], .decimal("9.99"))
        XCTAssertEqual(events[1].values["af_currency"], .string("USD"))
        XCTAssertEqual(events[1].values["subscription_tier"], .string("business"))
        XCTAssertEqual(events[1].values["purchase_source"], .string("three_tier_paywall"))
    }

    func test_reprocessingSameTransactionEmitsNoDuplicate() async {
        let sender = Sender()
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let item = purchase(productID: ProductID.businessMonthly, price: "9.99", tier: "business")

        let first = await service.recordVerifiedSubscriptionPurchase(item)
        let second = await service.recordVerifiedSubscriptionPurchase(item)
        let count = await sender.snapshot().count

        XCTAssertEqual(first, .recorded)
        XCTAssertEqual(second, .alreadyRecorded)
        XCTAssertEqual(count, 2)
    }

    func test_concurrentProcessingSameTransactionEmitsOnePair() async {
        let sender = Sender()
        await sender.setDelay(30_000_000)
        let service = PurchaseAttributionService(sender: sender, persistence: MemoryStore())
        let item = purchase(productID: ProductID.unlimitedMonthly, price: "14.99", tier: "unlimited")

        async let first = service.recordVerifiedSubscriptionPurchase(item)
        async let second = service.recordVerifiedSubscriptionPurchase(item)
        _ = await [first, second]

        let names = await sender.snapshot().map(\.name)
        XCTAssertEqual(names, ["af_subscribe", "af_purchase"])
    }

    func test_relaunchWithPersistedTransactionEmitsNoDuplicate() async {
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

    func test_revokedOrExpiredTransactionsAreNotAttributable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(PurchaseAttributionService.isAttributable(
            transactionRevocationDate: now,
            expirationDate: now.addingTimeInterval(3600),
            now: now
        ))
        XCTAssertFalse(PurchaseAttributionService.isAttributable(
            transactionRevocationDate: nil,
            expirationDate: now.addingTimeInterval(-1),
            now: now
        ))
        XCTAssertTrue(PurchaseAttributionService.isAttributable(
            transactionRevocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            now: now
        ))
    }

    func test_storeKitManagersUseCentralAttributionService() throws {
        for relativePath in [
            "SacredBillTracker/Services/StoreKit/SubscriptionManager.swift",
            "SacredBillTracker/Services/StoreKit/TierEntitlementManager.swift"
        ] {
            let source = try String(contentsOf: sourceRoot().appendingPathComponent(relativePath))
            XCTAssertFalse(source.contains("AppsFlyerManager.shared.logSubscriptionStarted"))
            XCTAssertFalse(source.contains("AppsFlyerManager.shared.logPurchase"))
            XCTAssertTrue(source.contains("PurchaseAttributionService.shared.recordVerifiedSubscriptionPurchase"))
            XCTAssertTrue(source.contains("PurchaseAttributionService.isAttributable"))
        }
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
                XCTAssertFalse(tail[..<end].contains("recordPurchaseAttribution"), "\(functionName) must not attribute")
            }
        }
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
