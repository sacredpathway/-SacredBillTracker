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

    /// Pure translator — exposed for tests / previews.
    static func makeSnapshot(from bills: [Bill], now: Date = Date()) -> WidgetBillSnapshot {
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
            upcoming: upcoming
        )
    }
}
