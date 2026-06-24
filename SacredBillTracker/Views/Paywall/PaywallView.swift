//
//  PaywallView.swift
//  SacredBillTracker
//
//  Full-screen Pro upgrade sheet. Shows:
//    - Hero header with brand gradient
//    - Feature list
//    - Yearly vs. Monthly toggle with "SAVE 33%" badge
//    - Big CTA button with intro-offer label ("Start 7-day free trial")
//    - Restore / Terms / Privacy in a footer
//

import SwiftUI
import StoreKit
import SafariServices
import UIKit

#if canImport(Supabase)
import Supabase
#endif

struct PaywallView: View {

    @EnvironmentObject private var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// The product the user currently has selected in the toggle.
    @State private var selectedPlan: Plan = .monthly

    /// True while `purchase()` is in flight so the CTA spins.
    @State private var purchaseInFlight = false

    /// "Why are you showing me this?" — optional context from the caller.
    var reason: String?

    /// When false, the ✕ close button is hidden. Used by
    /// `SubscriptionGateView` where the paywall sits at the root and
    /// cannot be dismissed — the user must purchase, restore, or sign
    /// out. Defaults to true so every existing sheet-style caller
    /// keeps its close affordance.
    var showCloseButton: Bool = true

    enum Plan {
        case monthly, yearly
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureList
                    planPicker
                    ctaSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await subs.prepareForPaywall()
            }
            .alert("Hmm, that didn't work",
                   isPresented: errorBinding,
                   presenting: subs.lastError) { _ in
                Button("OK", role: .cancel) { subs.lastError = nil }
            } message: { message in
                Text(message)
            }
            .onChange(of: subs.lastPurchaseSucceeded) { _, success in
                if success {
                    dismiss()
                    subs.lastPurchaseSucceeded = false
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.appAccent, Color.appAmber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.appAccent.opacity(0.35), radius: 18, y: 8)

                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            Text("Sacred Bill Tracker Pro")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(reason ?? "Unlock every feature. One calm place for every bill, household and business.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(ProFeature.all.enumerated()), id: \.element.id) { index, feature in
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.appAccent.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: feature.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline.weight(.semibold))
                        Text(feature.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)

                if index < ProFeature.all.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        VStack(spacing: 12) {
            planRow(.monthly, product: subs.monthlyProduct, badge: nil)
            planRow(.yearly, product: subs.yearlyProduct, badge: "SAVE 33%")
        }
    }

