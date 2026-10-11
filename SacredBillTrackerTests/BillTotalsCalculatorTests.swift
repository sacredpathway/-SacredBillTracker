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
import PDFKit
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

    // MARK: - Smart Upcoming Bills

    func test_upcomingTotals_respect7And30DayInclusiveBoundaries() {
        let now = date(2026, 3, 10)
        let bills = [
            Bill(name: "Today", amount: 10, dueDate: date(2026, 3, 10), category: .other, type: .household),
            Bill(name: "Day 7", amount: 70, dueDate: date(2026, 3, 17), category: .other, type: .household),
            Bill(name: "Day 8", amount: 8, dueDate: date(2026, 3, 18), category: .other, type: .household),
            Bill(name: "Day 30", amount: 30, dueDate: date(2026, 4, 9), category: .other, type: .household),
            Bill(name: "Day 31", amount: 31, dueDate: date(2026, 4, 10), category: .other, type: .household),
            Bill(name: "Overdue", amount: 99, dueDate: date(2026, 3, 9), category: .other, type: .household)
        ]

        let totals = BillTotalsCalculator.upcomingTotals(from: bills, now: now, calendar: gregorian)
        XCTAssertEqual(totals.dueNext7Days, 80)
        XCTAssertEqual(totals.dueNext30Days, 118)
    }

    func test_upcomingTotals_excludePaidAndDeletedBills() {
        let now = date(2026, 3, 10)
        var paid = Bill(name: "Paid", amount: 50, dueDate: date(2026, 3, 11), category: .other, type: .household)
        paid.status = .paid
        var deleted = Bill(name: "Deleted", amount: 75, dueDate: date(2026, 3, 12), category: .other, type: .household)
        deleted.deletedAt = now
        let unpaid = Bill(name: "Unpaid", amount: 25, dueDate: date(2026, 3, 13), category: .other, type: .household)

        let totals = BillTotalsCalculator.upcomingTotals(from: [paid, deleted, unpaid], now: now, calendar: gregorian)
        XCTAssertEqual(totals.dueNext7Days, 25)
        XCTAssertEqual(totals.dueNext30Days, 25)
    }

    func test_markingPaidImmediatelyRemovesBillFromUpcomingTotals() {
        let now = date(2026, 3, 10)
        let bill = Bill(name: "Phone", amount: 90, dueDate: date(2026, 3, 12), category: .phone, type: .household)
        let paid = BillPaymentTransition.markingPaid(bill, at: now)

        XCTAssertTrue(paid.isPaid)
        XCTAssertEqual(paid.lastPaidDate, now)
        XCTAssertEqual(BillTotalsCalculator.upcomingTotals(from: [paid], now: now, calendar: gregorian).dueNext7Days, 0)
    }

    func test_overdueDetectionUsesCalendarDaysAndNeverMarksPaidOverdue() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        var bill = Bill(name: "Insurance", amount: 100, dueDate: yesterday, category: .insurance, type: .household)
        XCTAssertTrue(bill.isOverdue)
        XCTAssertGreaterThanOrEqual(bill.daysOverdue, 3)
        bill.status = .paid
        XCTAssertFalse(bill.isOverdue)
        XCTAssertEqual(bill.effectiveStatus, .paid)
    }

    func test_reminderPlannerSupportsRequiredLeadTimesAndNoPastRequests() {
        let now = date(2026, 3, 10)
        let due = date(2026, 3, 20)
        for days in BillReminderPlanner.allowedLeadTimeDays {
            let trigger = BillReminderPlanner.triggerDate(
                dueDate: due, leadTimeDays: days, now: now, calendar: gregorian
            )
            XCTAssertNotNil(trigger, "\(days)-day reminder should schedule")
        }
        XCTAssertNil(BillReminderPlanner.triggerDate(
            dueDate: date(2026, 3, 9), leadTimeDays: 0, now: now, calendar: gregorian
        ))
    }

    func test_reminderIdentifiersPreventDuplicatesAndCancelEveryBillReminder() {
        let id = UUID()
        XCTAssertEqual(
            BillReminderPlanner.reminderIdentifier(for: id),
            BillReminderPlanner.reminderIdentifier(for: id),
            "rescheduling uses the same identifier and replaces the pending request"
        )
        let cancellationIDs = BillReminderPlanner.cancellationIdentifiers(for: id)
        XCTAssertEqual(cancellationIDs.count, 3)
        XCTAssertTrue(cancellationIDs.contains(id.uuidString), "paid/deleted bills cancel the standard reminder")
        XCTAssertTrue(cancellationIDs.contains(PaydownPlanService.NotificationKey.firstID(for: id)))
        XCTAssertTrue(cancellationIDs.contains(PaydownPlanService.NotificationKey.secondID(for: id)))
    }

    // MARK: - Professional PDF sharing

    private func pdfBill(_ name: String = "Electric & Water", amount: Decimal = 125,
                         due: Date? = nil, paid: Bool = false, notes: String = "") -> Bill {
        var bill = Bill(name: name, amount: amount, dueDate: due ?? date(2026, 9, 15),
                        category: .utilities, recurrence: .monthly, type: .household, notes: notes)
        if paid { bill.status = .paid }
        return bill
    }

    func test_singleBillPDFExistsIsNonEmptyAndParseable() throws {
        let report = try BillShareService.generatePDF(bills: [pdfBill()], generatedAt: date(2026, 9, 5))
        let data = try Data(contentsOf: report.url)
        XCTAssertGreaterThan(data.count, 1_000)
        let document = PDFDocument(url: report.url)
        XCTAssertNotNil(document)
        XCTAssertEqual(document?.pageCount, 1)
        XCTAssertTrue(document?.string?.contains("Bill Details Report") == true)
    }

    func test_multiBillPDFContainsSummaryAndCorrectTotals() throws {
        let bills = [pdfBill("Rent", amount: 1_400), pdfBill("Phone", amount: 100, paid: true)]
        let report = try BillShareService.generatePDF(bills: bills, generatedAt: date(2026, 9, 5))
        let text = PDFDocument(url: report.url)?.string ?? ""
        XCTAssertTrue(text.contains("Financial Summary Report"))
        XCTAssertTrue(text.contains("$1,500.00"))
        XCTAssertTrue(text.contains("$100.00"))
        XCTAssertTrue(text.contains("$1,400.00"))
    }

    func test_pdfMetricsOverdueAndUpcomingWindows() {
        let now = date(2026, 9, 5)
        let bills = [pdfBill("Late", amount: 50, due: date(2026, 9, 2)),
                     pdfBill("Week", amount: 75, due: date(2026, 9, 12)),
                     pdfBill("Month", amount: 125, due: date(2026, 10, 5)),
                     pdfBill("Paid", amount: 20, due: date(2026, 9, 6), paid: true)]
        let metrics = BillShareService.metrics(for: bills, generatedAt: now, calendar: gregorian)
        XCTAssertEqual(metrics.overdueAmount, 50)
        XCTAssertEqual(metrics.overdueCount, 1)
        XCTAssertEqual(metrics.dueNext7Days, 75)
        XCTAssertEqual(metrics.dueNext30Days, 200)
        XCTAssertEqual(metrics.totalPaid, 20)
        XCTAssertEqual(metrics.totalUnpaid, 250)
    }

    func test_pdfCategoryTotals() {
        var rent = pdfBill("Rent", amount: 900); rent.category = .rent
        var power = pdfBill("Power", amount: 100); power.category = .utilities
        var water = pdfBill("Water", amount: 50); water.category = .utilities
        let categories = BillShareService.metrics(for: [rent, power, water]).categoryTotals
        XCTAssertEqual(categories.first(where: { $0.name == "Utilities" })?.amount, 150)
        XCTAssertEqual(categories.first(where: { $0.name == "Rent" })?.amount, 900)
    }

    func test_pdfOmitsEmptyOptionalFields() throws {
        let report = try BillShareService.generatePDF(bills: [pdfBill(notes: "")])
        let text = PDFDocument(url: report.url)?.string ?? ""
        XCTAssertFalse(text.contains("Original amount"))
        XCTAssertFalse(text.contains("Remaining balance"))
        XCTAssertFalse(text.contains("Notes\n"))
    }

    func test_pdfLongNotesWrapAndRemainParseable() throws {
        let note = Array(repeating: "This is a detailed payment arrangement with clear terms and context.", count: 80).joined(separator: " ")
        let report = try BillShareService.generatePDF(bills: [pdfBill(notes: note)], note: note)
        let document = PDFDocument(url: report.url)
        XCTAssertNotNil(document)
        XCTAssertGreaterThan(document?.pageCount ?? 0, 1)
        XCTAssertTrue(document?.string?.contains("detailed payment arrangement") == true)
    }

    func test_largeBillPDFSpansMultiplePages() throws {
        let bills = (1...60).map { pdfBill("Bill \($0)", amount: Decimal($0)) }
        let report = try BillShareService.generatePDF(bills: bills)
        XCTAssertGreaterThan(PDFDocument(url: report.url)?.pageCount ?? 0, 1)
    }

    func test_filenameIsHumanReadableAndSanitized() {
        let name = BillShareService.filename(for: [pdfBill("José's Phone / Internet #1")], generatedAt: date(2026, 9, 5))
        XCTAssertEqual(name, "Sacred-Bill-Tracker-Joses-Phone-Internet-1-September-2026.pdf")
        XCTAssertFalse(name.contains("/"))
    }

    func test_accountReferenceMasking() {
        XCTAssertEqual(BillShareService.maskedReference("Account 1234 5678 4821"), "•••• 4821")
        XCTAssertNil(BillShareService.maskedReference("   "))
    }

    func test_specialCharactersInBillNameGenerateValidPDF() throws {
        let report = try BillShareService.generatePDF(bills: [pdfBill("Niño's Café — Rent & Wi-Fi 📶")])
        XCTAssertNotNil(PDFDocument(url: report.url))
        XCTAssertGreaterThan((try Data(contentsOf: report.url)).count, 1_000)
    }

    func test_emptyBillListFailsGracefully() {
        XCTAssertThrowsError(try BillShareService.generatePDF(bills: []))
    }

}


