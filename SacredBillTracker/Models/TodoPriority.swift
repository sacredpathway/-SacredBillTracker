//
//  TodoPriority.swift
//  SacredBillTracker
//

import SwiftUI

enum TodoPriority: String, Codable, CaseIterable, Identifiable, Hashable {
    case low, medium, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    /// Stable sort weight — high first.
    var sortWeight: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    var color: Color {
        switch self {
        case .low:    return .secondary
        case .medium: return Color.appAccentText
        case .high:   return .red
        }
    }

    var systemImage: String {
        switch self {
        case .low:    return "arrow.down.circle"
        case .medium: return "minus.circle"
        case .high:   return "exclamationmark.triangle.fill"
        }
    }
}
