//
//  BillStore.swift
//  SacredBillTracker
//
//  Main ObservableObject the UI observes. Reads / writes through a
//  BillRepository so the persistence backend can be swapped (Supabase etc.).
//

import Foundation
import SwiftUI

struct MonthlyBillTotals: Hashable {
    let totalBills: Decimal
    let paid: Decimal
    let remaining: Decimal
    let pending: Decimal
    let overdue: Decimal
    let autoPayCount: Int
    let billCount: Int
    let paidCount: Int
    let unpaidCount: Int
}

enum BillTotalsCalculator {
    static func bills(
        from bills: [Bill],
        in month: Date = Date(),
        calendar: Calendar = .current
    ) -> [Bill] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        return bills.filter { bill in
            bill.deletedAt == nil
                && bill.dueDate >= interval.start
                && bill.dueDate < interval.end
        }
    }

    /// Single source of truth for the user's full monthly bill obligation.
    /// `totalBills` always sums original bill amounts due for the month;
    /// paid status, remaining balance, and Auto Pay never reduce it.
    static func monthlyTotals(
        from bills: [Bill],
        in month: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyBillTotals {
        let monthBills = self.bills(from: bills, in: month, calendar: calendar)
        let totalBills = monthBills.reduce(Decimal(0)) { $0 + $1.amount }
        let paid = monthBills
            .filter { $0.isPaid }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let overdue = monthBills
            .filter { $0.isOverdue }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let pending = monthBills
            .filter { !$0.isPaid && !$0.isOverdue }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let rawRemaining = totalBills - paid
        let remaining = rawRemaining > 0 ? rawRemaining : Decimal(0)

        return MonthlyBillTotals(
            totalBills: totalBills,
            paid: paid,
            remaining: remaining,
            pending: pending,
            overdue: overdue,
            autoPayCount: monthBills.filter { $0.autoPay }.count,
            billCount: monthBills.count,
            paidCount: monthBills.filter(\.isPaid).count,
            unpaidCount: monthBills.filter { !$0.isPaid }.count
        )
    }
}

@MainActor
final class BillStore: ObservableObject {

    // MARK: - Published state

    @Published private var storedBills: [Bill] = []
    @Published var filter: BillTypeFilter = .all
    @Published var isLoading: Bool = false
    @Published private var profileContext: ManagedProfileContext = ManagedProfileStore.shared.context

    /// Soft-deleted bills (Trash). Populated by `reloadTrash()`; the
    /// Trash screen is the only consumer.
    @Published private(set) var deletedBills: [Bill] = []
    @Published var isLoadingTrash: Bool = false

    /// v1.1 (Milestone 1) — set true for one render when the account's first
    /// bill is created, so the signed-in root view can present a one-time
    /// celebration. The presenter resets it to false after showing it.
    @Published var didCreateFirstBill: Bool = false

    /// Profile-scoped active bills. Existing views use this property,
    /// which keeps bills from different managed profiles separated unless
    /// the user explicitly selects All Profiles.
    var bills: [Bill] { profileBills }

    /// All loaded active bills across every managed profile. Use for
    /// account-wide sync, billing limits, and destructive account actions.
    var allStoredBills: [Bill] { storedBills }

    var profileBills: [Bill] {
        storedBills.filter {
            isOwnedByCurrentAccount($0)
            && profileContext.includes(profileID: $0.profileID)
        }
    }

    var profileDeletedBills: [Bill] {
        deletedBills.filter {
            isOwnedByCurrentAccount($0)
            && profileContext.includes(profileID: $0.profileID)
        }
    }

    func applyProfileContext(_ context: ManagedProfileContext) {
        guard profileContext != context else { return }
        profileContext = context
        BillWidgetBridge.update(from: profileBills)
    }

    private var activeStoredBills: [Bill] {
        storedBills.filter { $0.deletedAt == nil }
    }

    private func stampProfileIfNeeded(_ bill: inout Bill) {
        if bill.profileID == nil {
            bill.profileID = profileContext.writeProfileID
        }
    }

