//
//  Entitlements.swift
//  SacredBillTracker
//
//  What the user is allowed to do based on their subscription state.
//  Keep this file small and declarative — it's the source of truth
//  every view consults via `@EnvironmentObject SubscriptionManager`.
//

import Foundation

/// Canonical Sacred Bill Tracker account identifier.
///
/// Supabase Auth already issues this internal UUID and all user-owned rows
/// should bind to it. Provider IDs, emails, Apple relay addresses, and Google
/// subjects may link to this UUID, but must never replace it as row ownership.
typealias SacredBillTrackerUserID = UUID

/// Discrete subscription tiers. `.free` is the default / fallback.
enum SubscriptionTier: String, Codable, Equatable {
    case free
    case proMonthly
    case proYearly

    var isPro: Bool {
        self == .proMonthly || self == .proYearly
    }

    var displayName: String {
        switch self {
        case .free:        return "Free"
        case .proMonthly:  return "Pro (Monthly)"
        case .proYearly:   return "Pro (Yearly)"
        }
    }
}

/// Caps that apply to the free tier. Tweak these in one place.
enum FreeTierLimits {
    /// Max number of bills a free user can track. Soft-enforced: existing
    /// bills stay visible, but new bills past this limit show the paywall.
    static let maxBills = 5

    /// Free users can add household bills but not business bills.
    static let allowBusinessBills = false

    /// Free users don't get the Reports tab content.
    static let allowReports = false

    /// Free users don't get cloud sync (stays local-only).
    static let allowCloudSync = false

    /// Managed Financial Profiles are Premium-only in v1.0.10.
    static let allowManagedProfiles = false
}

enum PremiumMessaging {
    static let managedProfiles = "Managed Financial Profiles is a Premium feature. Manage your personal, family, business, and rental property finances in one place."
}

/// A small, purely-advisory description of what's gated. Used by
/// `ProLockCard` and the paywall's "Why upgrade" section.
struct ProFeature: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String

    static let all: [ProFeature] = [
        .init(id: "unlimited",
              icon: "infinity",
              title: "Unlimited bills",
              subtitle: "Free is capped at \(FreeTierLimits.maxBills). Pro removes the limit."),
        .init(id: "business",
              icon: "briefcase.fill",
              title: "Business tracking",
              subtitle: "Separate books for side-hustles, LLCs, and contractors."),
        .init(id: "profiles",
              icon: "person.3.sequence.fill",
              title: "Managed Financial Profiles",
              subtitle: "Manage personal, family, business, and rental property finances in one subscription."),
        .init(id: "reports",
              icon: "chart.pie.fill",
              title: "Reports & insights",
              subtitle: "Cash-flow forecasts, category breakdowns, risk alerts."),
        .init(id: "sync",
              icon: "icloud.fill",
              title: "Cloud sync",
              subtitle: "Your bills on every device — iPhone, iPad, and beyond."),
        .init(id: "reminders",
              icon: "sparkles",
              title: "Smart reminders",
              subtitle: "Multi-day lead times and per-bill nudges you can tune."),
        .init(id: "priority",
              icon: "star.fill",
              title: "Priority support",
              subtitle: "Write us — we'll actually write back.")
    ]
}

// MARK: - Verified, account-scoped offline entitlement policy

/// Only the authenticated production verifier creates this envelope. Times are
/// Unix seconds from that verifier, never app-launch or cache-read timestamps.
struct SBTVerifiedEntitlementSnapshot: Codable, Equatable {
    struct Entitlement: Codable, Equatable {
        var product_id: String
        var original_transaction_id: String
        var transaction_id: String
        var status: String
        var expires_at: Double
        var revoked: Bool
        var source_platform: String? = nil
        var binding_state: String? = nil
    }
    var version: Int
    var account_id: UUID
    var bundle_id: String
    var environment: String
    var verified_at: Double
    var entitlements: [Entitlement]
    struct Reward: Codable, Equatable { var tier: String; var expires_at: Double }
    var rewards: [Reward]? = nil
    struct AccountSource: Codable, Equatable {
        var source_platform: String
        var source_id: UUID
        var product_id: String
        var tier: String
        var status: String
        var expires_at: Double
        var revoked: Bool
        var environment: String
        var verified_at: Double
        var binding_state: String
    }
    var account_sources: [AccountSource]? = nil
    var ownership_resolution: String? = nil
}

