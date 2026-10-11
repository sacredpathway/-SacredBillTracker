//
//  SubscriptionManager.swift
//  SacredBillTracker
//
//  StoreKit 2 wrapper. Exposes:
//    - Loaded `Product` objects for the paywall to display.
//    - `currentTier` driven by the user's active entitlements.
//    - `purchase(_:)` + `restorePurchases()` calls.
//    - A long-running transaction listener for renewals / external purchases.
//
//  This is the single source of truth for "is the user Pro?".
//

import Foundation
import Combine
import StoreKit
import SwiftUI
import UIKit

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class SubscriptionManager: ObservableObject {

    // MARK: - Published state

    /// Loaded products, keyed by ID. The paywall reads this to show
    /// localized price strings and call `purchase(_:)`.
    @Published private(set) var products: [String: Product] = [:]

    /// The user's current effective tier. `.free` until a valid
    /// transaction for a Pro product is found.
    @Published private(set) var currentTier: SubscriptionTier = .free

    /// True while `loadProducts()` is in flight. Paywall shows a spinner.
    @Published private(set) var isLoadingProducts: Bool = false

    /// Set when a purchase / restore call fails. Paywall surfaces it.
    @Published var lastError: String?

    /// Set immediately after a successful purchase so the paywall can
    /// dismiss itself with a celebratory toast.
    @Published var lastPurchaseSucceeded: Bool = false

    /// Set of purchased product IDs that are currently entitled. Useful
    /// for debug / settings displays.
    @Published private(set) var purchasedProductIDs: Set<String> = []

    private func attributionDebugLog(_ message: String) {
        #if DEBUG
        print("[AppsFlyer][Subscription] \(message)")
        #endif
    }

    /// v1.0.9 — Sacred Focus+ add-on entitlement. Tracked independently
    /// of the Pro tier: Pro users still need to subscribe to Focus+ for
    /// this to be true.
    @Published private(set) var hasFocusPlus: Bool = false

    /// Sacred AutoTrack Premium (Plaid-powered) entitlement. Independent of
    /// Pro and Focus+. This reflects the StoreKit receipt locally AND is
    /// reconciled against the server's `autotrack_entitlement()` RPC, which
    /// is the authoritative source (it reflects App Store / Play webhook
    /// updates for renewals, cancellations, refunds, and lapses).
    @Published private(set) var hasAutoTrack: Bool = false

    /// Highest 3-tier plan (Essential/Business/Unlimited) the user holds,
    /// derived from StoreKit entitlements in `refreshEntitlements()`.
    @Published private(set) var rawPlanTier: PlanTier = .free

    /// Receipt Jar one-time non-consumable entitlement, separate from
    /// subscription tiers and restored through StoreKit.
    @Published private(set) var hasReceiptJar: Bool = false

    #if DEBUG
    /// QA ONLY — simulate a 3-tier plan for gate testing when local StoreKit
    /// Testing isn't engaging in the simulator. Compiled out of Release builds
    /// entirely (#if DEBUG), so it cannot affect App Store / TestFlight archives.
    /// Set via the Debug section in Settings. nil = no override.
    @Published var debugTierOverride: PlanTier? = nil
    #endif

    #if DEBUG
    /// Debug-only owner allowlist for local QA. Release builds must unlock
    /// Sacred Focus+ only through StoreKit entitlements.
    private static let focusPlusOwnerEmails: Set<String> = [
        "demarquishinton@gmail.com"
    ]
    #endif

    // MARK: - Convenience

    /// Effective tier = max(new 3-tier plan, legacy Pro→Business, legacy
    /// AutoTrack→Unlimited). Single source of truth for feature gating.
    var effectiveTier: PlanTier {
        var t = max(rawPlanTier, SBTVerifiedEntitlementStore.shared.rewardTier, SBTVerifiedEntitlementStore.shared.accountTier)
        if currentTier.isPro { t = max(t, .business) }   // legacy Pro
        if hasAutoTrack      { t = max(t, .unlimited) }  // legacy AutoTrack
        #if DEBUG
        if let o = debugTierOverride { t = max(t, o) }   // QA-only simulation
        #endif
        return t
    }

    // Tier-aware capabilities — gate features on THESE, not on `isPro`.
    var canUnlimitedBills:    Bool { effectiveTier >= .essential }
    var canIncomeTracking:    Bool { effectiveTier >= .essential }
    var canBusinessTracking:  Bool { effectiveTier >= .business  }
    var canBusinessReports:   Bool { effectiveTier >= .business  }
    var canManagedProfiles:   Bool { effectiveTier >= .unlimited }
    var canForecasting:       Bool { effectiveTier >= .unlimited }
    var canAIInsights:        Bool { effectiveTier >= .unlimited }
    var canAdvancedAnalytics: Bool { effectiveTier >= .unlimited }

    /// Back-compat: any paid plan (Business+) counts as "Pro" for legacy call
    /// sites not yet migrated to a specific capability above.
    var isPro: Bool { effectiveTier >= .business }

    var monthlyProduct: Product? { products[ProductID.proMonthly] }
    var yearlyProduct:  Product? { products[ProductID.proYearly]  }

    /// Sacred Focus+ monthly add-on product (loaded from StoreKit).
    var focusPlusProduct: Product? { products[ProductID.focusPlusMonthly] }

    /// Sacred AutoTrack Premium products (loaded from StoreKit).
    var autoTrackMonthlyProduct: Product? { products[ProductID.autoTrackMonthly] }
    var autoTrackYearlyProduct:  Product? { products[ProductID.autoTrackYearly]  }

    /// Receipt Jar one-time non-consumable product (loaded from StoreKit).
    var receiptJarProduct: Product? {
        ReceiptJarReleaseGate.isEnabled ? products[ProductID.receiptJarLifetime] : nil
    }

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?

    // MARK: - Init

    private var entitlementObservation: AnyCancellable?
    private var accountObservation: AnyCancellable?
    private var rewardObservation: AnyCancellable?
    init() {
        accountObservation = SBTVerifiedEntitlementStore.shared.$accountTier.sink { [weak self] tier in
            guard let self else { return }
            self.hasAutoTrack = tier >= .unlimited || !self.purchasedProductIDs.isDisjoint(with: ProductID.autoTrack) || self.rawPlanTier >= .unlimited
            self.objectWillChange.send()
        }
        rewardObservation = SBTVerifiedEntitlementStore.shared.$rewardTier.sink { [weak self] _ in self?.objectWillChange.send() }
        entitlementObservation = SBTVerifiedEntitlementStore.shared.$productIDs.sink { [weak self] ids in
            self?.applyVerifiedProducts(ids)
        }
    }

    // Note: no `deinit` cancel — under Swift 6 strict concurrency, reading
    // a @MainActor-isolated stored property from a nonisolated `deinit` is
    // a compile error. SubscriptionManager is an @StateObject on the App,
    // so it lives for the whole app lifetime; the listener naturally exits
    // via the `[weak self]` guard if the instance ever deallocates.

    // MARK: - Products

    /// Called only from paywall/subscription surfaces or explicit upgrade
    /// actions. Keeping StoreKit lazy prevents the dashboard from showing
    /// Apple's account prompt during normal app launch.
    func prepareForPaywall() async {
        startTransactionListenerIfNeeded()
        await loadProducts()
        await refreshEntitlements()
    }

    /// Pull the current product catalog from StoreKit. Safe to call
    /// multiple times — the paywall calls this on appear to recover
    /// from transient network errors.
    func loadProducts() async {
        startTransactionListenerIfNeeded()
        guard products.isEmpty, !isLoadingProducts else { return }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: ProductID.all)
            var map: [String: Product] = [:]
            for product in fetched { map[product.id] = product }
            self.products = map

            if map.isEmpty {
                // Most common cause in development: no `.storekit` file is
                // selected in the run scheme and products aren't live on ASC.
                lastError = "Couldn't load subscriptions. Check your connection and try again."
            }
        } catch {
            lastError = "Couldn't load subscriptions: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchasing

    /// Attempt to purchase a product. Returns `true` if the purchase
    /// completed and entitlement was granted, `false` otherwise
    /// (user cancelled, pending parental approval, etc.).
    @discardableResult
    func purchase(_ product: Product, appAccountToken: UUID? = nil) async -> Bool {
        startTransactionListenerIfNeeded()
        lastError = nil
        do {
            // For AutoTrack we bind the Apple transaction to the Supabase
            // user id via appAccountToken so server notifications
            // (renewals/cancels/refunds) attribute to the right account.
            let authenticatedID = await AuthService.shared.verifiedPurchaseAccountID()
            // An explicit caller token must refer to this live authenticated session.
            if let requested = appAccountToken, requested != authenticatedID {
                lastError = "Sign in to the purchasing Sacred Bill Tracker account and try again."
                return false
            }
            var options: Set<Product.PurchaseOption> = []
            if let token = authenticatedID {
                options.insert(.appAccountToken(token))
            }
            let result = try await product.purchase(options: options)

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                // AutoTrack: verify server-side immediately so the backend
                // entitlement (authoritative) is seeded right after purchase.
                if ProductID.autoTrack.contains(product.id) {
                    await verifyAutoTrackOnBackend(transaction)
                    await refreshAutoTrackEntitlementFromBackend()
                }
                lastPurchaseSucceeded = true
                await recordPurchaseAttribution(
                    transaction: transaction,
                    product: product,
                    source: "legacy_paywall"
                )

                // Attribution: TikTok — fired ONLY here, inside the verified
                // transaction path (immediately after `checkVerified`). Never
                // from a paywall view or a button tap.
                //
                // `StartTrial` when the verified transaction applied an
                // introductory (free-trial) offer, otherwise `Subscribe`.
                // Renewals are deliberately NOT reported: they arrive via
                // `Transaction.updates` and reporting them would over-count.
                // Entitlement logic below is untouched — this block only reads.
                #if canImport(TikTokBusinessSDK)
                let usedIntroOffer: Bool = {
                    if #available(iOS 17.2, *) {
                        return transaction.offer?.type == .introductory
                    } else {
                        return transaction.offerType == .introductory
                    }
                }()
                let ttCurrency = product.priceFormatStyle.currencyCode
                attributionDebugLog("Verified purchase; TikTok event = \(usedIntroOffer ? "StartTrial" : "Subscribe")")
                if usedIntroOffer {
                    TikTokEventsManager.shared.logStartTrial(
                        productID: product.id,
                        value: product.price,
                        currency: ttCurrency
                    )
                } else {
                    TikTokEventsManager.shared.logSubscribe(
                        productID: product.id,
                        value: product.price,
                        currency: ttCurrency
                    )
                }
                #endif

                return purchasedProductIDs.contains(product.id)

            case .userCancelled:
                return false

            case .pending:
                // Ask-to-buy / SCA etc. Will arrive later via listener.
                lastError = "Your purchase is pending approval. We'll unlock Pro as soon as it clears."
                return false

            @unknown default:
                return false
            }
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Re-check all current entitlements. Called from the paywall's
    /// "Restore Purchases" button.
    func restorePurchases() async {
        startTransactionListenerIfNeeded()
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            // Reconcile AutoTrack against the server (authoritative) too, so
            // Restore re-grants AutoTrack from server-verified state.
            await refreshAutoTrackEntitlementFromBackend()
            if purchasedProductIDs.isEmpty && SBTVerifiedEntitlementStore.shared.rewardTier == .free && SBTVerifiedEntitlementStore.shared.accountTier == .free {
                lastError = SBTVerifiedEntitlementStore.shared.verificationMessage ?? "No active subscription was found on this Apple ID."
            }
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements

    /// Walks `Transaction.currentEntitlements` and derives the current tier.
    /// Yearly wins over Monthly if both somehow present.
    func refreshEntitlements() async {
        startTransactionListenerIfNeeded()
        await SBTVerifiedEntitlementStore.shared.refreshFromApple()
        applyVerifiedProducts(SBTVerifiedEntitlementStore.shared.productIDs)
        if purchasedProductIDs.isEmpty { lastError = SBTVerifiedEntitlementStore.shared.verificationMessage }
    }

    private func applyVerifiedProducts(_ activeIDs: Set<String>) {
        purchasedProductIDs = activeIDs
        currentTier = activeIDs.contains(ProductID.proYearly) ? .proYearly :
            activeIDs.contains(ProductID.proMonthly) ? .proMonthly : .free
        rawPlanTier = activeIDs.map(PlanTier.from(productID:)).max() ?? .free
        hasFocusPlus = activeIDs.contains(ProductID.focusPlusMonthly)
        hasAutoTrack = !activeIDs.isDisjoint(with: ProductID.autoTrack) || rawPlanTier >= .unlimited || SBTVerifiedEntitlementStore.shared.accountTier >= .unlimited
        hasReceiptJar = ReceiptJarReleaseGate.isEnabled && activeIDs.contains(ProductID.receiptJarLifetime)
    }

    #if DEBUG
    func applyVerifiedProductsForTesting(_ activeIDs: Set<String>) {
        applyVerifiedProducts(activeIDs)
    }
    #endif

    /// Allow external callers (e.g. auth state changes) to re-evaluate
    /// the owner override without waiting for the next StoreKit
    /// refresh. Sign-in updates `currentUserEmail` after the initial
    /// entitlement pass, so we call this on user change.
    func recheckOwnerOverride() {
        #if DEBUG
        guard let email = AuthService.shared.currentUserEmail else { return }
        if Self.focusPlusOwnerEmails.contains(email.lowercased()) {
            self.hasFocusPlus = true
        }
        #endif
    }

    /// Clear local entitlement presentation state on sign-out without
    /// touching StoreKit. A future paywall/restore action will re-check
    /// Apple's receipt stream intentionally.
    func clearForSignedOutUser() {
        currentTier = .free
        rawPlanTier = .free
        purchasedProductIDs = []
        hasFocusPlus = false
        hasAutoTrack = false
        hasReceiptJar = false
        lastPurchaseSucceeded = false
        lastError = nil
    }

    // MARK: - Transaction listener

    /// Long-running task that delivers transactions arriving outside of a
    /// direct purchase call — renewals, family sharing, interrupted flows.
    private func startTransactionListenerIfNeeded() {
        guard transactionListener == nil else { return }
        transactionListener = listenForTransactions()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result)
            }
        }
    }

    private func handle(transactionResult: VerificationResult<StoreKit.Transaction>) async {
        do {
            let transaction = try checkVerified(transactionResult)
            SBTVerifiedEntitlementStore.shared.invalidateVerifiedStoreKitTransaction(transaction)
            await transaction.finish()
            await refreshEntitlements()
            guard let product = await productForAttribution(id: transaction.productID) else { return }
            await recordPurchaseAttribution(
                transaction: transaction,
                product: product,
                source: "transaction_listener"
            )
        } catch {
            // Un-verifiable transaction — ignore; entitlement won't be granted.
        }
    }

    private func productForAttribution(id: String) async -> Product? {
        if let loaded = products[id] { return loaded }
        return try? await Product.products(for: [id]).first
    }

    private func recordPurchaseAttribution(
        transaction: StoreKit.Transaction,
        product: Product,
        source: String
    ) async {
        let outcome = await PurchaseAttributionService.shared.recordVerifiedSubscriptionPurchase(
            transaction: transaction,
            product: product,
            tier: attributionTier(for: product.id),
            source: source
        )
        if case .deferred(let reason) = outcome {
            attributionDebugLog("Attribution deferred for \(transaction.id): \(reason)")
        }
    }

    private func attributionTier(for productID: String) -> String {
        let planTier = PlanTier.from(productID: productID)
        if planTier != .free { return planTier.rawValue }
        switch productID {
        case ProductID.proMonthly, ProductID.proYearly: return "pro"
        case ProductID.focusPlusMonthly: return "focus_plus"
        case ProductID.autoTrackMonthly, ProductID.autoTrackYearly: return "autotrack"
        case ProductID.receiptJarLifetime: return "receipt_jar"
        default: return "subscription"
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Manage subscriptions

    /// Opens the system "Manage Subscriptions" sheet. Call from Settings.
    func openManageSubscriptions() async {
        // Uses AppStore API — lands the user on the standard Apple UI.
        do {
            guard let scene = UIApplication.shared
                .connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            lastError = "Couldn't open Manage Subscriptions: \(error.localizedDescription)"
        }
    }

    // MARK: - Sacred AutoTrack Premium (server-authoritative)

    /// Purchase an AutoTrack product, binding the Apple transaction to the
    /// signed-in Supabase user via `appAccountToken`, then verifying on the
    /// backend. Returns the resulting (server-reconciled) entitlement.
    @discardableResult
    func purchaseAutoTrack(_ product: Product) async -> Bool {
        let uid = AuthService.shared.currentUserID
        _ = await purchase(product, appAccountToken: uid)
        return hasAutoTrack
    }

    /// POST the verified transaction to the `verify-store-subscription` edge
    /// function so the server records authoritative entitlement state. The
    /// function re-fetches the truth from Apple using the original
    /// transaction id — no signed blob or secret is sent from the client.
    func verifyAutoTrackOnBackend(_ transaction: StoreKit.Transaction) async {
        guard transaction.environment == .production,
              transaction.appAccountToken == (await AuthService.shared.verifiedPurchaseAccountID()) else { return }
        #if canImport(Supabase)
        struct Body: Encodable {
            let platform: String
            let product_id: String
            let original_transaction_id: String
        }
        let body = Body(
            platform: "apple",
            product_id: transaction.productID,
            original_transaction_id: String(transaction.originalID)
        )
        do {
            // verify_jwt=true on the function -> the SDK attaches the
            // signed-in user's access token automatically.
            try await SupabaseConfig.client.functions.invoke(
                "verify-store-subscription",
                options: FunctionInvokeOptions(body: body)
            )
        } catch {
            #if DEBUG
            print("[AutoTrack] verify-store-subscription failed: \(error)")
            #endif
        }
        #endif
    }

    /// Reconcile through the same verified snapshot, never a promote-only RPC.
    func refreshAutoTrackEntitlementFromBackend() async {
        await refreshEntitlements()
    }

}

// MARK: - Price formatting helpers

extension Product {
    /// Formatted price per period, e.g. "$4.99 / month" or "$39.99 / year".
    var pricePerPeriod: String {
        guard let sub = subscription else { return displayPrice }
        let unit: String = {
            switch sub.subscriptionPeriod.unit {
            case .day:   return "day"
            case .week:  return "week"
            case .month: return "month"
            case .year:  return "year"
            @unknown default: return "period"
            }
        }()
        let value = sub.subscriptionPeriod.value
        return value == 1
            ? "\(displayPrice) / \(unit)"
            : "\(displayPrice) / \(value) \(unit)s"
    }

    /// For the yearly product: the implied per-month price, e.g. "$3.33 / mo".
    var impliedMonthlyPrice: String? {
        guard let sub = subscription,
              sub.subscriptionPeriod.unit == .year else { return nil }
        let months = Decimal(12 * sub.subscriptionPeriod.value)
        let monthly = price / months
        // Use priceFormatStyle so the currency matches the storefront
        // the user is purchasing in (USD, EUR, GBP, etc.).
        let formatted = monthly.formatted(priceFormatStyle)
        return "\(formatted) / mo"
    }

    /// Introductory offer label — e.g. "7 days free" or "$0.99 for 1 month".
    var introOfferLabel: String? {
        guard let intro = subscription?.introductoryOffer else { return nil }
        let period = intro.period
        let unit: String = {
            switch period.unit {
            case .day:   return period.value == 1 ? "day"   : "days"
            case .week:  return period.value == 1 ? "week"  : "weeks"
            case .month: return period.value == 1 ? "month" : "months"
            case .year:  return period.value == 1 ? "year"  : "years"
            @unknown default: return "period"
            }
        }()
        switch intro.paymentMode {
        case .freeTrial:
            return "\(period.value) \(unit) free"
        case .payAsYouGo:
            return "\(intro.displayPrice) / \(unit) for \(intro.periodCount) \(unit)"
        case .payUpFront:
            return "\(intro.displayPrice) for \(period.value) \(unit)"
        default:
            return nil
        }
    }
}
