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

struct PaywallView: View {

    @EnvironmentObject private var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// The product the user currently has selected in the toggle.
    @State private var selectedPlan: Plan = .yearly

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
                if subs.products.isEmpty { await subs.loadProducts() }
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
            planRow(.yearly, product: subs.yearlyProduct, badge: "SAVE 33%")
            planRow(.monthly, product: subs.monthlyProduct, badge: nil)
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
                        Text(plan == .yearly ? "$39.99 / year" : "$4.99 / month")
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

extension View {
    /// Presents the paywall when `isPresented` is true, passing an
    /// optional `reason` string shown in the hero copy.
    func paywallSheet(isPresented: Binding<Bool>, reason: String? = nil) -> some View {
        sheet(isPresented: isPresented) {
            PaywallView(reason: reason)
        }
    }
}

#Preview {
    PaywallView(reason: "Track business bills with Pro.")
        .environmentObject(SubscriptionManager())
}
