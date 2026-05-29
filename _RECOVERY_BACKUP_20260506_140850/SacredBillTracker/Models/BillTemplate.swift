//
//  BillTemplate.swift
//  SacredBillTracker
//
//  Common bill presets that seed a new bill with sensible defaults.
//

import Foundation

struct BillTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let category: BillCategory
    let recurrence: RecurrenceType
    let type: BillType
    let autoPaySuggested: Bool
    let systemImage: String

    /// Seeds a `Bill` from this template. Amount defaults to zero so the
    /// user is forced to confirm the dollar value.
    func makeBill(dueDate: Date = Date()) -> Bill {
        Bill(
            name: name,
            amount: 0,
            dueDate: dueDate,
            category: category,
            recurrence: recurrence,
            type: type,
            autoPay: autoPaySuggested,
            notes: "",
            status: .unpaid
        )
    }
}

enum BillTemplates {
    static let all: [BillTemplate] = [
        // Household
        BillTemplate(id: "rent",        name: "Rent",          category: .rent,          recurrence: .monthly, type: .household, autoPaySuggested: false, systemImage: "house.fill"),
        BillTemplate(id: "electric",    name: "Electric",      category: .utilities,     recurrence: .monthly, type: .household, autoPaySuggested: true,  systemImage: "bolt.fill"),
        BillTemplate(id: "internet",    name: "Internet",      category: .internet,      recurrence: .monthly, type: .household, autoPaySuggested: true,  systemImage: "wifi"),
        BillTemplate(id: "phone",       name: "Phone",         category: .phone,         recurrence: .monthly, type: .household, autoPaySuggested: true,  systemImage: "phone.fill"),
        BillTemplate(id: "insurance",   name: "Insurance",     category: .insurance,     recurrence: .monthly, type: .household, autoPaySuggested: true,  systemImage: "shield.fill"),
        BillTemplate(id: "subscription",name: "Subscription",  category: .subscriptions, recurrence: .monthly, type: .household, autoPaySuggested: true,  systemImage: "repeat.circle.fill"),

        // Business / owner-operator
        BillTemplate(id: "trucknote",   name: "Truck Note",    category: .transportation, recurrence: .monthly, type: .business,  autoPaySuggested: false, systemImage: "truck.box.fill"),
        BillTemplate(id: "fuelcard",    name: "Fuel Card",     category: .transportation, recurrence: .weekly,  type: .business,  autoPaySuggested: false, systemImage: "fuelpump.fill"),
        BillTemplate(id: "software",    name: "Software",      category: .software,       recurrence: .monthly, type: .business,  autoPaySuggested: true,  systemImage: "laptopcomputer"),
        BillTemplate(id: "officerent",  name: "Office Rent",   category: .rentBusiness,   recurrence: .monthly, type: .business,  autoPaySuggested: false, systemImage: "building.2.fill"),
    ]
}
