//
//  BillScope.swift
//  SacredBillTracker
//
//  Top-of-screen filter for the Bills tab: My Bills vs Shared Bills.
//  Lives next to Bill.swift so the filter helper has access to the
//  `isShared` flag added in v1.2.
//

import Foundation

enum BillScope: String, CaseIterable, Identifiable {
    case mine   = "My Bills"
    case shared = "Shared Bills"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .mine:   return "person.fill"
        case .shared: return "person.2.fill"
        }
    }
}

extension Array where Element == Bill {
    /// Filter a list of bills by scope. `mine` excludes anything flagged as
    /// shared (those live exclusively in the Shared tab). `shared` returns
    /// only flagged bills.
    func filtered(by scope: BillScope) -> [Bill] {
        switch scope {
        case .mine:   return filter { !$0.isShared }
        case .shared: return filter { $0.isShared }
        }
    }
}
