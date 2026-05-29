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
    /// Filter a list of bills by scope.
    ///
    /// As of v1.0.5 (Partner Budgeting fully wired) ownership decides
    /// the tab, not the `isShared` flag:
    ///   - `.mine`   → bills owned by `currentUserID` (or local-only bills with nil owner)
    ///   - `.shared` → bills owned by a connected partner (the server only
    ///                 returns those when the partner flagged them
    ///                 `is_shared = true`, so this tab doubles as
    ///                 "what my partner is sharing with me")
    func filtered(by scope: BillScope, currentUserID: UUID?) -> [Bill] {
        switch scope {
        case .mine:
            return filter { bill in
                bill.ownerUserID == nil || bill.ownerUserID == currentUserID
            }
        case .shared:
            return filter { bill in
                guard let owner = bill.ownerUserID, let me = currentUserID else { return false }
                return owner != me
            }
        }
    }

    /// Backwards-compat overload — delegates to the user-aware version
    /// with no current user, which preserves the previous "all bills are
    /// mine" behavior for tests / previews that don't run against
    /// Supabase.
    func filtered(by scope: BillScope) -> [Bill] {
        filtered(by: scope, currentUserID: nil)
    }
}
