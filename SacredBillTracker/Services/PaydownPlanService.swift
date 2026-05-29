//
//  PaydownPlanService.swift
//  SacredBillTracker
//
//  Pure calculator + eligibility helper for the "15/3 Paydown Plan"
//  feature (v1.4). Splits a revolving-credit bill into two equal
//  reminders: 50% fifteen days before the due date, the remaining
//  50% three days before the due date.
//
//  No I/O, no SwiftUI — kept side-effect-free so it can be reused by
//  the Add/Edit form (live preview), the Bill detail view (display),
//  the BillStore (persist on save), and NotificationManager (schedule
//  the two extra reminders).
//

import Foundation

enum PaydownPlanService {

    // MARK: - Public surface

    /// Concrete plan output. Both dates and both amounts are always
    /// populated when this struct exists — `compute(...)` returns
    /// `nil` rather than partial data.
    struct Plan: Hashable {
        let firstDate: Date
        let firstAmount: Decimal
        let secondDate: Date
        let secondAmount: Decimal
    }

    /// Day offsets that give the plan its name. Surfaced as constants
    /// so notification copy / UI labels can reference them.
    static let firstOffsetDays: Int = 15
    static let secondOffsetDays: Int = 3

    /// One-line disclaimer required on every screen that surfaces the
    /// plan. Stored centrally so we never drift between Edit and
    /// Detail copy.
    static let disclaimer: String =
        "Sacred Bill Tracker provides organization tools and educational information only. " +
        "It does not provide financial, credit, tax, or legal advice and does not guarantee credit score improvement."

    /// Per-bill helper shown next to the toggle.
    static let helperText: String =
        "Split this bill into two planned payments to stay ahead of your due date and better manage utilization."

    // MARK: - Eligibility

    /// True when the toggle should appear at all. Currently keyed off
    /// `BillCategory.isRevolvingCredit` (credit card + line of credit).
    static func isEligible(category: BillCategory) -> Bool {
        category.isRevolvingCredit
    }

    /// Convenience overload that takes the whole bill.
    static func isEligible(for bill: Bill) -> Bool {
        isEligible(category: bill.category)
    }

    // MARK: - Computation

    /// Build a plan for a given amount and due date. Returns `nil`
    /// when the inputs are nonsensical (zero/negative amount, or a
    /// due date so close to "now" that both offsets would land in the
    /// past — see `allowPastDates` for the UI-preview case).
    ///
    /// - Parameter allowPastDates: pass `true` from the live preview
    ///   so the user can still see the math when they're editing a
    ///   bill whose due date already passed. Pass `false` from the
    ///   reminder scheduler so we never try to fire a notification
    ///   for a date in the past.
    static func compute(
        amount: Decimal,
        dueDate: Date,
        allowPastDates: Bool = true,
        calendar: Calendar = .current
    ) -> Plan? {

        guard amount > 0 else { return nil }

        // Split into two halves with no penny drift: round the first
        // half to the cent, give the rest to the second half. This
        // guarantees `first + second == amount` exactly.
        let firstAmount = roundedHalf(of: amount)
        let secondAmount = amount - firstAmount

        let dueStart = calendar.startOfDay(for: dueDate)
        guard
            let firstDate = calendar.date(byAdding: .day,
                                          value: -firstOffsetDays,
                                          to: dueStart),
            let secondDate = calendar.date(byAdding: .day,
                                           value: -secondOffsetDays,
                                           to: dueStart)
        else { return nil }

        if !allowPastDates {
            // Caller (notification scheduler) needs both reminders to
            // be in the future. If both are in the past there's no
            // value scheduling either.
            let now = Date()
            if firstDate <= now && secondDate <= now { return nil }
        }

        return Plan(
            firstDate: firstDate,
            firstAmount: firstAmount,
            secondDate: secondDate,
            secondAmount: secondAmount
        )
    }

    /// Apply the toggle state to a `Bill`, mutating the five paydown
    /// fields in place. Centralizes the on/off bookkeeping so the
    /// Add/Edit form, the detail view (future), and any background
    /// recompute path all go through the same code path.
    ///
    /// v1.4.1 — the eligibility gate was removed so the plan is
    /// available on every bill. `isEligible(...)` is kept for callers
    /// that still want to ask, but it does not block `apply`.
    static func apply(
        isOn: Bool,
        to bill: inout Bill,
        calendar: Calendar = .current
    ) {
        guard isOn else {
            clear(&bill)
            return
        }

        guard let plan = compute(amount: bill.amount,
                                 dueDate: bill.dueDate,
                                 allowPastDates: true,
                                 calendar: calendar) else {
            clear(&bill)
            return
        }

        bill.isUsing153Plan      = true
        bill.firstPaydownDate    = plan.firstDate
        bill.firstPaydownAmount  = plan.firstAmount
        bill.secondPaydownDate   = plan.secondDate
        bill.secondPaydownAmount = plan.secondAmount
    }

    /// Wipes every paydown field — used when the toggle is turned off
    /// or when the bill becomes ineligible (e.g. category changed
    /// away from creditCard).
    static func clear(_ bill: inout Bill) {
        bill.isUsing153Plan      = false
        bill.firstPaydownDate    = nil
        bill.firstPaydownAmount  = nil
        bill.secondPaydownDate   = nil
        bill.secondPaydownAmount = nil
    }

    // MARK: - Formatting helpers (shared across screens)

    /// Cents-precision currency, locale-aware. Used in the live
    /// preview, the detail card, and the notification body.
    static func currency(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    /// `May 15` / `Jan 3` — same template the rest of the app uses on
    /// row-level due-date text.
    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: date)
    }

    /// `May 15, 2026` — used on the detail card so the year is visible
    /// on cross-year due dates.
    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Stable notification identifier suffixes — referenced by
    /// `NotificationManager` so canceling a bill's reminders also
    /// catches its paydown reminders.
    enum NotificationKey {
        static let firstSuffix  = ":paydown1"
        static let secondSuffix = ":paydown2"

        static func firstID(for billID: UUID)  -> String { "\(billID.uuidString)\(firstSuffix)" }
        static func secondID(for billID: UUID) -> String { "\(billID.uuidString)\(secondSuffix)" }
    }

    // MARK: - Internal

    /// Round half of `amount` to two decimal places using bankers'
    /// rounding so it matches `NumberFormatter.currency`.
    private static func roundedHalf(of amount: Decimal) -> Decimal {
        var input = amount / 2
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .bankers)
        return rounded
    }
}
