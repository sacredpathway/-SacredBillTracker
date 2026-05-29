//
//  FocusTodo.swift
//  SacredBillTracker
//
//  Sacred Focus to-do entry. Supersedes the lightweight `FocusTask`
//  used by the prior placeholder. A migration path lets us decode old
//  `FocusTask` JSON shaped as { id, text, done } into the richer
//  format with sensible defaults so users don't lose their tasks.
//

import Foundation

struct FocusTodo: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var notes: String

    /// Day the task is due. Combined with `hasTime` to decide whether
    /// we surface a time component.
    var dueDate: Date
    /// When false, the time component of `dueDate` is ignored at the
    /// display layer.
    var hasTime: Bool

    var priority: TodoPriority
    var repeatRule: FocusRepeatRule
    var customWeekdays: Set<Int>

    var isComplete: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date = Date(),
        hasTime: Bool = false,
        priority: TodoPriority = .medium,
        repeatRule: FocusRepeatRule = .oneTime,
        customWeekdays: Set<Int> = [],
        isComplete: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priority = priority
        self.repeatRule = repeatRule
        self.customWeekdays = customWeekdays
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Codable migration

    /// Decode that tolerates the legacy `FocusTask` shape
    /// (`{ id, text, done }`) so users who already added quick to-dos
    /// don't lose them when the model upgrades.
    private enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, hasTime, priority, repeatRule, customWeekdays, isComplete, createdAt, updatedAt
        // Legacy keys
        case text, done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        if let t = try? c.decode(String.self, forKey: .title) {
            self.title = t
        } else {
            self.title = (try? c.decode(String.self, forKey: .text)) ?? ""
        }
        self.notes     = (try? c.decode(String.self, forKey: .notes)) ?? ""
        self.dueDate   = (try? c.decode(Date.self, forKey: .dueDate)) ?? Date()
        self.hasTime   = (try? c.decode(Bool.self, forKey: .hasTime)) ?? false
        self.priority  = (try? c.decode(TodoPriority.self, forKey: .priority)) ?? .medium
        self.repeatRule = (try? c.decode(FocusRepeatRule.self, forKey: .repeatRule)) ?? .oneTime
        self.customWeekdays = (try? c.decode(Set<Int>.self, forKey: .customWeekdays)) ?? []
        if let complete = try? c.decode(Bool.self, forKey: .isComplete) {
            self.isComplete = complete
        } else {
            self.isComplete = (try? c.decode(Bool.self, forKey: .done)) ?? false
        }
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    /// Explicit encoder so the synthesized one doesn't try to write the
    /// legacy `text` / `done` keys (which are decode-only).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(notes, forKey: .notes)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encode(hasTime, forKey: .hasTime)
        try c.encode(priority, forKey: .priority)
        try c.encode(repeatRule, forKey: .repeatRule)
        try c.encode(customWeekdays, forKey: .customWeekdays)
        try c.encode(isComplete, forKey: .isComplete)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    /// Does this todo show on the given day?
    func appearsOn(_ date: Date, calendar: Calendar = .current) -> Bool {
        repeatRule.occursOn(
            date,
            anchorDate: dueDate,
            customWeekdays: customWeekdays,
            calendar: calendar
        )
    }
}