enum SBTOfflineEntitlementPolicy {
    // This release cannot enable Google access through a server response/cache.
    static let googleCrossPlatformEnabled = false
    static let grace: TimeInterval = 72 * 60 * 60
    static let statuses: Set<String> = ["active", "trial", "grace", "expired", "revoked", "on_hold"]

    static func isWellFormed(_ snapshot: SBTVerifiedEntitlementSnapshot, owner: UUID, now: Date, environment: String = "production") -> Bool {
        let timestamp = now.timeIntervalSince1970
        guard timestamp.isFinite, snapshot.version == 1, snapshot.account_id == owner,
              snapshot.bundle_id == "com.sacredbilltracker.app", snapshot.environment == environment, ["production", "sandbox"].contains(environment),
              snapshot.verified_at.isFinite, snapshot.verified_at > 0, snapshot.verified_at <= timestamp,
              snapshot.entitlements.count <= 32,
              (snapshot.ownership_resolution == nil || ["securely_bound", "legacy_ownership_unresolved", "unbound"].contains(snapshot.ownership_resolution!)),
              (snapshot.rewards ?? []).allSatisfy({ ["essential", "business", "unlimited"].contains($0.tier) &&
                  $0.expires_at.isFinite && $0.expires_at > 0 }) else { return false }
        var sources = Set<UUID>()
        guard (snapshot.account_sources ?? []).count <= 32,
              (snapshot.account_sources ?? []).allSatisfy({ item in
                  item.source_platform == "android_play" && item.environment == environment &&
                  !item.product_id.isEmpty && item.product_id.utf8.count <= 256 &&
                  ["essential", "business", "unlimited"].contains(item.tier) && statuses.contains(item.status) &&
                  item.binding_state == "reviewed" && item.expires_at.isFinite && item.expires_at > 0 &&
                  item.verified_at.isFinite && item.verified_at >= snapshot.verified_at && item.verified_at <= timestamp &&
                  sources.insert(item.source_id).inserted
              }) else { return false }
        var originals = Set<String>()
        return snapshot.entitlements.allSatisfy { item in
            (item.source_platform == nil || item.source_platform == "ios_appstore") &&
            (item.binding_state == nil || ["reviewed", "signed_account_token"].contains(item.binding_state!)) &&
            ProductID.allKnown.contains(item.product_id) &&
            ReceiptJarReleaseGate.allowsEntitlement(productID: item.product_id) &&
            statuses.contains(item.status) &&
            item.expires_at.isFinite && item.expires_at > 0 &&
            isTransactionID(item.original_transaction_id) && isTransactionID(item.transaction_id) &&
            originals.insert(item.original_transaction_id).inserted
        }
    }

    static func rewardTier(_ snapshot: SBTVerifiedEntitlementSnapshot?, owner: UUID?, now: Date, environment: String) -> PlanTier {
        guard let owner, let snapshot, isWellFormed(snapshot, owner: owner, now: now, environment: environment),
              now.timeIntervalSince1970 - snapshot.verified_at <= grace else { return .free }
        return (snapshot.rewards ?? []).filter { $0.expires_at > now.timeIntervalSince1970 }
            .map { PlanTier.from(backend: $0.tier) }.max() ?? .free
    }

    static func accountTier(_ snapshot: SBTVerifiedEntitlementSnapshot?, owner: UUID?, now: Date, environment: String, googleEnabled: Bool = googleCrossPlatformEnabled) -> PlanTier {
        guard googleEnabled, let owner, let snapshot, isWellFormed(snapshot, owner: owner, now: now, environment: environment),
              now.timeIntervalSince1970 - snapshot.verified_at <= grace else { return .free }
        return (snapshot.account_sources ?? []).filter {
            ["active", "trial", "grace"].contains($0.status) && !$0.revoked && $0.expires_at > now.timeIntervalSince1970
        }.map { PlanTier.from(backend: $0.tier) }.max() ?? .free
    }

