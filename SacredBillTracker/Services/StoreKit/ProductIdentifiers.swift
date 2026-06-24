//
//  ProductIdentifiers.swift
//  SacredBillTracker
//
//  Central list of StoreKit product IDs. These must match the products
//  configured in App Store Connect (and in `Configuration.storekit` for
//  local simulator testing).
//
//  Naming convention: <bundle-id>.<tier>.<period>
//

import Foundation

enum ProductID {
    /// Sacred Bill Tracker Pro — billed monthly. Auto-renewing.
    static let proMonthly = "com.sacredbilltracker.app.pro.monthly"

    /// Sacred Bill Tracker Pro — billed yearly. Auto-renewing. Best value.
    static let proYearly  = "com.sacredbilltracker.app.pro.yearly"

    /// Sacred Focus+ — monthly add-on. v1.0.9.
    /// Unlocks Daily Focus Center, Schedule Buddy, focus quotes, to-do
    /// list, suggested daily plan, financial focus reminders, progress
    /// tracking, and saved favorite quotes. Sold **on top of** any
    /// existing Sacred Bill Tracker Pro subscription — Pro users still
    /// need this entitlement to unlock the Focus+ features. Belongs to
    /// its own subscription group so it never upgrade/downgrade-collides
    /// with the Pro tier.
    static let focusPlusMonthly = "sacred_focus_plus_monthly"

    /// Sacred AutoTrack Premium — Plaid-powered automatic bill/spending
    /// tracking. Monthly + annual, billed via StoreKit. Sold as its own
    /// independent add-on (its own subscription group) so it never
    /// upgrade/downgrade-collides with the Pro tier. Server-side
    /// entitlement is the source of truth (see SubscriptionManager
    /// AutoTrack section): purchases are verified by the
    /// `verify-store-subscription` edge function.
    static let autoTrackMonthly = "com.sacredbilltracker.app.autotrack.monthly"
    static let autoTrackYearly  = "com.sacredbilltracker.app.autotrack.annual"

    /// AutoTrack product IDs (for entitlement checks).
    static let autoTrack: Set<String> = [autoTrackMonthly, autoTrackYearly]

    // MARK: - 3-Tier Plans (Essential / Business / Unlimited)
    //
    // One subscription group ("Sacred Bill Tracker Plans") so StoreKit
    // handles upgrade/downgrade between the three tiers automatically.
    // Product IDs match App Store Connect and `Configuration.storekit`.

    static let essentialMonthly = "essential_monthly_499"
    static let businessMonthly  = "business_monthly_999"
    static let unlimitedMonthly = "unlimited_monthly_1499"

    /// All tier product IDs, low → high.
    static let tierPlans: [String] = [essentialMonthly, businessMonthly, unlimitedMonthly]

    /// Subscription group that contains the three tier plans. Must be a
    /// single shared group in App Store Connect for upgrade/downgrade.
    /// Real ASC group ID for "Sacred Bill Tracker Plans" (the local
    /// Configuration.storekit uses its own id "30010001" for simulator tests).
    static let plansGroupID = "22184614"

    /// All product IDs to request from StoreKit on launch.
    static let all: [String] = [proMonthly, proYearly, focusPlusMonthly,
                                autoTrackMonthly, autoTrackYearly,
                                essentialMonthly, businessMonthly, unlimitedMonthly]

    /// The subscription group all Pro tiers belong to. Configured in
    /// App Store Connect; StoreKit uses this for upgrade / downgrade paths.
    /// Real ASC group ID for "Sacred Bill Tracker Pro".
    static let subscriptionGroupID = "22047990"

    /// Subscription group for the Sacred Focus+ add-on. Must be a
    /// SEPARATE group from Pro so Focus+ does not appear as a Pro-tier
    /// alternative inside the system Manage Subscriptions sheet. New
    /// group needs to be created in App Store Connect before submitting.
    static let focusPlusGroupID = "sacred_focus_plus"

    /// Subscription group for Sacred AutoTrack Premium. Separate group so
    /// AutoTrack never appears as a Pro-tier alternative in Manage
    /// Subscriptions. Create this group in App Store Connect before submit.
    static let autoTrackGroupID = "sacred_autotrack_premium"
}
