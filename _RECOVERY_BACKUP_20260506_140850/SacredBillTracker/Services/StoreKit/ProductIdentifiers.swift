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

    /// All product IDs to request from StoreKit on launch.
    static let all: [String] = [proMonthly, proYearly]

    /// The subscription group all Pro tiers belong to. Configured in
    /// App Store Connect; StoreKit uses this for upgrade / downgrade paths.
    /// Real ASC group ID for "Sacred Bill Tracker Pro".
    static let subscriptionGroupID = "22047990"
}
