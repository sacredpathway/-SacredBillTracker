//
//  BillRepository.swift
//  SacredBillTracker
//
//  Abstract persistence layer. Allows swapping UserDefaults for Supabase
//  without touching any view or BillStore logic.
//

import Foundation

protocol BillRepository {
    /// Returns only ACTIVE bills (deleted_at IS NULL), scoped to the
    /// current user. Used for every normal list / dashboard / calendar /
    /// reports query.
    func loadBills() async throws -> [Bill]

    /// Returns ONLY soft-deleted bills (deleted_at IS NOT NULL), scoped
    /// to the current user. Powers the Trash screen.
    func loadDeletedBills() async throws -> [Bill]

    /// UPSERT semantics: writes/updates each bill in `bills`. Does NOT
    /// delete rows that were removed from the in-memory snapshot. To
    /// soft-delete a single bill use `softDelete(id:)`; to wipe everything
    /// use `deleteAll()`.
    func saveBills(_ bills: [Bill]) async throws

    func upsert(_ bill: Bill) async throws

    /// Soft delete: set deleted_at = now(). Bill remains in the DB and
    /// can be restored. This is the user-facing delete path.
    func softDelete(id: UUID) async throws

    /// Restore: clear deleted_at. Bill returns to normal queries.
    func restore(id: UUID) async throws

    /// Hard delete a single row (legacy demo purge / system housekeeping
    /// only — never the user-facing delete action). Bypasses Trash.
    func delete(id: UUID) async throws

    /// Remove every bill belonging to the current user from this
    /// repository. On a remote-backed repo this issues a DELETE WHERE
    /// user_id = currentUser; on a local cache it clears the cache.
    /// Used by wipeAll / sign-out / account deletion flows so that
    /// removed data does NOT come back on next refresh. Hard delete.
    func deleteAll() async throws
}
