//
//  BillRepository.swift
//  SacredBillTracker
//
//  Abstract persistence layer. Allows swapping UserDefaults for Supabase
//  without touching any view or BillStore logic.
//

import Foundation

protocol BillRepository {
    func loadBills() async throws -> [Bill]

    /// UPSERT semantics: writes/updates each bill in `bills`. Does NOT
    /// delete rows that were removed from the in-memory snapshot. To
    /// delete a single bill use `delete(id:)`; to wipe everything use
    /// `deleteAll()`.
    func saveBills(_ bills: [Bill]) async throws

    func upsert(_ bill: Bill) async throws
    func delete(id: UUID) async throws

    /// Remove every bill belonging to the current user from this
    /// repository. On a remote-backed repo this issues a DELETE WHERE
    /// user_id = currentUser; on a local cache it clears the cache.
    /// Used by wipeAll / sign-out / account deletion flows so that
    /// removed data does NOT come back on next refresh.
    func deleteAll() async throws
}
