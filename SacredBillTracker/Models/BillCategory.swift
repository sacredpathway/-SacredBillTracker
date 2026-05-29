//
//  BillCategory.swift
//  SacredBillTracker
//

import Foundation
import SwiftUI

enum BillCategory: String, Codable, CaseIterable, Identifiable {
    // Household
    case rent
    case mortgage
    case utilities
    case internet
    case phone
    case insurance
    case groceries
    case subscriptions
    case transportation
    case medical
    case tithe
    case childcare
    case creditCard
    case lineOfCredit

    // Business
    case software
    case payroll
    case officeSupplies
    case marketing
    case taxes
    case legal
    case rentBusiness
    case utilitiesBusiness
    case equipment
    case services

    // Shared
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rent: return "Rent"
        case .mortgage: return "Mortgage"
        case .utilities: return "Utilities"
        case .internet: return "Internet"
        case .phone: return "Phone"
        case .insurance: return "Insurance"
        case .groceries: return "Groceries"
        case .subscriptions: return "Subscriptions"
        case .transportation: return "Transportation"
        case .medical: return "Medical"
        case .tithe: return "Tithe / Giving"
        case .childcare: return "Childcare"
        case .creditCard: return "Credit Card"
        case .lineOfCredit: return "Line of Credit"
        case .software: return "Software / SaaS"
        case .payroll: return "Payroll"
        case .officeSupplies: return "Office Supplies"
        case .marketing: return "Marketing"
        case .taxes: return "Taxes"
        case .legal: return "Legal / Professional"
        case .rentBusiness: return "Business Rent"
        case .utilitiesBusiness: return "Business Utilities"
        case .equipment: return "Equipment"
        case .services: return "Services"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .rent, .mortgage, .rentBusiness: return "house"
        case .utilities, .utilitiesBusiness:  return "bolt.fill"
        case .internet:       return "wifi"
        case .phone:          return "phone.fill"
        case .insurance:      return "shield.fill"
        case .groceries:      return "cart.fill"
        case .subscriptions:  return "repeat.circle.fill"
        case .transportation: return "car.fill"
        case .medical:        return "cross.case.fill"
        case .tithe:          return "heart.fill"
        case .childcare:      return "figure.and.child.holdinghands"
        case .creditCard:     return "creditcard.fill"
        case .lineOfCredit:   return "creditcard.and.123"
        case .software:       return "laptopcomputer"
        case .payroll:        return "person.3.fill"
        case .officeSupplies: return "pencil.and.ruler.fill"
        case .marketing:      return "megaphone.fill"
        case .taxes:          return "doc.text.fill"
        case .legal:          return "scalemass.fill"
        case .equipment:      return "wrench.and.screwdriver.fill"
        case .services:       return "hands.sparkles.fill"
        case .other:          return "tag.fill"
        }
    }

    static var householdCategories: [BillCategory] {
        [.rent, .mortgage, .utilities, .internet, .phone, .insurance,
         .groceries, .subscriptions, .transportation, .medical, .tithe,
         .childcare, .creditCard, .lineOfCredit, .other]
    }

    static var businessCategories: [BillCategory] {
        [.software, .payroll, .officeSupplies, .marketing, .taxes, .legal,
         .rentBusiness, .utilitiesBusiness, .equipment, .services,
         .subscriptions, .insurance, .creditCard, .lineOfCredit, .other]
    }

    /// Revolving-credit / credit-card-style categories. Used by the
    /// 15/3 Paydown Plan toggle to decide whether the option is shown
    /// for this bill.
    static var revolvingCreditCategories: [BillCategory] {
        [.creditCard, .lineOfCredit]
    }

    var isRevolvingCredit: Bool {
        BillCategory.revolvingCreditCategories.contains(self)
    }

    static func categories(for type: BillType) -> [BillCategory] {
        switch type {
        case .household: return householdCategories
        case .business:  return businessCategories
        }
    }
}
