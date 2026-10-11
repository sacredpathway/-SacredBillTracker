//
//  FeatureGate.swift
//  SacredBillTracker
//
//  Declarative feature gating for the 3-tier model. Wrap any premium
//  surface in `.tierGated(.forecasting)` — entitled users see the content;
//  everyone else sees a benefit-led upsell card (NEVER "Feature Locked")
//  that opens the 3-tier paywall.
//

import SwiftUI

// MARK: - Upsell card

struct UpgradePromptCard: View {
    let feature: GatedFeature
    var onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 30))
                .foregroundStyle(Color.appAccentText)
            Text(feature.upsellTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(feature.upsellSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appSubtleText)
                .multilineTextAlignment(.center)
            Button {
                AnalyticsService.shared.track(.upsellTapped,
                                              tier: feature.requiredTier.rawValue,
                                              source: feature.rawValue)
                onUpgrade()
            } label: {
                Text("Upgrade to \(feature.requiredTier.displayName)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.appOnGold)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.appCardSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appHairline, lineWidth: 1))
        .onAppear {
            AnalyticsService.shared.track(.upsellShown,
                                          tier: feature.requiredTier.rawValue,
                                          source: feature.rawValue)
        }
    }

    private var iconName: String {
        switch feature {
        case .businessDashboard, .businessTracking, .personalBusinessSplit: return "briefcase.fill"
        case .forecasting:        return "chart.line.uptrend.xyaxis"
        case .aiInsights:         return "sparkles"
        case .familyProfiles, .unlimitedProfiles: return "person.3.sequence.fill"
        case .advancedAnalytics:  return "chart.bar.xaxis"
        case .goalTracking:       return "target"
        case .netWorth:           return "chart.pie.fill"
        case .advancedExports:    return "square.and.arrow.up.on.square.fill"
        case .premiumThemes:      return "paintpalette.fill"
        }
    }
}

// MARK: - Gate modifier

private struct TierGateModifier: ViewModifier {
    @EnvironmentObject private var tiers: TierEntitlementManager
    let feature: GatedFeature
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        Group {
            if tiers.has(feature) {
                content
            } else {
                UpgradePromptCard(feature: feature) { showPaywall = true }
            }
        }
        .sheet(isPresented: $showPaywall) {
            ThreeTierPaywallView(source: feature.rawValue, highlight: feature.requiredTier)
                .environmentObject(tiers)
        }
    }
}

extension View {
    /// Show this view only if the user meets `feature`'s required tier;
    /// otherwise show a benefit-led upsell that opens the paywall.
    func tierGated(_ feature: GatedFeature) -> some View {
        modifier(TierGateModifier(feature: feature))
    }
}

// MARK: - Inline upsell banner (for embedding in scrollable screens)

struct InlineUpsellBanner: View {
    @EnvironmentObject private var tiers: TierEntitlementManager
    let feature: GatedFeature
    @State private var showPaywall = false

    var body: some View {
        if !tiers.has(feature) {
            Button {
                AnalyticsService.shared.track(.upsellTapped, tier: feature.requiredTier.rawValue, source: feature.rawValue)
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(Color.appAccentText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.upsellTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text("Upgrade to \(feature.requiredTier.displayName)")
                            .font(.caption).foregroundStyle(Color.appAccentText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.appSubtleText)
                }
                .padding(14)
                .background(Color.appCardSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appHairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPaywall) {
                ThreeTierPaywallView(source: feature.rawValue, highlight: feature.requiredTier)
                    .environmentObject(tiers)
            }
        }
    }
}