    private func planRow(_ plan: Plan, product: Product?, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.appAccent : Color.secondary.opacity(0.4),
                                      lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan == .yearly ? "Yearly" : "Monthly")
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.appLime, in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                    if let product {
                        Text(product.pricePerPeriod)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if plan == .yearly, let implied = product.impliedMonthlyPrice {
                            Text("≈ \(implied)")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                    } else if subs.isLoadingProducts {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text(plan == .yearly ? "$39.99 / year" : "$9.99 / month")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            Button {
                Task { await performPurchase() }
            } label: {
                ZStack {
                    if purchaseInFlight {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ctaLabel)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(
                LinearGradient(colors: [Color.appAccent, Color.appAmber],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
            .shadow(color: Color.appAccent.opacity(0.3), radius: 12, y: 6)
            .disabled(purchaseInFlight || selectedProduct == nil)
            .opacity(selectedProduct == nil && !subs.isLoadingProducts ? 0.6 : 1)

            Text(ctaDisclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Restore Purchases") {
                Task { await subs.restorePurchases() }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.appAccent)

            HStack(spacing: 6) {
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("·")
                Link("Privacy", destination: URL(string: "https://www.sacredpathway.org/sacred-bill-tracker-privacy")!)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Derived

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .monthly: return subs.monthlyProduct
        case .yearly:  return subs.yearlyProduct
        }
    }

    private var ctaLabel: String {
        if let intro = selectedProduct?.introOfferLabel {
            return "Start \(intro.lowercased())"
        }
        return "Continue"
    }

    private var ctaDisclaimer: String {
        let trialLine: String
        if let product = selectedProduct, product.introOfferLabel != nil {
            trialLine = "After your 7-day free trial, you will be charged \(product.pricePerPeriod). "
        } else if let product = selectedProduct {
            trialLine = "You will be charged \(product.pricePerPeriod). "
        } else {
            trialLine = ""
        }
        return trialLine +
            "Payment will be charged to your Apple ID account at confirmation of purchase. " +
            "Subscription automatically renews for the same price and duration unless " +
            "auto-renew is turned off at least 24 hours before the end of the current period. " +
            "Your account will be charged for renewal within 24 hours prior to the end of the " +
            "current period. You can manage and cancel your subscription in your App Store account settings."
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.appAccent.opacity(0.18),
                Theme.Color.background
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { subs.lastError != nil },
            set: { if !$0 { subs.lastError = nil } }
        )
    }

    // MARK: - Actions

    private func performPurchase() async {
        guard let product = selectedProduct else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        _ = await subs.purchase(product)
    }
}

// MARK: - Convenience sheet modifier

/// Presents the 3-tier paywall (Essential / Business / Unlimited). Replaces
/// the legacy single-tier `PaywallView` at every call site. `reason` is
/// passed through as the analytics `source`.
private struct PaywallSheetModifier: ViewModifier {
    @EnvironmentObject private var tiers: TierEntitlementManager
    @Binding var isPresented: Bool
    var reason: String?
    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ThreeTierPaywallView(source: reason ?? "paywall")
                .environmentObject(tiers)
        }
    }
}

extension View {
    /// Presents the 3-tier paywall when `isPresented` is true. `reason` is
    /// used as the analytics source.
    func paywallSheet(isPresented: Binding<Bool>, reason: String? = nil) -> some View {
        modifier(PaywallSheetModifier(isPresented: isPresented, reason: reason))
    }
}

#Preview {
    PaywallView(reason: "Track business bills with Pro.")
        .environmentObject(SubscriptionManager())
}

// MARK: - Sacred AutoTrack Premium paywall
//
// Independent add-on paywall for the Plaid-powered AutoTrack feature.
// Price is read live from StoreKit (never hardcoded). Purchase binds the
// Apple transaction to the Supabase user id and verifies server-side.

struct AutoTrackPaywallView: View {
    @EnvironmentObject private var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var purchaseInFlight = false
    @State private var selectedPlan: Plan = .monthly

    /// Hide the close button when presented as a hard gate.
    var showCloseButton: Bool = true

    enum Plan { case monthly, annual }

    private var monthly: Product? { subs.autoTrackMonthlyProduct }
    private var annual:  Product? { subs.autoTrackYearlyProduct }