final class FinancialEducationTests: XCTestCase {
    func testLibraryUniqueAndComplete() {
        XCTAssertEqual(FinancialEducation.all.count, 155)
        XCTAssertEqual(Set(FinancialEducation.all.map(\.id)).count, 155)
        XCTAssertEqual(Set(FinancialEducation.all.map(\.text)).count, 155)
        XCTAssertEqual(FinancialEducation.categories.count, 31)
        XCTAssertTrue(FinancialEducation.all.allSatisfy { !$0.text.isEmpty && $0.text.count < 350 })
    }
    func testDeterministicRotationAndWrap() {
        XCTAssertEqual(FinancialEducation.lesson(day: 0), FinancialEducation.lesson(day: 155))
        XCTAssertNotEqual(FinancialEducation.lesson(day: 0), FinancialEducation.lesson(day: 1))
        XCTAssertEqual(FinancialEducation.lesson(day: -1), FinancialEducation.all.last)
    }
    func testCategorySelectionDoesNotRequireFinancialRecords() {
        for day in -5...160 {
            XCTAssertEqual(FinancialEducation.lesson(day: day, category: "Bills & Due Dates").category, "Bills & Due Dates")
        }
        XCTAssertEqual(FinancialEducation.lesson(day: 0, category: "unknown"), FinancialEducation.lesson(day: 0))
    }
    func testSharingOnlyStaticLessonFields() {
        for lesson in FinancialEducation.all {
            XCTAssertEqual(lesson.shareText, "Financial Education\nSacred Bill Tracker\n\n" + lesson.category + "\n" + lesson.text)
        }
    }
    func testNoOldQuoteTextOrAdvicePromise() {
        XCTAssertFalse(FinancialEducation.all.contains { $0.text.contains("Discipline beats motivation") })
        XCTAssertTrue(FinancialEducation.disclosure.contains("does not provide personalized"))
    }
}


