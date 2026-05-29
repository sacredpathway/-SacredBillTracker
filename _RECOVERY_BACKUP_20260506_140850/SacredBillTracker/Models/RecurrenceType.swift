//
//  RecurrenceType.swift
//  SacredBillTracker
//

import Foundation

enum RecurrenceType: String, Codable, CaseIterable, Identifiable {
    case oneTime
    case weekly
    case biweekly
    case monthly
    case quarterly
    case semiAnnual
    case annual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneTime:    return "One-Time"
        case .weekly:     return "Weekly"
        case .biweekly:   return "Biweekly"
        case .monthly:    return "Monthly"
        case .quarterly:  return "Quarterly"
        case .semiAnnual: return "Semi-Annual"
        case .annual:     return "Annual"
        }
    }

    var isRecurring: Bool { self != .oneTime }

    /// Returns the next due date given a current due date, or nil if one-time.
    func nextDueDate(from date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneTime:
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date)
        case .semiAnnual:
            return calendar.date(byAdding: .month, value: 6, to: date)
        case .annual:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}
