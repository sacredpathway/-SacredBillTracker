//
//  ScheduleItem.swift
//  SacredBillTracker
//
//  Single Sacred Focus schedule entry. Codable for local persistence
//  via UserDefaults (mirrors IncomeStore / BillStore patterns).
//

import Foundation

struct ScheduleItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var notes: String

    var repeatRule: FocusRepeatRule
    /// 1 = Sunday … 7 = Saturday (matches `Calendar.component(.weekday:…)`).
    /// Only consulted when `repeatRule == .custom`.
    var customWeekdays: Set<Int>

    /// Minutes-before-start when the user wants a reminder. nil = none.
    var reminderMinutesBefore: Int?

    var isComplete: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        startTime: Date,
        endTime: Date,
        notes: String = "",
        repeatRule: FocusRepeatRule = .oneTime,
        customWeekdays: Set<Int> = [],
        reminderMinutesBefore: Int? = nil,
        isComplete: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.repeatRule = repeatRule
        self.customWeekdays = customWeekdays
        self.reminderMinutesBefore = reminderMinutesBefore
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var duration: TimeInterval {
        max(0, endTime.timeIntervalSince(startTime))
    }

    var durationLabel: String {
        let seconds = Int(duration)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0          { return "\(h)h" }
        if m > 0          { return "\(m)m" }
        return "—"
    }

    /// Does this item occur on the given calendar day?
    func occursOn(_ date: Date, calendar: Calendar = .current) -> Bool {
        repeatRule.occursOn(
            date,
            anchorDate: startTime,
            customWeekdays: customWeekdays,
            calendar: calendar
        )
    }

    /// Time-of-day label, e.g. "9:00 AM – 10:30 AM" (locale-aware).
    var timeRangeLabel: String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return "\(fmt.string(from: startTime)) – \(fmt.string(from: endTime))"
    }
}