    private var selectedProduct: Product? {
        selectedPlan == .annual ? annual : monthly
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    featureList
                    priceBlock
                    cta
                    trust
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(
                LinearGradient(colors: [Color.appAccent.opacity(0.18), Theme.Color.background],
                               startPoint: .top, endPoint: .center).ignoresSafeArea()
            )
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2).foregroundStyle(.secondary)
                        }.accessibilityLabel("Close")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await subs.prepareForPaywall()
                await subs.refreshAutoTrackEntitlementFromBackend()
            }
            .alert("Hmm, that didn't work",
                   isPresented: Binding(get: { subs.lastError != nil },
                                        set: { if !$0 { subs.lastError = nil } }),
                   presenting: subs.lastError) { _ in
                Button("OK", role: .cancel) { subs.lastError = nil }
            } message: { Text($0) }
            .onChange(of: subs.hasAutoTrack) { _, entitled in
                if entitled { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color.appAccent, Color.appAmber],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.appAccent.opacity(0.35), radius: 18, y: 8)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
            }.padding(.top, 8)
            Text("Automate your bill tracking")
                .font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text("AutoTrack Premium connects your bank securely through Plaid and automatically finds recurring bills and spending activity.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 8)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(["Connect bank & card accounts securely",
                     "Automatic transaction import",
                     "Recurring bill & subscription detection",
                     "Suggested bill-payment matching"], id: \.self) { line in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appAccent)
                    Text(line).font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var priceBlock: some View {
        VStack(spacing: 12) {
            planRow(.monthly, product: monthly, fallback: "$14.99 / month", badge: nil)
            planRow(.annual,  product: annual,  fallback: "$119.99 / year", badge: "BEST VALUE")
        }
    }

    private func planRow(_ plan: Plan, product: Product?, fallback: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().strokeBorder(isSelected ? Color.appAccent : Color.secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Color.appAccent).frame(width: 12, height: 12) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan == .annual ? "Annual" : "Monthly").font(.headline)
                        if let badge {
                            Text(badge).font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.appLime, in: Capsule()).foregroundStyle(.black)
                        }
                    }
                    if let product {
                        Text(product.pricePerPeriod).font(.footnote).foregroundStyle(.secondary)
                    } else if subs.isLoadingProducts {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(fallback).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 2))
            )
        }
        .buttonStyle(.plain)
    }

    private var cta: some View {
        VStack(spacing: 10) {
            Button {
                Task { await purchase() }
            } label: {
                ZStack {
                    if purchaseInFlight { ProgressView().tint(.white) }
                    else { Text("Start AutoTrack Premium").font(.headline) }
                }.frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(LinearGradient(colors: [Color.appAccent, Color.appAmber],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
            .disabled(purchaseInFlight || selectedProduct == nil)
            .opacity(selectedProduct == nil && !subs.isLoadingProducts ? 0.6 : 1)

            Button("Restore Purchase") { Task { await subs.restorePurchases() } }
                .font(.footnote.weight(.medium)).foregroundStyle(Color.appAccent)
        }
    }

    private var trust: some View {
        VStack(spacing: 4) {
            Text("Secure account connection powered by Plaid.")
            Text("SacredBillTracker never stores your bank login credentials.")
            Text("Disconnect your accounts anytime.")
        }
        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Text("·")
            Link("Privacy", destination: URL(string: "https://www.sacredpathway.org/sacred-bill-tracker-privacy")!)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        _ = await subs.purchaseAutoTrack(product)
    }
}

/// Gate any Plaid/AutoTrack feature: shows `content` only when entitled,
/// otherwise the AutoTrack paywall. Reconciles with the server on appear.
struct AutoTrackGateView<Content: View>: View {
    @EnvironmentObject private var subs: SubscriptionManager
    @ViewBuilder var content: () -> Content
    @State private var showPaywall = false

    var body: some View {
        Group {
            if subs.hasAutoTrack {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                    Text("AutoTrack Premium required").font(.headline)
                    Button("View AutoTrack Premium") { showPaywall = true }
                        .buttonStyle(.borderedProminent).tint(Color.appAccent)
                }
                .padding()
                .sheet(isPresented: $showPaywall) { AutoTrackPaywallView() }
            }
        }
        .task { await subs.refreshAutoTrackEntitlementFromBackend() }
    }
}

extension View {
    /// Presents the AutoTrack paywall when `isPresented` is true.
    func autoTrackPaywallSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { AutoTrackPaywallView() }
    }
}

// MARK: - Plaid Connect (AutoTrack) — Hosted Link
//
// Uses Plaid Hosted Link (no SDK / SPM dependency): the app fetches a
// hosted_link_url from `create-plaid-link-token`, opens it in an in-app Safari
// view, and on return calls `finalize-plaid-link`, which retrieves the public
// token server-side, exchanges it, and syncs. All Edge Functions enforce
// premium server-side; no Plaid secrets ever touch the client.

struct PlaidLinkTokenResponse: Decodable { let link_token: String; let hosted_link_url: String?; let expiration: String? }
struct PlaidFinalizeResponse: Decodable {
    let ok: Bool?; let items: Int?; let accounts: Int?; let transactions: Int?
    let status: String?; let message: String?
}

