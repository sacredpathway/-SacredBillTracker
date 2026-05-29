//
//  SupabaseBillRepository.swift
//  SacredBillTracker
//
//  Real Supabase-backed BillRepository. Only compiles when the
//  supabase-swift SPM package is linked; without it, falls back to a
//  pass-through on top of LocalBillRepository so the project still builds.
//
//  Schema (run once in Supabase SQL editor):
//
//    create extension if not exists "pgcrypto";
//
//    create table public.bills (
//      id            uuid primary key,
//      user_id       uuid not null references auth.users(id) on delete cascade,
//      name          text not null,
//      amount        numeric(14,2) not null,
//      due_date      timestamptz not null,
//      category      text not null,
//      recurrence    text not null,
//      type          text not null,
//      auto_pay      boolean not null default false,
//      notes         text not null default '',
//      status        text not null default 'unpaid',
//      last_paid_date timestamptz,
//      created_at    timestamptz not null default now(),
//      updated_at    timestamptz not null default now(),
//      deleted_at    timestamptz                          -- v1.3 soft delete
//    );
//
//    alter table public.bills enable row level security;
//
//    create policy "Users can read own bills"   on public.bills for select using (auth.uid() = user_id);
//    create policy "Users can insert own bills" on public.bills for insert with check (auth.uid() = user_id);
//    create policy "Users can update own bills" on public.bills for update using (auth.uid() = user_id);
//    create policy "Users can delete own bills" on public.bills for delete using (auth.uid() = user_id);
//
//    create index bills_user_due_idx on public.bills(user_id, due_date);
//
//    create or replace function public.set_updated_at() returns trigger as $$
//    begin new.updated_at = now(); return new; end;
//    $$ language plpgsql;
//
//    create trigger bills_set_updated_at
//      before update on public.bills
//      for each row execute function public.set_updated_at();
//

import Foundation

#if canImport(Supabase)
import Supabase

/// Wire-format row matching the `bills` table. Converts to/from `Bill`.
private struct BillRow: Codable {
    let id: UUID
    let user_id: UUID
    let name: String
    let amount: Double
    let due_date: Date
    let category: String
    let recurrence: String
    let type: String
    let auto_pay: Bool
    let notes: String
    let status: String
    let last_paid_date: Date?
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
    let is_shared: Bool?
    // v1.5 — Payment Link. Optional column so rows from before the
    // migration decode cleanly (and rows from the new build encode null
    // when the user didn't set one).
    let payment_url: String?

    init(bill: Bill, userID: UUID) {
        self.id            = bill.id
        self.user_id       = userID
        self.name          = bill.name
        self.amount        = (bill.amount as NSDecimalNumber).doubleValue
        self.due_date      = bill.dueDate
        self.category      = bill.category.rawValue
        self.recurrence    = bill.recurrence.rawValue
        self.type          = bill.type.rawValue
        self.auto_pay      = bill.autoPay
        self.notes         = bill.notes
        self.status        = bill.status.rawValue
        self.last_paid_date = bill.lastPaidDate
        self.created_at    = bill.createdAt
        self.updated_at    = bill.updatedAt
        self.deleted_at    = bill.deletedAt
        self.is_shared     = bill.isShared
        self.payment_url   = bill.paymentURL
    }

    func toBill() -> Bill? {
        guard
            let category   = BillCategory(rawValue: category),
            let recurrence = RecurrenceType(rawValue: recurrence),
            let type       = BillType(rawValue: type),
            let status     = PaymentStatus(rawValue: status)
        else { return nil }
        return Bill(
            id: id,
            name: name,
            amount: Decimal(amount),
            dueDate: due_date,
            category: category,
            recurrence: recurrence,
            type: type,
            autoPay: auto_pay,
            notes: notes,
            status: status,
            lastPaidDate: last_paid_date,
            createdAt: created_at,
            updatedAt: updated_at,
            isShared: is_shared ?? false,
            deletedAt: deleted_at,
            ownerUserID: user_id,
            paymentURL: payment_url?.nilIfEmpty
        )
    }
}

/// Update payload for soft-delete. We send only the columns we want to
/// change so we don't accidentally clobber other fields.
private struct SoftDeletePayload: Encodable {
    let deleted_at: Date
    let updated_at: Date
}

/// Update payload for restore. Explicitly encodes `deleted_at` as JSON
/// null so PostgREST clears the column (Swift's default encoder would
/// omit a nil Optional, leaving the column unchanged).
private struct RestorePayload: Encodable {
    let updated_at: Date
    enum CodingKeys: String, CodingKey { case deleted_at, updated_at }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNil(forKey: .deleted_at)
        try c.encode(updated_at, forKey: .updated_at)
    }
}

final class SupabaseBillRepository: BillRepository {

    private let client: SupabaseClient
    private let table = "bills"

    init(client: SupabaseClient = SupabaseConfig.client) {
        self.client = client
    }

    // MARK: - Helpers

    private func currentUserID() async throws -> UUID {
        // supabase-swift 2.x: session is an async-throws property; user
        // comes off of the session.
        let session = try await client.auth.session
        return session.user.id
    }

    // MARK: - BillRepository