    private func isOwnedByCurrentAccount(_ bill: Bill) -> Bool {
        guard let owner = bill.ownerUserID,
              let currentUserID = AuthService.shared.currentUserID
        else { return true }
        return owner == currentUserID
    }

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
        self.storedBills = newBills
        Task { await notifications.rescheduleAll(for: activeStoredBills) }
        BillWidgetBridge.update(from: profileBills)
    }

    func resetForSignedOutUser() {
        storedBills = []
        deletedBills = []
        BillWidgetBridge.clearSnapshotAndReloadTimelines()
        Task { await notifications.rescheduleAll(for: []) }
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
            #if DEBUG
            // DEBUG ONLY: auto-seed sample bills so the simulator/dev runs
            // are never empty. Excluded from Release builds — production
            // signed-out users still see an empty Bills tab.
            var sample = SampleData.bills()
            for idx in sample.indices { stampProfileIfNeeded(&sample[idx]) }
            self.storedBills = sample
            await notifications.rescheduleAll(for: activeStoredBills)
            #else
            self.storedBills = []
            await notifications.rescheduleAll(for: [])
            BillWidgetBridge.clearSnapshotAndReloadTimelines()
            #endif
            return
        }

        do {
            // Load whatever the authenticated user has saved.
            let loaded = try await repository.loadBills()

            #if DEBUG
            // DEBUG ONLY: skip the legacy demo purge so dev/screenshot
            // sample data is never wiped from the simulator. If the
            // signed-in account has zero bills, auto-seed SampleData so
            // every dev launch shows a populated UI.
            if loaded.isEmpty {
                var seed = SampleData.bills()
                for idx in seed.indices { stampProfileIfNeeded(&seed[idx]) }
                self.storedBills = seed
                try? await repository.saveBills(seed)
            } else {
                self.storedBills = loaded
            }
            #else
            // Release: run the one-time legacy demo purge (v2 — actually
            // deletes from Supabase via repository.delete(id:), unlike
            // the v1 attempt that only upserted survivors).
            self.storedBills = await purgeLegacyDemoBillsIfNeeded(in: loaded)
            #endif
        } catch {
            self.storedBills = []
        }

        await notifications.rescheduleAll(for: activeStoredBills)
        BillWidgetBridge.update(from: profileBills)
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
        // v1.1 (Milestone 1) — capture whether this is the account's very
        // first bill BEFORE the append. `add(_:)` is the single choke point
        // for BOTH the template and start-from-scratch paths, so first-bill
        // detection lives here (no duplicated logic in the views).
        let isFirstBill = storedBills.isEmpty
        var new = bill
        stampProfileIfNeeded(&new)
        new.createdAt = Date()
        new.updatedAt = Date()
        settlePayoffIfPaid(&new)
        storedBills.append(new)
        persist()
        if isFirstBill {
            didCreateFirstBill = true
            AnalyticsService.shared.track(.firstBillCreated, source: "bill_store")
        }
        // Attribution: bill_created (no-op while AppsFlyer dormant).
        #if canImport(AppsFlyerLib)
        AppsFlyerManager.shared.logBillCreated()
        #endif
        if !new.isPaid {
            Task { await notifications.scheduleReminder(for: new) }
        }

        // Positive moment for the App Store review prompt — once the
        // user reaches 3+ bills they've clearly engaged with the app.
        // ReviewPromptService applies its own per-version + first-launch
        // throttle, so calling here is safe even on every add.
        if storedBills.count >= 3 {
            ReviewPromptService.shared.recordPositiveMoment()
        }
    }

    func update(_ bill: Bill) {
        guard let idx = storedBills.firstIndex(where: { $0.id == bill.id }) else { return }
        var updated = bill
        stampProfileIfNeeded(&updated)
        updated.updatedAt = Date()
        settlePayoffIfPaid(&updated)
        storedBills[idx] = updated
        persist()
        notifications.cancelReminder(for: updated.id)
        if !updated.isPaid {
            Task { await notifications.scheduleReminder(for: updated) }
        }
    }

    /// User-facing delete. Soft-deletes the bill (sets deleted_at) so
    /// it can be restored from the Trash screen. The bill disappears
    /// from the active list immediately, and any pending reminder is
    /// cancelled.
    ///
    /// Hard delete is intentionally NOT exposed here — `repository.delete`
    /// is reserved for system housekeeping (legacy demo purge / account
    /// wipe). Permanent purge of an individual bill is DEBUG-only and
    /// lives in `permanentlyDelete(_:)` below.
    func delete(_ bill: Bill) {
        // Remove from in-memory active state first for instant UI feedback.
        storedBills.removeAll { $0.id == bill.id }
        notifications.cancelReminder(for: bill.id)

        // Mirror in cached deletedBills so a Trash screen that's already
        // on screen reflects the soft-delete without needing an extra
        // network round-trip. Stamp deletedAt locally so the row sorts
        // correctly in Trash; the server's value will replace it on the
        // next `reloadTrash()`.
        var trashed = bill
        trashed.deletedAt = Date()
        trashed.updatedAt = Date()
        if !deletedBills.contains(where: { $0.id == bill.id }) {
            deletedBills.insert(trashed, at: 0)
        }

        let deletedID = bill.id
        Task { try? await repository.softDelete(id: deletedID) }
        BillWidgetBridge.update(from: profileBills)
    }

    /// Restore a soft-deleted bill back to the active list.
    func restore(_ bill: Bill) {
        deletedBills.removeAll { $0.id == bill.id }

        var revived = bill
        revived.deletedAt = nil
        revived.updatedAt = Date()
        settlePayoffIfPaid(&revived)
        stampProfileIfNeeded(&revived)
        if !storedBills.contains(where: { $0.id == bill.id }) {
            storedBills.append(revived)
        }
        if !revived.isPaid {
            Task { await notifications.scheduleReminder(for: revived) }
        }

        let restoreID = bill.id
        Task { try? await repository.restore(id: restoreID) }
        BillWidgetBridge.update(from: profileBills)
    }

    /// Refresh the Trash list from the repository. Call from TrashView
    /// `.task { await store.reloadTrash() }` and pull-to-refresh.
    func reloadTrash() async {
        isLoadingTrash = true
        defer { isLoadingTrash = false }
        do {
            self.deletedBills = try await repository.loadDeletedBills()
        } catch {
            // On failure, leave the existing snapshot in place so the
            // user keeps any locally-mirrored entries from `delete(_:)`.
        }
    }

    #if DEBUG
    /// DEBUG ONLY: permanently hard-delete a bill. Compiled out of
    /// Release builds so the App Store binary cannot ever bypass the
    /// soft-delete safety net. The Trash screen's "Delete Forever"
    /// button is gated behind the same `#if DEBUG`.
    func permanentlyDelete(_ bill: Bill) {
        deletedBills.removeAll { $0.id == bill.id }
        storedBills.removeAll { $0.id == bill.id }
        notifications.cancelReminder(for: bill.id)
        let id = bill.id
        Task { try? await repository.delete(id: id) }
    }
    #endif

    /// Writes the full in-memory snapshot via UPSERT. Used by `add` and
    /// `update` only — never for delete. See `delete(_:)` for why.
    private func persist() {
        let snapshot = storedBills
        Task { try? await repository.saveBills(snapshot) }
        // v1.6 — keep the Home Screen widget snapshot in sync after every
        // local mutation. Safe no-op if the App Group entitlement isn't
        // provisioned (e.g. older signed builds).
        BillWidgetBridge.update(from: profileBills)
    }

    private func settlePayoffIfPaid(_ bill: inout Bill) {
        guard bill.isPaid else { return }
        let kind: PayoffPaymentKind = bill.isAutoPaid ? .autoPay : .manual
        bill.applyPayoffPaymentIfNeeded(kind: kind)
    }

    func delete(at offsets: IndexSet, from list: [Bill]) {
        let ids = offsets.map { list[$0].id }
        for id in ids {
            if let bill = storedBills.first(where: { $0.id == id }) {
                delete(bill)
            }
        }
    }

    func markPaid(_ bill: Bill) {
        var updated = bill
        updated.status = .paid
        updated.lastPaidDate = Date()
        updated.applyPayoffPaymentIfNeeded(kind: updated.isAutoPaid ? .autoPay : .manual)
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
                lastPaidDate: updated.lastPaidDate,
                profileID: updated.profileID,
                isPayoffTrackingEnabled: updated.isPayoffTrackingEnabled,
                payoffOriginalBalance: updated.payoffOriginalBalance,
                payoffRemainingBalance: updated.payoffRemainingBalance,
                payoffPaymentAmount: updated.payoffPaymentAmount,
                payoffInterestRate: updated.payoffInterestRate,
                payoffGoalDate: updated.payoffGoalDate,
                payoffCategory: updated.payoffCategory,
                payoffHistory: updated.payoffHistory
            )
            add(next)
        }
    }

    func markUnpaid(_ bill: Bill) {
        var updated = bill
        updated.reversePayoffPaymentForCurrentCycle()
        updated.status = .unpaid
        // `isPaid` now keys off `.paid` status alone (see `Bill.isPaid`), so
        // clearing the status is enough to make the bill unpaid. Leave
        // `autoPay` untouched so marking a bill unpaid never silently wipes
        // the user's autopay setting.
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

    func monthlyTotals(
        in month: Date = Date(),
        for scope: BillTypeFilter = .all
    ) -> MonthlyBillTotals {
        BillTotalsCalculator.monthlyTotals(
            from: bills.filter { scope.matches($0.type) },
            in: month
        )
    }

    func totalThisMonth(for type: BillType) -> Decimal {
        monthlyTotals(for: filter(for: type)).totalBills
    }

    func totalUnpaidThisMonth(for type: BillType) -> Decimal {
        monthlyTotals(for: filter(for: type)).remaining
    }

    private func filter(for type: BillType) -> BillTypeFilter {
        switch type {
        case .household:
            return .household
        case .business:
            return .business
        }
    }

    // MARK: - Combined Totals (v1.3)
    //
    // These helpers ignore both `BillType` and the active `BillTypeFilter`,
    // returning aggregates across household + business. The Dashboard's
    // Combined Totals toggle (`@AppStorage("sbt.combinedTotals.v1")`)
    // chooses between these and the per-type variants above.

    /// All non-deleted bills, sorted by due date. Equivalent to
    /// `filteredBills` with `filter = .all`, regardless of the
    /// currently-selected `BillTypeFilter`.
    var allBills: [Bill] {
        bills.sorted { $0.dueDate < $1.dueDate }
    }

    var allDueToday: [Bill] {
        allBills.filter { $0.isDueToday && !$0.isPaid }
    }

    var allDueThisWeek: [Bill] {
        allBills.filter { $0.isDueThisWeek && !$0.isPaid }
    }

    var allOverdue: [Bill] {
        allBills.filter { $0.isOverdue }
    }

    var allUpcoming: [Bill] {
        let today = Calendar.current.startOfDay(for: Date())
        return allBills.filter { !$0.isPaid && $0.dueDate >= today }
    }

    /// Total due across both Personal AND Business bills this month.
    func combinedTotalThisMonth() -> Decimal {
        monthlyTotals().totalBills
    }

    /// Total UNPAID across both types this month.
    func combinedUnpaidThisMonth() -> Decimal {
        monthlyTotals().remaining
    }

    /// Total PAID across both types this month.
    func combinedPaidThisMonth() -> Decimal {
        monthlyTotals().paid
    }

    /// Sum of every overdue bill (no time limit), both types.
    func combinedOverdueTotal() -> Decimal {
        bills
            .filter { $0.isOverdue }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    struct PayoffSummary: Hashable {
        let trackedCount: Int
        let originalBalance: Decimal
        let paidDown: Decimal
        let remainingBalance: Decimal
        let monthlyPaymentAmount: Decimal

        var progress: Double {
            let original = (originalBalance as NSDecimalNumber).doubleValue
            guard original > 0 else { return 0 }
            let paid = (paidDown as NSDecimalNumber).doubleValue
            return min(max(paid / original, 0), 1)
        }
    }

    func payoffSummary(for scope: BillTypeFilter? = nil) -> PayoffSummary {
        let activeScope = scope ?? filter
        let tracked = latestPayoffSnapshots(
            in: bills.filter { bill in
                bill.isPayoffTrackingEnabled && activeScope.matches(bill.type)
            }
        )

        let original = tracked.reduce(Decimal(0)) { $0 + $1.payoffOriginalBalanceValue }
        let remaining = tracked.reduce(Decimal(0)) { $0 + $1.payoffRemainingBalanceValue }
        let paidDown = tracked.reduce(Decimal(0)) { $0 + $1.payoffPaidDown }
        let monthly = tracked.reduce(Decimal(0)) { $0 + $1.payoffEffectivePaymentAmount }

        return PayoffSummary(
            trackedCount: tracked.count,
            originalBalance: original,
            paidDown: paidDown,
            remainingBalance: remaining,
            monthlyPaymentAmount: monthly
        )
    }

    private func latestPayoffSnapshots(in bills: [Bill]) -> [Bill] {
        var byIdentity: [String: Bill] = [:]

        for bill in bills {
            let key = payoffIdentityKey(for: bill)
            if let existing = byIdentity[key] {
                if bill.dueDate > existing.dueDate
                    || (bill.dueDate == existing.dueDate && bill.updatedAt > existing.updatedAt) {
                    byIdentity[key] = bill
                }
            } else {
                byIdentity[key] = bill
            }
        }

        return Array(byIdentity.values)
    }

    private func payoffIdentityKey(for bill: Bill) -> String {
        let normalizedName = bill.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let original = NSDecimalNumber(decimal: bill.payoffOriginalBalanceValue).stringValue
        let category = bill.payoffCategory?.rawValue ?? "uncategorized"
        return "\(normalizedName)|\(bill.type.rawValue)|\(category)|\(original)"
    }

    func bills(on day: Date) -> [Bill] {
        let cal = Calendar.current
        return filteredBills.filter { cal.isDate($0.dueDate, inSameDayAs: day) }
    }

    func bills(in month: Date) -> [Bill] {
        BillTotalsCalculator.bills(from: filteredBills, in: month)
    }

    /// Category breakdown for the given type in the given month.
    func categoryBreakdown(for type: BillType, in month: Date) -> [(category: BillCategory, total: Decimal)] {
        let filtered = BillTotalsCalculator.bills(
            from: bills.filter { $0.type == type },
            in: month
        )
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
        let totals = BillTotalsCalculator.monthlyTotals(from: filteredBills)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let next7 = filteredBills
            .filter { !$0.isPaid && $0.dueDate >= today && $0.dueDate < end }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return CashFlow(
            dueThisMonth: totals.totalBills,
            paidThisMonth: totals.paid,
            remainingThisMonth: totals.remaining,
            nextSevenDays: next7,
            projectedLeftover: -totals.remaining,
            unpaidCount: totals.unpaidCount
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
            lastPaidDate: bill.lastPaidDate,
            profileID: bill.profileID,
            isPayoffTrackingEnabled: bill.isPayoffTrackingEnabled,
            payoffOriginalBalance: bill.payoffOriginalBalance,
            payoffRemainingBalance: bill.payoffRemainingBalance,
            payoffPaymentAmount: bill.payoffPaymentAmount,
            payoffInterestRate: bill.payoffInterestRate,
            payoffGoalDate: bill.payoffGoalDate,
            payoffCategory: bill.payoffCategory,
            payoffHistory: bill.payoffHistory
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
        var fresh = SampleData.bills()
        for idx in fresh.indices { stampProfileIfNeeded(&fresh[idx]) }
        storedBills = fresh
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
        var profiledSeed = seed
        for idx in profiledSeed.indices { stampProfileIfNeeded(&profiledSeed[idx]) }
        storedBills = profiledSeed
        Task {
            try? await repository.saveBills(profiledSeed)
            await notifications.rescheduleAll(for: profiledSeed)
        }
    }
    #endif

    func wipeAll() {
        storedBills = []
        BillWidgetBridge.clearSnapshotAndReloadTimelines()
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