final class NextBuildIntegrationTests: XCTestCase {
    func test_accountOriginRejectsInsecureAndCredentialURLs() {
        for raw in ["http://example.com", "https://user:password@example.com", "https://example.com?token=x", "https://example.com/#secret", "https://example.com/arbitrary"] {
            XCTAssertNil(SBTAccountConnection.approvedOrigin(raw))
        }
        XCTAssertNil(SBTAccountConnection.approvedOrigin("https://example.com"))
        XCTAssertNotNil(SBTAccountConnection.approvedOrigin(SBTAccountConnection.sandboxAccountBase))
    }
    func test_essentialDoesNotUnlockUnlimited() {
        XCTAssertEqual(PlanTier.from(productID: "essential_monthly_499"), .essential)
        XCTAssertLessThan(PlanTier.from(productID: "essential_monthly_499"), .unlimited)
        XCTAssertEqual(PlanTier.from(productID: "unlimited_monthly_1499"), .unlimited)
    }
    func test_analyticsDropsFreeformPIIAndFinancialDimensions() {
        let d = AnalyticsPrivacy.dimensions(tier: "income:1000", source: "qa@example.invalid")
        XCTAssertNil(d.tier); XCTAssertNil(d.source)
        XCTAssertEqual(AnalyticsPrivacy.dimensions(tier: "essential", source: "education").source, "education")
    }
    func test_unknownProductNeverGrantsTier() {
        XCTAssertEqual(PlanTier.from(productID: "SAVE20"), .free)
        XCTAssertEqual(PlanTier.from(productID: "lifetime_premium_v1"), .free)
    }
    private func snapshot(_ changes: [String: Any] = [:]) throws -> SBTAccountSnapshot {
        var value: [String: Any] = ["account": "00000000-0000-0000-0000-000000000001", "environment": "sandbox",
            "offers_enabled": false, "marketing": ["state": "not_enrolled", "suppressed": false, "production_sending_enabled": false]]
        changes.forEach { value[$0.key] = $0.value }
        return try JSONDecoder().decode(SBTAccountSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func test_snapshotRejectsWrongAccount() throws {
        XCTAssertFalse(try snapshot().validate(owner: UUID()))
    }
    func test_snapshotRejectsProductionEnvironmentAndEnabledOffers() throws {
        let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        XCTAssertTrue(try snapshot().validate(owner: owner))
        XCTAssertFalse(try snapshot(["environment": "production"]).validate(owner: owner))
        XCTAssertFalse(try snapshot(["offers_enabled": true]).validate(owner: owner))
        XCTAssertFalse(try snapshot(["marketing": ["state":"confirmed", "suppressed":false, "production_sending_enabled":true]]).validate(owner: owner))
    }
    func test_lifetimePreservesTierAndRejectsPlatformPromotion() {
        let v = SBTLifetimeSnapshot(entitlement_id: "lifetime_premium_v1", environment: "sandbox", scope: "staging-premium-only", platform: "apple", product: "essential_monthly_499", tier: "essential", version: 1)
        XCTAssertTrue(v.isValidSandboxContract)
        let promoted = SBTLifetimeSnapshot(entitlement_id: v.entitlement_id, environment: v.environment, scope: v.scope, platform: v.platform, product: v.product, tier: "unlimited", version: 1)
        XCTAssertFalse(promoted.isValidSandboxContract)
        let production = SBTLifetimeSnapshot(entitlement_id: v.entitlement_id, environment: "production", scope: v.scope, platform: v.platform, product: v.product, tier: v.tier, version: 1)
        XCTAssertFalse(production.isValidSandboxContract)
    }
}

final class SandboxRecoveryContractTests: XCTestCase {
    @MainActor func test_appleVerificationPayloadPreservesTransactionAndAddsPlatform() {
        let payload = SBTAccountIntegration.appleVerificationPayload(originalTransactionID: "123456789")
        XCTAssertEqual(payload, ["original_transaction_id": "123456789", "platform": "apple"])
    }

    func test_subscriptionExpiryAndTierIsolation() {
        let item = SBTSubscriptionSnapshot(original_transaction_id: "123", product: "essential_monthly_499", active: true, revoked: false, expires_at: "2030-01-01T00:00:00Z", environment: "sandbox")
        XCTAssertEqual(item.tier(at: Date(timeIntervalSince1970: 1000)), .essential)
        XCTAssertEqual(item.tier(at: Date(timeIntervalSince1970: 2000000000)), .free)
    }
    func test_refundUnknownProductAndProductionCannotGrant() {
        for (product, revoked, environment) in [("essential_monthly_499", true, "sandbox"), ("SAVE20", false, "sandbox"), ("unlimited_monthly_1499", false, "production"), ("lifetime_premium_v1", false, "sandbox")] {
            let item = SBTSubscriptionSnapshot(original_transaction_id: "123", product: product, active: true, revoked: revoked, expires_at: "2030-01-01T00:00:00Z", environment: environment)
            XCTAssertFalse(item.isValidSandboxContract)
            XCTAssertEqual(item.tier(at: Date(timeIntervalSince1970: 1000)), .free)
        }
    }
    func test_bearerPreflightNeverForwardsProductionOrOtherOwner() throws {
        let owner = UUID()
        func fixture(_ issuer: String, _ subject: UUID) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["iss": issuer, "aud": "authenticated", "sub": subject.uuidString, "exp": 2000000000])
            return "fixture." + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") + ".not-a-signature"
        }
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(SBTAccountConnection.permitsSandboxBearer(try fixture(SBTAccountConnection.sandboxAuthIssuer, owner), owner: owner, now: now))
        XCTAssertFalse(SBTAccountConnection.permitsSandboxBearer(try fixture("https://zziauybwemoiqfpidiur.supabase.co/auth/v1", owner), owner: owner, now: now))
        XCTAssertFalse(SBTAccountConnection.permitsSandboxBearer(try fixture(SBTAccountConnection.sandboxAuthIssuer, UUID()), owner: owner, now: now))
        XCTAssertFalse(SBTAccountConnection.permitsSandboxBearer("malformed", owner: owner))
    }
    @MainActor func test_logoutDropsSandboxRecoveryState() {
        let integration = SBTAccountIntegration()
        integration.clear()
        XCTAssertNil(integration.snapshot)
        XCTAssertFalse(integration.busy)
    }
}

