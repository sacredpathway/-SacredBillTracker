//
//  BillWidgetBridge.swift
//  SacredBillTracker (main app only)
//
//  Translates the live `[Bill]` from BillStore into a small JSON snapshot
//  inside the App Group container, then kicks every active widget
//  timeline. Called after every mutation in BillStore.
//
//  Safe to call on every mutation:
//   • If the App Group isn't provisioned the writer no-ops (returns false).
//   • WidgetCenter.shared.reloadAllTimelines() is a cheap no-op when no
//     widget is installed on the device.
//

import Foundation
import WidgetKit

enum BillWidgetBridge {

    /// Build a snapshot from the current bills list, write it into the
    /// shared App Group container, and reload widget timelines.
    static func update(from bills: [Bill], now: Date = Date()) {
        let snapshot = makeSnapshot(from: bills, now: now)
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Privacy cleanup for sign-out/account deletion. Unlike
    /// `update(from: [])`, this removes both bill and income data from
    /// the shared App Group snapshot.
    static func clearSnapshotAndReloadTimelines() {
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Pure translator — exposed for tests / previews.
    static func makeSnapshot(from bills: [Bill], now: Date = Date()) -> WidgetBillSnapshot {
        let previous = WidgetSnapshotStore.load()
        let live = bills.filter { $0.deletedAt == nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let endOfWeek = cal.date(byAdding: .day, value: 7, to: today) ?? today

        // Upcoming = unpaid bills, sorted ascending by due date. Overdue
        // bills sort first because their dueDate is in the past.
        let upcoming: [WidgetBillSummary] = live
            .filter { !$0.isPaid }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(8) // cap for snapshot size
            .map { bill in
                WidgetBillSummary(
                    id: bill.id.uuidString,
                    name: bill.name,
                    amount: (bill.amount as NSDecimalNumber).doubleValue,
                    dueDate: bill.dueDate,
                    isPaid: bill.isPaid,
                    isOverdue: bill.isOverdue,
                    categoryTitle: bill.category.title
                )
            }

        let overdueCount = live.filter { $0.isOverdue }.count
        let dueTodayCount = live.filter { !$0.isPaid && cal.isDate($0.dueDate, inSameDayAs: now) }.count
        let dueThisWeekCount = live.filter { bill in
            guard !bill.isPaid else { return false }
            let d = cal.startOfDay(for: bill.dueDate)
            return d >= today && d <= endOfWeek
        }.count

        let monthlyTotalDecimal = live
            .filter { $0.isDueThisMonth }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let monthlyTotal = (monthlyTotalDecimal as NSDecimalNumber).doubleValue

        return WidgetBillSnapshot(
            generatedAt: now,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            dueThisWeekCount: dueThisWeekCount,
            monthlyTotal: monthlyTotal,
            monthlyIncomeTotal: previous.monthlyIncomeTotal,
            thisWeekIncomeTotal: previous.thisWeekIncomeTotal,
            healthScore: BillHealthScore.compute(from: live, now: now).score,
            upcoming: upcoming,
            recentIncome: previous.recentIncome
        )
    }
}

enum IncomeWidgetBridge {

    static func update(from entries: [WeeklyIncome], now: Date = Date()) {
        let previous = WidgetSnapshotStore.load()
        let snapshot = makeSnapshot(from: entries, previous: previous, now: now)
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func makeSnapshot(
        from entries: [WeeklyIncome],
        previous: WidgetBillSnapshot = WidgetSnapshotStore.load(),
        now: Date = Date()
    ) -> WidgetBillSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let month = cal.dateInterval(of: .month, for: today)
        let week = cal.dateInterval(of: .weekOfYear, for: today)

        let monthlyIncome = entries
            .filter { entry in
                guard let month else { return false }
                return month.contains(entry.entryDate)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }

        let weeklyIncome = entries
            .filter { entry in
                guard let week else { return false }
                return week.contains(entry.entryDate)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }

        let recentIncome = entries
            .sorted { $0.entryDate > $1.entryDate }
            .prefix(6)
            .map { entry in
                WidgetIncomeSummary(
                    id: entry.id.uuidString,
                    name: entry.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Income" : entry.sourceName,
                    amount: (entry.amount as NSDecimalNumber).doubleValue,
                    entryDate: entry.entryDate,
                    typeTitle: entry.type.title
                )
            }

        return WidgetBillSnapshot(
            generatedAt: now,
            overdueCount: previous.overdueCount,
            dueTodayCount: previous.dueTodayCount,
            dueThisWeekCount: previous.dueThisWeekCount,
            monthlyTotal: previous.monthlyTotal,
            monthlyIncomeTotal: (monthlyIncome as NSDecimalNumber).doubleValue,
            thisWeekIncomeTotal: (weeklyIncome as NSDecimalNumber).doubleValue,
            healthScore: previous.healthScore,
            upcoming: previous.upcoming,
            recentIncome: Array(recentIncome)
        )
    }
}