enum PlaidAutoTrackService {
    static func createLinkToken() async throws -> PlaidLinkTokenResponse {
        #if canImport(Supabase)
        return try await SupabaseConfig.client.functions.invoke("create-plaid-link-token")
        #else
        throw NSError(domain: "AutoTrack", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Supabase not available."])
        #endif
    }

    static func finalize(linkToken: String) async throws -> PlaidFinalizeResponse {
        #if canImport(Supabase)
        struct Body: Encodable { let link_token: String }
        return try await SupabaseConfig.client.functions.invoke(
            "finalize-plaid-link",
            options: FunctionInvokeOptions(body: Body(link_token: linkToken)))
        #else
        throw NSError(domain: "AutoTrack", code: -1)
        #endif
    }

    /// Lists the user's currently connected banks/accounts (premium-gated).
    static func connectedAccounts() async throws -> [PlaidConnectedAccount] {
        #if canImport(Supabase)
        return try await SupabaseConfig.client
            .rpc("autotrack_connected_accounts")
            .execute()
            .value
        #else
        return []
        #endif
    }

    /// Disconnects ONE bank (by plaid_items.id), removing it at Plaid and
    /// deleting its locally-synced accounts/transactions.
    @discardableResult
    static func disconnect(itemId: String) async throws -> PlaidDisconnectResponse {
        #if canImport(Supabase)
        struct Body: Encodable { let item_id: String }
        return try await SupabaseConfig.client.functions.invoke(
            "disconnect-plaid-item",
            options: FunctionInvokeOptions(body: Body(item_id: itemId)))
        #else
        throw NSError(domain: "AutoTrack", code: -1)
        #endif
    }

    // MARK: - Account classification (Business vs Personal) — v1.9

    /// Per-account classification list for the override + one-time review
    /// screen (premium-gated `autotrack_accounts_for_override`).
    static func accountsForOverride() async throws -> [PlaidAccountUsage] {
        #if canImport(Supabase)
        return try await SupabaseConfig.client
            .rpc("autotrack_accounts_for_override")
            .execute()
            .value
        #else
        return []
        #endif
    }

    /// Re-runs the auto-classifier across the user's unlocked accounts and
    /// returns the resulting decisions (premium-gated `autotrack_classify_accounts`).
    @discardableResult
    static func reclassifyAccounts() async throws -> [PlaidClassifyResult] {
        #if canImport(Supabase)
        return try await SupabaseConfig.client
            .rpc("autotrack_classify_accounts")
            .execute()
            .value
        #else
        return []
        #endif
    }

    /// Manually sets an account's classification. `personal`/`business` lock
    /// the account so the auto-classifier never overwrites it; `unknown`
    /// unlocks it for re-classification.
    static func setUsage(accountId: String, usageType: AccountUsageType) async throws {
        #if canImport(Supabase)
        struct Args: Encodable { let p_account_id: String; let p_usage_type: String }
        _ = try await SupabaseConfig.client
            .rpc("autotrack_set_account_usage",
                 params: Args(p_account_id: accountId, p_usage_type: usageType.rawValue))
            .execute()
        #endif
    }

    /// Dismisses the one-time "Personal or Business?" prompt for an account
    /// without choosing (it stays `unknown` but won't be asked again).
    static func dismissReview(accountId: String) async throws {
        #if canImport(Supabase)
        struct Args: Encodable { let p_account_id: String }
        _ = try await SupabaseConfig.client
            .rpc("autotrack_dismiss_account_review",
                 params: Args(p_account_id: accountId))
            .execute()
        #endif
    }
}

/// One connected bank account with its business/personal classification.
/// Backs the manual-override screen and the one-time review prompt.
struct PlaidAccountUsage: Decodable, Identifiable {
    let account_id: String
    let item_id: String?
    let institution_name: String?
    let name: String?
    let official_name: String?
    let mask: String?
    let type: String?
    let subtype: String?
    let current_balance: Double?
    let usage_type: String?
    let usage_source: String?
    let usage_confidence: Double?
    let usage_reason: String?
    let usage_locked: Bool?
    let usage_reviewed: Bool?
    let needs_user_review: Bool?

    var id: String { account_id }
    var usage: AccountUsageType { AccountUsageType(safe: usage_type) }
    var displayName: String { (name?.isEmpty == false ? name : official_name) ?? "Account" }
    var maskedName: String { mask.map { "\(displayName) ••\($0)" } ?? displayName }
    var confidencePercent: Int { Int(((usage_confidence ?? 0) * 100).rounded()) }
    var isUserSet: Bool { (usage_source ?? "") == "user" }
}

/// Decision row returned by `autotrack_classify_accounts`.
struct PlaidClassifyResult: Decodable {
    let account_id: String
    let usage_type: String?
}

/// One connected bank (a Plaid item) with its aggregated accounts.
struct PlaidConnectedAccount: Decodable, Identifiable {
    let item_id: String
    let institution_name: String?
    let status: String?
    let last_synced_at: String?
    let account_count: Int?
    let account_names: String?
    // v1.9 — per-bank business/personal breakdown.
    let business_count: Int?
    let personal_count: Int?
    let unknown_count: Int?
    var id: String { item_id }

