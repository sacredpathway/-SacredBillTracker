//
//  TierEntitlementManager.swift
//  SacredBillTracker
//
//  Source of truth for the 3-tier plan (Essential / Business / Unlimited).
//  Computes the active tier from StoreKit `Transaction.currentEntitlements`
//  (local, authoritative for the device) and PROMOTES from the backend
//  `current_subscription_tier` RPC (cross-device / webhook-updated). It only
//  ever promotes from the backend — it never demotes a valid local
//  StoreKit entitlement (mirrors the AutoTrack pattern in SubscriptionManager).
//
//  Additive: does not replace SubscriptionManager. Inject both as
//  @EnvironmentObject. Feature gating throughout the app reads `activeTier`.
//

import Foundation
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

    init() {}

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

    /// Compute tier from local StoreKit entitlements (authoritative for lapse).
    func refreshFromStoreKit() async {
        var best: PlanTier = .free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            if txn.revocationDate != nil { continue }
            if let exp = txn.expirationDate, exp < Date() { continue }
            let tier = PlanTier.from(productID: txn.productID)
            if tier > best { best = tier }
        }
        // Local entitlements are authoritative downward: set directly.
        activeTier = best
    }

    /// Promote (never demote) from the backend cross-device tier.
    func refreshFromBackend() async {
        #if canImport(Supabase)
        do {
            // current_subscription_tier() returns a scalar text; decode as String.
            let tierString: String = try await SupabaseConfig.client
                .rpc("current_subscription_tier")
                .execute()
                .value
            let backendTier = PlanTier.from(backend: tierString)
            if backendTier > activeTier { activeTier = backendTier }
        } catch {
            #if DEBUG
            print("[Tier] current_subscription_tier failed: \(error)")
            #endif
        }
        #endif
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
            var options: Set<Product.PurchaseOption> = []
            if let token = appAccountToken { options.insert(.appAccountToken(token)) }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    let purchased = PlanTier.from(productID: txn.productID)
                    let previous = activeTier
                    let attributionPreparation = await preparePurchaseAttribution(
                        transaction: txn,
                        tier: purchased,
                        source: "three_tier_paywall"
                    )
                    if attributionPreparation.permitsStoreKitFinish {
                        await txn.finish()
                    }
                    schedulePurchaseAttributionDelivery(
                        transactionID: String(txn.id),
                        preparation: attributionPreparation
                    )
                    await refreshFromStoreKit()
                    await syncPurchaseToBackend(txn)
                    await AnalyticsService.shared.log(
                        purchased > previous ? .upgrade : (purchased < previous ? .downgrade : .purchase),
                        tier: purchased.rawValue, source: "paywall")
                    lastPurchaseSucceeded = true
                    return true
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
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refreshFromStoreKit()
        #endif
    }

    private func syncPurchaseToBackend(_ txn: StoreKit.Transaction) async {
        #if canImport(Supabase)
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
                guard ProductID.tierPlans.contains(txn.productID), let self else { continue }
                let attributionPreparation = await self.preparePurchaseAttribution(
                    transaction: txn,
                    tier: PlanTier.from(productID: txn.productID),
                    source: "transaction_listener"
                )
                if attributionPreparation.permitsStoreKitFinish {
                    await txn.finish()
                }
                await self.schedulePurchaseAttributionDelivery(
                    transactionID: String(txn.id),
                    preparation: attributionPreparation
                )
                await self.refreshFromStoreKit()
            }
        }
    }

    private func preparePurchaseAttribution(
        transaction: StoreKit.Transaction,
        tier: PlanTier,
        source: String
    ) async -> PurchaseAttributionPreparationOutcome {
        let outcome = await PurchaseAttributionService.shared.prepareVerifiedSubscriptionPurchase(
            transaction: transaction,
            tier: tier.rawValue,
            source: source
        )
        if case .ineligible(let reason) = outcome {
            #if DEBUG
            print("[AppsFlyer][Tier] Attribution preparation skipped for \(transaction.id): \(reason)")
            #endif
        } else if case .deferred(let reason) = outcome {
            #if DEBUG
            print("[AppsFlyer][Tier] Attribution preparation deferred for \(transaction.id): \(reason)")
            #endif
        }
        return outcome
    }

    private func schedulePurchaseAttributionDelivery(
        transactionID: String,
        preparation: PurchaseAttributionPreparationOutcome
    ) {
        guard preparation == .prepared else { return }
        Task {
            let outcome = await PurchaseAttributionService.shared
                .deliverPreparedPurchase(transactionID: transactionID)
            if case .deferred(let reason) = outcome {
                #if DEBUG
                print("[AppsFlyer][Tier] Attribution delivery deferred for \(transactionID): \(reason)")
                #endif
            }
        }
    }

    func clearForSignedOutUser() {
        activeTier = .free
    }
}
