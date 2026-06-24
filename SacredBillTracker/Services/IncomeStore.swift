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
    @Published private var profileContext: ManagedProfileContext = ManagedProfileStore.shared.context

    // MARK: - Storage

    private let defaultsKey = "sacred.bill.tracker.income.v1"
    private let storage: CloudBackedDefaults
    private var cloudObserver: NSObjectProtocol?

    private func attributionDebugLog(_ message: String) {
        #if DEBUG
        print("[AppsFlyer][Income] \(message)")
        #endif
    }

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

    var profileEntries: [WeeklyIncome] {
        guard profileContext.ownerID != nil else { return [] }
        return entries.filter {
            profileContext.owns(ownerID: $0.ownerUserID)
            && profileContext.includes(profileID: $0.profileID)
        }
    }

    func applyProfileContext(_ context: ManagedProfileContext) {
        guard profileContext != context else { return }
        profileContext = context
        if adoptLegacyEntriesIfNeeded() {
            persist()
            return
        }
        IncomeWidgetBridge.update(from: profileEntries)
    }

    private func stampProfileIfNeeded(_ entry: inout WeeklyIncome) {
        if entry.ownerUserID == nil {
            entry.ownerUserID = profileContext.ownerID
        }
        if entry.profileID == nil {
            entry.profileID = profileContext.writeProfileID
        }
    }

    private func adoptLegacyEntriesIfNeeded() -> Bool {
        guard let ownerID = profileContext.ownerID else { return false }
        var changed = false
        for idx in entries.indices where entries[idx].ownerUserID == nil {
            entries[idx].ownerUserID = ownerID
            if entries[idx].profileID == nil {
                entries[idx].profileID = profileContext.defaultProfileID
            }
            entries[idx].updatedAt = Date()
            changed = true
        }
        return changed
    }

    // MARK: - I/O

    private func load() {
        guard let data = storage.data(forKey: defaultsKey) else {
            entries = []
            IncomeWidgetBridge.update(from: profileEntries)
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([WeeklyIncome].self, from: data)
            // Newest weeks first.
            entries = decoded.sorted { $0.weekStart > $1.weekStart }
            if adoptLegacyEntriesIfNeeded() {
                persist()
            } else {
                IncomeWidgetBridge.update(from: profileEntries)
            }
        } catch {
            entries = []
            IncomeWidgetBridge.update(from: profileEntries)
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        storage.set(data, forKey: defaultsKey)
        IncomeWidgetBridge.update(from: profileEntries)
    }

    // MARK: - CRUD

    func add(_ entry: WeeklyIncome) {
        var new = entry
        stampProfileIfNeeded(&new)
        new.createdAt = Date()
        new.updatedAt = Date()
        entries.insert(new, at: 0)
        sort()
        persist()
        // Attribution: income_created (no-op while AppsFlyer is dormant).
        #if canImport(AppsFlyerLib)
        attributionDebugLog("Income add success path reached; requesting income_created")
        AppsFlyerManager.shared.logIncomeCreated()
        #endif
    }

    func update(_ entry: WeeklyIncome) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        stampProfileIfNeeded(&updated)
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

    // MARK: - Bank-imported income (AutoTrack / Plaid)

    /// Replaces ALL previously bank-imported entries with `imported`, while
    /// leaving manually-entered income untouched. Idempotent: calling it
    /// repeatedly with the latest server truth never duplicates deposits.
    /// Imported entries are stamped to the current profile so they appear in
    /// the dashboard income counter.
    func syncBankIncome(_ imported: [WeeklyIncome]) {
        let manual = entries.filter { $0.externalRef == nil }
        var bank = imported
        for idx in bank.indices { stampProfileIfNeeded(&bank[idx]) }
        entries = manual + bank
        sort()
        persist()
    }

    /// Pulls INCOME-category deposits from connected banks (via the
    /// premium-gated `autotrack_income_entries` RPC) and merges them into the
    /// income counter. No-op if Supabase isn't linked or the user isn't
    /// AutoTrack-entitled (the RPC simply returns no rows). Safe to call on
    /// every dashboard appearance and after a Plaid sync.
    func refreshBankIncome() async {
        #if canImport(Supabase)
        struct Row: Decodable {
            let plaid_transaction_id: String
            let txn_date: String
            let amount: Double
            let source_name: String?
            let institution_name: String?
            /// Source account's business/personal classification. Used so
            /// business deposits never land in Personal totals.
            let usage_type: String?

            private enum K: String, CodingKey {
                case plaid_transaction_id, txn_date, amount, source_name, institution_name, usage_type
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: K.self)
                plaid_transaction_id = try c.decode(String.self, forKey: .plaid_transaction_id)
                txn_date = try c.decode(String.self, forKey: .txn_date)
                // numeric may arrive as a JSON number or string — accept both.
                if let d = try? c.decode(Double.self, forKey: .amount) {
                    amount = d
                } else if let s = try? c.decode(String.self, forKey: .amount), let d = Double(s) {
                    amount = d
                } else {
                    amount = 0
                }
                source_name = try c.decodeIfPresent(String.self, forKey: .source_name)
                institution_name = try c.decodeIfPresent(String.self, forKey: .institution_name)
                usage_type = try c.decodeIfPresent(String.self, forKey: .usage_type)
            }
        }

        do {
            let rows: [Row] = try await SupabaseConfig.client
                .rpc("autotrack_income_entries")
                .execute()
                .value

            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            df.dateFormat = "yyyy-MM-dd"

            let imported: [WeeklyIncome] = rows.compactMap { r in
                guard r.amount > 0, let day = df.date(from: r.txn_date) else { return nil }
                let source = (r.source_name?.isEmpty == false) ? r.source_name! : "Bank deposit"
                let note = r.institution_name.map { "Imported from \($0)" } ?? "Imported from bank"
                // Route the deposit by its source account's classification so
                // business income is never mixed into Personal totals. `unknown`
                // accounts stay out of both Personal and Business (All only).
                let usage = AccountUsageType(safe: r.usage_type)
                return WeeklyIncome(
                    amount: Decimal(r.amount),
                    weekStart: day,
                    weekEnd: day,
                    type: usage.incomeType,
                    sourceName: source,
                    note: note,
                    externalRef: r.plaid_transaction_id,
                    bankUsage: usage
                )
            }
            syncBankIncome(imported)
        } catch {
            #if DEBUG
            print("[AutoTrack] income sync failed: \(error)")
            #endif
        }
        #endif
    }

    // MARK: - Totals

    /// Sum of entries whose week-start falls inside the user's current
    /// Mon→Sun week. (Matches `WeeklyIncome.currentWeekBounds`.)
    var thisWeekTotal: Decimal {
        let (start, end) = WeeklyIncome.currentWeekBounds()
        return profileEntries
            .filter { $0.weekStart >= start && $0.weekStart <= end }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Sum of entries whose week-start is within the last 30 days
    /// (inclusive of today).
    var last30DaysTotal: Decimal {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -30, to: today) else { return 0 }
        return profileEntries
            .filter { $0.weekStart >= start }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Sum of entries whose week-start falls inside the calendar month
    /// containing "now". Used by the v1.7 Share Bill Summary so the
    /// shared text can show a true "This Month" income figure.
    var thisMonthTotal: Decimal {
        let cal = Calendar.current
        let now = Date()
        return profileEntries
            .filter {
                cal.component(.month, from: $0.weekStart) == cal.component(.month, from: now)
                && cal.component(.year,  from: $0.weekStart) == cal.component(.year,  from: now)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var allTimeTotal: Decimal {
        profileEntries.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// All entries that fall (by `weekStart`) inside the given closed range.
    func entries(in range: ClosedRange<Date>) -> [WeeklyIncome] {
        profileEntries.filter { range.contains($0.weekStart) }
    }

    /// Sum entries whose `weekStart` is in `range`.
    func total(in range: ClosedRange<Date>) -> Decimal {
        entries(in: range).reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Monthly breakdown across all entries — used by CPA export.
    /// Returned newest-month first.
    func monthlyBreakdown() -> [(month: Date, total: Decimal)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: profileEntries) { entry -> Date in
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
        let scoped = profileEntries.filter { range.contains($0.weekStart) }
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
        profileEntries
            .filter { range.contains($0.weekStart) && $0.type == type }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// All-time total for a given type (used by IncomeListView totals
    /// and CPA summary).
    func allTimeTotal(type: IncomeType) -> Decimal {
        profileEntries
            .filter { $0.type == type }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    // MARK: - All / Personal / Business tabs (v1.9 — account classification)
    //
    // These sum by the entry's `usageTab` (bank account classification for
    // imported income, IncomeType for manual income). Business income is
    // therefore NEVER counted under Personal, and `unknown` bank income only
    // appears in the unfiltered ("All") totals — exactly the tab contract:
    //   All      = personal + business + unknown
    //   Personal = only personal-classified entries
    //   Business = only business-classified entries

    /// Entries for a tab. Pass `nil` (or `.unknown` is treated literally) —
    /// `nil` means "All" and returns every entry.
    func entries(usage: AccountUsageType?) -> [WeeklyIncome] {
        guard let usage else { return profileEntries }
        return profileEntries.filter { $0.usageTab == usage }
    }

    /// All-time total for a tab. `nil` = All.
    func allTimeTotal(usage: AccountUsageType?) -> Decimal {
        entries(usage: usage).reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Total within a date range for a tab. `nil` = All.
    func total(in range: ClosedRange<Date>, usage: AccountUsageType?) -> Decimal {
        entries(usage: usage)
            .filter { range.contains($0.weekStart) }
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
