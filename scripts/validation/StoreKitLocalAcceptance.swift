
#if canImport(StoreKitTest) && SBT_ISOLATED_VALIDATION
// Appended only in the isolated acceptance checkout, never in the 130-test workflow.
@MainActor
final class StoreKitLocalAcceptanceTests: XCTestCase {
    private func localSession() throws -> SKTestSession {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let session = try SKTestSession(contentsOf: root.appendingPathComponent("SacredBillTracker/Configuration.storekit"))
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    func test_localPurchaseRestoreAndRefund() async throws {
        let session = try localSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let owner = UUID()
        let purchased = try await session.buyProduct(identifier: ProductID.essentialMonthly, options: [.appAccountToken(owner)])
        guard purchased.environment == .xcode else { XCTFail("Only local StoreKit is authorized"); return }
        XCTAssertEqual(purchased.appAccountToken, owner)
        XCTAssertNil(purchased.revocationDate)
        XCTAssertGreaterThan(try XCTUnwrap(purchased.expirationDate), Date())
        // Same StoreKit restore API used by the app; the active local configuration
        // and successful .xcode transaction are prerequisites, not a live store login.
        try await AppStore.sync()
        guard case .verified(let restored)? = await StoreKit.Transaction.latest(for: ProductID.essentialMonthly) else {
            XCTFail("Local restore must return a verified transaction"); return
        }
        XCTAssertEqual(restored.originalID, purchased.originalID)
        XCTAssertEqual(restored.appAccountToken, owner)
        XCTAssertEqual(restored.environment, .xcode)
        try session.refundTransaction(identifier: UInt(purchased.id))
        var refunded: StoreKit.Transaction?
        for _ in 0..<40 {
            if case .verified(let current)? = await StoreKit.Transaction.latest(for: ProductID.essentialMonthly), current.revocationDate != nil {
                refunded = current; break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let negative = try XCTUnwrap(refunded, "Local refund must reach StoreKit's verified transaction state")
        XCTAssertEqual(negative.originalID, purchased.originalID)
        XCTAssertNotNil(negative.revocationDate)
        XCTAssertEqual(negative.environment, .xcode)
        XCTAssertNil(SBTVerifiedEntitlementStore.serverEnvironment(for: negative.environment))
    }

    func test_localExpiredSubscriptionLosesCurrentEntitlement() async throws {
        let session = try localSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let purchased = try await session.buyProduct(identifier: ProductID.essentialMonthly, options: [.appAccountToken(UUID())])
        guard purchased.environment == .xcode else { XCTFail("Only local StoreKit is authorized"); return }
        try session.disableAutoRenewForTransaction(identifier: UInt(purchased.id))
        try session.expireSubscription(productIdentifier: ProductID.essentialMonthly)
        var hasActive = true
        for _ in 0..<40 {
            hasActive = false
            for await result in StoreKit.Transaction.currentEntitlements {
                if case .verified(let value) = result, value.productID == ProductID.essentialMonthly,
                   value.revocationDate == nil, (value.expirationDate ?? .distantPast) > Date() { hasActive = true }
            }
            if !hasActive { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(hasActive, "Expired local subscription must not remain active")
    }
}
#endif