    private static func isTransactionID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// Inclusive at exactly 72h, matching Android's 0..OFFLINE_GRACE_MILLIS.
    /// Verified expiry (including a verified billing grace end) is a stricter cap.
    static func products(_ snapshot: SBTVerifiedEntitlementSnapshot?, owner: UUID?, now: Date, environment: String = "production") -> Set<String> {
        guard let owner, let snapshot, isWellFormed(snapshot, owner: owner, now: now, environment: environment),
              now.timeIntervalSince1970 - snapshot.verified_at <= grace else { return [] }
        return Set(snapshot.entitlements.filter {
            ["active", "trial", "grace"].contains($0.status) && !$0.revoked && $0.expires_at > now.timeIntervalSince1970
        }.map(\.product_id))
    }
}

// MARK: - Unified account identity and cross-platform entitlements

enum SBTAuthProvider: String, Codable, CaseIterable, Equatable {
    case apple
    case google
    case emailPassword = "email_password"
}

struct SBTLinkedIdentity: Codable, Equatable, Identifiable {
    var id: String { "\(provider.rawValue):\(providerSubject)" }
    var accountID: SacredBillTrackerUserID
    var provider: SBTAuthProvider
    var providerSubject: String
    var verifiedEmail: String?
    var isPrivateRelayEmail: Bool
    var linkedAt: Date
}

enum SBTAccountLinkDecision: Equatable {
    case alreadyLinked(SacredBillTrackerUserID)
    case linkToSignedInAccount(SacredBillTrackerUserID)
    case requireExplicitReauthentication(reason: String)
    case createNewAccount
    case deny(reason: String)
}

enum SBTAccountLinkingPolicy {
    static func decision(
        signedInAccountID: SacredBillTrackerUserID?,
        incomingProvider: SBTAuthProvider,
        incomingProviderSubject: String,
        incomingVerifiedEmail: String?,
        existingLinks: [SBTLinkedIdentity]
    ) -> SBTAccountLinkDecision {
        let normalizedSubject = incomingProviderSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSubject.isEmpty else {
            return .deny(reason: "Provider subject is required before linking an identity.")
        }

        if let exact = existingLinks.first(where: {
            $0.provider == incomingProvider && $0.providerSubject == normalizedSubject
        }) {
            return .alreadyLinked(exact.accountID)
        }

        guard let signedInAccountID else {
            return .createNewAccount
        }

        if let email = incomingVerifiedEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !email.isEmpty,
           existingLinks.contains(where: { link in
               link.accountID != signedInAccountID &&
               link.verifiedEmail?.lowercased() == email
           }) {
            return .requireExplicitReauthentication(
                reason: "A matching email alone is not enough to merge Sacred Bill Tracker accounts."
            )
        }

        return .linkToSignedInAccount(signedInAccountID)
    }
}

enum SBTBillingProvider: String, Codable, CaseIterable, Equatable {
    case appleAppStore = "ios_appstore"
    case googlePlay = "android_play"
}

enum SBTAccountEntitlementKind: Codable, Equatable {
    case plan(PlanTier)
    case receiptJarLifetime

    var productIDs: Set<String> {
        switch self {
        case .plan(.essential):
            return [ProductID.essentialMonthly]
        case .plan(.business):
            return [ProductID.businessMonthly]
        case .plan(.unlimited):
            return [ProductID.unlimitedMonthly]
        case .plan(.free):
            return []
        case .receiptJarLifetime:
            return [ProductID.receiptJarLifetime]
        }
    }
}

struct SBTAccountEntitlement: Codable, Equatable, Identifiable {
    var id: String { "\(provider.rawValue):\(originalTransactionID)" }
    var accountID: SacredBillTrackerUserID
    var provider: SBTBillingProvider
    var productID: String
    var originalTransactionID: String
    var latestTransactionID: String
    var kind: SBTAccountEntitlementKind
    var status: String
    var expiresAt: Date?
    var renewalState: String?
    var lastVerifiedAt: Date
    var revokedAt: Date?
}