final class StoreTransactionLifecycleTests: XCTestCase {
    func test_expiredRefundedUpgradedAndMissingExpiryNeverUnlock() {
        let now = Date(timeIntervalSince1970: 1000)
        for (expiry, revoked, upgraded) in [(Optional(now), false, false), (nil, false, false), (Optional(now.addingTimeInterval(60)), true, false), (Optional(now.addingTimeInterval(60)), false, true)] {
            XCTAssertEqual(SBTVerifiedTransactionTier.resolve(product: "unlimited_monthly_1499", expiry: expiry, revoked: revoked, upgraded: upgraded, now: now), .free)
        }
    }
    func test_verifiedOrdinaryTiersAndUnknownCodes() {
        let now = Date(timeIntervalSince1970: 1000)
        for (product, expected) in [("essential_monthly_499", PlanTier.essential), ("unlimited_monthly_1499", .unlimited), ("SAVE20", .free), ("lifetime_premium_v1", .free), ("unknown", .free)] {
            XCTAssertEqual(SBTVerifiedTransactionTier.resolve(product: product, expiry: now.addingTimeInterval(60), revoked: false, upgraded: false, now: now), expected)
        }
    }
}

#if DEBUG && canImport(Supabase)
final class SandboxSessionConfigurationTests: XCTestCase {
    @MainActor func test_missingAndProductionConfigurationsNeverCreateSandboxClient() {
        XCTAssertFalse(SBTSandboxSession(environment: [:]).isConfigured)
        XCTAssertFalse(SBTSandboxSession(environment: ["SBT_SANDBOX_ACCOUNT_URL": "https://zziauybwemoiqfpidiur.supabase.co", "SBT_SANDBOX_ANON_KEY": "public-fixture"]).isConfigured)
        XCTAssertFalse(SBTSandboxSession(environment: ["SBT_SANDBOX_ACCOUNT_URL": SBTAccountConnection.sandboxAccountBase]).isConfigured)
    }
}
#endif

