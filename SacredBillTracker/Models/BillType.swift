//
//  BillType.swift
//  SacredBillTracker
//
//  Household vs. Business classification.
//

import Foundation
import SwiftUI

enum BillType: String, Codable, CaseIterable, Identifiable {
    case household
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .household: return "Personal"
        case .business:  return "Business"
        }
    }

    var systemImage: String {
        switch self {
        case .household: return "house.fill"
        case .business:  return "briefcase.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .household: return .appHousehold
        case .business:  return .appBusiness
        }
    }
}

/// Used as a filter across every listing screen.
enum BillTypeFilter: String, CaseIterable, Identifiable {
    case all
    case household
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       return "All"
        case .household: return "Personal"
        case .business:  return "Business"
        }
    }

    func matches(_ type: BillType) -> Bool {
        switch self {
        case .all:       return true
        case .household: return type == .household
        case .business:  return type == .business
        }
    }
}