enum SBTCrossPlatformEntitlementPolicy {
    static let activeStatuses: Set<String> = ["active", "trial", "grace"]

    static func activeProducts(
        for accountID: SacredBillTrackerUserID,
        entitlements: [SBTAccountEntitlement],
        now: Date
    ) -> Set<String> {
        entitlements.reduce(into: Set<String>()) { products, item in
            guard item.accountID == accountID,
                  item.revokedAt == nil,
                  activeStatuses.contains(item.status) else { return }
            if let expiry = item.expiresAt, expiry <= now { return }
            products.formUnion(item.kind.productIDs.intersection([item.productID]))
        }
    }

    static func planTier(
        for accountID: SacredBillTrackerUserID,
        entitlements: [SBTAccountEntitlement],
        now: Date
    ) -> PlanTier {
        entitlements.compactMap { item -> PlanTier? in
            guard item.accountID == accountID,
                  item.revokedAt == nil,
                  activeStatuses.contains(item.status) else { return nil }
            if let expiry = item.expiresAt, expiry <= now { return nil }
            if case let .plan(tier) = item.kind { return tier }
            return nil
        }.max() ?? .free
    }

    static func hasReceiptJarLifetime(
        for accountID: SacredBillTrackerUserID,
        entitlements: [SBTAccountEntitlement],
        now: Date
    ) -> Bool {
        activeProducts(for: accountID, entitlements: entitlements, now: now)
            .contains(ProductID.receiptJarLifetime)
    }
}

// MARK: - Backend verification contract model

enum SBTStoreEntitlementStatus: String, Codable, Equatable {
    case active
    case trial
    case grace
    case billingRetry = "billing_retry"
    case accountHold = "account_hold"
    case cancelledActive = "cancelled_active"
    case expired
    case revoked
    case refunded
    case quarantined

    var grantsAccessThroughExpiry: Bool {
        switch self {
        case .active, .trial, .grace, .cancelledActive:
            return true
        case .billingRetry, .accountHold, .expired, .revoked, .refunded, .quarantined:
            return false
        }
    }
}

struct SBTVerifiedStoreEvent: Codable, Equatable {
    var eventID: String
    var accountID: SacredBillTrackerUserID
    var provider: SBTBillingProvider
    var providerOriginalID: String
    var providerLatestID: String
    var productID: String
    var kind: SBTAccountEntitlementKind
    var status: SBTStoreEntitlementStatus
    var eventTime: Date
    var verifiedAt: Date
    var expiresAt: Date?
    var revokedAt: Date?
    var environment: String
    var isSignatureVerified: Bool
}

struct SBTStoredPurchase: Codable, Equatable, Identifiable {
    var id: String { "\(provider.rawValue):\(environment):\(providerOriginalID)" }
    var accountID: SacredBillTrackerUserID
    var provider: SBTBillingProvider
    var environment: String
    var providerOriginalID: String
    var providerLatestID: String
    var productID: String
    var kind: SBTAccountEntitlementKind
    var status: SBTStoreEntitlementStatus
    var eventTime: Date
    var lastVerifiedAt: Date
    var expiresAt: Date?
    var revokedAt: Date?
    var ownershipState: String
}

enum SBTStoreEventApplyResult: Equatable {
    case applied
    case duplicate
    case ignoredOutOfOrder
    case failedVerification
    case ownershipConflict(existingOwner: SacredBillTrackerUserID)
}

struct SBTEntitlementResolution: Equatable {
    var planTier: PlanTier
    var receiptJarLifetime: Bool
    var sourcePurchaseIDs: Set<String>
    var hasConflict: Bool
}

/// Pure, backend-equivalent entitlement reducer. The deployed edge function
/// must do the external cryptographic/provider verification first, then apply
/// these ownership, idempotency, lifecycle, and precedence rules.
struct SBTAuthoritativeEntitlementReducer {
    private(set) var purchases: [String: SBTStoredPurchase] = [:]
    private(set) var processedEventIDs: Set<String> = []
    private(set) var conflictedPurchaseIDs: Set<String> = []