    /// True when at least one account under this bank still needs the user
    /// to confirm Personal vs Business.
    var hasUnclassified: Bool { (unknown_count ?? 0) > 0 }
}

struct PlaidDisconnectResponse: Decodable {
    let ok: Bool?; let removed_accounts: Int?; let removed_transactions: Int?
}

/// In-app Safari host for the Plaid Hosted Link URL. Reports when the user
/// closes it (Done / swipe) so the caller can finalize.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }
}

/// AutoTrack "Connect a bank" screen. Orchestrates link-token → Plaid Link →
/// exchange → sync, surfacing each step and the imported counts.
struct AutoTrackConnectView: View {
    @EnvironmentObject private var incomeStore: IncomeStore

    @State private var phase: Phase = .idle
    @State private var linkToken: String?
    @State private var hostedURL: URL?
    @State private var showSafari = false
    @State private var resultText: String?
    @State private var errorText: String?

    // Multi-account state
    @State private var connected: [PlaidConnectedAccount] = []
    @State private var loadingConnected = false
    @State private var disconnectingItemID: String?
    @State private var pendingDisconnect: PlaidConnectedAccount?

    // Account classification (Business/Personal) — v1.9
    @State private var showUsageManager = false
    @State private var showUsageReview = false
    @State private var hasAutoPresentedReview = false

    enum Phase { case idle, loadingToken, presenting, finalizing, done, error }

