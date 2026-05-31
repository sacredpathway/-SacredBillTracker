//
//  FocusStores.swift
//  SacredBillTracker
//
//  Local-only stores for Sacred Focus schedule items and to-dos.
//  UserDefaults-backed (mirrors IncomeStore). MainActor-isolated.
//

import Foundation
import SwiftUI

struct FocusNote: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
final class NoteStore: ObservableObject {

    @Published private(set) var items: [FocusNote] = []

    private let key = "sbt.focus.notes.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([FocusNote].self, from: data)) ?? []
        sort()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    private func sort() {
        items.sort { $0.updatedAt > $1.updatedAt }
    }

    func add(_ item: FocusNote) {
        var new = item
        new.createdAt = Date()
        new.updatedAt = Date()
        items.insert(new, at: 0)
        sort()
        persist()
    }

    func update(_ item: FocusNote) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()
        items[idx] = updated
        sort()
        persist()
    }

    func delete(_ item: FocusNote) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    var mostRecent: FocusNote? {
        items.max { $0.updatedAt < $1.updatedAt }
    }
}

@MainActor
final class ScheduleStore: ObservableObject {

    @Published private(set) var items: [ScheduleItem] = []

    private let key = "sbt.focus.schedule.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        rescheduleReminders()
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ScheduleItem].self, from: data)) ?? []
        sort()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    private func sort() {
        items.sort { $0.startTime < $1.startTime }
    }

    func add(_ item: ScheduleItem) {
        var new = item
        new.createdAt = Date()
        new.updatedAt = Date()
        items.append(new)
        sort()
        persist()
        syncReminder(for: new)
    }

    func update(_ item: ScheduleItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var u = item
        u.updatedAt = Date()
        items[idx] = u
        sort()
        persist()
        syncReminder(for: u)
    }

    func delete(_ item: ScheduleItem) {
        items.removeAll { $0.id == item.id }
        persist()
        Task { await NotificationManager.shared.cancelScheduleReminders(for: item.id) }
    }

    func toggleComplete(_ item: ScheduleItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isComplete.toggle()
        items[idx].updatedAt = Date()
        persist()
        syncReminder(for: items[idx])
    }

    // MARK: - Queries

    /// All items whose recurrence rule places them on the given day.
    func items(on date: Date, calendar: Calendar = .current) -> [ScheduleItem] {
        items
            .filter { $0.occursOn(date, calendar: calendar) }
            .sorted { lhs, rhs in
                let cal = calendar
                let lhsTime = cal.dateComponents([.hour, .minute], from: lhs.startTime)
                let rhsTime = cal.dateComponents([.hour, .minute], from: rhs.startTime)
                let lh = (lhsTime.hour ?? 0) * 60 + (lhsTime.minute ?? 0)
                let rh = (rhsTime.hour ?? 0) * 60 + (rhsTime.minute ?? 0)
                return lh < rh
            }
    }

    private func rescheduleReminders() {
        let snapshot = items
        Task { await NotificationManager.shared.rescheduleScheduleReminders(for: snapshot) }
    }

    private func syncReminder(for item: ScheduleItem) {
        Task {
            await NotificationManager.shared.cancelScheduleReminders(for: item.id)
            await NotificationManager.shared.scheduleReminder(for: item)
        }
    }
}

@MainActor
final class TodoStore: ObservableObject {

    @Published private(set) var items: [FocusTodo] = []

    private let key = "sbt.focus.todos.v2"
    private let legacyKey = "sbt.focusplus.todos.v1"  // AppStorage JSON from earlier placeholder
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        rescheduleReminders()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = defaults.data(forKey: key) {
            items = (try? decoder.decode([FocusTodo].self, from: data)) ?? []
        } else if let legacyString = defaults.string(forKey: legacyKey),
                  let legacyData = legacyString.data(using: .utf8),
                  let legacy = try? decoder.decode([FocusTodo].self, from: legacyData) {
            // v1.0.9 → productivity-system migration. FocusTodo's
            // custom decoder tolerates the old `{id, text, done}` shape.
            items = legacy
            persist()
        }
        sort()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    private func sort() {
        items.sort { a, b in
            if a.isComplete != b.isComplete { return !a.isComplete && b.isComplete }
            if a.priority.sortWeight != b.priority.sortWeight {
                return a.priority.sortWeight < b.priority.sortWeight
            }
            return a.dueDate < b.dueDate
        }
    }

    func add(_ item: FocusTodo) {
        var new = item
        new.createdAt = Date()
        new.updatedAt = Date()
        items.insert(new, at: 0)
        sort()
        persist()
        syncReminder(for: new)
    }

    func update(_ item: FocusTodo) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var u = item
        u.updatedAt = Date()
        items[idx] = u
        sort()
        persist()
        syncReminder(for: u)
    }

    func delete(_ item: FocusTodo) {
        items.removeAll { $0.id == item.id }
        persist()
        Task { await NotificationManager.shared.cancelTodoReminder(for: item.id) }
    }

    func toggleComplete(_ item: FocusTodo) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isComplete.toggle()
        items[idx].updatedAt = Date()
        sort()
        persist()
        syncReminder(for: items[idx])
    }

    // MARK: - Queries

    func items(for date: Date, calendar: Calendar = .current) -> [FocusTodo] {
        items.filter { $0.appearsOn(date, calendar: calendar) }
    }

    private func rescheduleReminders() {
        let snapshot = items
        Task { await NotificationManager.shared.rescheduleTodoReminders(for: snapshot) }
    }

    private func syncReminder(for item: FocusTodo) {
        Task {
            await NotificationManager.shared.cancelTodoReminder(for: item.id)
            await NotificationManager.shared.scheduleReminder(for: item)
        }
    }
}
