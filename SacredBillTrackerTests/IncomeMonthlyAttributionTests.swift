//
//  IncomeMonthlyAttributionTests.swift
//  SacredBillTrackerTests
//
//  Regression lock for the "This Month income = $0" bug.
//
//  Root cause: IncomeStore bucketed entries by `WeeklyIncome.weekStart`.
//  A legacy week-range row like Mon Jun 29 → Sun Jul 5, 2026 has a
//  weekStart in JUNE, so it fell outside July's month range. Until the
//  first Monday landed inside the month, "This Month" income read $0.
//
//  Fix: bucket by `WeeklyIncome.incomeDate` (== weekEnd, the settlement
//  date). Single-day entries — every Plaid import and every entry made
//  through the current Add Income flow — have weekStart == weekEnd, so
//  they are completely unaffected.
//
//  These tests exercise `incomeDate` and the exact range predicate
//  IncomeStore uses (`range.contains(entry.incomeDate)`), against a
//  month range built the same way `IncomeStore.bounds(for: .thisMonth)`
//  builds it. Pure logic — no store, no UserDefaults, no Supabase,
//  no MainActor, no wall clock.
//

import XCTest
@testable import SacredBillTracker

final class IncomeMonthlyAttributionTests: XCTestCase {

    // MARK: - Fixture

