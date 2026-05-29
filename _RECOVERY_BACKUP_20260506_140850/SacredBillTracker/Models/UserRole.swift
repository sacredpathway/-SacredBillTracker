//
//  UserRole.swift
//  SacredBillTracker
//
//  Role-based access for Sacred Pathway LLC trucking features.
//  Persisted in UserDefaults so the user keeps their role across launches.
//

import Foundation
import SwiftUI

enum UserRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case driver
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driver: return "Driver"
        case .admin:  return "Admin / Dispatcher"
        }
    }

    var systemImage: String {
        switch self {
        case .driver: return "truck.box.fill"
        case .admin:  return "person.badge.shield.checkmark.fill"
        }
    }
}

// MARK: - Paystub model

/// A generated paystub rolling approved loads into driver pay.
struct Paystub: Identifiable, Codable, Hashable {

    var id: UUID
    var driverId: UUID
    var driverName: String
    var payPeriodStart: Date
    var payPeriodEnd: Date
    var loadIds: [UUID]                 // IDs of loads rolled in
    var totalGross: Decimal             // sum of gross amounts
    var driverPayRate: Decimal          // 0.05 for v1
    var driverPayAmount: Decimal        // totalGross * driverPayRate
    var totalMiles: Double
    var loadCount: Int
    var generatedAt: Date
    var notes: String

    init(
        id: UUID = UUID(),
        driverId: UUID,
        driverName: String,
        payPeriodStart: Date,
        payPeriodEnd: Date,
        loadIds: [UUID],
        totalGross: Decimal,
        driverPayRate: Decimal = Decimal(0.05),
        totalMiles: Double,
        loadCount: Int,
        generatedAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.driverId = driverId
        self.driverName = driverName
        self.payPeriodStart = payPeriodStart
        self.payPeriodEnd = payPeriodEnd
        self.loadIds = loadIds
        self.totalGross = totalGross
        self.driverPayRate = driverPayRate
        self.driverPayAmount = totalGross * driverPayRate
        self.totalMiles = totalMiles
        self.loadCount = loadCount
        self.generatedAt = generatedAt
        self.notes = notes
    }

    var formattedPay: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: driverPayAmount as NSDecimalNumber) ?? "$\(driverPayAmount)"
    }

    var formattedGross: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: totalGross as NSDecimalNumber) ?? "$\(totalGross)"
    }

    var payPeriodLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return "\(fmt.string(from: payPeriodStart)) – \(fmt.string(from: payPeriodEnd))"
    }
}