    mutating func apply(_ event: SBTVerifiedStoreEvent) -> SBTStoreEventApplyResult {
        guard event.isSignatureVerified else { return .failedVerification }
        let eventKey = "\(event.provider.rawValue):\(event.environment):\(event.eventID)"
        guard processedEventIDs.insert(eventKey).inserted else { return .duplicate }

        let purchaseKey = "\(event.provider.rawValue):\(event.environment):\(event.providerOriginalID)"
        if let existing = purchases[purchaseKey] {
            guard existing.accountID == event.accountID else {
                conflictedPurchaseIDs.insert(purchaseKey)
                return .ownershipConflict(existingOwner: existing.accountID)
            }
            guard event.eventTime >= existing.eventTime else { return .ignoredOutOfOrder }
        }

        purchases[purchaseKey] = SBTStoredPurchase(
            accountID: event.accountID,
            provider: event.provider,
            environment: event.environment,
            providerOriginalID: event.providerOriginalID,
            providerLatestID: event.providerLatestID,
            productID: event.productID,
            kind: event.kind,
            status: event.status,
            eventTime: event.eventTime,
            lastVerifiedAt: event.verifiedAt,
            expiresAt: event.expiresAt,
            revokedAt: event.revokedAt,
            ownershipState: conflictedPurchaseIDs.contains(purchaseKey) ? "conflict" : "bound"
        )
        return .applied
    }

    func resolve(accountID: SacredBillTrackerUserID, now: Date) -> SBTEntitlementResolution {
        let accountPurchases = purchases.filter { key, purchase in
            purchase.accountID == accountID &&
            !conflictedPurchaseIDs.contains(key) &&
            purchase.revokedAt == nil &&
            purchase.status.grantsAccessThroughExpiry &&
            (purchase.expiresAt == nil || purchase.expiresAt! > now)
        }

        var tier: PlanTier = .free
        var receiptJar = false
        var sources = Set<String>()

        for (key, purchase) in accountPurchases {
            switch purchase.kind {
            case .plan(let candidate):
                if candidate > tier { tier = candidate }
                sources.insert(key)
            case .receiptJarLifetime:
                receiptJar = true
                sources.insert(key)
            }
        }

        return SBTEntitlementResolution(
            planTier: tier,
            receiptJarLifetime: receiptJar,
            sourcePurchaseIDs: sources,
            hasConflict: !conflictedPurchaseIDs.isEmpty
        )
    }
}

import Combine
import Security

protocol SBTEntitlementCacheStorage {
    func read(owner: UUID) -> Data?
    func write(_ data: Data, owner: UUID) -> Bool
    func remove(owner: UUID)
}

/// Device-only Keychain, not UserDefaults or an iCloud-synchronized claim.
/// Only verified envelopes are written; storage failure never permits a grace grant.
struct SBTKeychainEntitlementStorage: SBTEntitlementCacheStorage {
    private func query(_ owner: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: SBTStagingRoute.cacheService,
         kSecAttrAccount as String: owner.uuidString.lowercased(),
         kSecAttrSynchronizable as String: false]
    }
    func read(owner: UUID) -> Data? {
        var q = query(owner)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    func write(_ data: Data, owner: UUID) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(owner) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query(owner).merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
    func remove(owner: UUID) { SecItemDelete(query(owner) as CFDictionary) }
}

/// Shared policy/cache feeding BOTH existing StoreKit managers. It does not add
/// another tier system and never touches bills, income, profiles, or notifications.
@MainActor
final class SBTVerifiedEntitlementStore: ObservableObject {
    #if SBT_STAGING_ACCEPTANCE
    static let shared = SBTVerifiedEntitlementStore(environment: "sandbox")
    #else
    static let shared = SBTVerifiedEntitlementStore(environment: nil)
    #endif
    @Published private(set) var accountTier: PlanTier = .free
    @Published private(set) var rewardTier: PlanTier = .free
    @Published private(set) var productIDs: Set<String> = []
    @Published private(set) var verificationMessage: String?
    private(set) var owner: UUID?
    private(set) var revision = 0
    private(set) var environment: String?
    private var refreshTask: Task<Void, Never>?
    private var refreshOwner: UUID?
    private var refreshID: UUID?
    private(set) var snapshot: SBTVerifiedEntitlementSnapshot?
    private let storage: SBTEntitlementCacheStorage
    private let clock: () -> Date
    private let schedulesExpiry: Bool
    private var expiryTask: Task<Void, Never>?

