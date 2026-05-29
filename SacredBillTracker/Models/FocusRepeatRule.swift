//
//  FocusRepeatRule.swift
//  SacredBillTracker
//
//  Shared recurrence rule for Sacred Focus schedule items and todos.
//  Encoded once into UserDefaults so the user's repeat preference
//  survives relaunch and is readable across both surfaces.
//

import Foundation

enum FocusRepeatRule: String, Codable, CaseIterable, Identifiable, Hashable {
    case oneTime
    case daily
    case weekly
    case monthly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneTime: return "One-time"
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        case .custom:  return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .oneTime: return "1.circle"
        case .daily:   return "repeat"
        case .weekly:  return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .custom:  return "slider.horizontal.3"
        }
    }

    /// Returns true if an item with this rule should appear on `date`
    /// given its `anchorDate` (the original start) and optional set of
    /// custom weekdays (1 = Sunday … 7 = Saturday, matches Calendar).
    ///
    /// The match is calendar-day based — start-of-day comparisons —
    /// so a 9:00 AM item still shows up "today" at 11 PM.
    func occursOn(
        _ date: Date,
        anchorDate: Date,
        customWeekdays: Set<Int> = [],
        calendar: Calendar = .current
    ) -> Bool {
        let day      = calendar.startOfDay(for: date)
        let anchor   = calendar.startOfDay(for: anchorDate)

        // Future-dated items never show before their anchor.
        if day < anchor { return false }

        switch self {
        case .oneTime:
            return calendar.isDate(day, inSameDayAs: anchor)

        case .daily:
            return true   // anchor or later → always

        case .weekly:
            let comps = calendar.dateComponents([.weekday], from: anchor)
            let target = calendar.dateComponents([.weekday], from: day)
            return comps.weekday == target.weekday

        case .monthly:
            let comps = calendar.dateComponents([.day], from: anchor)
            let target = calendar.dateComponents([.day], from: day)
            return comps.day == target.day

        case .custom:
            guard !customWeekdays.isEmpty else { return false }
            let weekday = calendar.component(.weekday, from: day)
            return customWeekdays.contains(weekday)
        }
    }
}

/// Convenience labels for custom weekday picker.
enum FocusWeekday: Int, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }
    var shortLabel: String {
        switch self {
        case .sunday:    return "Sun"
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        }
    }
}
