//
//  LegacyDemoBills.swift
//  SacredBillTracker
//
//  Identifies the 10 demo bills that v1.0 auto-seeded into UserDefaults via
//  SampleData.bills(). Used by both BillStore (post-load purge) and
//  CachingBillRepository (pre-upload filter) to guarantee a brand-new user
//  starts with ZERO bills, even if iCloud Backup restored stale v1.0 cache.
//

import Foundation

enum LegacyDemoBills {

    /// Exact (name | NSDecimalNumber stringValue of amount) pairs that the
    /// v1.0 SampleData seeded. Match is exact — a user-added bill named
    /// "Rent" with a different amount survives untouched.
    static let signature: Set<String> = [
        "Rent|1850",
        "Electric|142.18",
        "Internet|79.99",
        "Car Insurance|132.5",
        "Tithe|300",
        "Adobe Creative Cloud|54.99",
        "LLC Annual Filing|125",
        "Office Rent|950",
        "Contractor Invoice|1200",
        "Quickbooks|30"
    ]

    static func isLegacyDemo(_ bill: Bill) -> Bool {
        let amountString = NSDecimalNumber(decimal: bill.amount).stringValue
        return signature.contains("\(bill.name)|\(amountString)")
    }

    static func filterOut(_ bills: [Bill]) -> [Bill] {
        bills.filter { !isLegacyDemo($0) }
    }
}