    init(storage: SBTEntitlementCacheStorage = SBTKeychainEntitlementStorage(),
         clock: @escaping () -> Date = Date.init, schedulesExpiry: Bool = true, environment: String? = "production") {
        self.storage = storage
        self.clock = clock
        self.schedulesExpiry = schedulesExpiry
        self.environment = environment
    }

    func changeAccount(_ newOwner: UUID?) {
        guard owner != newOwner else { reevaluate(); return }
        revision += 1
        refreshTask?.cancel()
        refreshTask = nil
        expiryTask?.cancel()
        owner = newOwner
        snapshot = nil
        productIDs = []
        rewardTier = .free
        accountTier = .free
        verificationMessage = nil
        if let newOwner, let data = storage.read(owner: newOwner) {
            if let decoded = try? JSONDecoder().decode(SBTVerifiedEntitlementSnapshot.self, from: data),
               SBTOfflineEntitlementPolicy.isWellFormed(decoded, owner: newOwner, now: clock(), environment: decoded.environment) {
                snapshot = decoded
            } else { storage.remove(owner: newOwner) }
        }
        reevaluate()
    }

    func signOut() {
        if let owner { storage.remove(owner: owner) }
        revision += 1 // Also invalidate pending requests when already anonymous.
        refreshTask?.cancel()
        refreshTask = nil
        owner = nil
        snapshot = nil
        productIDs = []
        rewardTier = .free
        accountTier = .free
        verificationMessage = nil
        expiryTask?.cancel()
    }

    /// Called only after the authenticated verifier's successful HTTP response.
    /// Its timestamp must be fresh; a successful local decode is not verification.
    @discardableResult
    func acceptVerified(_ value: SBTVerifiedEntitlementSnapshot, expectedOwner: UUID, expectedRevision: Int) -> Bool {
        guard owner == expectedOwner, revision == expectedRevision else { return false }
        let now = clock()
        guard SBTOfflineEntitlementPolicy.isWellFormed(value, owner: expectedOwner, now: now, environment: environment ?? ""),
              now.timeIntervalSince1970 - value.verified_at <= 300,
              value.verified_at >= (snapshot?.verified_at ?? 0),
              let encoded = try? JSONEncoder().encode(value), storage.write(encoded, owner: expectedOwner) else {
            rejectVerification(expectedOwner: expectedOwner, expectedRevision: expectedRevision)
            return false
        }
        snapshot = value
        verificationMessage = value.ownership_resolution == "legacy_ownership_unresolved"
            ? "Your purchase needs account verification. Contact support to recover access. Your bill data is unchanged." : nil
        reevaluate()
        return true
    }

    /// Definitive auth/identity/contract rejection cannot fall back to paid cache.
    func rejectVerification(expectedOwner: UUID, expectedRevision: Int) {
        guard owner == expectedOwner, revision == expectedRevision else { return }
        storage.remove(owner: expectedOwner)
        snapshot = nil
        verificationMessage = "Sign in to the purchasing account and restore purchases to verify access."
        reevaluate()
    }

    /// A transport failure never advances verified_at or rewrites the envelope.
    func verificationUnavailable(expectedOwner: UUID, expectedRevision: Int) {
        guard owner == expectedOwner, revision == expectedRevision else { return }
        verificationMessage = "Purchase verification is unavailable. Connect and restore purchases to verify access."
        reevaluate()
    }

    /// Verified StoreKit revocation/upgrade immediately removes that lineage,
    /// including from persistent storage; an outage cannot resurrect it.
    func invalidate(originalID: String, expectedOwner: UUID) {
        guard owner == expectedOwner, var value = snapshot else { return }
        for index in value.entitlements.indices where value.entitlements[index].original_transaction_id == originalID {
            value.entitlements[index].revoked = true
            value.entitlements[index].status = "revoked"
        }
        snapshot = value
        if let data = try? JSONEncoder().encode(value), !storage.write(data, owner: expectedOwner) {
            storage.remove(owner: expectedOwner)
        }
        reevaluate()
    }

