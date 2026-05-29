//
//  BillSortOption.swift
//  SacredBillTracker
//
//  Sort modes for the Bills screen. Persisted via @AppStorage so the
//  user's preferred ordering survives launches.
//

import Foundation

enum BillSortOption: String, CaseIterable, Identifiable, Codable {
    case nameAsc          // 1.  A → Z
    case nameDesc         // 2.  Z → A
    case amountDesc       // 3.  Highest → Lowest
    case amountAsc        // 4.  Lowest  → Highest
    case dueSoonest       // 5.  Soonest first (default)
    case dueLatest        // 6.  Latest first
    case recentlyAdded    // 7.  Most recently added
    case oldestAdded      // 8.  Oldest added
    case paidStatus       // 9.  Unpaid → Overdue → Paid
    case overdueFirst     // 10. Overdue → Unpaid → Paid
    case category         // 11. Category A → Z
    case frequency        // 12. Most-frequent → Least-frequent (weekly → annual)
    case businessFirst    // 13. Business → Household
    case personalFirst    // 14. Household → Business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAsc:        return "Name (A → Z)"
        case .nameDesc:       return "Name (Z → A)"
        case .amountDesc:     return "Amount (High → Low)"
        case .amountAsc:      return "Amount (Low → High)"
        case .dueSoonest:     return "Due Date (Soonest)"
        case .dueLatest:      return "Due Date (Latest)"
        case .recentlyAdded:  return "Recently Added"
        case .oldestAdded:    return "Oldest Added"
        case .paidStatus:     return "Paid Status"
        case .overdueFirst:   return "Overdue First"
        case .category:       return "Category"
        case .frequency:      return "Frequency"
        case .businessFirst:  return "Business First"
        case .personalFirst:  return "Personal First"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAsc:        return "textformat.abc"
        case .nameDesc:       return "textformat.abc.dottedunderline"
        case .amountDesc:     return "arrow.down.right.circle"
        case .amountAsc:      return "arrow.up.right.circle"
        case .dueSoonest:     return "calendar.badge.clock"
        case .dueLatest:      return "calendar"
        case .recentlyAdded:  return "clock.arrow.circlepath"
        case .oldestAdded:    return "clock"
        case .paidStatus:     return "checkmark.seal"
        case .overdueFirst:   return "exclamationmark.triangle.fill"
        case .category:       return "folder"
        case .frequency:      return "repeat"
        case .businessFirst:  return "briefcase.fill"
        case .personalFirst:  return "house.fill"
        }
    }
}

// MARK: - Sorting

extension Array where Element == Bill {

    /// Returns `self` ordered by the given sort option. All sorts are
    /// stable for the secondary key (due date asc) so equal primary
    /// keys produce a deterministic order.
    func sorted(by option: BillSortOption) -> [Bill] {
        switch option {
        case .nameAsc:
            return sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .amountDesc:
            return sorted { $0.amount > $1.amount }
        case .amountAsc:
            return sorted { $0.amount < $1.amount }
        case .dueSoonest:
            return sorted { $0.dueDate < $1.dueDate }
        case .dueLatest:
            return sorted { $0.dueDate > $1.dueDate }
        case .recentlyAdded:
            return sorted { $0.createdAt > $1.createdAt }
        case .oldestAdded:
            return sorted { $0.createdAt < $1.createdAt }
        case .paidStatus:
            // Unpaid → Overdue → Paid; tie-break by soonest due date.
            return sorted { lhs, rhs in
                let l = paidStatusRank(for: lhs)
                let r = paidStatusRank(for: rhs)
                if l != r { return l < r }
                return lhs.dueDate < rhs.dueDate
            }
        case .overdueFirst:
            return sorted { lhs, rhs in
                let l = overdueRank(for: lhs)
                let r = overdueRank(for: rhs)
                if l != r { return l < r }
                return lhs.dueDate < rhs.dueDate
            }
        case .category:
            return sorted { lhs, rhs in
                let l = lhs.category.title
                let r = rhs.category.title
                if l != r { return l.localizedCaseInsensitiveCompare(r) == .orderedAscending }
                return lhs.dueDate < rhs.dueDate
            }
        case .frequency:
            // Most-frequent first: weekly < biweekly < monthly < quarterly
            //                  < semiAnnual < annual < oneTime
            return sorted { lhs, rhs in
                let l = frequencyRank(lhs.recurrence)
                let r = frequencyRank(rhs.recurrence)
                if l != r { return l < r }
                return lhs.dueDate < rhs.dueDate
            }
        case .businessFirst:
            return sorted { lhs, rhs in
                if lhs.type != rhs.type { return lhs.type == .business }
                return lhs.dueDate < rhs.dueDate
            }
        case .personalFirst:
            return sorted { lhs, rhs in
                if lhs.type != rhs.type { return lhs.type == .household }
                return lhs.dueDate < rhs.dueDate
            }
        }
    }

    private func paidStatusRank(for bill: Bill) -> Int {
        switch bill.effectiveStatus {
        case .unpaid:  return 0
        case .overdue: return 1
        case .paid:    return 2
        }
    }

    private func overdueRank(for bill: Bill) -> Int {
        switch bill.effectiveStatus {
        case .overdue: return 0
        case .unpaid:  return 1
        case .paid:    return 2
        }
    }

    private func frequencyRank(_ r: RecurrenceType) -> Int {
        switch r {
        case .weekly:     return 0
        case .biweekly:   return 1
        case .monthly:    return 2
        case .quarterly:  return 3
        case .semiAnnual: return 4
        case .annual:     return 5
        case .oneTime:    return 6
        }
    }
}
