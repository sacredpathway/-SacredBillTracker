//
//  CategoryDetailDebugSeeder.swift
//  SacredBillTracker
//
//  DEBUG-ONLY helper. The previous version of this file seeded sample
//  bills for the v1.0.9 Reports → Category Detail QA pass. Per the
//  follow-up request, the seeder has been removed and replaced by a
//  one-shot WIPER that soft-deletes any bills whose name starts with
//  `[QA] Sample` so QA data left behind by earlier DEBUG launches is
//  cleared from the user's account.
//
//  Never compiled into Release builds (`#if DEBUG`). Idempotent — once
//  there are no `[QA] Sample` bills left, every call is a no-op.
//

#if DEBUG
import Foundation

enum CategoryDetailDebugSeeder {

    /// Bill-name prefix used by the (now-removed) seeder. Anything
    /// matching is treated as QA leftover and removed.
    private static let qaPrefix = "[QA] Sample"

    /// DEBUG-only wipe pass. Soft-deletes (BillStore.delete →
    /// repository.softDelete) every bill whose name starts with the
    /// QA prefix. Safe to call on every cold start — turns into a
    /// no-op the moment all QA bills are gone.
    @MainActor
    static func seedIfNeeded(into store: BillStore) {
        let leftovers = store.bills.filter { $0.name.hasPrefix(qaPrefix) }
        guard !leftovers.isEmpty else { return }
        for bill in leftovers {
            store.delete(bill)
        }
    }
}
#endif