    /// Called only with the environment from a verified StoreKit AppTransaction.
    func setVerifiedAppEnvironment(_ value: String) {
        #if SBT_STAGING_ACCEPTANCE
        guard value == "sandbox" else { return }
        #endif
        guard ["production", "sandbox"].contains(value), value != environment else { return }
        revision += 1
        environment = value
        reevaluate()
    }

    func reevaluate() {
        accountTier = SBTOfflineEntitlementPolicy.accountTier(snapshot, owner: owner, now: clock(), environment: environment ?? "")
        rewardTier = SBTOfflineEntitlementPolicy.rewardTier(snapshot, owner: owner, now: clock(), environment: environment ?? "")
        productIDs = SBTOfflineEntitlementPolicy.products(snapshot, owner: owner, now: clock(), environment: environment ?? "")
        expiryTask?.cancel()
        guard schedulesExpiry, (!productIDs.isEmpty || rewardTier != .free || accountTier != .free), let snapshot else { return }
        let expiries = snapshot.entitlements.filter { productIDs.contains($0.product_id) && !$0.revoked &&
            ["active", "trial", "grace"].contains($0.status) && $0.expires_at > clock().timeIntervalSince1970 }.map(\.expires_at)
            + (snapshot.rewards ?? []).filter { $0.expires_at > clock().timeIntervalSince1970 }.map(\.expires_at)
        let sourceExpiries = (snapshot.account_sources ?? []).filter {
            !$0.revoked && ["active", "trial", "grace"].contains($0.status) && $0.expires_at > clock().timeIntervalSince1970
        }.map(\.expires_at)
        let deadline = min(snapshot.verified_at + SBTOfflineEntitlementPolicy.grace, (expiries + sourceExpiries).min() ?? .infinity)
        let seconds = max(0.01, deadline - clock().timeIntervalSince1970 + 0.01)
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(min(seconds, SBTOfflineEntitlementPolicy.grace + 1) * 1_000_000_000)) }
            catch { return }
            self?.reevaluate()
        }
    }
}

import StoreKit
#if canImport(Supabase)
import Supabase
#endif

extension SBTVerifiedEntitlementStore {
    static func serverEnvironment(for environment: AppStore.Environment) -> String? {
        switch environment {
        case .production: return "production"
        case .sandbox: return "sandbox"
        default: return nil
        }
    }

    func invalidateVerifiedStoreKitTransaction(_ transaction: StoreKit.Transaction) {
        guard let owner,
              (transaction.appAccountToken == owner || (transaction.appAccountToken == nil &&
               snapshot?.account_id == owner && snapshot?.entitlements.contains(where: {
                   $0.original_transaction_id == String(transaction.originalID)
               }) == true)),
              transaction.revocationDate != nil || transaction.isUpgraded else { return }
        guard (environment == "production" && transaction.environment == .production) ||
              (environment == "sandbox" && transaction.environment == .sandbox) else { return }
        invalidate(originalID: String(transaction.originalID), expectedOwner: owner)
    }

