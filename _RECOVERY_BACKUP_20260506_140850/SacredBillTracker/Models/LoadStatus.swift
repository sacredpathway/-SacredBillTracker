//
//  LoadStatus.swift
//  SacredBillTracker
//
//  Status lifecycle for driver-submitted loads:
//    submitted → approved / rejected
//    approved  → rolled_into_paystub
//

import SwiftUI

enum LoadStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case submitted
    case approved
    case rejected
    case rolledIntoPaystub = "rolled_into_paystub"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .submitted:         return "Submitted"
        case .approved:          return "Approved"
        case .rejected:          return "Rejected"
        case .rolledIntoPaystub: return "Paid"
        }
    }

    var systemImage: String {
        switch self {
        case .submitted:         return "paperplane.fill"
        case .approved:          return "checkmark.circle.fill"
        case .rejected:          return "xmark.circle.fill"
        case .rolledIntoPaystub: return "banknote.fill"
        }
    }

    var color: Color {
        switch self {
        case .submitted:         return .orange
        case .approved:          return .appLime
        case .rejected:          return .red
        case .rolledIntoPaystub: return .appAccent
        }
    }

    /// Statuses visible to drivers in the filter picker.
    static let driverVisible: [LoadStatus] = [.submitted, .approved, .rejected, .rolledIntoPaystub]

    /// Statuses the admin can act on (approve / reject).
    static let reviewable: [LoadStatus] = [.submitted]
}