    /// Active bills only — own bills + partner's shared bills.
    ///
    /// As of v1.0.5 the bills RLS includes a "partners can read shared bills"
    /// policy, so a plain SELECT (no user_id filter) returns BOTH the
    /// caller's own rows AND any rows belonging to a connected partner
    /// where `is_shared = true`. The `user_id` filter was removed so the
    /// partner read path actually returns rows; the RLS policies do the
    /// scoping instead.
    func loadBills() async throws -> [Bill] {
        _ = try await currentUserID() // ensure session is live; throws if not
        let rows: [BillRow] = try await client
            .from(table)
            .select()
            .filter("deleted_at", operator: "is", value: "null")
            .order("due_date", ascending: true)
            .execute()
            .value
        return rows.compactMap { $0.toBill() }
    }

    /// Soft-deleted bills only. Used by the Trash screen.
    ///
    /// Filtering is done client-side after a user-scoped fetch. PostgREST's
    /// "deleted_at IS NOT NULL" filter has a wire format (`not.is.null`)
    /// that didn't round-trip cleanly through supabase-swift 2.43.1's
    /// strongly-typed builder, so we trade one extra in-memory pass for
    /// portability across SDK versions. Bills-per-user is small in
    /// practice (free tier caps at \(FreeTierLimits.maxBills)), so the
    /// client-side filter is a non-issue.
    func loadDeletedBills() async throws -> [Bill] {
        let userID = try await currentUserID()
        let rows: [BillRow] = try await client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("updated_at", ascending: false)
            .execute()
            .value
        return rows
            .compactMap { $0.toBill() }
            .filter { $0.deletedAt != nil }
    }

    func saveBills(_ bills: [Bill]) async throws {
        guard !bills.isEmpty else { return }
        let userID = try await currentUserID()

        // CRITICAL — Build 21 fix.
        // `BillStore.persist()` passes the FULL in-memory snapshot here,
        // which can include a partner's shared bills. Stamping every row
        // with `user_id = ME` and upserting would attempt to rewrite the
        // owner of partner-owned rows. Postgres RLS on `bills` rejects
        // that, and the rejection cascades through the batched upsert —
        // so the user's OWN legitimate edits (e.g. toggling "Share with
        // partner" off) don't land either. The partner-owned bill is then
        // re-fetched from the server with its original state, and from
        // the user's perspective "stop sharing" appears to do nothing.
        //
        // Filter the snapshot to bills the current user actually owns.
        // Bills with `ownerUserID == nil` are still included — those are
        // locally-created rows that haven't been round-tripped to the
        // server yet.
        let myBills = bills.filter { bill in
            guard let owner = bill.ownerUserID else { return true }
            return owner == userID
        }
        guard !myBills.isEmpty else { return }

        let rows = myBills.map { BillRow(bill: $0, userID: userID) }
        try await client
            .from(table)
            .upsert(rows, onConflict: "id")
            .execute()
    }

    func upsert(_ bill: Bill) async throws {
        let userID = try await currentUserID()
        let row = BillRow(bill: bill, userID: userID)
        try await client
            .from(table)
            .upsert(row, onConflict: "id")
            .execute()
    }

    func softDelete(id: UUID) async throws {
        let userID = try await currentUserID()
        let now = Date()
        try await client
            .from(table)
            .update(SoftDeletePayload(deleted_at: now, updated_at: now))
            .eq("id", value: id)
            .eq("user_id", value: userID)
            .execute()
    }

    func restore(id: UUID) async throws {
        let userID = try await currentUserID()
        try await client
            .from(table)
            .update(RestorePayload(updated_at: Date()))
            .eq("id", value: id)
            .eq("user_id", value: userID)
            .execute()
    }

    func delete(id: UUID) async throws {
        // Scope by user_id as well as id. RLS already prevents cross-user
        // deletes server-side, but adding the explicit filter makes the
        // intent obvious and survives any future RLS policy changes.
        // NOTE: this is the HARD-DELETE path. User-facing delete actions
        // must call `softDelete(id:)` instead — `delete(id:)` is reserved
        // for system housekeeping (legacy demo purge, account wipe).
        let userID = try await currentUserID()
        try await client
            .from(table)
            .delete()
            .eq("id", value: id)
            .eq("user_id", value: userID)
            .execute()
    }

    func deleteAll() async throws {
        let userID = try await currentUserID()
        try await client
            .from(table)
            .delete()
            .eq("user_id", value: userID)
            .execute()
    }
}

#else

// ---------- Fallback shim when supabase-swift is not linked ----------

final class SupabaseBillRepository: BillRepository {

    private let fallback: BillRepository

    init(fallback: BillRepository = LocalBillRepository()) {
        self.fallback = fallback
    }

    func loadBills() async throws -> [Bill]            { try await fallback.loadBills() }
    func loadDeletedBills() async throws -> [Bill]     { try await fallback.loadDeletedBills() }
    func saveBills(_ bills: [Bill]) async throws       { try await fallback.saveBills(bills) }
    func upsert(_ bill: Bill) async throws             { try await fallback.upsert(bill) }
    func softDelete(id: UUID) async throws             { try await fallback.softDelete(id: id) }
    func restore(id: UUID) async throws                { try await fallback.restore(id: id) }
    func delete(id: UUID) async throws                 { try await fallback.delete(id: id) }
    func deleteAll() async throws                      { try await fallback.deleteAll() }
}

#endif
