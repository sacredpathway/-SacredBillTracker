//
//  BillBucket.swift
//  SacredBillTracker
//
//  Identifies one of the four "snapshot" stat cards on the Dashboard.
//  Used as a `Hashable` `NavigationLink(value:)` payload so each card
//  pushes a filtered Bills list with the matching bucket of bills.
//

import Foundation

enum BillBucket: String, Hashable, Identifiable, CaseIterable {

    case dueToday
    case thisWeek
    case overdue
    case upcoming

    var id: String { rawValue }

    /// Short label used on the Dashboard StatCard.
    var shortTitle: String {
        switch self {
        case .dueToday: return "Due Today"
        case .thisWeek: return "This Week"
        case .overdue:  return "Overdue"
        case .upcoming: return "Upcoming"
        }
    }

    /// Long title shown at the top of the destination list.
    var listTitle: String {
        switch self {
        case .dueToday: return "Due Today Bills"
        case .thisWeek: return "This Week Bills"
        case .overdue:  return "Overdue Bills"
        case .upcoming: return "Upcoming Bills"
        }
    }

    /// Empty-state copy when the bucket has no bills.
    var emptyMessage: String {
        switch self {
        case .dueToday: return "Nothing is due today. Enjoy the road."
        case .thisWeek: return "Nothing on the books this week."
        case .overdue:  return "Nothing is overdue. Stay rooted."
        case .upcoming: return "No upcoming bills queued up."
        }
    }
}
