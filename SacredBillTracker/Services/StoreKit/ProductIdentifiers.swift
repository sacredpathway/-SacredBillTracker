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

    /// All product IDs to request from StoreKit on launch.
    static let all: [String] = [proMonthly, proYearly, focusPlusMonthly]

    /// The subscription group all Pro tiers belong to. Configured in
    /// App Store Connect; StoreKit uses this for upgrade / downgrade paths.
    /// Real ASC group ID for "Sacred Bill Tracker Pro".
    static let subscriptionGroupID = "22047990"

    /// Subscription group for the Sacred Focus+ add-on. Must be a
    /// SEPARATE group from Pro so Focus+ does not appear as a Pro-tier
    /// alternative inside the system Manage Subscriptions sheet. New
    /// group needs to be created in App Store Connect before submitting.
    static let focusPlusGroupID = "sacred_focus_plus"
}