@MainActor
final class OfflineEntitlementPolicyTests: XCTestCase {
    private final class MemoryStorage: SBTEntitlementCacheStorage {
        var values: [UUID: Data] = [:]
        var writes = 0
        var failsWrites = false
        func read(owner: UUID) -> Data? { values[owner] }
        func write(_ data: Data, owner: UUID) -> Bool {
            writes += 1
            guard !failsWrites else { return false }
            values[owner] = data
            return true
        }
        func remove(owner: UUID) { values.removeValue(forKey: owner) }
    }
    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    private let a = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let b = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private func value(_ owner: UUID, at: Date, status: String = "active") -> SBTVerifiedEntitlementSnapshot {
        .init(version: 1, account_id: owner, bundle_id: "com.sacredbilltracker.app", environment: "production",
              verified_at: at.timeIntervalSince1970, entitlements: [.init(product_id: ProductID.essentialMonthly,
              original_transaction_id: "100", transaction_id: "101", status: status,
              expires_at: at.addingTimeInterval(10 * 86400).timeIntervalSince1970, revoked: status == "revoked")])
    }
    func test_paidTrialAndSupportedGraceGrantOnline() {
        for state in ["active", "trial", "grace"] {
            let clock = Clock(), storage = MemoryStorage()
            let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
            store.changeAccount(a)
            XCTAssertTrue(store.acceptVerified(value(a, at: clock.now, status: state), expectedOwner: a, expectedRevision: store.revision))
            XCTAssertEqual(store.productIDs, [ProductID.essentialMonthly])
        }
    }
    func test_offlineBoundariesAreInclusiveAtExactly72Hours() {
        let clock = Clock(), snapshot = value(a, at: Clock().now)
        let cases: [(TimeInterval, Bool)] = [(3600, true), (259140, true), (259200, true), (259200.001, false)]
        for (seconds, expected) in cases {
            XCTAssertEqual(!SBTOfflineEntitlementPolicy.products(snapshot, owner: a, now: clock.now.addingTimeInterval(seconds)).isEmpty, expected)
        }
    }
    func test_expiryIsAStricterLimitThan72Hours() {
        let clock = Clock()
        var snapshot = value(a, at: clock.now)
        snapshot.entitlements[0].expires_at = clock.now.addingTimeInterval(3600).timeIntervalSince1970
        XCTAssertTrue(SBTOfflineEntitlementPolicy.products(snapshot, owner: a, now: clock.now.addingTimeInterval(3600)).isEmpty)
    }
    func test_corruptFutureZeroAndMissingTimestampDeny() throws {
        let clock = Clock()
        for time in [Double.nan, Double.infinity, 0, -1, clock.now.timeIntervalSince1970 + 1] {
            var snapshot = value(a, at: clock.now); snapshot.verified_at = time
            XCTAssertTrue(SBTOfflineEntitlementPolicy.products(snapshot, owner: a, now: clock.now).isEmpty)
        }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value(a, at: clock.now))) as? [String: Any])
        json.removeValue(forKey: "verified_at")
        XCTAssertThrowsError(try JSONDecoder().decode(SBTVerifiedEntitlementSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func test_launchAndFailureNeverRefreshVerificationTime() {
        let clock = Clock(), storage = MemoryStorage(), originalTime = Clock().now
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
        clock.now.addTimeInterval(3600)
        store.verificationUnavailable(expectedOwner: a, expectedRevision: store.revision)
        let relaunched = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        relaunched.changeAccount(a)
        XCTAssertEqual(relaunched.snapshot?.verified_at, originalTime.timeIntervalSince1970)
        XCTAssertEqual(storage.writes, 1)
        XCTAssertFalse(relaunched.productIDs.isEmpty)
        clock.now = originalTime.addingTimeInterval(72 * 3600 + 1)
        relaunched.reevaluate()
        XCTAssertTrue(relaunched.productIDs.isEmpty)
    }
    func test_logoutAndUserBOfflineCannotReuseUserA() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
        store.signOut()
        store.changeAccount(b)
        XCTAssertTrue(store.productIDs.isEmpty)
        store.changeAccount(a)
        XCTAssertTrue(store.productIDs.isEmpty) // Explicit logout deletes A's cache.
    }
    func test_directAToBToAUsesOnlyMatchingCache() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
        store.changeAccount(b)
        XCTAssertTrue(store.productIDs.isEmpty)
        store.changeAccount(a)
        XCTAssertEqual(store.productIDs, [ProductID.essentialMonthly])
    }
    func test_anonymousToAuthenticatedAndBackCannotGrantAnonymousAccess() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        XCTAssertFalse(store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision))
        store.changeAccount(a)
        store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
        store.changeAccount(nil)
        XCTAssertTrue(store.productIDs.isEmpty)
        XCTAssertTrue(SBTOfflineEntitlementPolicy.products(value(a, at: clock.now), owner: nil, now: clock.now).isEmpty)
    }
    func test_revokedExpiredAndVerifiedFreeReplacePreviousPaidCache() {
        for status in ["revoked", "expired", "on_hold", "free"] {
            let clock = Clock(), storage = MemoryStorage()
            let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
            store.changeAccount(a)
            store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
            clock.now.addTimeInterval(1)
            var denied = value(a, at: clock.now, status: status)
            if status == "free" { denied.entitlements = [] }
            XCTAssertTrue(store.acceptVerified(denied, expectedOwner: a, expectedRevision: store.revision))
            store.verificationUnavailable(expectedOwner: a, expectedRevision: store.revision)
            XCTAssertTrue(store.productIDs.isEmpty)
            let restart = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
            restart.changeAccount(a)
            XCTAssertTrue(restart.productIDs.isEmpty)
        }
    }
    func test_storeKitRevocationCannotResurrectAfterFailedVerificationAndRestart() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
        store.invalidate(originalID: "100", expectedOwner: a)
        store.verificationUnavailable(expectedOwner: a, expectedRevision: store.revision)
        let restart = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        restart.changeAccount(a)
        XCTAssertTrue(restart.productIDs.isEmpty)
    }
    func test_inFlightAToBToACannotApplyStaleResponse() {
        let clock = Clock(), store = SBTVerifiedEntitlementStore(storage: MemoryStorage(), clock: { Clock().now }, schedulesExpiry: false)
        store.changeAccount(a)
        let capturedRevision = store.revision
        store.changeAccount(b); store.changeAccount(a)
        XCTAssertFalse(store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: capturedRevision))
        XCTAssertTrue(store.productIDs.isEmpty)
    }
    func test_restoreAndReverificationAfterGraceRestartWindowOnlyOnSuccess() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
        clock.now.addTimeInterval(73 * 3600)
        store.verificationUnavailable(expectedOwner: a, expectedRevision: store.revision)
        XCTAssertTrue(store.productIDs.isEmpty)
        // A restore attempts StoreKit sync; only the later verified response resets grace.
        store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision)
        clock.now.addTimeInterval(3600)
        store.verificationUnavailable(expectedOwner: a, expectedRevision: store.revision)
        XCTAssertFalse(store.productIDs.isEmpty)
    }
    func test_wrongOwnerEnvironmentUnknownProductAndStaleResponseDeny() {
        let clock = Clock()
        for change in 0..<4 {
            let store = SBTVerifiedEntitlementStore(storage: MemoryStorage(), clock: { clock.now }, schedulesExpiry: false)
            store.changeAccount(a)
            var snapshot = value(a, at: clock.now)
            if change == 0 { snapshot.account_id = b }
            if change == 1 { snapshot.environment = "sandbox" }
            if change == 2 { snapshot.entitlements[0].product_id = "unknown" }
            if change == 3 { snapshot.verified_at -= 301 }
            XCTAssertFalse(store.acceptVerified(snapshot, expectedOwner: a, expectedRevision: store.revision))
            XCTAssertTrue(store.productIDs.isEmpty)
        }
    }
    func test_sandboxCacheNeverGrantsToProductionReceipt() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false, environment: "sandbox")
        store.changeAccount(a)
        var snapshot = value(a, at: clock.now); snapshot.environment = "sandbox"
        XCTAssertTrue(store.acceptVerified(snapshot, expectedOwner: a, expectedRevision: store.revision))
        store.setVerifiedAppEnvironment("production")
        XCTAssertTrue(store.productIDs.isEmpty)
    }
    func test_keychainWriteFailureCannotCreateOfflineAccess() {
        let clock = Clock(), storage = MemoryStorage()
        storage.failsWrites = true
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        XCTAssertFalse(store.acceptVerified(value(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision))
        XCTAssertTrue(store.productIDs.isEmpty)
        XCTAssertNil(storage.read(owner: a))
    }
    func test_corruptedStoredEnvelopeIsRemovedWithoutGrant() {
        let storage = MemoryStorage()
        storage.values[a] = Data("corrupt cache".utf8)
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { Clock().now }, schedulesExpiry: false)
        store.changeAccount(a)
        XCTAssertTrue(store.productIDs.isEmpty)
        XCTAssertNil(storage.read(owner: a))
    }
    func test_rewardAccessIsPreservedSeparatelyAndExpires() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        var snapshot = value(a, at: clock.now); snapshot.entitlements = []
        snapshot.rewards = [.init(tier: "business", expires_at: clock.now.addingTimeInterval(60).timeIntervalSince1970)]
        XCTAssertTrue(store.acceptVerified(snapshot, expectedOwner: a, expectedRevision: store.revision))
        XCTAssertEqual(store.rewardTier, .business)
        XCTAssertTrue(store.productIDs.isEmpty)
        clock.now.addTimeInterval(60); store.reevaluate()
        XCTAssertEqual(store.rewardTier, .free)
    }
}

