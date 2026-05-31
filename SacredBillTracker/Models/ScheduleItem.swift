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
    var location: String
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
        location: String = "",
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
        self.location = location
        self.notes = notes
        self.repeatRule = repeatRule
        self.customWeekdays = customWeekdays
        self.reminderMinutesBefore = reminderMinutesBefore
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startTime, endTime, location, notes, repeatRule, customWeekdays, reminderMinutesBefore, isComplete, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.startTime = (try? c.decode(Date.self, forKey: .startTime)) ?? Date()
        self.endTime = (try? c.decode(Date.self, forKey: .endTime)) ?? self.startTime
        self.location = (try? c.decode(String.self, forKey: .location)) ?? ""
        self.notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        self.repeatRule = (try? c.decode(FocusRepeatRule.self, forKey: .repeatRule)) ?? .oneTime
        self.customWeekdays = (try? c.decode(Set<Int>.self, forKey: .customWeekdays)) ?? []
        self.reminderMinutesBefore = try? c.decode(Int.self, forKey: .reminderMinutesBefore)
        self.isComplete = (try? c.decode(Bool.self, forKey: .isComplete)) ?? false
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(location, forKey: .location)
        try c.encode(notes, forKey: .notes)
        try c.encode(repeatRule, forKey: .repeatRule)
        try c.encode(customWeekdays, forKey: .customWeekdays)
        try c.encodeIfPresent(reminderMinutesBefore, forKey: .reminderMinutesBefore)
        try c.encode(isComplete, forKey: .isComplete)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
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
