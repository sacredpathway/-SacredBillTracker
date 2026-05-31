//
//  IncomeStore.swift
//  SacredBillTracker
//
//  ObservableObject that manages WeeklyIncome entries. Mirrors the
//  shape of BillStore so views can inject it as an @EnvironmentObject.
//
//  Persistence: CloudBackedDefaults — writes go to BOTH UserDefaults
//  (local cache) AND NSUbiquitousKeyValueStore (iCloud). Survives app
//  delete/reinstall and syncs across the user's devices on the same
//  Apple ID. Requires entitlement
//  `com.apple.developer.ubiquity-kvstore-identifier`.
//

import Foundation
import SwiftUI

@MainActor
final class IncomeStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var entries: [WeeklyIncome] = []

    // MARK: - Storage

    private let defaultsKey = "sacred.bill.tracker.income.v1"
    private let storage: CloudBackedDefaults
    private var cloudObserver: NSObjectProtocol?

    // MARK: - Init

    init(storage: CloudBackedDefaults = .shared) {
        self.storage = storage
        load()
        // Reload when iCloud pushes external changes (e.g. data restored
        // after a reinstall, or another device updated entries).
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudBackedDefaults.storeDidUpdateLocally,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let keys = note.userInfo?["keys"] as? [String],
                keys.contains(self.defaultsKey)
            else { return }
            Task { @MainActor in self.load() }
        }
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    // MARK: - I/O

    private func load() {
        guard let data = storage.data(forKey: defaultsKey) else {
            entries = []
            IncomeWidgetBridge.update(from: entries)
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([WeeklyIncome].self, from: data)
            // Newest weeks first.
            entries = decoded.sorted { $0.weekStart > $1.weekStart }
            IncomeWidgetBridge.update(from: entries)
        } catch {
            entries = []
            IncomeWidgetBridge.update(from: entries)
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        storage.set(data, forKey: defaultsKey)
        IncomeWidgetBridge.update(from: entries)
    }

    // MARK: - CRUD

    func add(_ entry: WeeklyIncome) {
        var new = entry
        new.createdAt = Date()
        new.updatedAt = Date()
        entries.insert(new, at: 0)
        sort()
        persist()
    }

    func update(_ entry: WeeklyIncome) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.updatedAt = Date()
        entries[idx] = updated
        sort()
        persist()
    }

    func delete(_ entry: WeeklyIncome) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func delete(at offsets: IndexSet, from list: [WeeklyIncome]) {
        let ids = offsets.map { list[$0].id }
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    func wipeAll() {
        entries = []
        storage.remove(forKey: defaultsKey)
        BillWidgetBridge.clearSnapshotAndReloadTimelines()
    }

    private func sort() {
        entries.sort { $0.weekStart > $1.weekStart }
    }

    // MARK: - Totals

    /// Sum of entries whose week-start falls inside the user's current
    /// Mon→Sun week. (Matches `WeeklyIncome.currentWeekBounds`.)
    var thisWeekTotal: Decimal {
        let (start, end) = WeeklyIncome.currentWeekBounds()
        return entries
            .filter { $0.weekStart >= start && $0.weekStart <= end }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Sum of entries whose week-start is within the last 30 days
    /// (inclusive of today).
    var last30DaysTotal: Decimal {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -30, to: today) else { return 0 }
        return entries
            .filter { $0.weekStart >= start }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Sum of entries whose week-start falls inside the calendar month
    /// containing "now". Used by the v1.7 Share Bill Summary so the
    /// shared text can show a true "This Month" income figure.
    var thisMonthTotal: Decimal {
        let cal = Calendar.current
        let now = Date()
        return entries
            .filter {
                cal.component(.month, from: $0.weekStart) == cal.component(.month, from: now)
                && cal.component(.year,  from: $0.weekStart) == cal.component(.year,  from: now)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var allTimeTotal: Decimal {
        entries.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// All entries that fall (by `weekStart`) inside the given closed range.
    func entries(in range: ClosedRange<Date>) -> [WeeklyIncome] {
        entries.filter { range.contains($0.weekStart) }
    }

    /// Sum entries whose `weekStart` is in `range`.
    func total(in range: ClosedRange<Date>) -> Decimal {
        entries(in: range).reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Monthly breakdown across all entries — used by CPA export.
    /// Returned newest-month first.
    func monthlyBreakdown() -> [(month: Date, total: Decimal)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            let comps = cal.dateComponents([.year, .month], from: entry.weekStart)
            return cal.date(from: comps) ?? entry.weekStart
        }
        return grouped
            .map { (month: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.month > $1.month }
    }

    /// Monthly breakdown restricted to a date range.
    func monthlyBreakdown(in range: ClosedRange<Date>) -> [(month: Date, total: Decimal)] {
        let cal = Calendar.current
        let scoped = entries.filter { range.contains($0.weekStart) }
        let grouped = Dictionary(grouping: scoped) { entry -> Date in
            let comps = cal.dateComponents([.year, .month], from: entry.weekStart)
            return cal.date(from: comps) ?? entry.weekStart
        }
        return grouped
            .map { (month: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.month < $1.month }
    }

    // MARK: - Business / Personal split (v1.0.9)

    /// Sum entries of a given type inside a closed range.
    func total(in range: ClosedRange<Date>, type: IncomeType) -> Decimal {
        entries
            .filter { range.contains($0.weekStart) && $0.type == type }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// All-time total for a given type (used by IncomeListView totals
    /// and CPA summary).
    func allTimeTotal(type: IncomeType) -> Decimal {
        entries
            .filter { $0.type == type }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Returns the start/end bounds for a given dashboard period.
    /// Uses the user's WeekStartDay preference where relevant.
    func bounds(
        for period: IncomeDashboardPeriod,
        weekStartDay: WeekStartDay = .monday,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        var cal = calendar
        cal.firstWeekday = weekStartDay.rawValue
        let today = cal.startOfDay(for: now)
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? now

        switch period {

        case .thisWeek:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else {
                return today...endOfToday
            }
            let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return interval.start...end

        case .last30Days:
            let start = cal.date(byAdding: .day, value: -29, to: today) ?? today
            return start...endOfToday

        case .thisMonth:
            guard let interval = cal.dateInterval(of: .month, for: today) else {
                return today...endOfToday
            }
            let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return interval.start...end

        case .lastMonth:
            // Shift one month back, then take that month's full interval.
            let lastMonthDate = cal.date(byAdding: .month, value: -1, to: today) ?? today
            guard let interval = cal.dateInterval(of: .month, for: lastMonthDate) else {
                return today...endOfToday
            }
            let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return interval.start...end

        case .thisYear:
            guard let interval = cal.dateInterval(of: .year, for: today) else {
                return today...endOfToday
            }
            let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return interval.start...end

        case .allTime:
            // Distant past → end of today. Inclusive of every entry.
            let distantPast = Date(timeIntervalSince1970: 0)
            return distantPast...endOfToday
        }
    }
}

// MARK: - IncomeDashboardPeriod

/// User-selectable filter on the dashboard's Business / Personal income
/// section. Separate from `IncomePeriod` (which is the *income tracking*
/// preference) — this enum just picks which window the cards sum over.
enum IncomeDashboardPeriod: String, CaseIterable, Identifiable, Codable {
    case thisMonth
    case lastMonth
    case last30Days
    case thisWeek
    case thisYear
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisMonth:   return "This Month"
        case .lastMonth:   return "Last Month"
        case .last30Days:  return "Last 30 Days"
        case .thisWeek:    return "This Week"
        case .thisYear:    return "This Year"
        case .allTime:     return "All Time"
        }
    }

    /// Short label for the picker pill.
    var shortTitle: String {
        switch self {
        case .thisMonth:   return "Month"
        case .lastMonth:   return "Last Mo."
        case .last30Days:  return "30 Days"
        case .thisWeek:    return "Week"
        case .thisYear:    return "Year"
        case .allTime:     return "All"
        }
    }

    static func from(rawValue: String) -> IncomeDashboardPeriod {
        IncomeDashboardPeriod(rawValue: rawValue) ?? .thisMonth
    }
}
