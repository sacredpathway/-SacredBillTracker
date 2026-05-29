//
//  BillStore.swift
//  SacredBillTracker
//
//  Main ObservableObject the UI observes. Reads / writes through a
//  BillRepository so the persistence backend can be swapped (Supabase etc.).
//

import Foundation
import SwiftUI

@MainActor
final class BillStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var bills: [Bill] = []
    @Published var filter: BillTypeFilter = .all
    @Published var isLoading: Bool = false

    // MARK: - Dependencies

    private let repository: BillRepository
    private let notifications: NotificationManager

    // MARK: - Init

    init(
        repository: BillRepository = LocalBillRepository(),
        notifications: NotificationManager? = nil
    ) {
        self.repository    = repository
        // `.shared` is @MainActor-isolated; resolving it here (inside a
        // @MainActor init body) is safe under Swift 6, but evaluating it
        // as a default parameter expression is not.
        self.notifications = notifications ?? NotificationManager.shared
        Task { await bootstrap() }
    }

    // MARK: - Bootstrapping

    /// Public re-trigger of initial load. Called after sign-in or a
    /// manual refresh.
    func reload() async {
        await bootstrap()
    }

    /// Replace the in-memory snapshot with an already-authoritative list
    /// (e.g. one returned from a successful remote refresh in the
    /// CachingBillRepository). Does NOT persist — the caller is
    /// expected to have already written to the repository.
    func replace(bills newBills: [Bill]) {
        self.bills = newBills
        Task { await notifications.rescheduleAll(for: newBills) }
    }

    private func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        // Hard guard: never load bills when there is no authenticated user.
        // This prevents any cached/stale local data from being shown to a
        // signed-out session, and guarantees the Bills tab is empty until
        // the user actually signs in. The signed-in path runs through
        // `handleUserChange` in `SacredBillTrackerApp` which calls
        // `replace(bills:)` with the remote, user-scoped list.
        guard AuthService.shared.currentUserID != nil else {
            self.bills = []
            await notifications.rescheduleAll(for: [])
            return
        }

        do {
            // Load whatever the authenticated user has saved. There is NO
            // auto-seed here. A brand-new account loads zero bills until
            // the user adds one. Demo data is DEBUG-only (see SampleData.swift)
            // and can only be invoked from the development reset action,
            // which itself is excluded from Release builds.
            let loaded = try await repository.loadBills()

            // Run the one-time legacy demo purge (v2 — actually deletes from
            // Supabase via repository.delete(id:), unlike the v1 attempt
            // that only upserted survivors).
            self.bills = await purgeLegacyDemoBillsIfNeeded(in: loaded)
        } catch {
            self.bills = []
        }

        await notifications.rescheduleAll(for: bills)
    }

    /// UserDefaults flag — set ONLY after the legacy demo cleanup has
    /// successfully deleted every demo row from BOTH local cache and
    /// Supabase. Bumped from v1 (which only stripped local) to v2.
    private static let didPurgeLegacyDemoKey = "SBT_didPurgeLegacyDemo_v2"

    // Signature + filter helpers live in `LegacyDemoBills.swift` so the
    // CachingBillRepository can also use them (pre-upload) and we don't
    // duplicate the demo definition in two places.

    /// Public, idempotent legacy demo cleanup. Returns the survivors.
    ///
    /// Unlike the v1 attempt — which only stripped demo bills from the
    /// local snapshot and called `saveBills(survivors)` (an UPSERT that
    /// left the demo rows alive on Supabase) — this version explicitly
    /// calls `repository.delete(id:)` on every demo bill it finds. Only
    /// flips the UserDefaults flag if every delete succeeded, so a
    /// network failure causes the cleanup to retry on next launch
    /// instead of being silently skipped forever.
    ///
    /// Called from two places:
    ///   - `bootstrap()` — covers the case where AuthService restores a
    ///     session before BillStore.init runs.
    ///   - `SacredBillTrackerApp.handleUserChange(_:)` — the primary
    ///     production path, runs after `refreshFromRemote()` so the
    ///     remote demo rows can be deleted.
    @discardableResult
    func purgeLegacyDemoBillsIfNeeded(in incoming: [Bill]) async -> [Bill] {
        // Already cleaned on this device — fast path. Still strip locally
        // in case a stale row slipped in from a different code path.
        if UserDefaults.standard.bool(forKey: Self.didPurgeLegacyDemoKey) {
            return LegacyDemoBills.filterOut(incoming)
        }

        let demoBills = incoming.filter { LegacyDemoBills.isLegacyDemo($0) }

        // Nothing to delete — flip the flag so we never run again.
        guard !demoBills.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.didPurgeLegacyDemoKey)
            return incoming
        }

        var allDeleted = true
        for bill in demoBills {
            do {
                try await repository.delete(id: bill.id)
            } catch {
                allDeleted = false
            }
        }

        // Only mark cleanup complete if every delete actually succeeded
        // on Supabase. Otherwise we'll retry on next launch — that's the
        // whole point of failing v1's "set the flag unconditionally" bug.
        if allDeleted {
            UserDefaults.standard.set(true, forKey: Self.didPurgeLegacyDemoKey)
        }

        return LegacyDemoBills.filterOut(incoming)
    }

    // MARK: - CRUD

    func add(_ bill: Bill) {
        var new = bill
        new.createdAt = Date()
        new.updatedAt = Date()
        bills.append(new)
        persist()
        Task { await notifications.scheduleReminder(for: new) }

        // Positive moment for the App Store review prompt — once the
        // user reaches 3+ bills they've clearly engaged with the app.
        // ReviewPromptService applies its own per-version + first-launch
        // throttle, so calling here is safe even on every add.
        if bills.count >= 3 {
            ReviewPromptService.shared.recordPositiveMoment()
        }
    }

    func update(_ bill: Bill) {
        guard let idx = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        var updated = bill
        updated.updatedAt = Date()
        bills[idx] = updated
        persist()
        notifications.cancelReminder(for: updated.id)
        if updated.status != .paid {
            Task { await notifications.scheduleReminder(for: updated) }
        }
    }

    func delete(_ bill: Bill) {
        // Remove from in-memory state first for instant UI feedback.
        bills.removeAll { $0.id == bill.id }
        notifications.cancelReminder(for: bill.id)

        // CRITICAL: deletion must call `repository.delete(id:)` directly,
        // NOT `persist()`. `repository.saveBills` is an UPSERT only — it
        // would write the surviving snapshot but leave the deleted row
        // alive on Supabase, and the next `refreshFromRemote()` would
        // resurrect it. v1.0's "deleted bills come back" bug was caused
        // by routing deletes through saveBills.
        let deletedID = bill.id
        Task { try? await repository.delete(id: deletedID) }
    }

    /// Writes the full in-memory snapshot via UPSERT. Used by `add` and
    /// `update` only — never for delete. See `delete(_:)` for why.
    private func persist() {
        let snapshot = bills
        Task { try? await repository.saveBills(snapshot) }
    }

    func delete(at offsets: IndexSet, from list: [Bill]) {
        let ids = offsets.map { list[$0].id }
        for id in ids {
            if let bill = bills.first(where: { $0.id == id }) {
                delete(bill)
            }
        }
    }

    func markPaid(_ bill: Bill) {
        var updated = bill
        updated.status = .paid
        updated.lastPaidDate = Date()
        update(updated)

        // Marking a bill paid is a clean positive moment — bill done,
        // user feels good, prime time for the system review prompt
        // (subject to ReviewPromptService's launch / version gates).
        ReviewPromptService.shared.recordPositiveMoment()

        // If recurring, auto-create the next occurrence as unpaid,
        // carrying the lastPaidDate forward so "Paid recently" stays true
        // for a week after payment.
        if updated.recurrence.isRecurring,
           let nextDate = updated.recurrence.nextDueDate(from: updated.dueDate) {
            let next = Bill(
                name: updated.name,
                amount: updated.amount,
                dueDate: nextDate,
                category: updated.category,
                recurrence: updated.recurrence,
                type: updated.type,
                autoPay: updated.autoPay,
                notes: updated.notes,
                status: .unpaid,
                lastPaidDate: updated.lastPaidDate
            )
            add(next)
        }
    }

    func markUnpaid(_ bill: Bill) {
        var updated = bill
        updated.status = .unpaid
        update(updated)
    }

    // MARK: - Filtering & queries

    var filteredBills: [Bill] {
        bills.filter { filter.matches($0.type) }
             .sorted  { $0.dueDate < $1.dueDate }
    }

    var dueToday: [Bill] {
        filteredBills.filter { $0.isDueToday && !$0.isPaid }
    }

    var dueThisWeek: [Bill] {
        filteredBills.filter { $0.isDueThisWeek && !$0.isPaid }
    }

    var overdue: [Bill] {
        filteredBills.filter { $0.isOverdue }
    }

    var upcoming: [Bill] {
        let today = Calendar.current.startOfDay(for: Date())
        return filteredBills.filter { !$0.isPaid && $0.dueDate >= today }
    }

    // MARK: - Totals

    func totalThisMonth(for type: BillType) -> Decimal {
        bills
            .filter { $0.type == type && $0.isDueThisMonth }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    func totalUnpaidThisMonth(for type: BillType) -> Decimal {
        bills
            .filter { $0.type == type && $0.isDueThisMonth && !$0.isPaid }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    func bills(on day: Date) -> [Bill] {
        let cal = Calendar.current
        return filteredBills.filter { cal.isDate($0.dueDate, inSameDayAs: day) }
    }

    func bills(in month: Date) -> [Bill] {
        let cal = Calendar.current
        return filteredBills.filter {
            cal.component(.month, from: $0.dueDate) == cal.component(.month, from: month) &&
            cal.component(.year,  from: $0.dueDate) == cal.component(.year,  from: month)
        }
    }

    /// Category breakdown for the given type in the given month.
    func categoryBreakdown(for type: BillType, in month: Date) -> [(category: BillCategory, total: Decimal)] {
        let cal = Calendar.current
        let filtered = bills.filter {
            $0.type == type
            && cal.component(.month, from: $0.dueDate) == cal.component(.month, from: month)
            && cal.component(.year,  from: $0.dueDate) == cal.component(.year,  from: month)
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.category })
        return grouped
            .map { (category: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Smart insights & forecast

    /// Top N bills needing attention (ordered by priority score, excludes paid).
    func priorityBills(limit: Int = 3) -> [Bill] {
        Array(filteredBills
            .filter { !$0.isPaid }
            .sorted { $0.priorityScore > $1.priorityScore }
            .prefix(limit))
    }

    /// Max unpaid amount in the active filter scope — used to flag
    /// "Highest amount" insights on bill rows.
    var maxUnpaidAmount: Decimal {
        filteredBills.filter { !$0.isPaid }.map(\.amount).max() ?? 0
    }

    /// Snapshot for the Cash Flow forecast card.
    struct CashFlow: Hashable {
        let dueThisMonth: Decimal
        let paidThisMonth: Decimal
        let remainingThisMonth: Decimal
        let nextSevenDays: Decimal
        let projectedLeftover: Decimal   // = -(remainingThisMonth). Negative = outflow.
        let unpaidCount: Int
    }

    func cashFlow() -> CashFlow {
        let scope = filteredBills.filter { $0.isDueThisMonth }
        let due  = scope.reduce(Decimal(0)) { $0 + $1.amount }
        let paid = scope.filter { $0.isPaid }.reduce(Decimal(0)) { $0 + $1.amount }
        let remaining = due - paid
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let next7 = filteredBills
            .filter { !$0.isPaid && $0.dueDate >= today && $0.dueDate < end }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let unpaidCount = scope.filter { !$0.isPaid }.count
        return CashFlow(
            dueThisMonth: due,
            paidThisMonth: paid,
            remainingThisMonth: remaining,
            nextSevenDays: next7,
            projectedLeftover: -remaining,
            unpaidCount: unpaidCount
        )
    }

    // MARK: - Risk flags

    struct RiskFlags: Hashable {
        var veryOverdueBills: [Bill]       // overdue by > 3 days
        var highAmountUnpaid: [Bill]       // top 25% unpaid by amount, not paid
        var clusterUpcoming: [Bill]        // 3+ due in next 7 days
        var hasAny: Bool {
            !veryOverdueBills.isEmpty || !highAmountUnpaid.isEmpty || !clusterUpcoming.isEmpty
        }
    }

    func riskFlags() -> RiskFlags {
        let veryOverdue = filteredBills.filter { $0.isOverdue && $0.daysOverdue > 3 }

        let unpaid = filteredBills.filter { !$0.isPaid }.sorted { $0.amount > $1.amount }
        let topQuartile = Int(Double(unpaid.count) * 0.25)
        let highAmount  = topQuartile > 0 ? Array(unpaid.prefix(topQuartile)) : []

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let next7 = filteredBills.filter {
            !$0.isPaid && $0.dueDate >= today && $0.dueDate < end
        }
        let cluster = next7.count >= 3 ? next7 : []

        return RiskFlags(
            veryOverdueBills: veryOverdue,
            highAmountUnpaid: highAmount,
            clusterUpcoming: cluster
        )
    }

    /// Duplicates a bill (next month's instance, unpaid, same everything).
    /// Used by the Quick Add "duplicate from existing" flow.
    @discardableResult
    func duplicate(_ bill: Bill) -> Bill {
        let cal = Calendar.current
        let nextDue = cal.date(byAdding: .month, value: 1, to: bill.dueDate) ?? bill.dueDate
        let copy = Bill(
            name: bill.name,
            amount: bill.amount,
            dueDate: nextDue,
            category: bill.category,
            recurrence: bill.recurrence,
            type: bill.type,
            autoPay: bill.autoPay,
            notes: bill.notes,
            status: .unpaid,
            lastPaidDate: bill.lastPaidDate
        )
        add(copy)
        return copy
    }

    // MARK: - Sample reset / wipe (used by Settings)

    #if DEBUG
    /// DEBUG-only: replace the user's bills with the SampleData fixtures.
    /// This function does not exist in Release / App Store builds — both
    /// the function body and the Settings entry that invokes it are
    /// compiled out, so production code cannot seed sample bills.
    ///
    /// Wipes existing bills FIRST (via `repository.deleteAll()`) so the
    /// new fixture set replaces — not merges with — whatever was there.
    /// `saveBills` is an UPSERT; without the wipe, old bills survive.
    func resetWithSampleData() {
        let fresh = SampleData.bills()
        bills = fresh
        Task {
            try? await repository.deleteAll()
            try? await repository.saveBills(fresh)
            await notifications.rescheduleAll(for: fresh)
        }
    }

    /// DEBUG-only: seed the App Store-screenshot bill set. Realistic
    /// user-style entries with amounts that DO NOT overlap the v1.0
    /// auto-seeded demo data, so they never trigger the legacy demo
    /// purge. Used to capture marketing screenshots of populated
    /// Dashboard / Bills / Calendar / Reports views from the simulator
    /// without the production app ever shipping mock data.
    func seedScreenshotBills() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func d(_ days: Int) -> Date {
            cal.date(byAdding: .day, value: days, to: today) ?? today
        }
        let seed: [Bill] = [
            Bill(name: "Rent",     amount: 1475.00, dueDate: d(5),
                 category: .rent,          recurrence: .monthly,
                 type: .household, autoPay: false, notes: "", status: .unpaid),
            Bill(name: "Internet", amount: 82.99,   dueDate: d(8),
                 category: .internet,      recurrence: .monthly,
                 type: .household, autoPay: true,  notes: "", status: .unpaid),
            Bill(name: "Phone",    amount: 91.20,   dueDate: d(12),
                 category: .phone,         recurrence: .monthly,
                 type: .household, autoPay: true,  notes: "", status: .unpaid),
            Bill(name: "Gym",      amount: 39.00,   dueDate: d(15),
                 category: .subscriptions, recurrence: .monthly,
                 type: .household, autoPay: true,  notes: "", status: .unpaid),
            Bill(name: "Software", amount: 29.99,   dueDate: d(2),
                 category: .software,      recurrence: .monthly,
                 type: .business,  autoPay: true,  notes: "", status: .unpaid),
        ]
        bills = seed
        Task {
            try? await repository.saveBills(bills)
            await notifications.rescheduleAll(for: bills)
        }
    }
    #endif

    func wipeAll() {
        bills = []
        Task {
            // CRITICAL: `saveBills([])` was a no-op on Supabase (its
            // empty-guard returned early). Wipe must use `deleteAll()`
            // so the rows actually disappear from the server, otherwise
            // the next `refreshFromRemote()` would bring them all back.
            try? await repository.deleteAll()
            await notifications.rescheduleAll(for: [])
        }
    }
}
