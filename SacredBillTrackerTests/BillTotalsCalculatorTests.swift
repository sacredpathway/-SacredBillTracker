//
//  BillTotalsCalculatorTests.swift
//  SacredBillTrackerTests
//
//  Regression lock for the "Total Bills goes to $0" bug.
//
//  Guarantees the Financial Overview baseline (`totalBills`) always
//  reflects the user's FULL monthly bill obligation and is NEVER reduced
//  by paid or auto-pay status. Only the separate paid / remaining /
//  pending / overdue values may change as bills are settled.
//
//  Pure-logic tests against `BillTotalsCalculator` — no UI, no store,
//  no async, no network. Fast and deterministic.
//
//  This file is a member of the `SacredBillTrackerTests` unit-test target
//  (host application: SacredBillTracker). Run with Xcode ▸ Product ▸ Test
//  (⌘U) or `xcodebuild test -scheme SacredBillTracker`.
//

import XCTest
@testable import SacredBillTracker

final class BillTotalsCalculatorTests: XCTestCase {

    // MARK: - Fixture

    /// Five bills due this month, mixed household/business.
    /// Amounts use `Decimal(string:)` so the expected sum is exact.
    private func makeBills() -> [Bill] {
        let due = Date() // in the current month → counted by monthlyTotals
        func d(_ s: String) -> Decimal { Decimal(string: s)! }
        return [
            Bill(name: "Rent",     amount: d("1475.00"), dueDate: due, category: .rent,          type: .household),
            Bill(name: "Internet", amount: d("82.99"),   dueDate: due, category: .internet,      type: .household),
            Bill(name: "Phone",    amount: d("91.20"),   dueDate: due, category: .phone,         type: .household),
            Bill(name: "Gym",      amount: d("39.00"),   dueDate: due, category: .subscriptions, type: .household),
            Bill(name: "Software", amount: d("29.99"),   dueDate: due, category: .software,      type: .business),
        ]
    }

    /// 1475.00 + 82.99 + 91.20 + 39.00 + 29.99
    private var expectedTotal: Decimal { Decimal(string: "1718.18")! }

    // MARK: - Baseline

    func test_totalBills_baseline_isFullObligation() {
        let t = BillTotalsCalculator.monthlyTotals(from: makeBills())
        XCTAssertEqual(t.totalBills, expectedTotal)
        XCTAssertEqual(t.remaining, expectedTotal, "Nothing paid yet → remaining equals total")
        XCTAssertEqual(t.paid, 0)
    }

    // MARK: - The bug: total must never collapse

    func test_totalBills_unchanged_whenEveryBillPaid() {
        let bills = makeBills().map { b -> Bill in var c = b; c.status = .paid; return c }
        let t = BillTotalsCalculator.monthlyTotals(from: bills)

        XCTAssertEqual(t.totalBills, expectedTotal, "Total Bills MUST stay full when every bill is paid")
        XCTAssertEqual(t.paid, expectedTotal)
        XCTAssertEqual(t.remaining, 0, "Remaining may go to zero — that part is correct")
    }

    func test_totalBills_unchanged_whenEveryBillAutoPay() {
        // Bills are due TODAY (not past due), so auto-pay has NOT drafted yet.
        // The full amount is still owed — this is the "counter drops to $0 the
        // moment I switch on autopay" bug the fix targets.
        let bills = makeBills().map { b -> Bill in var c = b; c.autoPay = true; return c }
        let t = BillTotalsCalculator.monthlyTotals(from: bills)

        XCTAssertEqual(t.totalBills, expectedTotal, "Total Bills MUST stay full when every bill is on autopay")
        XCTAssertEqual(t.paid, 0, "Auto-pay before the due date is NOT paid yet")
        XCTAssertEqual(t.remaining, expectedTotal, "Remaining MUST NOT collapse just because autopay is on")
    }

