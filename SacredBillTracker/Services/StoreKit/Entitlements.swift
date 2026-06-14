//
//  Entitlements.swift
//  SacredBillTracker
//
//  What the user is allowed to do based on their subscription state.
//  Keep this file small and declarative — it's the source of truth
//  every view consults via `@EnvironmentObject SubscriptionManager`.
//

import Foundation

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