extension OfflineEntitlementPolicyTests {
    private func googleValue(_ owner: UUID, at: Date) -> SBTVerifiedEntitlementSnapshot {
        var snapshot = value(owner, at: at)
        snapshot.entitlements = []
        snapshot.account_sources = [.init(source_platform: "android_play",
            source_id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, product_id: "google_business",
            tier: "business", status: "active", expires_at: at.addingTimeInterval(10 * 86400).timeIntervalSince1970,
            revoked: false, environment: "production", verified_at: at.timeIntervalSince1970, binding_state: "reviewed")]
        return snapshot
    }
    func test_googleOnlySnapshotRemainsDisabledWithoutAppleProduct() {
        let clock = Clock(), store = SBTVerifiedEntitlementStore(storage: MemoryStorage(), clock: { Clock().now }, schedulesExpiry: false)
        store.changeAccount(a)
        XCTAssertTrue(store.acceptVerified(googleValue(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision))
        XCTAssertEqual(store.accountTier, .free)
        XCTAssertTrue(store.productIDs.isEmpty)
        XCTAssertEqual(store.rewardTier, .free)
    }
    func test_googleOffline72HoursAndFailureDoNotRefreshClock() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        XCTAssertTrue(store.acceptVerified(googleValue(a, at: clock.now), expectedOwner: a, expectedRevision: store.revision))
        for seconds: TimeInterval in [3600, 259140, 259200] {
            clock.now = Date(timeIntervalSince1970: 1800000000 + seconds)
            store.verificationUnavailable(expectedOwner: a, expectedRevision: store.revision)
            XCTAssertEqual(store.accountTier, .free)
            XCTAssertEqual(store.snapshot?.verified_at, 1800000000)
        }
        clock.now.addTimeInterval(0.01); store.reevaluate()
        XCTAssertEqual(store.accountTier, .free)
        XCTAssertEqual(storage.writes, 1)
    }
    func test_googleExpiredRevokedFreeReplacementCannotResurrectOffline() {
        for status in ["expired", "revoked"] {
            let clock = Clock(), storage = MemoryStorage()
            let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
            store.changeAccount(a)
            var snapshot = googleValue(a, at: clock.now)
            XCTAssertTrue(store.acceptVerified(snapshot, expectedOwner: a, expectedRevision: store.revision))
            snapshot.account_sources![0].status = status
            snapshot.account_sources![0].revoked = status == "revoked"
            XCTAssertTrue(store.acceptVerified(snapshot, expectedOwner: a, expectedRevision: store.revision))
            let reloaded = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
            reloaded.changeAccount(a)
            XCTAssertEqual(reloaded.accountTier, .free)
        }
    }
    func test_googleLogoutSwitchAndDelayedResponseAreAccountIsolated() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        let oldRevision = store.revision
        XCTAssertTrue(store.acceptVerified(googleValue(a, at: clock.now), expectedOwner: a, expectedRevision: oldRevision))
        store.changeAccount(b); XCTAssertEqual(store.accountTier, .free)
        store.changeAccount(a); XCTAssertEqual(store.accountTier, .free)
        XCTAssertFalse(store.acceptVerified(googleValue(a, at: clock.now), expectedOwner: a, expectedRevision: oldRevision))
        store.signOut(); XCTAssertNil(storage.read(owner: a)); XCTAssertEqual(store.accountTier, .free)
        store.changeAccount(b); XCTAssertEqual(store.accountTier, .free)
    }
    func test_googleWrongEnvironmentUnknownTierAndFutureVerificationDeny() {
        let clock = Clock()
        for scenario in 0..<4 {
            var snapshot = googleValue(a, at: clock.now)
            switch scenario {
            case 0: snapshot.account_sources![0].environment = "sandbox"
            case 1: snapshot.account_sources![0].tier = "admin"
            case 2: snapshot.account_sources![0].verified_at += 1
            default: snapshot.account_sources![0].binding_state = "unverified"
            }
            XCTAssertFalse(SBTOfflineEntitlementPolicy.isWellFormed(snapshot, owner: a, now: clock.now))
        }
    }
    func test_googleExpiryIsStricterThanOfflineGrace() {
        let clock = Clock()
        var snapshot = googleValue(a, at: clock.now)
        snapshot.account_sources![0].expires_at = clock.now.addingTimeInterval(60).timeIntervalSince1970
        XCTAssertEqual(SBTOfflineEntitlementPolicy.accountTier(snapshot, owner: a, now: clock.now.addingTimeInterval(60), environment: "production"), .free)
    }
    func test_unifiedAppleAndGoogleSourcesRemainIndependent() {
        let clock = Clock()
        var snapshot = googleValue(a, at: clock.now)
        snapshot.entitlements = value(a, at: clock.now).entitlements
        XCTAssertEqual(SBTOfflineEntitlementPolicy.products(snapshot, owner: a, now: clock.now), [ProductID.essentialMonthly])
        XCTAssertEqual(SBTOfflineEntitlementPolicy.accountTier(snapshot, owner: a, now: clock.now, environment: "production"), .free)
        XCTAssertEqual(SBTOfflineEntitlementPolicy.accountTier(snapshot, owner: b, now: clock.now, environment: "production"), .free)
    }
    func test_googleFuturePolicyRequiresExplicitEnableAndStillChecksTime() {
        let clock = Clock(), snapshot = googleValue(a, at: Clock().now)
        XCTAssertFalse(SBTOfflineEntitlementPolicy.googleCrossPlatformEnabled)
        XCTAssertEqual(SBTOfflineEntitlementPolicy.accountTier(snapshot, owner: a, now: clock.now,
            environment: "production", googleEnabled: true), .business)
        XCTAssertEqual(SBTOfflineEntitlementPolicy.accountTier(snapshot, owner: a, now: clock.now.addingTimeInterval(259201),
            environment: "production", googleEnabled: true), .free)
    }
    func test_unresolvedLegacyPreservesSeparatelyVerifiedAppleAndShowsRecovery() {
        let clock = Clock(), storage = MemoryStorage()
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { clock.now }, schedulesExpiry: false)
        store.changeAccount(a)
        var snapshot = value(a, at: clock.now)
        snapshot.ownership_resolution = "legacy_ownership_unresolved"
        XCTAssertTrue(store.acceptVerified(snapshot, expectedOwner: a, expectedRevision: store.revision))
        XCTAssertEqual(store.productIDs, [ProductID.essentialMonthly])
        XCTAssertNotNil(store.verificationMessage)
        snapshot.entitlements = []
        XCTAssertTrue(store.acceptVerified(snapshot, expectedOwner: a, expectedRevision: store.revision))
        XCTAssertTrue(store.productIDs.isEmpty)
        XCTAssertNotNil(store.verificationMessage)
    }
    func test_ownershipStateIsAdditiveAndUnknownStateFailsSafely() throws {
        let clock = Clock()
        var snapshot = value(a, at: clock.now)
        XCTAssertTrue(SBTOfflineEntitlementPolicy.isWellFormed(snapshot, owner: a, now: clock.now))
        snapshot.ownership_resolution = "unexpected"
        XCTAssertFalse(SBTOfflineEntitlementPolicy.isWellFormed(snapshot, owner: a, now: clock.now))
    }
    func test_unifiedWireSnapshotRoundTripPreservesGoogleSource() throws {
        let clock = Clock(), original = googleValue(a, at: clock.now)
        let decoded = try JSONDecoder().decode(SBTVerifiedEntitlementSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.entitlements.isEmpty)
        XCTAssertEqual(decoded.account_sources?.first?.source_platform, "android_play")
    }
}