    func test_totalBills_unchanged_whenEveryBillAutoPayAndPaid() {
        let bills = makeBills().map { b -> Bill in
            var c = b; c.status = .paid; c.autoPay = true; return c
        }
        let t = BillTotalsCalculator.monthlyTotals(from: bills)

        XCTAssertEqual(t.totalBills, expectedTotal, "Total Bills MUST stay full when every bill is autopay AND paid")
        XCTAssertEqual(t.remaining, 0)
    }

    // MARK: - Partial settle: total holds, remaining shrinks

    func test_remaining_shrinks_butTotalHolds_whenSomePaid() {
        var bills = makeBills()
        bills[0].status = .paid           // pay the $1,475 rent
        let t = BillTotalsCalculator.monthlyTotals(from: bills)

        XCTAssertEqual(t.totalBills, expectedTotal, "Total is unaffected by partial payment")
        XCTAssertEqual(t.paid, Decimal(string: "1475.00")!)
        XCTAssertEqual(t.remaining, Decimal(string: "243.18")!) // 1718.18 - 1475.00
    }

    // MARK: - isPaid semantics (root cause guard)

    /// Root-cause guard: switching on auto-pay must NOT flip a bill to paid.
    /// Auto-pay is a scheduling flag, not proof the draft cleared, so the bill
    /// still counts toward `remaining` until it is actually confirmed paid.
    /// (Past its due date an unconfirmed autopay bill reads as overdue — see
    /// `test_autoPay_afterDueDate_unconfirmed_readsOverdue_notPaid`.)
    func test_autoPay_beforeDueDate_isNotPaid_totalAndRemainingBothCount() {
        var autoOnly = makeBills()[0]      // Rent, unpaid, due today
        XCTAssertFalse(autoOnly.isPaid)
        autoOnly.autoPay = true
        XCTAssertFalse(autoOnly.isPaid, "autopay before its due date is NOT paid")

        let t = BillTotalsCalculator.monthlyTotals(from: [autoOnly])
        XCTAssertEqual(t.totalBills, Decimal(string: "1475.00")!, "total counts it")
        XCTAssertEqual(t.paid, 0)
        XCTAssertEqual(t.remaining, Decimal(string: "1475.00")!, "and so does remaining, until it drafts")
    }

    // MARK: - Bill COUNT must never collapse
    //
    // The tests above lock the dollar total. These lock the *count* the
    // dashboard reports: every ACTIVE bill counts, regardless of paid or
    // auto-pay status. Soft-deleted (Trash) bills are the only exclusion.
    //
    // Dates are pinned to March 2026 in UTC and the anchor month is passed
    // explicitly, so these never depend on the wall clock or the local
    // time zone.

    private let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Anchor inside the fixture month — passed as `in:` so the window is fixed.
    private var marchAnchor: Date { date(2026, 3, 15) }

    /// Exactly three ACTIVE bills, all due in March 2026.
    /// 1850.00 + 642.50 + 91.20 = 2583.70
    private func makeThreeActiveBills() -> [Bill] {
        func d(_ s: String) -> Decimal { Decimal(string: s)! }
        return [
            Bill(name: "Truck Note", amount: d("1850.00"), dueDate: date(2026, 3, 1),
                 category: .transportation, type: .business),
            Bill(name: "Insurance",  amount: d("642.50"),  dueDate: date(2026, 3, 15),
                 category: .insurance,      type: .business),
            Bill(name: "Phone",      amount: d("91.20"),   dueDate: date(2026, 3, 28),
                 category: .phone,          type: .household),
        ]
    }

    private var expectedThreeBillTotal: Decimal { Decimal(string: "2583.70")! }

    func test_billCount_isThree_whenAllThreePaid() {
        let bills = makeThreeActiveBills().map { b -> Bill in var c = b; c.status = .paid; return c }
        let t = BillTotalsCalculator.monthlyTotals(from: bills, in: marchAnchor, calendar: gregorian)

        XCTAssertEqual(t.billCount, 3, "Total bill counter MUST be 3 when all three bills are paid")
        XCTAssertEqual(t.paidCount, 3)
        XCTAssertEqual(t.unpaidCount, 0)
        XCTAssertEqual(t.totalBills, expectedThreeBillTotal)
    }

