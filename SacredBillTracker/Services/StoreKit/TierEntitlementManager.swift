//
//  TierEntitlementManager.swift
//  SacredBillTracker
//
//  Three-tier presentation over the shared verified StoreKit/backend snapshot.
//  SubscriptionManager and this manager consume the same account-scoped policy;
//  a backend scalar cannot bypass expiry, revocation or the offline time limit.
//

import Foundation
import Combine
import StoreKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class TierEntitlementManager: ObservableObject {

    /// Highest tier the user currently holds (local ∪ backend).
    @Published private(set) var activeTier: PlanTier = .free
    /// Loaded StoreKit products for the three plans, keyed by product ID.
    @Published private(set) var planProducts: [String: Product] = [:]
    @Published private(set) var isLoading = false
    @Published var lastError: String?
    @Published var lastPurchaseSucceeded = false

    private var identityRevision = 0
    private var listener: Task<Void, Never>?

    // MARK: Convenience gating

    var hasEssential: Bool { activeTier >= .essential }
    var hasBusiness:  Bool { activeTier >= .business }
    var hasUnlimited: Bool { activeTier >= .unlimited }

    func has(_ feature: GatedFeature) -> Bool {
        activeTier >= feature.requiredTier
    }

    func product(for tier: PlanTier) -> Product? {
        guard let pid = tier.productID else { return nil }
        return planProducts[pid]
    }

    // MARK: Lifecycle

    private var entitlementObservation: AnyCancellable?
    private var accountObservation: AnyCancellable?
    private var rewardObservation: AnyCancellable?
    init() {
        accountObservation = SBTVerifiedEntitlementStore.shared.$accountTier.sink { [weak self] tier in
            self?.activeTier = max(tier, SBTVerifiedEntitlementStore.shared.rewardTier,
                SBTVerifiedEntitlementStore.shared.productIDs.map(PlanTier.from(productID:)).max() ?? .free)
        }
        rewardObservation = SBTVerifiedEntitlementStore.shared.$rewardTier.sink { [weak self] tier in
            self?.activeTier = max(tier, SBTVerifiedEntitlementStore.shared.accountTier, SBTVerifiedEntitlementStore.shared.productIDs.map(PlanTier.from(productID:)).max() ?? .free)
        }
        entitlementObservation = SBTVerifiedEntitlementStore.shared.$productIDs.sink { [weak self] ids in
            self?.activeTier = max(SBTVerifiedEntitlementStore.shared.rewardTier, SBTVerifiedEntitlementStore.shared.accountTier, ids.map(PlanTier.from(productID:)).max() ?? .free)
        }
    }

    func start() async {
        await loadProducts()
        await refreshFromStoreKit()
        await refreshFromBackend()
        startListener()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: ProductID.tierPlans)
            var map: [String: Product] = [:]
            for p in products { map[p.id] = p }
            planProducts = map
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Both existing managers consume the same account-bound verified snapshot.
    func refreshFromStoreKit() async {
        await SBTVerifiedEntitlementStore.shared.refreshFromApple()
        lastError = SBTVerifiedEntitlementStore.shared.verificationMessage
        activeTier = max(SBTVerifiedEntitlementStore.shared.rewardTier, SBTVerifiedEntitlementStore.shared.accountTier, SBTVerifiedEntitlementStore.shared.productIDs.map(PlanTier.from(productID:)).max() ?? .free)
    }

    func refreshFromBackend() async {
        await refreshFromStoreKit()
    }

    // MARK: Purchase / upgrade / downgrade / restore

    /// Purchase (or upgrade/downgrade — StoreKit resolves within the group).
    @discardableResult
    func purchase(tier: PlanTier, appAccountToken: UUID? = nil) async -> Bool {
        guard let product = product(for: tier) else {
            lastError = "Plan not available."
            return false
        }
        await AnalyticsService.shared.log(.planSelected, tier: tier.rawValue, source: "paywall")
        do {
            let authenticatedID = await AuthService.shared.verifiedPurchaseAccountID()
            // An explicit caller token must refer to this live authenticated session.
            if let requested = appAccountToken, requested != authenticatedID {
                lastError = "Sign in to the purchasing Sacred Bill Tracker account and try again."
                return false
            }
            var options: Set<Product.PurchaseOption> = []
            if let token = authenticatedID { options.insert(.appAccountToken(token)) }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    let purchased = PlanTier.from(productID: txn.productID)
                    let previous = activeTier
                    await txn.finish()
                    await syncPurchaseToBackend(txn)
                    await refreshFromStoreKit()
                    await AnalyticsService.shared.log(
                        purchased > previous ? .upgrade : (purchased < previous ? .downgrade : .purchase),
                        tier: purchased.rawValue, source: "paywall")
                    await recordPurchaseAttribution(
                        transaction: txn,
                        product: product,
                        tier: purchased,
                        source: "three_tier_paywall"
                    )
                    let granted = SBTPostPurchaseAccessPolicy.grantsPurchasedPlan(
                        purchased: purchased,
                        active: activeTier
                    )
                    lastPurchaseSucceeded = granted
                    if !granted {
                        lastError = SBTVerifiedEntitlementStore.shared.verificationMessage
                            ?? "Your purchase was verified, but access has not finished syncing. Restore purchases or try again in a moment."
                    }
                    return granted
                }
                return false
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshFromStoreKit()
        await refreshFromBackend()
        await AnalyticsService.shared.log(.restore, tier: activeTier.rawValue, source: "settings")
    }

    func manageSubscriptions() async {
        AnalyticsService.shared.track(.subscriptionManagementOpened, source: "settings")
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refreshFromStoreKit()
        #endif
    }

    private func syncPurchaseToBackend(_ txn: StoreKit.Transaction) async {
        #if DEBUG && canImport(Supabase)
        // Xcode fixtures never call a hosted service. Sandbox transactions never
        // fall through to production verification/referral writes in DEBUG.
        if txn.environment == .xcode { return }
        if txn.environment == .sandbox {
            guard let session = try? await SBTSandboxSession.shared.verifiedSession(), txn.appAccountToken == session.owner else { return }
            let sandbox = SBTAccountIntegration()
            await sandbox.verifySubscription(originalTransactionID: String(txn.originalID))
            return
        }
        #endif
        #if canImport(Supabase)
        guard txn.environment == .production,
              let owner = await AuthService.shared.verifiedPurchaseAccountID(),
              txn.appAccountToken == owner else { return }
        struct Body: Encodable {
            let platform: String
            let product_id: String
            let original_transaction_id: String
        }
        let body = Body(platform: "apple",
                        product_id: txn.productID,
                        original_transaction_id: String(txn.originalID))
        do {
            try await SupabaseConfig.client.functions.invoke(
                "verify-store-subscription",
                options: FunctionInvokeOptions(body: body))
        } catch {
            #if DEBUG
            print("[Tier] verify-store-subscription failed: \(error)")
            #endif
        }
        // Mark any pending referral as subscribed (qualification handled
        // server-side via qualify_referrals after 30 days). Uses auth.uid()
        // on the server — no client-supplied user id.
        do {
            try await SupabaseConfig.client.rpc("referral_self_mark_subscribed").execute()
        } catch { /* best-effort */ }
        #endif
    }

    private func startListener() {
        guard listener == nil else { return }
        listener = Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let txn) = update else { continue }
                await SBTVerifiedEntitlementStore.shared.invalidateVerifiedStoreKitTransaction(txn)
                await txn.finish()
                await self?.syncPurchaseToBackend(txn)
                await self?.refreshFromStoreKit()
                guard ProductID.tierPlans.contains(txn.productID),
                      let self,
                      let product = await self.productForAttribution(id: txn.productID) else { continue }
                await self.recordPurchaseAttribution(
                    transaction: txn,
                    product: product,
                    tier: PlanTier.from(productID: txn.productID),
                    source: "transaction_listener"
                )
            }
        }
    }

    private func productForAttribution(id: String) async -> Product? {
        if let loaded = planProducts[id] { return loaded }
        return try? await Product.products(for: [id]).first
    }

    private func recordPurchaseAttribution(
        transaction: StoreKit.Transaction,
        product: Product,
        tier: PlanTier,
        source: String
    ) async {
        let outcome = await PurchaseAttributionService.shared.recordVerifiedSubscriptionPurchase(
            transaction: transaction,
            product: product,
            tier: tier.rawValue,
            source: source
        )
        if case .deferred(let reason) = outcome {
            #if DEBUG
            print("[AppsFlyer][Tier] Attribution deferred for \(transaction.id): \(reason)")
            #endif
        }
    }

    func clearForSignedOutUser() {
        identityRevision += 1
        activeTier = .free
    }
}

enum SBTPostPurchaseAccessPolicy {
    static func grantsPurchasedPlan(purchased: PlanTier, active: PlanTier) -> Bool {
        active >= purchased
    }
}

/// Call only after StoreKit cryptographic verification. No offer-code/lifetime fallback.
enum SBTVerifiedTransactionTier {
    static func resolve(product: String, expiry: Date?, revoked: Bool, upgraded: Bool, now: Date = Date()) -> PlanTier {
        guard !revoked, !upgraded, let expiry, expiry > now else { return .free }
        return PlanTier.from(productID: product)
    }
}