    /// No AppStore.sync at launch: this reads signed local StoreKit evidence only
    /// to discover candidate IDs/negative state. Only the server response grants.
    func refreshFromApple() async {
        let account = AuthService.shared.offlineEntitlementAccountID
        changeAccount(account)
        guard let account else { return }
        if let running = refreshTask, refreshOwner == account {
            await running.value
            return
        }
        refreshOwner = account
        let identifier = UUID()
        refreshID = identifier
        let running = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performAppleRefresh(account: account)
        }
        refreshTask = running
        await running.value
        if refreshID == identifier { refreshTask = nil }
    }

    private func performAppleRefresh(account: UUID) async {
        let initialRevision = revision
        do {
            let app = try await AppTransaction.shared
            guard case .verified(let transaction) = app else {
                rejectVerification(expectedOwner: account, expectedRevision: initialRevision)
                return
            }
            guard owner == account, revision == initialRevision,
                  AuthService.shared.offlineEntitlementAccountID == account else { return }
            guard transaction.bundleID == "com.sacredbilltracker.app" else {
                rejectVerification(expectedOwner: account, expectedRevision: revision)
                return
            }
            guard let verifiedEnvironment = Self.serverEnvironment(for: transaction.environment) else {
                // Xcode fixtures must never seed a production/sandbox grant.
                rejectVerification(expectedOwner: account, expectedRevision: revision)
                return
            }
            setVerifiedAppEnvironment(verifiedEnvironment)
        } catch {
            verificationUnavailable(expectedOwner: account, expectedRevision: initialRevision)
            return
        }
        let requestRevision = revision
        // Previously verified IDs are discovery hints only; the server must
        // re-fetch them. A temporarily empty StoreKit cache cannot become FREE.
        var originals = Set(snapshot?.environment == environment ? (snapshot?.entitlements.map(\.original_transaction_id) ?? []) : [])
        for product in ProductID.all {
            guard !Task.isCancelled else { return }
            guard let result = await StoreKit.Transaction.latest(for: product),
                  case .verified(let transaction) = result,
                  (transaction.appAccountToken == account || transaction.appAccountToken == nil) else { continue }
            let matchesEnvironment = (environment == "production" && transaction.environment == .production) ||
                                     (environment == "sandbox" && transaction.environment == .sandbox)
            guard matchesEnvironment else { continue }
            guard owner == account, revision == requestRevision else { return }
            let original = String(transaction.originalID)
            originals.insert(original)
            if transaction.revocationDate != nil || transaction.isUpgraded {
                invalidate(originalID: original, expectedOwner: account)
            }
            // Expiry is also enforced continuously against the verified snapshot.
            // An expired local transaction alone cannot invalidate a later server-
            // verified grace period or renewal for the same subscription lineage.
        }
        guard owner == account, revision == requestRevision,
              AuthService.shared.offlineEntitlementAccountID == account else { return }
        #if canImport(Supabase)
        do {
            let response = try await Self.fetchVerifiedSnapshot(functions: SupabaseConfig.client.functions,
                environment: environment ?? "production", originals: originals.sorted())
            guard AuthService.shared.offlineEntitlementAccountID == account else { return }
            _ = acceptVerified(response, expectedOwner: account, expectedRevision: requestRevision)
        } catch let error as FunctionsError {
            switch error {
            case .httpError(let code, _):
                if [400,401,403,404].contains(code) { rejectVerification(expectedOwner: account, expectedRevision: requestRevision) }
                else { verificationUnavailable(expectedOwner: account, expectedRevision: requestRevision) }
            default: verificationUnavailable(expectedOwner: account, expectedRevision: requestRevision)
            }
        } catch is DecodingError {
            rejectVerification(expectedOwner: account, expectedRevision: requestRevision)
        } catch {
            verificationUnavailable(expectedOwner: account, expectedRevision: requestRevision)
        }
        #endif
    }
}

#if canImport(Supabase)
extension SBTVerifiedEntitlementStore {
    /// Shared production wire contract; injected FunctionsClient permits offline
    /// SDK integration tests without using the application's live client.
    static func fetchVerifiedSnapshot(functions: FunctionsClient, environment: String,
                                      originals: [String]) async throws -> SBTVerifiedEntitlementSnapshot {
        struct Request: Encodable {
            let platform = "apple"
            let operation = "entitlement_snapshot"
            let environment: String
            let original_transaction_ids: [String]
        }
        return try await PackageCClientBoundary.dormant {
            try await functions.invoke("verify-store-subscription", options: FunctionInvokeOptions(
            body: Request(environment: environment, original_transaction_ids: originals)))
        }
    }
}
#endif

/// Compile-time dormant integration; existing legacy request remains authoritative.
enum PackageCClientBoundary {
    static func dormant<T>(_ legacy: () async throws -> T) async rethrows -> T { try await legacy() }
}