    func test_billCount_isThree_whenAllThreeAutoPay() {
        let bills = makeThreeActiveBills().map { b -> Bill in var c = b; c.autoPay = true; return c }
        let t = BillTotalsCalculator.monthlyTotals(from: bills, in: marchAnchor, calendar: gregorian)

        XCTAssertEqual(t.billCount, 3, "Total bill counter MUST be 3 when all three bills are on autopay")
        XCTAssertEqual(t.autoPayCount, 3)
        XCTAssertEqual(t.totalBills, expectedThreeBillTotal)
    }

    /// The exact scenario from the bug report: three active bills, each one
    /// paid, on autopay, or both. The counter must read 3 — never 0.
    func test_billCount_isThree_whenMixedPaidAndAutoPay() {
        var bills = makeThreeActiveBills()
        bills[0].status  = .paid                          // paid
        bills[1].autoPay = true                           // autopay
        bills[2].status  = .paid                          // both
        bills[2].autoPay = true

        let t = BillTotalsCalculator.monthlyTotals(from: bills, in: marchAnchor, calendar: gregorian)

        XCTAssertEqual(t.billCount, 3, "Total bill counter MUST be 3, not 0")
        XCTAssertEqual(t.totalBills, expectedThreeBillTotal)
        XCTAssertEqual(t.unpaidCount, 1, "the autopay-only bill isn't confirmed paid, so it stays unpaid")
    }

    /// The counter is a *total*, not a due/overdue view. Every March 2026
    /// bill is in the past relative to "now", so each unpaid one is overdue.
    /// The count must still be 3.
    func test_billCount_independentOfDueAndOverdueFilters() {
        let t = BillTotalsCalculator.monthlyTotals(
            from: makeThreeActiveBills(), in: marchAnchor, calendar: gregorian
        )

        XCTAssertEqual(t.billCount, 3)
        XCTAssertEqual(t.unpaidCount, 3)
        XCTAssertEqual(t.totalBills, expectedThreeBillTotal, "Overdue bills still count toward the total")
    }

    /// Soft-deleted (Trash) bills are the ONLY bills excluded from the count.
    func test_billCount_excludesSoftDeletedBills() {
        var bills = makeThreeActiveBills()
        bills[2].deletedAt = Date()   // Phone → Trash

        let t = BillTotalsCalculator.monthlyTotals(from: bills, in: marchAnchor, calendar: gregorian)

        XCTAssertEqual(t.billCount, 2, "Soft-deleted bills drop out of the count")
        XCTAssertEqual(t.totalBills, Decimal(string: "2492.50")!) // 1850.00 + 642.50
    }

    // MARK: - Auto-pay is never proof of payment (Bug 4 money-bug fix)

    /// Far-FUTURE auto-pay bill: not drafted yet -> owed, never $0.
    func test_autoPay_beforeDueDate_countsAsRemaining_notPaid() {
        var bill = Bill(name: "Truck Note", amount: Decimal(string: "1850.00")!,
                        dueDate: date(2099, 6, 20), category: .transportation, type: .business)
        bill.autoPay = true
        XCTAssertFalse(bill.isPaid, "future autopay has not drafted")
        XCTAssertEqual(bill.effectiveStatus, .unpaid, "upcoming, not paid, not overdue")

        let t = BillTotalsCalculator.monthlyTotals(from: [bill], in: date(2099, 6, 15), calendar: gregorian)
        XCTAssertEqual(t.totalBills, Decimal(string: "1850.00")!)
        XCTAssertEqual(t.paid, 0)
        XCTAssertEqual(t.remaining, Decimal(string: "1850.00")!)
        XCTAssertEqual(t.pending, Decimal(string: "1850.00")!)
    }

