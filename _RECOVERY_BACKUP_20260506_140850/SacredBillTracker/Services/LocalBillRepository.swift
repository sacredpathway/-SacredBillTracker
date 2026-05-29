//
//  LocalBillRepository.swift
//  SacredBillTracker
//
//  Default repository backed by UserDefaults (JSON encoded).
//

import Foundation

final class LocalBillRepository: BillRepository {

    private let key = "sacred.bill.tracker.bills.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadBills() async throws -> [Bill] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Bill].self, from: data)
    }

    func saveBills(_ bills: [Bill]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bills)
        defaults.set(data, forKey: key)
    }

    func upsert(_ bill: Bill) async throws {
        var bills = (try? await loadBills()) ?? []
        if let idx = bills.firstIndex(where: { $0.id == bill.id }) {
            bills[idx] = bill
        } else {
            bills.append(bill)
        }
        try await saveBills(bills)
    }

    func delete(id: UUID) async throws {
        var bills = (try? await loadBills()) ?? []
        bills.removeAll { $0.id == id }
        try await saveBills(bills)
    }

    func deleteAll() async throws {
        defaults.removeObject(forKey: key)
    }
}
