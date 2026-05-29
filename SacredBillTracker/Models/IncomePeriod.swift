//
//  IncomePeriod.swift
//  SacredBillTracker
//
//  User-controlled income tracking period (v1.2.2). Combined with
//  `WeekStartDay`, these two preferences determine:
//    - The Dashboard income card's title + "this period" total
//    - The default date range pre-filled in AddEditIncomeView
//
//  Persistence: AppStorage in each consuming View. Keys:
//    - "sbt.income.period.v1"        → IncomePeriod.rawValue
//    - "sbt.income.weekStartDay.v1"  → WeekStartDay.rawValue (Int 1–7)
//
//  Backward compatibility: `WeeklyIncome` entries store explicit
//  weekStart / weekEnd dates, so previously-saved records render
//  correctly regardless of the user's current period selection.
//

import Foundation

// MARK: - Week start day

/// Which day the user's week "rolls over" on. Mirrors Apple's
/// `Calendar.firstWeekday` integer values so it can be passed
/// straight into a `Calendar` without translation.
enum WeekStartDay: Int, Codable, CaseIterable, Identifiable {
    case sunday    = 1
    case monday    = 2
    case tuesday   = 3
    case wednesday = 4
    case thursday  = 5
    case friday    = 6
    case saturday  = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sunday:    return "Sunday"
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        }
    }

    /// Resolve from the raw AppStorage Int, falling back to Monday
    /// (the v1.0 hardcoded behavior) if the stored value is invalid.
    static func from(rawValue: Int) -> WeekStartDay {
        WeekStartDay(rawValue: rawValue) ?? .monday
    }
}

// MARK: - Income tracking period

enum IncomePeriod: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    /// Picker label.
    var title: String {
        switch self {
        case .weekly:   return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly:  return "Monthly"
        }
    }

    /// Title used on the Dashboard's income card.
    var dashboardCardTitle: String {
        switch self {
        case .weekly:   return "Weekly Income"
        case .biweekly: return "Biweekly Income"
        case .monthly:  return "Monthly Income"
        }
    }

    /// Short label for the "this period" stat tile.
    var currentPeriodLabel: String {
        switch self {
        case .weekly:   return "This Week"
        case .biweekly: return "This Period"
        case .monthly:  return "This Month"
        }
    }

    /// Subtitle shown under the current-period income card on the
    /// Dashboard. Wording is income-specific (NOT "Total due this
    /// month" — that's bill copy and was leaking into income cards
    /// before v1.7).
    var periodCaption: String {
        switch self {
        case .weekly:   return "Income earned this week"
        case .biweekly: return "Income earned this pay period"
        case .monthly:  return "Income earned this month"
        }
    }

    /// Subtitle shown under the Last-30-Days income card.
    static let last30DaysCaption = "Income earned in last 30 days"

    /// Subtitle shown anywhere an all-time income total is displayed
    /// (CPA export, future All-Time card, etc.).
    static let allTimeCaption = "Total income recorded"

    /// Resolve from the raw AppStorage String, falling back to weekly.
    static func from(rawValue: String) -> IncomePeriod {
        IncomePeriod(rawValue: rawValue) ?? .weekly
    }

    /// Compute the current period [start, end] (inclusive end at 23:59:59)
    /// given the user's chosen first-day-of-week. For `.monthly`,
    /// `weekStartDay` is ignored — the calendar month is fixed.
    func currentBounds(
        weekStartDay: WeekStartDay,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        var cal = calendar
        cal.firstWeekday = weekStartDay.rawValue
        let today = cal.startOfDay(for: now)

        switch self {

        case .weekly:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else {
                return (today, endOfDay(today, cal: cal))
            }
            let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return (interval.start, end)

        case .biweekly:
            // Anchor: 1970-01-01 Unix epoch. Count whole-week buckets
            // between the anchor and the start of *this* week, then put
            // even-indexed buckets at the bottom of the biweek. That
            // guarantees a stable two-week window that never shifts
            // mid-month — the biweek the user is in only changes when
            // their week itself rolls over.
            guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today) else {
                return (today, endOfDay(today, cal: cal))
            }
            let anchor = Date(timeIntervalSince1970: 0) // 1970-01-01
            // Use number of days / 7 (integer) to avoid timezone-driven
            // weekOfYear ambiguity around year boundaries.
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: anchor),
                                          to: thisWeek.start).day ?? 0
            let weeksSinceAnchor = days / 7
            let isOdd = (weeksSinceAnchor % 2) != 0
            let biweekStart = isOdd
                ? (cal.date(byAdding: .day, value: -7, to: thisWeek.start) ?? thisWeek.start)
                : thisWeek.start
            let biweekEndExclusive = cal.date(byAdding: .day, value: 14, to: biweekStart)
                ?? cal.date(byAdding: .day, value: 14, to: thisWeek.start)
                ?? thisWeek.end
            let end = cal.date(byAdding: .second, value: -1, to: biweekEndExclusive) ?? biweekEndExclusive
            return (biweekStart, end)

        case .monthly:
            guard let interval = cal.dateInterval(of: .month, for: today) else {
                return (today, endOfDay(today, cal: cal))
            }
            let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return (interval.start, end)
        }
    }

    private func endOfDay(_ date: Date, cal: Calendar) -> Date {
        cal.date(bySettingHour: 23, minute: 59, second: 59,
                 of: cal.startOfDay(for: date)) ?? date
    }
}