    /// Far-PAST auto-pay bill that was never confirmed paid: auto-pay is not
    /// proof the draft cleared, so once it is past due it reads as OVERDUE and
    /// stays owed. This is the Bug 4 fix — a failed autopay draft can no longer
    /// hide as "paid".
    func test_autoPay_afterDueDate_unconfirmed_readsOverdue_notPaid() {
        var bill = Bill(name: "Truck Note", amount: Decimal(string: "1850.00")!,
                        dueDate: date(2020, 6, 15), category: .transportation, type: .business)
        bill.autoPay = true
        XCTAssertFalse(bill.isPaid, "autopay alone is never paid — only .paid status is")
        XCTAssertTrue(bill.isOverdue, "an unconfirmed autopay bill past its due date is overdue")
        XCTAssertEqual(bill.effectiveStatus, .overdue)

        let t = BillTotalsCalculator.monthlyTotals(from: [bill], in: date(2020, 6, 15), calendar: gregorian)
        XCTAssertEqual(t.totalBills, Decimal(string: "1850.00")!, "total still counts it")
        XCTAssertEqual(t.paid, 0, "nothing is paid until confirmed")
        XCTAssertEqual(t.overdue, Decimal(string: "1850.00")!, "it surfaces as overdue")
        XCTAssertEqual(t.remaining, Decimal(string: "1850.00")!, "still owed")
    }

    /// Bug 4 (money bug), aggregated: in a past month where two autopay bills
    /// were never confirmed paid and one was actually paid, the two unconfirmed
    /// drafts must land in `overdue` (never `paid`) and stay owed.
    func test_autoPay_unconfirmedPastDue_aggregateOverdue_notPaid() {
        var paid    = Bill(name: "Rent",  amount: Decimal(string: "1500.00")!,
                           dueDate: date(2020, 3, 5), category: .rent, type: .household)
        paid.status = .paid
        var autoA   = Bill(name: "Truck", amount: Decimal(string: "900.00")!,
                           dueDate: date(2020, 3, 10), category: .transportation, type: .business)
        autoA.autoPay = true             // never confirmed → draft failed
        var autoB   = Bill(name: "Insurance", amount: Decimal(string: "642.50")!,
                           dueDate: date(2020, 3, 20), category: .insurance, type: .business)
        autoB.autoPay = true             // never confirmed → draft failed

        let t = BillTotalsCalculator.monthlyTotals(
            from: [paid, autoA, autoB], in: date(2020, 3, 15), calendar: gregorian
        )
        XCTAssertEqual(t.totalBills, Decimal(string: "3042.50")!, "full obligation")
        XCTAssertEqual(t.paid, Decimal(string: "1500.00")!, "only the confirmed-paid bill counts as paid")
        XCTAssertEqual(t.overdue, Decimal(string: "1542.50")!, "both failed autopay drafts are overdue")
        XCTAssertEqual(t.remaining, Decimal(string: "1542.50")!, "and still owed")
        XCTAssertEqual(t.unpaidCount, 2)
        XCTAssertEqual(t.paidCount, 1)
    }

    // MARK: - Status matrix (unpaid / paid / overdue-paid / overdue-unpaid)

    func test_unpaidBill_countsTowardRemaining() {
        let bill = makeBills()[1]      // Internet 82.99, due today, unpaid
        XCTAssertFalse(bill.isPaid)
        let t = BillTotalsCalculator.monthlyTotals(from: [bill])
        XCTAssertEqual(t.paid, 0)
        XCTAssertEqual(t.remaining, Decimal(string: "82.99")!)
        XCTAssertEqual(t.unpaidCount, 1)
    }

    func test_paidBill_movesToPaid_totalHolds() {
        var bill = makeBills()[1]
        bill.status = .paid
        XCTAssertTrue(bill.isPaid)
        let t = BillTotalsCalculator.monthlyTotals(from: [bill])
        XCTAssertEqual(t.totalBills, Decimal(string: "82.99")!)
        XCTAssertEqual(t.paid, Decimal(string: "82.99")!)
        XCTAssertEqual(t.remaining, 0)
        XCTAssertEqual(t.paidCount, 1)
    }

