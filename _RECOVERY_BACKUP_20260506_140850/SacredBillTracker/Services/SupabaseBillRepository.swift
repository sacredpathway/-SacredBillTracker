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
//      updated_at    timestamptz not null default now()
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
            updatedAt: updated_at
        )
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

    func loadBills() async throws -> [Bill] {
        let userID = try await currentUserID()
        let rows: [BillRow] = try await client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("due_date", ascending: true)
            .execute()
            .value
        return rows.compactMap { $0.toBill() }
    }

    func saveBills(_ bills: [Bill]) async throws {
        guard !bills.isEmpty else { return }
        let userID = try await currentUserID()
        let rows = bills.map { BillRow(bill: $0, userID: userID) }
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

    func delete(id: UUID) async throws {
        // Scope by user_id as well as id. RLS already prevents cross-user
        // deletes server-side, but adding the explicit filter makes the
        // intent obvious and survives any future RLS policy changes.
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

    func loadBills() async throws -> [Bill]       { try await fallback.loadBills() }
    func saveBills(_ bills: [Bill]) async throws  { try await fallback.saveBills(bills) }
    func upsert(_ bill: Bill) async throws        { try await fallback.upsert(bill) }
    func delete(id: UUID) async throws            { try await fallback.delete(id: id) }
    func deleteAll() async throws                 { try await fallback.deleteAll() }
}

#endif
