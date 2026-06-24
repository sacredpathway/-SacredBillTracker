//
//  ThreeTierPaywallView.swift
//  SacredBillTracker
//
//  Modern 3-plan paywall: Unlimited (Most Popular) anchored on top,
//  Business, then Essential. Pricing-psychology layout with a value
//  anchor on Unlimited and an "only $5 more" upsell line.
//
//  Inject `TierEntitlementManager` as an @EnvironmentObject.
//

import SwiftUI
import StoreKit

struct ThreeTierPaywallView: View {
    @EnvironmentObject private var tiers: TierEntitlementManager
    @Environment(\.dismiss) private var dismiss

    /// Optional context for analytics + a contextual headline.
    var source: String = "paywall"
    var highlight: PlanTier = .unlimited

    @State private var selected: PlanTier = .unlimited
    @State private var working = false

    // Display order (visual hierarchy): Unlimited → Business → Essential
    private let order: [PlanTier] = [.unlimited, .business, .essential]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    ForEach(order) { tier in
                        PlanCard(tier: tier,
                                 product: tiers.product(for: tier),
                                 isSelected: selected == tier,
                                 isCurrent: tiers.activeTier == tier)
                            .onTapGesture {
                                selected = tier
                                AnalyticsService.shared.track(.planSelected, tier: tier.rawValue, source: source)
                            }
                    }
                    upsellLine
                    purchaseButton
                    footer
                }
                .padding()
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Choose Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(.appAccentText)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restore") { Task { working = true; await tiers.restore(); working = false } }
                        .tint(.appAccentText)
                }
            }
            .task {
                if tiers.planProducts.isEmpty { await tiers.loadProducts() }
                await AnalyticsService.shared.log(.paywallView, source: source)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.appAccent)
            Text("Unlock Sacred Bill Tracker")
                .font(.title2.bold())
            Text("Your complete financial command center.")
                .font(.subheadline)
                .foregroundStyle(Color.appSubtleText)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private var upsellLine: some View {
        Group {
            if selected == .business {
                Label("Only $5 more to unlock everything with Unlimited.",
                      systemImage: "arrow.up.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.appAccentText)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            Task {
                working = true
                let ok = await tiers.purchase(tier: selected)
                working = false
                if ok { dismiss() }
            }
        } label: {
            HStack {
                if working { ProgressView().tint(.appOnGold) }
                Text(working ? "Processing…" : ctaTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Color.appOnGold)
        }
        .disabled(working || tiers.product(for: selected) == nil)
    }

    private var ctaTitle: String {
        if tiers.activeTier == selected { return "Current Plan" }
        if tiers.activeTier > selected { return "Switch to \(selected.displayName)" }
        if tiers.activeTier != .free { return "Upgrade to \(selected.displayName)" }
        return "Start \(selected.displayName) — \(selected.priceDisplay)"
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Auto-renewing subscription. Cancel anytime in Settings.")
            Text("Payment charged to your Apple ID. Renews unless canceled 24h before period ends.")
        }
        .font(.caption2)
        .foregroundStyle(Color.appSubtleText)
        .multilineTextAlignment(.center)
        .padding(.top, 6)
    }
}

private struct PlanCard: View {
    let tier: PlanTier
    let product: Product?
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let badge = tier.badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(badgeColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(badgeColor)
                }
                Spacer()
                if isCurrent {
                    Text("CURRENT")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.appHouseholdText)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(tier.displayName).font(.title3.bold())
                Spacer()
                Text(product?.displayPrice ?? tier.priceDisplay)
                    .font(.headline)
                    .foregroundStyle(Color.appAccentText)
                Text("/mo").font(.caption).foregroundStyle(Color.appSubtleText)
            }
            Text(tier.tagline)
                .font(.caption)
                .foregroundStyle(Color.appSubtleText)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(tier.features, id: \.self) { f in
                    Label(f, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .labelStyle(.titleAndIcon)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.appHouseholdText, .primary)
                }
            }
        }
        .padding()
        .background(Color.appCardSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.appAccent : Color.appHairline,
                        lineWidth: isSelected ? 2.5 : 1)
        )
    }

    private var badgeColor: Color {
        switch tier {
        case .unlimited: return .appAccent
        case .business:  return .appBusinessText
        default:         return .appSubtleText
        }
    }
}