    /// A bill paid LATE (past its due date) stays paid, never resurfaces overdue.
    func test_overduePaidBill_readsPaid_notOverdue() {
        var bill = Bill(name: "Insurance", amount: Decimal(string: "642.50")!,
                        dueDate: date(2020, 3, 1), category: .insurance, type: .business)
        bill.status = .paid
        XCTAssertTrue(bill.isPaid)
        XCTAssertFalse(bill.isOverdue)
        XCTAssertEqual(bill.effectiveStatus, .paid)

        let t = BillTotalsCalculator.monthlyTotals(from: [bill], in: date(2020, 3, 1), calendar: gregorian)
        XCTAssertEqual(t.overdue, 0, "a paid bill is never overdue, even if paid late")
        XCTAssertEqual(t.paid, Decimal(string: "642.50")!)
        XCTAssertEqual(t.remaining, 0)
    }

    /// A non-autopay unpaid bill past its due date IS overdue and still owed.
    func test_overdueUnpaidBill_readsOverdue_andCountsRemaining() {
        let bill = Bill(name: "Insurance", amount: Decimal(string: "642.50")!,
                        dueDate: date(2020, 3, 1), category: .insurance, type: .business)
        XCTAssertFalse(bill.isPaid)
        XCTAssertTrue(bill.isOverdue)
        XCTAssertEqual(bill.effectiveStatus, .overdue)

        let t = BillTotalsCalculator.monthlyTotals(from: [bill], in: date(2020, 3, 1), calendar: gregorian)
        XCTAssertEqual(t.overdue, Decimal(string: "642.50")!)
        XCTAssertEqual(t.paid, 0)
        XCTAssertEqual(t.remaining, Decimal(string: "642.50")!, "overdue bills are still owed")
    }

    // MARK: - Recurring

    /// Recurrence never changes the money math for a month: a recurring bill
    /// counts exactly like a one-off in its due month, and rolls forward.
    func test_recurringBill_countsLikeAnyBill_andRollsForward() {
        let bill = makeThreeActiveBills()[0]   // Truck Note 1850, .monthly by default
        XCTAssertTrue(bill.isRecurring)
        let t = BillTotalsCalculator.monthlyTotals(from: [bill], in: marchAnchor, calendar: gregorian)
        XCTAssertEqual(t.totalBills, Decimal(string: "1850.00")!)
        XCTAssertEqual(t.billCount, 1)

        let next = bill.recurrence.nextDueDate(from: bill.dueDate, calendar: gregorian)
        let expectedNext: Date? = date(2026, 4, 1)
        XCTAssertEqual(next, expectedNext, "monthly recurrence advances one month")
    }

    // MARK: - Dashboard totals & remaining balance (mixed realistic month)

    /// One paid, one autopay-not-yet-drafted, one plain unpaid. The dashboard
    /// total holds; paid reflects only the settled bill; remaining reflects
    /// the two unsettled ones. This is the end-to-end shape of the fix.
    func test_dashboardTotals_mixedMonth_remainingNeverCollapses() {
        func d(_ s: String) -> Decimal { Decimal(string: s)! }
        var paid    = Bill(name: "Rent",  amount: d("1500.00"), dueDate: date(2099, 6, 10),
                           category: .rent, type: .household)
        paid.status = .paid
        var autopay = Bill(name: "Truck", amount: d("900.00"),  dueDate: date(2099, 6, 20),
                           category: .transportation, type: .business)
        autopay.autoPay = true                                   // future -> not drafted
        let unpaid  = Bill(name: "Phone", amount: d("100.00"),  dueDate: date(2099, 6, 25),
                           category: .phone, type: .household)

        let t = BillTotalsCalculator.monthlyTotals(from: [paid, autopay, unpaid],
                                                   in: date(2099, 6, 15), calendar: gregorian)
        XCTAssertEqual(t.totalBills, d("2500.00"), "full obligation never collapses")
        XCTAssertEqual(t.paid, d("1500.00"), "only the actually-paid bill counts as paid")
        XCTAssertEqual(t.remaining, d("1000.00"), "autopay-not-drafted (900) + unpaid (100) still owed")
        XCTAssertEqual(t.pending, d("1000.00"))
        XCTAssertEqual(t.billCount, 3)
        XCTAssertEqual(t.paidCount, 1)
        XCTAssertEqual(t.unpaidCount, 2)
    }

