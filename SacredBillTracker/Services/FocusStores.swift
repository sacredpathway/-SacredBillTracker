//
//  FocusStores.swift
//  SacredBillTracker
//
//  Local-only stores for Sacred Focus schedule items and to-dos.
//  UserDefaults-backed (mirrors IncomeStore). MainActor-isolated.
//

import Foundation
import SwiftUI

@MainActor
final class ScheduleStore: ObservableObject {

    @Published private(set) var items: [ScheduleItem] = []

    private let key = "sbt.focus.schedule.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
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
    }

    func update(_ item: ScheduleItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var u = item
        u.updatedAt = Date()
        items[idx] = u
        sort()
        persist()
    }

    func delete(_ item: ScheduleItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func toggleComplete(_ item: ScheduleItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isComplete.toggle()
        items[idx].updatedAt = Date()
        persist()
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
    }

    func update(_ item: FocusTodo) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var u = item
        u.updatedAt = Date()
        items[idx] = u
        sort()
        persist()
    }

    func delete(_ item: FocusTodo) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func toggleComplete(_ item: FocusTodo) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isComplete.toggle()
        items[idx].updatedAt = Date()
        sort()
        persist()
    }

    // MARK: - Queries

    func items(for date: Date, calendar: Calendar = .current) -> [FocusTodo] {
        items.filter { $0.appearsOn(date, calendar: calendar) }
    }
}