    private var busy: Bool { phase == .loadingToken || phase == .finalizing }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 40)).foregroundStyle(Color.appAccent)
                Text("Connect your banks").font(.title2.bold())
                Text("Securely connect one or more accounts through Plaid. Deposits flow into your income, and spending is scanned for recurring bills.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                connectedSection

                if let resultText {
                    Text(resultText).font(.footnote).foregroundStyle(.green)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                Button {
                    Task { await start() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
                        Image(systemName: "plus.circle.fill")
                        Text(buttonLabel).font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .disabled(busy)
                .padding(.horizontal)

                if phase == .presenting {
                    Button("I finished in Plaid — import now") { Task { await finalize() } }
                        .font(.footnote.weight(.medium)).foregroundStyle(Color.appAccent)
                }
            }
            .padding()
        }
        .navigationTitle("AutoTrack")
        .task { await loadConnected() }
        .sheet(isPresented: $showUsageManager) {
            NavigationStack {
                AccountUsageOverrideView().environmentObject(incomeStore)
            }
        }
        .sheet(isPresented: $showUsageReview, onDismiss: { Task { await loadConnected() } }) {
            NavigationStack {
                AccountUsageOverrideView(reviewOnly: true).environmentObject(incomeStore)
            }
        }
        .sheet(isPresented: $showSafari, onDismiss: { Task { await finalize() } }) {
            if let u = hostedURL {
                SafariView(url: u, onFinish: { showSafari = false }).ignoresSafeArea()
            }
        }
        .confirmationDialog(
            "Disconnect this bank?",
            isPresented: Binding(get: { pendingDisconnect != nil },
                                 set: { if !$0 { pendingDisconnect = nil } }),
            presenting: pendingDisconnect
        ) { item in
            Button("Disconnect \(item.institution_name ?? "bank")", role: .destructive) {
                Task { await disconnect(item) }
            }
            Button("Cancel", role: .cancel) { pendingDisconnect = nil }
        } message: { _ in
            Text("This removes the account and its imported transactions. Income from this bank will no longer be counted.")
        }
    }

    // MARK: - Connected accounts list

    @ViewBuilder private var connectedSection: some View {
        if loadingConnected && connected.isEmpty {
            ProgressView().padding(.vertical, 8)
        } else if !connected.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connected accounts")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(connected) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(Color.appAccent).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.institution_name ?? "Bank").font(.subheadline.weight(.semibold))
                            if let names = item.account_names, !names.isEmpty {
                                Text(names).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let status = item.status, status != "active" {
                                Text(status == "login_required" ? "Needs reconnection" : status.capitalized)
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                        if disconnectingItemID == item.item_id {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                pendingDisconnect = item
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Disconnect \(item.institution_name ?? "bank")")
                        }
                    }
                    .padding(12)
                    .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Account classification (Business vs Personal) entry point.
                Button {
                    showUsageManager = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(Color.appAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage account types").font(.subheadline.weight(.semibold))
                            Text(usageSummary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if needsReviewCount > 0 {
                            Text("\(needsReviewCount) to review")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.appAmber, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    /// "2 Business · 3 Personal · 5 to review" summary across all banks.
    private var usageSummary: String {
        let biz = connected.reduce(0) { $0 + ($1.business_count ?? 0) }
        let per = connected.reduce(0) { $0 + ($1.personal_count ?? 0) }
        let unk = needsReviewCount
        var parts: [String] = []
        if biz > 0 { parts.append("\(biz) Business") }
        if per > 0 { parts.append("\(per) Personal") }
        if unk > 0 { parts.append("\(unk) to review") }
        return parts.isEmpty ? "Sort accounts into Personal or Business" : parts.joined(separator: " · ")
    }

    private var needsReviewCount: Int {
        connected.reduce(0) { $0 + ($1.unknown_count ?? 0) }
    }

    private var buttonLabel: String {
        switch phase {
        case .loadingToken: return "Preparing…"
        case .presenting:   return "Reopen Plaid"
        case .finalizing:   return "Importing…"
        default:            return connected.isEmpty ? "Connect a bank account" : "Add another bank"
        }
    }

    // MARK: - Actions

    private func loadConnected() async {
        loadingConnected = true
        defer { loadingConnected = false }
        connected = (try? await PlaidAutoTrackService.connectedAccounts()) ?? connected
        // One-time prompt: if any account is still unclassified, ask the user
        // to sort it — but only auto-present once per screen visit. The prompt
        // itself records the answer (or a skip) server-side so it won't nag.
        if !hasAutoPresentedReview, needsReviewCount > 0, !showSafari, phase != .finalizing {
            hasAutoPresentedReview = true
            showUsageReview = true
        }
    }

    private func start() async {
        errorText = nil; resultText = nil; phase = .loadingToken
        do {
            let res = try await PlaidAutoTrackService.createLinkToken()
            linkToken = res.link_token
            guard let urlStr = res.hosted_link_url, let url = URL(string: urlStr) else {
                phase = .error; errorText = "Plaid didn’t return a hosted link URL."; return
            }
            hostedURL = url; phase = .presenting; showSafari = true
        } catch { phase = .error; errorText = "Couldn’t start Plaid: \(error.localizedDescription)" }
    }

    /// Called when the Safari sheet closes (or via the manual button). Asks the
    /// backend to retrieve the public token, exchange, and sync. If the user
    /// hasn't finished linking yet, the backend reports "incomplete".
    private func finalize() async {
        guard let token = linkToken, phase != .finalizing, phase != .done else { return }
        phase = .finalizing; errorText = nil
        do {
            let r = try await PlaidAutoTrackService.finalize(linkToken: token)
            if r.ok == true {
                phase = .idle
                resultText = "Imported \(r.items ?? 0) bank(s) • \(r.accounts ?? 0) account(s) • \(r.transactions ?? 0) transaction(s)."
                linkToken = nil
                await loadConnected()
                await incomeStore.refreshBankIncome()
            } else {
                phase = .presenting
                errorText = r.message ?? "Plaid Link wasn’t completed yet. Finish in Plaid, then tap “Import now.”"
            }
        } catch { phase = .error; errorText = "Import failed: \(error.localizedDescription)" }
    }

    private func disconnect(_ item: PlaidConnectedAccount) async {
        pendingDisconnect = nil
        disconnectingItemID = item.item_id
        defer { disconnectingItemID = nil }
        do {
            try await PlaidAutoTrackService.disconnect(itemId: item.item_id)
            connected.removeAll { $0.item_id == item.item_id }
            await incomeStore.refreshBankIncome()
            resultText = "Disconnected \(item.institution_name ?? "bank")."
        } catch {
            errorText = "Couldn’t disconnect: \(error.localizedDescription)"
        }
    }
}

// MARK: - Account classification override + one-time review (v1.9)
//
// Lets the user see how each connected bank account was classified
// (Business / Personal / Needs review), confirm `unknown` accounts via a
// one-time prompt, and manually override any account at any time. Manual
// choices are saved permanently server-side (the account is "locked" so the
// auto-classifier never overwrites them). After any change, bank income is
// re-pulled so dashboard totals re-route immediately.

struct AccountUsageOverrideView: View {
    @EnvironmentObject private var incomeStore: IncomeStore
    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [PlaidAccountUsage] = []
    @State private var loading = false
    @State private var savingID: String?
    @State private var errorText: String?

    /// When true, only the accounts that still need confirmation are shown
    /// (used for the one-time "Personal or Business?" prompt). When false,
    /// every connected account is listed for manual override.
    var reviewOnly: Bool = false

    private var needsReview: [PlaidAccountUsage] { accounts.filter { $0.needs_user_review == true } }
    private var visibleAccounts: [PlaidAccountUsage] { reviewOnly ? needsReview : accounts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if loading && accounts.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                } else if visibleAccounts.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.seal.fill",
                        title: reviewOnly ? "All set" : "No accounts yet",
                        message: reviewOnly
                            ? "Every account has been sorted into Personal or Business."
                            : "Connect a bank to classify its accounts as Personal or Business."
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(visibleAccounts) { acct in
                        accountCard(acct)
                    }
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding()
        }
        .background(Theme.Color.background)
        .navigationTitle(reviewOnly ? "Sort your accounts" : "Account types")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(reviewOnly ? "Done" : "Close") { dismiss() }
            }
            if !reviewOnly {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await reclassify() }
                    } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Re-detect account types")
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reviewOnly
                 ? "We couldn’t tell whether these accounts are Personal or Business. Pick one for each — we’ll only ask once."
                 : "Each connected account is sorted as Personal or Business. Business income is never mixed into your Personal totals. Tap to change any account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func accountCard(_ acct: PlaidAccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: acct.usage.systemImage)
                    .foregroundStyle(Color.appAccent).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(acct.maskedName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(acct.institution_name ?? "Bank")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if savingID == acct.account_id { ProgressView().controlSize(.small) }
            }

            // Detected reason / confidence line.
            if acct.isUserSet {
                Text("Set by you").font(.caption2).foregroundStyle(.secondary)
            } else if let reason = acct.usage_reason, !reason.isEmpty {
                Text("Auto: \(acct.usage.title) • \(acct.confidencePercent)% — \(reason)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Manual override buttons. Each tap always writes (a segmented
            // Picker can't, because an `unknown` account would have no selected
            // segment and tapping the mapped-default would be a no-op).
            // Personal / Business lock the account; Auto unlocks for re-detection.
            HStack(spacing: 8) {
                usageButton(acct, .personal, "Personal", "house.fill")
                usageButton(acct, .business, "Business", "briefcase.fill")
                usageButton(acct, .unknown, "Auto", "wand.and.stars")
            }

            if acct.needs_user_review == true {
                Button("Not sure — skip for now") {
                    Task { await skip(acct) }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.appAccent)
            }
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(acct.needs_user_review == true ? Color.appAmber : .clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func usageButton(_ acct: PlaidAccountUsage, _ usage: AccountUsageType,
                             _ title: String, _ icon: String) -> some View {
        let selected = acct.usage == usage
        Button {
            Task { await setUsage(acct, usage) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(selected ? Color.appAccent : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(savingID == acct.account_id)
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        defer { loading = false }
        do { accounts = try await PlaidAutoTrackService.accountsForOverride() }
        catch { errorText = "Couldn’t load accounts: \(error.localizedDescription)" }
    }

    private func setUsage(_ acct: PlaidAccountUsage, _ usage: AccountUsageType) async {
        savingID = acct.account_id
        defer { savingID = nil }
        do {
            try await PlaidAutoTrackService.setUsage(accountId: acct.account_id, usageType: usage)
            await load()
            await incomeStore.refreshBankIncome()
        } catch { errorText = "Couldn’t save: \(error.localizedDescription)" }
    }

    private func skip(_ acct: PlaidAccountUsage) async {
        savingID = acct.account_id
        defer { savingID = nil }
        do {
            try await PlaidAutoTrackService.dismissReview(accountId: acct.account_id)
            await load()
        } catch { errorText = "Couldn’t skip: \(error.localizedDescription)" }
    }

    private func reclassify() async {
        loading = true
        defer { loading = false }
        do {
            _ = try await PlaidAutoTrackService.reclassifyAccounts()
            await load()
            await incomeStore.refreshBankIncome()
        } catch { errorText = "Couldn’t re-detect: \(error.localizedDescription)" }
    }
}