    // MARK: - Widget totals parity

    /// The Home-Screen widget lists bills where `!isPaid`. An undrafted autopay
    /// bill must appear (so the widget total isn't $0); a settled one drops off.
    /// Mirrors `BillWidgetBridge`'s core filter without its App Group side-effect.
    func test_widgetUpcomingFilter_includesUndraftedAutoPay() {
        var undrafted = Bill(name: "Truck", amount: Decimal(string: "900.00")!,
                             dueDate: date(2099, 6, 20), category: .transportation, type: .business)
        undrafted.autoPay = true
        var settled = Bill(name: "Rent", amount: Decimal(string: "1500.00")!,
                           dueDate: date(2099, 6, 10), category: .rent, type: .household)
        settled.status = .paid

        let widgetVisible = [undrafted, settled].filter { $0.deletedAt == nil && !$0.isPaid }
        XCTAssertEqual(widgetVisible.map(\.name), ["Truck"], "undrafted autopay shows; paid drops off")
        let widgetTotal = widgetVisible.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(widgetTotal, Decimal(string: "900.00")!, "widget total reflects what's owed, not $0")
    }

    // MARK: - Out-of-month exclusion (requirement 7)

    /// Bills due in a DIFFERENT month must never leak into the active month's
    /// total or count — even when they are on auto-pay. Anchored to March 2026,
    /// a February and an April auto-pay bill are both excluded; only the single
    /// March bill remains.
    func test_billsOutsideActiveMonth_areExcluded_evenOnAutoPay() {
        func d(_ s: String) -> Decimal { Decimal(string: s)! }
        var feb = Bill(name: "Feb Rent", amount: d("500.00"), dueDate: date(2026, 2, 20),
                       category: .rent, type: .household)
        feb.autoPay = true
        let march = Bill(name: "March Phone", amount: d("100.00"), dueDate: date(2026, 3, 15),
                         category: .phone, type: .household)
        var apr = Bill(name: "Apr Truck", amount: d("700.00"), dueDate: date(2026, 4, 3),
                       category: .transportation, type: .business)
        apr.autoPay = true

        let t = BillTotalsCalculator.monthlyTotals(
            from: [feb, march, apr], in: marchAnchor, calendar: gregorian
        )
        XCTAssertEqual(t.billCount, 1, "only the March bill is in the active month")
        XCTAssertEqual(t.totalBills, d("100.00"), "Feb & Apr bills are excluded from the monthly total")
        XCTAssertEqual(t.remaining, d("100.00"), "and from remaining")
        XCTAssertEqual(t.autoPayCount, 0, "the excluded bills' auto-pay flags don't leak in either")
    }

    // MARK: - Dashboard <-> Widget parity (requirement 8)

    /// The dashboard's baseline (`BillTotalsCalculator.monthlyTotals`) and the
    /// Home-Screen widget's `monthlyTotal` (`BillWidgetBridge.makeSnapshot`) are
    /// produced by two different code paths. For the same bills — including the
    /// all-auto-pay case that used to collapse to $0 — both surfaces MUST report
    /// the identical, non-zero monthly total, and every undrafted auto-pay bill
    /// must remain visible to the widget.
    func test_dashboardAndWidgetTotals_match_whenAllAutoPay() {
        let now = Date() // makeBills() are due "now", so both anchor to this month
        let bills = makeBills().map { b -> Bill in var c = b; c.autoPay = true; return c }

        let dashboardTotal = BillTotalsCalculator.monthlyTotals(from: bills).totalBills
        let snapshot = BillWidgetBridge.makeSnapshot(from: bills, now: now)

        XCTAssertEqual(dashboardTotal, expectedTotal, "dashboard baseline holds under all-auto-pay")
        XCTAssertEqual(snapshot.monthlyTotal, (expectedTotal as NSDecimalNumber).doubleValue,
                       accuracy: 0.001, "widget monthlyTotal matches the dashboard and is not $0")
        XCTAssertEqual(snapshot.upcoming.count, bills.count,
                       "all undrafted auto-pay bills stay visible to the widget")
    }

}
