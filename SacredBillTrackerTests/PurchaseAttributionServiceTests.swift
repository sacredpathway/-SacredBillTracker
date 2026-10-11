import XCTest
@testable import SacredBillTracker

final class PurchaseAttributionServiceTests: XCTestCase {
    private actor Sender: PurchaseAttributionEventSending {
        struct Sent: Equatable { let name: String; let values: [String: String] }
        private(set) var events: [Sent] = []
        var delayNanoseconds: UInt64 = 0

        func send(event: String, values: [String: String]) async throws {
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

    private func assertEventPair(
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
        XCTAssertEqual(events.map(\.name), ["af_subscribe", "af_purchase"], file: file, line: line)
        XCTAssertEqual(events[0].values["af_transaction_id"], item.transactionID, file: file, line: line)
        XCTAssertEqual(events[1].values["af_revenue"], price, file: file, line: line)
        XCTAssertEqual(events[1].values["af_currency"], currency, file: file, line: line)
        XCTAssertEqual(events[1].values["af_content_id"], productID, file: file, line: line)
        XCTAssertEqual(events[1].values["subscription_tier"], tier, file: file, line: line)
        XCTAssertEqual(events[1].values["purchase_source"], "three_tier_paywall", file: file, line: line)
    }

    func test_verifiedEssential_emitsExactlyOnePair() async {
        await assertEventPair(tier: "essential", productID: ProductID.essentialMonthly, price: "4.99")
    }

    func test_verifiedBusiness_emitsExactlyOnePair() async {
        await assertEventPair(tier: "business", productID: ProductID.businessMonthly, price: "9.99")
    }

    func test_verifiedUnlimited_emitsExactlyOnePair() async {
        await assertEventPair(tier: "unlimited", productID: ProductID.unlimitedMonthly, price: "14.99", currency: "CAD")
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
        XCTAssertEqual(count, 2)
    }

    func test_concurrentProcessingSameTransaction_emitsOnePair() async {
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

    func test_nonSuccessStoreKitOutcomesHaveNoAttributionCallSite() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("SacredBillTracker/Services/StoreKit/TierEntitlementManager.swift"))
        let cancelled = source.range(of: "case .userCancelled:")!
        let pending = source.range(of: "case .pending:")!
        let unknown = source.range(of: "@unknown default:")!
        XCTAssertFalse(source[cancelled.lowerBound..<pending.lowerBound].contains("recordPurchaseAttribution"))
        XCTAssertFalse(source[pending.lowerBound..<unknown.lowerBound].contains("recordPurchaseAttribution"))
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

    func test_metaSDKIsNotLinkedAsSecondPurchasePath() {
        XCTAssertNil(NSClassFromString("FBSDKAppEvents"))
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}


final class StagingRoutingTests: XCTestCase {
    private func configuration(ref: String = SBTStagingRoute.project, role: String = "anon") -> [String: String] {
        let data = try! JSONSerialization.data(withJSONObject: ["ref": ref, "role": role])
        let payload = data.base64EncodedString().replacingOccurrences(of: "=", with: "")
        return ["SBT_STAGING_PROJECT": SBTStagingRoute.project,
                "SBT_STAGING_URL": "https://" + SBTStagingRoute.host,
                "SBT_STAGING_PUBLIC_KEY": "fixture." + payload + ".fixture"]
    }
    func testStagingResolvesExactProject() throws {
        XCTAssertEqual(try SBTStagingRoute.resolve(configuration()).url.host, SBTStagingRoute.host)
    }
    func testProductionURLRejected() {
        var v = configuration(); v["SBT_STAGING_URL"] = "https://zziauybwemoiqfpidiur.supabase.co"
        XCTAssertThrowsError(try SBTStagingRoute.resolve(v))
    }
    func testPlaceholderRejected() {
        var v = configuration(); v["SBT_STAGING_URL"] = "https://sbt-native-validation.invalid"
        XCTAssertThrowsError(try SBTStagingRoute.resolve(v))
    }
    func testMissingProjectRejected() {
        var v = configuration(); v.removeValue(forKey: "SBT_STAGING_PROJECT")
        XCTAssertThrowsError(try SBTStagingRoute.resolve(v))
    }
    func testMissingKeyRejected() {
        var v = configuration(); v.removeValue(forKey: "SBT_STAGING_PUBLIC_KEY")
        XCTAssertThrowsError(try SBTStagingRoute.resolve(v))
    }
    func testOtherProjectKeyRejected() { XCTAssertThrowsError(try SBTStagingRoute.resolve(configuration(ref: "zziauybwemoiqfpidiur"))) }
    func testPrivilegedKeyRejected() { XCTAssertThrowsError(try SBTStagingRoute.resolve(configuration(role: "service_role"))) }
    func testHostBoundary() {
        XCTAssertTrue(SBTStagingRoute.permits(URL(string: "https://" + SBTStagingRoute.host + "/auth/v1/user")))
        for value in ["http://" + SBTStagingRoute.host, "https://" + SBTStagingRoute.host + ".evil.invalid", "https://zziauybwemoiqfpidiur.supabase.co", "https://user@" + SBTStagingRoute.host, "https://" + SBTStagingRoute.host + ":444"] {
            XCTAssertFalse(SBTStagingRoute.permits(URL(string: value)))
        }
    }
    #if SBT_STAGING_ACCEPTANCE
    func testStagingAuthenticatesBothFixtureAccounts() async throws {
        for (label, expected) in [("A", "fef84b78-43b3-470b-97cf-95c17faee5c8"), ("B", "7107bedd-ea60-4dec-8ac9-aaedbea2deda")] {
            let token = try XCTUnwrap(ProcessInfo.processInfo.environment["SBT_ROUTING_ACCOUNT_" + label + "_TOKEN"])
            var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/user"))
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            let (data, response) = try await SupabaseConfig.networkSession.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let user = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(user["id"] as? String, expected)
            XCTAssertEqual(user["role"] as? String, "authenticated")
            print("STAGING_AUTH_VERIFIED account=" + label + " project=thwjnpofhrpxfuvwkfgd")
        }
    }
    func testCompiledStagingClientAndHealth() async throws {
        XCTAssertEqual(SupabaseConfig.url.host, SBTStagingRoute.host)
        XCTAssertEqual(SBTStagingRoute.cacheService, "com.sacredbilltracker.entitlement.staging.v1")
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/sbt-sandbox-account/health")
        let (data, response) = try await SupabaseConfig.networkSession.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 503)
        let health = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(health["ready"] as? Bool, false)
        print("STAGING_ROUTE_VERIFIED project=thwjnpofhrpxfuvwkfgd health=503 ready=false")
    }
    func testProductionRequestBlockedBeforeNetwork() async {
        do {
            _ = try await SupabaseConfig.networkSession.data(from: URL(string: "https://zziauybwemoiqfpidiur.supabase.co/rest/v1/subscriptions")!)
            XCTFail("Production request must be blocked")
        } catch { XCTAssertEqual((error as? URLError)?.code, .unsupportedURL) }
    }
    func testPlaceholderRequestBlockedBeforeNetwork() async {
        do {
            _ = try await SupabaseConfig.networkSession.data(from: URL(string: "https://sbt-native-validation.invalid")!)
            XCTFail("Placeholder request must be blocked")
        } catch { XCTAssertEqual((error as? URLError)?.code, .unsupportedURL) }
    }
    #endif
}
