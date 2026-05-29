//
//  BillHealthScore.swift
//  SacredBillTracker
//
//  Deterministic, AI-free 0–100 score for the dashboard's at-a-glance
//  health card. Uses the existing `Bill` model + `effectiveStatus` so
//  there's a single source of truth for "overdue" / "due today" /
//  "due soon".
//
//  Scoring:
//    100 base
//    -15 per overdue bill
//    - 4 per bill due today
//    - 2 per bill due in 1...7 days
//    floor 0
//
//  Status thresholds:
//    overdue > 0           → "Overdue bills found"   (red)
//    score   < 85          → "Needs attention"       (gold)
//    else                  → "Great shape"           (green)
//

import Foundation

struct BillHealthScore: Equatable {

    let score: Int
    let status: Status
    let overdueCount: Int
    let dueTodayCount: Int
    let dueSoonCount: Int

    enum Status: String {
        case great     = "Great shape"
        case attention = "Needs attention"
        case overdue   = "Overdue bills found"

        var systemImage: String {
            switch self {
            case .great:     return "leaf.fill"
            case .attention: return "exclamationmark.circle.fill"
            case .overdue:   return "exclamationmark.triangle.fill"
            }
        }
    }

    /// Compute the score from the user's full bills list. Excludes paid
    /// bills (handled bills don't drag the score) and excludes anything
    /// in Trash (`deletedAt != nil`).
    static func compute(from bills: [Bill], now: Date = Date()) -> BillHealthScore {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        var overdue = 0, todayCount = 0, soon = 0

        for bill in bills where bill.deletedAt == nil && !bill.isPaid {
            // Use the bill's own effectiveStatus where possible so this
            // matches the rest of the app's overdue/due semantics.
            if bill.effectiveStatus == .overdue {
                overdue += 1
                continue
            }
            let dueDay = calendar.startOfDay(for: bill.dueDate)
            let days   = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
            if days == 0       { todayCount += 1 }
            else if days <= 7  { soon += 1 }
        }

        var s = 100
        s -= overdue * 15
        s -= todayCount * 4
        s -= soon * 2
        s = max(0, s)

        let status: Status
        if overdue > 0 { status = .overdue }
        else if s < 85 { status = .attention }
        else           { status = .great }

        return BillHealthScore(
            score: s,
            status: status,
            overdueCount: overdue,
            dueTodayCount: todayCount,
            dueSoonCount: soon
        )
    }
}
