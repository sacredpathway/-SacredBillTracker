//
//  SubscriptionPlanTier.swift
//  SacredBillTracker
//
//  The 3-tier subscription model (Essential / Business / Unlimited).
//  This is ADDITIVE to the legacy Pro / AutoTrack StoreKit setup — it does
//  not replace `SubscriptionTier` in Entitlements.swift. The backend
//  (`current_subscription_tier`, `has_business`, `has_unlimited`) is the
//  cross-device source of truth; legacy `autotrack_premium` maps to
//  `.unlimited` so existing paying subscribers are never downgraded.
//

import Foundation

/// Ranked subscription plans. Higher rank includes everything below it.
enum PlanTier: String, Codable, CaseIterable, Comparable, Identifiable {
    case free
    case essential
    case business
    case unlimited

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .free:      return 0
        case .essential: return 1
        case .business:  return 2
        case .unlimited: return 3
        }
    }

    static func < (lhs: PlanTier, rhs: PlanTier) -> Bool { lhs.rank < rhs.rank }

    /// Map a StoreKit product ID to the tier it grants.
    /// Legacy products are folded into the closest tier so current
    /// subscribers keep (at least) the access they paid for.
    static func from(productID: String) -> PlanTier {
        switch productID {
        case ProductID.essentialMonthly: return .essential
        case ProductID.businessMonthly:  return .business
        case ProductID.unlimitedMonthly: return .unlimited
        // Legacy mappings (never downgrade an existing customer):
        case ProductID.autoTrackMonthly, ProductID.autoTrackYearly:
            return .unlimited                 // AutoTrack ($14.99) == Unlimited
        case ProductID.proMonthly, ProductID.proYearly:
            return .business                  // Legacy Pro → Business
        default: return .free
        }
    }

    /// Backend string ("free"/"essential"/"business"/"unlimited") → tier.
    static func from(backend string: String) -> PlanTier {
        PlanTier(rawValue: string) ?? .free
    }

    var displayName: String {
        switch self {
        case .free:      return "Free"
        case .essential: return "Essential"
        case .business:  return "Business"
        case .unlimited: return "Unlimited"
        }
    }

    var priceDisplay: String {
        switch self {
        case .free:      return "Free"
        case .essential: return "Price available from Apple"
        case .business:  return "Price available from Apple"
        case .unlimited: return "Price available from Apple"
        }
    }

    /// Short marketing line shown on the paywall card.
    var tagline: String {
        switch self {
        case .free:      return "Get started."
        case .essential: return "Take control of your finances in minutes."
        case .business:  return "Built for entrepreneurs, side hustles, truck drivers, and growing businesses."
        case .unlimited: return "Your complete financial command center."
        }
    }

    /// Badge above the card in the paywall hierarchy.
    var badge: String? {
        switch self {
        case .unlimited: return "MOST POPULAR"
        case .business:  return "BEST FOR ENTREPRENEURS"
        case .essential: return "STARTER"
        case .free:      return nil
        }
    }

    var productID: String? {
        switch self {
        case .essential: return ProductID.essentialMonthly
        case .business:  return ProductID.businessMonthly
        case .unlimited: return ProductID.unlimitedMonthly
        case .free:      return nil
        }
    }

    /// Feature bullet list for the paywall comparison.
    var features: [String] {
        switch self {
        case .free:
            return ["Limited bills", "Basic tracking"]
        case .essential:
            return [
                "Manual bill & income entry",
                "Bill reminders & due-date tracking",
                "Payment tracking",
                "Basic dashboard",
                "Monthly spending totals",
                "Basic financial reports",
            ]
        case .business:
            return [
                "Everything in Essential",
                "Personal + business income tracking",
                "Personal + business expense tracking",
                "Separate business & personal dashboards",
                "Business cash flow & profit reports",
                "Business category tracking",
            ]
        case .unlimited:
            return [
                "Everything in Business",
                "Unlimited financial profiles",
                "Family, spouse, child & rental profiles",
                "Advanced analytics & forecasting",
                "Goal & net-worth tracking",
                "AI financial insights",
                "Advanced exports & premium themes",
                "Priority support + all future features",
            ]
        }
    }
}

/// Discrete capabilities gated by tier. Each maps to the minimum tier
/// required. Used by `FeatureGate` and contextual upsell prompts.
enum GatedFeature: String, CaseIterable {
    case businessDashboard
    case businessTracking
    case personalBusinessSplit
    case familyProfiles
    case unlimitedProfiles
    case forecasting
    case aiInsights
    case advancedAnalytics
    case goalTracking
    case netWorth
    case advancedExports
    case premiumThemes

    var requiredTier: PlanTier {
        switch self {
        case .businessDashboard, .businessTracking, .personalBusinessSplit:
            return .business
        default:
            return .unlimited
        }
    }

    /// Benefit-led upsell copy — NEVER "Feature Locked".
    var upsellTitle: String {
        switch requiredTier {
        case .business:  return "Track personal and business finances separately."
        case .unlimited: return "Unlock advanced forecasting and complete financial control."
        default:         return "Upgrade for more."
        }
    }

    var upsellSubtitle: String {
        switch self {
        case .businessDashboard, .businessTracking, .personalBusinessSplit:
            return "Separate dashboards, profit tracking, and business cash-flow reports."
        case .forecasting:
            return "See where your money is heading before the month ends."
        case .aiInsights:
            return "Personalized insights that explain your spending and savings."
        case .familyProfiles, .unlimitedProfiles:
            return "Manage personal, family, business, and rental finances in one place."
        case .advancedAnalytics, .goalTracking, .netWorth, .advancedExports, .premiumThemes:
            return "Advanced analytics, goals, net worth, exports, and premium themes."
        }
    }

    var upsellCTATier: PlanTier { requiredTier }
}
