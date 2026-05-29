//
//  PaymentStatus.swift
//  SacredBillTracker
//

import Foundation
import SwiftUI

enum PaymentStatus: String, Codable, CaseIterable, Identifiable {
    case paid
    case unpaid
    case overdue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paid:    return "Paid"
        case .unpaid:  return "Unpaid"
        case .overdue: return "Overdue"
        }
    }

    var color: Color {
        switch self {
        case .paid:    return .green
        case .unpaid:  return .orange
        case .overdue: return .appDanger   // stronger true red (presentation only)
        }
    }

    var systemImage: String {
        switch self {
        case .paid:    return "checkmark.seal.fill"
        case .unpaid:  return "clock.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }
}
