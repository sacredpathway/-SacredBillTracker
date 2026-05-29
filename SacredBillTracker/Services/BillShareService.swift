//
//  BillShareService.swift
//  SacredBillTracker
//
//  Builds a plain-text, share-sheet-ready summary of a set of bills.
//  Produces the v1.6 spec format:
//
//      Sacred Bill Tracker Summary
//      Generated <date>
//
//      Total Bills: 8
//      Monthly Total: $1,842.50
//      Paid: $900.00
//      Pending: $742.50
//      Overdue: $200.00
//
//      Upcoming Bills:
//      • Rent — $1,200.00 — Due Jun 1 — Pending
//      • Phone — $95.00 — Due Jun 3 — Paid
//      • Insurance — $210.00 — Due Jun 7 — Overdue
//
//      Shared from Sacred Bill Tracker.
//
//  Lightweight by design: no PDF rendering, no networking, no extra
//  dependencies — just string formatting on top of the existing `Bill`
//  model. Pairs with the Bills tab's "Share Summary" toolbar button
//  and the Settings → Data row, both via SwiftUI `ShareLink`.
//
//  PRIVACY: NEVER reads `Bill.notes`. The summary is built purely from
//  publicly-shareable fields (name, amount, due date, status).
//

import Foundation

enum BillShareService {

    /// Plain-old-data container for the four income aggregates included
    /// in a shared summary. Keeps `makeSummary` decoupled from
    /// `IncomeStore` so the generator stays unit-testable without
    /// spinning up the store.
    struct IncomeAggregates: Equatable {
        var thisWeek:   Decimal
        var last30Days: Decimal
        var thisMonth:  Decimal
        var allTime:    Decimal

        static let zero = IncomeAggregates(
            thisWeek: 0, last30Days: 0, thisMonth: 0, allTime: 0
        )
    }

    // MARK: - Public API

    /// Build the full share-sheet body from a list of bills, with an
    /// optional Income Summary section prepended.
    ///
    /// Backward-compatible: callers that don't pass `income` (or pass
    /// `.zero`) get the v1.6 bill-only layout; the Income Summary
    /// section is omitted when every income aggregate is zero.
    ///
    /// Bills already filtered / scoped by the caller are passed in
    /// as-is; this service does not re-filter beyond skipping any
    /// soft-deleted rows defensively.
    static func makeSummary(
        bills: [Bill],
        income: IncomeAggregates = .zero,
        generatedAt: Date = Date(),
        calendar cal: Calendar = .current
    ) -> String {

        // Defensive: never include trashed bills in a shared summary.
        let live = bills.filter { $0.deletedAt == nil }

        // -------- Bill aggregates --------
        let count = live.count

        // "Monthly total" = sum of bills whose due date falls inside the
        // current month, matching the in-app dashboard semantics.
        let monthlyTotal = live
            .filter { isInCurrentMonth($0.dueDate, calendar: cal) }
            .reduce(Decimal(0)) { $0 + $1.amount }

        let paid    = live.filter { $0.effectiveStatus == .paid }
                          .reduce(Decimal(0)) { $0 + $1.amount }
        let pending = live.filter { $0.effectiveStatus == .unpaid }
                          .reduce(Decimal(0)) { $0 + $1.amount }
        let overdue = live.filter { $0.effectiveStatus == .overdue }
                          .reduce(Decimal(0)) { $0 + $1.amount }

        // -------- Compose --------
        var lines: [String] = []
        lines.append("Sacred Bill Tracker Summary")
        lines.append("Generated \(longDate(generatedAt))")
        lines.append("")

        // v1.7 — Income Summary section. Shown only when the user has
        // recorded any income, so older / fresh installs still get the
        // clean bills-only layout the prior spec described.
        if income != .zero {
            lines.append("Income Summary")
            lines.append("• This Week: \(currency(income.thisWeek))")
            lines.append("• Last 30 Days: \(currency(income.last30Days))")
            lines.append("• This Month: \(currency(income.thisMonth))")
            lines.append("• All Time: \(currency(income.allTime))")
            lines.append("")
        }

        // Bills Overview header keeps the document scannable when both
        // the income and bills sections are present.
        lines.append("Bills Overview")
        lines.append("• Total Bills: \(count)")
        lines.append("• Monthly Total: \(currency(monthlyTotal))")
        lines.append("• Paid: \(currency(paid))")
        lines.append("• Pending: \(currency(pending))")
        lines.append("• Overdue: \(currency(overdue))")
        lines.append("")

        // -------- Upcoming bills, grouped by due date --------
        //
        // Surfaces ALL non-trash bills, grouped by date, sorted by due
        // date ascending. Matches the "Upcoming Bills" example in spec.
        let upcoming = live.sorted { $0.dueDate < $1.dueDate }

        lines.append("Upcoming Bills")
        if upcoming.isEmpty {
            lines.append("• No upcoming bills.")
        } else {
            appendGroupedByDate(bills: upcoming, calendar: cal, into: &lines)
        }
        lines.append("")
        lines.append("Generated by Sacred Bill Tracker")

        return lines.joined(separator: "\n")
    }

    // MARK: - Grouping

    /// Appends bills under per-day headers, e.g.
    ///
    ///     May 24
    ///     • Rent — $850.00
    ///
    ///     May 28
    ///     • Internet — $75.00
    ///
    /// Bills are sorted by due date ascending; a blank line separates
    /// each day for legibility in the share sheet preview.
    private static func appendGroupedByDate(
        bills: [Bill],
        calendar cal: Calendar,
        into lines: inout [String]
    ) {
        var lastDay: Date? = nil
        for bill in bills {
            let day = cal.startOfDay(for: bill.dueDate)
            if lastDay == nil || !cal.isDate(lastDay!, inSameDayAs: day) {
                if lastDay != nil { lines.append("") } // gap between dates
                lines.append(shortDueDate(day)) // date header (e.g. "May 24")
            }
            lines.append(formatRow(bill))
            lastDay = day
        }
    }

    /// Single bill row matching the v1.7 spec example:
    /// `• Rent — $850.00`
    /// (Day header lives on the line above; status tag is dropped in
    /// the per-day list to keep each row short and readable.)
    static func formatRow(_ bill: Bill) -> String {
        "• \(bill.name) — \(currency(bill.amount))"
    }

    // MARK: - Formatting helpers

    /// Locale-aware currency, 2 fractional digits to match the spec
    /// examples (`$1,842.50`, `$95.00`).
    static func currency(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    /// Short due date used on each bill row, e.g. `Jun 1`.
    static func shortDueDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: date)
    }

    /// Long header date, e.g. `May 22, 2026`.
    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Title-cased status label — relies on `Bill.effectiveStatus`
    /// so unpaid + past-due bills are surfaced as "Overdue".
    static func statusLabel(_ status: PaymentStatus) -> String {
        switch status {
        case .paid:    return "Paid"
        case .unpaid:  return "Pending"
        case .overdue: return "Overdue"
        }
    }

    /// True when `date` falls inside the calendar month containing
    /// "now" (per the supplied calendar's current time).
    private static func isInCurrentMonth(_ date: Date, calendar cal: Calendar) -> Bool {
        let now = Date()
        return cal.component(.month, from: date) == cal.component(.month, from: now)
            && cal.component(.year,  from: date) == cal.component(.year,  from: now)
    }
}