    /// Gregorian / UTC / Monday-start, so nothing depends on locale or TZ.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func endOfDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d,
                                      hour: 23, minute: 59, second: 59))!
    }

    /// Mirrors `IncomeStore.bounds(for: .thisMonth)`: full calendar month,
    /// inclusive, ending one second before the next month begins.
    private func monthRange(_ y: Int, _ m: Int) -> ClosedRange<Date> {
        let anchor = day(y, m, 1)
        let interval = cal.dateInterval(of: .month, for: anchor)!
        let end = cal.date(byAdding: .second, value: -1, to: interval.end)!
        return interval.start...end
    }

    private func income(_ amount: String, from start: Date, to end: Date) -> WeeklyIncome {
        WeeklyIncome(
            amount: Decimal(string: amount)!,
            weekStart: start,
            weekEnd: end,
            type: .business,
            sourceName: "Load settlement",
            note: ""
        )
    }

    /// The exact predicate IncomeStore now uses for every range filter.
    private func total(_ entries: [WeeklyIncome], in range: ClosedRange<Date>) -> Decimal {
        entries.filter { range.contains($0.incomeDate) }
               .reduce(Decimal(0)) { $0 + $1.amount }
    }

    // Mon Jun 29 → Sun Jul 5, 2026. The straddling week from the bug report.
    private var straddlingWeek: WeeklyIncome {
        income("1200.00", from: day(2026, 6, 29), to: endOfDay(2026, 7, 5))
    }

    // Mon Jun 22 → Sun Jun 28, 2026. Entirely inside June.
    private var juneOnlyWeek: WeeklyIncome {
        income("800.00", from: day(2026, 6, 22), to: endOfDay(2026, 6, 28))
    }

    // Thu Jul 2, 2026 — a Plaid import / modern manual entry (single day).
    private var julySingleDay: WeeklyIncome {
        income("300.00", from: day(2026, 7, 2), to: endOfDay(2026, 7, 2))
    }

    // MARK: - 1. July 1–5 income counts toward July

    func test_straddlingWeek_countsTowardJuly() {
        let july = monthRange(2026, 7)
        XCTAssertEqual(total([straddlingWeek], in: july), Decimal(string: "1200.00")!,
                       "A week ending Jul 5 MUST count toward July")
    }

    // MARK: - 2. A month-crossing week does not zero out the current month

    func test_monthCrossingWeek_doesNotZeroOutCurrentMonth() {
        let july = monthRange(2026, 7)
        let entries = [straddlingWeek, julySingleDay]

        let sum = total(entries, in: july)
        XCTAssertNotEqual(sum, 0, "July income MUST NOT be $0 while the month is in progress")
        XCTAssertEqual(sum, Decimal(string: "1500.00")!, "1200.00 straddling week + 300.00 single day")
    }

    // MARK: - 3. Previous-month income is not incorrectly counted

    func test_previousMonthIncome_notCountedInJuly() {
        let july = monthRange(2026, 7)
        XCTAssertEqual(total([juneOnlyWeek], in: july), 0,
                       "A week wholly inside June must never appear in July")
    }

    func test_straddlingWeek_notCountedInJune() {
        let june = monthRange(2026, 6)
        XCTAssertEqual(total([straddlingWeek], in: june), 0,
                       "The Jun 29 → Jul 5 week is attributed to July, not June")
    }

    /// No double counting: every entry lands in exactly one month, so the
    /// months sum to the all-time total. Guards the CPA export.
    func test_monthsSumToAllTime_noDoubleCounting() {
        let entries = [juneOnlyWeek, straddlingWeek, julySingleDay]
        let allTime = entries.reduce(Decimal(0)) { $0 + $1.amount }

        let june = total(entries, in: monthRange(2026, 6))
        let july = total(entries, in: monthRange(2026, 7))

        XCTAssertEqual(june, Decimal(string: "800.00")!)
        XCTAssertEqual(july, Decimal(string: "1500.00")!)
        XCTAssertEqual(june + july, allTime, "Months must not double-count a straddling week")
    }

    // MARK: - 4. Single-day entries (Plaid + modern manual) are unaffected

    func test_singleDayEntry_incomeDateIsThatDay() {
        let e = julySingleDay
        XCTAssertEqual(e.incomeDate, e.weekEnd)
        XCTAssertTrue(cal.isDate(e.incomeDate, inSameDayAs: e.weekStart),
                      "Single-day entries bucket to their own day — behavior unchanged")
    }

    func test_plaidStyleEntry_countsInItsOwnMonth() {
        XCTAssertEqual(total([julySingleDay], in: monthRange(2026, 7)), Decimal(string: "300.00")!)
        XCTAssertEqual(total([julySingleDay], in: monthRange(2026, 6)), 0)
    }

    // MARK: - 5. Existing income survives a month change

    /// Changing the selected month must not mutate or drop entries — the
    /// same array yields each month's own figure, and nothing is lost.
    func test_incomeRemainsAvailableAcrossMonthChanges() {
        let entries = [juneOnlyWeek, straddlingWeek, julySingleDay]

        XCTAssertEqual(total(entries, in: monthRange(2026, 5)), 0, "No May income")
        XCTAssertEqual(total(entries, in: monthRange(2026, 6)), Decimal(string: "800.00")!)
        XCTAssertEqual(total(entries, in: monthRange(2026, 7)), Decimal(string: "1500.00")!)
        XCTAssertEqual(entries.count, 3, "Reading totals never removes entries")
    }

    // MARK: - 6. incomeDate semantics + decode behavior unchanged

    func test_incomeDate_isWeekEnd_forLegacyWeekRange() {
        XCTAssertEqual(straddlingWeek.incomeDate, straddlingWeek.weekEnd)
        XCTAssertNotEqual(straddlingWeek.incomeDate, straddlingWeek.weekStart)
    }

    /// `incomeDate` is defensive: a corrupt row with weekEnd < weekStart
    /// still yields the later of the two rather than an inverted bucket.
    func test_incomeDate_guardsAgainstInvertedRange() {
        let corrupt = income("100.00", from: day(2026, 7, 10), to: day(2026, 7, 1))
        XCTAssertEqual(corrupt.incomeDate, day(2026, 7, 10))
    }

    /// Codable round-trip is untouched by the fix: `incomeDate` is derived,
    /// never encoded, and weekStart / weekEnd survive verbatim.
    func test_codableRoundTrip_preservesStoredDates() throws {
        let original = straddlingWeek
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeeklyIncome.self, from: data)

        XCTAssertEqual(decoded.weekStart, original.weekStart)
        XCTAssertEqual(decoded.weekEnd, original.weekEnd)
        XCTAssertEqual(decoded.amount, original.amount)
        XCTAssertEqual(decoded.incomeDate, original.incomeDate)
    }
}