#if canImport(Supabase)
import Supabase

@MainActor
final class EntitlementTransportIntegrationTests: XCTestCase {
    nonisolated private static let envelope = #"{"version":1,"account_id":"11111111-1111-4111-8111-111111111111","bundle_id":"com.sacredbilltracker.app","environment":"production","verified_at":1800000000,"entitlements":[{"product_id":"essential_monthly_499","original_transaction_id":"100","transaction_id":"101","status":"active","expires_at":1800086400,"revoked":false}],"rewards":[]}"#

    func test_actualSupabaseSDKEncodesAppleSnapshotRequestAndDecodesServerEnvelope() async throws {
        let client = FunctionsClient(url: URL(string: "https://entitlement-test.invalid/functions/v1")!, fetch: { request in
            XCTAssertEqual(request.url?.host, "entitlement-test.invalid")
            XCTAssertEqual(request.url?.path, "/functions/v1/verify-store-subscription")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["platform"] as? String, "apple")
            XCTAssertEqual(body["operation"] as? String, "entitlement_snapshot")
            XCTAssertEqual(body["environment"] as? String, "production")
            XCTAssertEqual(body["original_transaction_ids"] as? [String], ["100"])
            return (Data(Self.envelope.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        })
        let result = try await SBTVerifiedEntitlementStore.fetchVerifiedSnapshot(functions: client,
            environment: "production", originals: ["100"])
        let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        XCTAssertEqual(SBTOfflineEntitlementPolicy.products(result, owner: owner,
            now: Date(timeIntervalSince1970: 1800000001)), [ProductID.essentialMonthly])
        XCTAssertTrue(SBTOfflineEntitlementPolicy.products(result, owner: UUID(),
            now: Date(timeIntervalSince1970: 1800000001)).isEmpty)
    }

    func test_actualSupabaseSDKPreservesVerificationHTTPFailures() async throws {
        for status in [401, 403, 503] {
            let client = FunctionsClient(url: URL(string: "https://entitlement-test.invalid/functions/v1")!, fetch: { request in
                (Data(#"{"error":"verification_rejected"}"#.utf8), HTTPURLResponse(url: request.url!,
                    statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            })
            do {
                _ = try await SBTVerifiedEntitlementStore.fetchVerifiedSnapshot(functions: client,
                    environment: "production", originals: [])
                XCTFail("HTTP failure must not decode as verified Free")
            } catch FunctionsError.httpError(let code, _) { XCTAssertEqual(code, status) }
        }
    }

    func test_actualSupabaseSDKRejectsOldScalarTierAsSnapshot() async throws {
        let client = FunctionsClient(url: URL(string: "https://entitlement-test.invalid/functions/v1")!, fetch: { request in
            (Data(#""unlimited""#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        })
        do {
            _ = try await SBTVerifiedEntitlementStore.fetchVerifiedSnapshot(functions: client,
                environment: "production", originals: [])
            XCTFail("Scalar tier has no verified timestamp or account binding")
        } catch is DecodingError { }
    }
}
#endif

#if canImport(Supabase)
extension EntitlementTransportIntegrationTests {
    func test_googleSDKResponsePersistsInRealKeychainThenLogoutIsolatesAccount() async throws {
        let owner = UUID(), other = UUID(), now = Date(timeIntervalSince1970: 1800000000)
        let source: [String: Any] = ["source_platform": "android_play", "source_id": UUID().uuidString,
            "product_id": "business_monthly_999", "tier": "business", "status": "active", "expires_at": 1800086400,
            "revoked": false, "environment": "production", "verified_at": 1800000000, "binding_state": "reviewed"]
        let payload = try JSONSerialization.data(withJSONObject: ["version": 1, "account_id": owner.uuidString,
            "bundle_id": "com.sacredbilltracker.app", "environment": "production", "verified_at": 1800000000,
            "entitlements": [], "account_sources": [source]])
        let client = FunctionsClient(url: URL(string: "https://entitlement-test.invalid/functions/v1")!, fetch: { request in
            (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!)
        })
        let storage = SBTKeychainEntitlementStorage()
        defer { storage.remove(owner: owner); storage.remove(owner: other) }
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { now }, schedulesExpiry: false)
        store.changeAccount(owner)
        let response = try await SBTVerifiedEntitlementStore.fetchVerifiedSnapshot(functions: client,
            environment: "production", originals: [])
        XCTAssertTrue(store.acceptVerified(response, expectedOwner: owner, expectedRevision: store.revision))
        XCTAssertEqual(store.accountTier, .free)
        XCTAssertTrue(store.productIDs.isEmpty)
        XCTAssertNotNil(storage.read(owner: owner))
        let reopened = SBTVerifiedEntitlementStore(storage: storage, clock: { now }, schedulesExpiry: false)
        reopened.changeAccount(owner)
        XCTAssertEqual(reopened.accountTier, .free)
        reopened.signOut()
        XCTAssertNil(storage.read(owner: owner))
        reopened.changeAccount(other)
        XCTAssertEqual(reopened.accountTier, .free)
    }
    func test_revokedSDKResponseImmediatelyReplacesRealKeychainPaidSnapshot() async throws {
        let owner = UUID(), now = Date(timeIntervalSince1970: 1800000000)
        let storage = SBTKeychainEntitlementStorage()
        defer { storage.remove(owner: owner) }
        let store = SBTVerifiedEntitlementStore(storage: storage, clock: { now }, schedulesExpiry: false)
        store.changeAccount(owner)
        for status in ["active", "revoked"] {
            let text = Self.envelope.replacingOccurrences(of: "11111111-1111-4111-8111-111111111111", with: owner.uuidString)
                .replacingOccurrences(of: "\"status\":\"active\"", with: "\"status\":\"\(status)\"")
                .replacingOccurrences(of: "\"revoked\":false", with: "\"revoked\":\(status == "revoked")")
            let client = FunctionsClient(url: URL(string: "https://entitlement-test.invalid/functions/v1")!, fetch: { request in
                (Data(text.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            })
            let response = try await SBTVerifiedEntitlementStore.fetchVerifiedSnapshot(functions: client,
                environment: "production", originals: ["100"])
            XCTAssertTrue(store.acceptVerified(response, expectedOwner: owner, expectedRevision: store.revision))
            XCTAssertEqual(store.productIDs.isEmpty, status == "revoked")
        }
        let reopened = SBTVerifiedEntitlementStore(storage: storage, clock: { now }, schedulesExpiry: false)
        reopened.changeAccount(owner)
        XCTAssertTrue(reopened.productIDs.isEmpty)
    }
}
#endif

#if canImport(StoreKitTest) && SBT_ISOLATED_VALIDATION
import StoreKitTest
import StoreKit

@MainActor
final class StoreKitEnvironmentIntegrationTests: XCTestCase {
    func test_localStoreKitPurchaseCannotSeedRealOfflineEntitlement() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let session = try SKTestSession(contentsOf: root.appendingPathComponent("SacredBillTracker/Configuration.storekit"))
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let owner = UUID()
        let transaction = try await session.buyProduct(identifier: ProductID.essentialMonthly, options: [.appAccountToken(owner)])
        XCTAssertEqual(transaction.appAccountToken, owner)
        XCTAssertEqual(transaction.environment, .xcode)
        XCTAssertNil(SBTVerifiedEntitlementStore.serverEnvironment(for: transaction.environment))
        XCTAssertEqual(SBTVerifiedEntitlementStore.serverEnvironment(for: .production), "production")
        XCTAssertEqual(SBTVerifiedEntitlementStore.serverEnvironment(for: .sandbox), "sandbox")
    }
}
#endif
