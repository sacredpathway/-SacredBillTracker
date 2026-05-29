//
//  LocalBillRepository.swift
//  SacredBillTracker
//
//  Default repository backed by UserDefaults (JSON encoded).
//
//  NOTE on soft-delete: storage holds ALL bills (active + soft-deleted).
//  `loadBills()` filters to active only; `loadDeletedBills()` filters to
//  soft-deleted only. Filtering happens at read time so callers never
//  have to reason about it.
//

import Foundation

final class LocalBillRepository: BillRepository {

    private let key = "sacred.bill.tracker.bills.v1"
    // Cloud-backed so anonymous / offline users don't lose bills when
    // they delete & reinstall the app. Logged-in users continue to hit
    // Supabase via the caching repository on top of this.
    private let storage: CloudBackedDefaults

    init(storage: CloudBackedDefaults = .shared) {
        self.storage = storage
    }

    // MARK: - Internal raw I/O

    private func loadAllRaw() async throws -> [Bill] {
        guard let data = storage.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Bill].self, from: data)
    }

    private func saveAllRaw(_ bills: [Bill]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bills)
        storage.set(data, forKey: key)
    }

    // MARK: - BillRepository

    func loadBills() async throws -> [Bill] {
        let all = (try? await loadAllRaw()) ?? []
        return all.filter { $0.deletedAt == nil }
    }

    func loadDeletedBills() async throws -> [Bill] {
        let all = (try? await loadAllRaw()) ?? []
        return all
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// UPSERT — writes each bill in `bills` to local storage, preserving
    /// any row that's already in storage but absent from `bills` (so a
    /// soft-deleted entry already on disk is NOT silently dropped just
    /// because the caller passed in an active-only snapshot).
    func saveBills(_ bills: [Bill]) async throws {
        var current = (try? await loadAllRaw()) ?? []
        for bill in bills {
            if let idx = current.firstIndex(where: { $0.id == bill.id }) {
                current[idx] = bill
            } else {
                current.append(bill)
            }
        }
        try await saveAllRaw(current)
    }

    func upsert(_ bill: Bill) async throws {
        var bills = (try? await loadAllRaw()) ?? []
        if let idx = bills.firstIndex(where: { $0.id == bill.id }) {
            bills[idx] = bill
        } else {
            bills.append(bill)
        }
        try await saveAllRaw(bills)
    }

    func softDelete(id: UUID) async throws {
        var bills = (try? await loadAllRaw()) ?? []
        if let idx = bills.firstIndex(where: { $0.id == id }) {
            let now = Date()
            bills[idx].deletedAt = now
            bills[idx].updatedAt = now
            try await saveAllRaw(bills)
        }
    }

    func restore(id: UUID) async throws {
        var bills = (try? await loadAllRaw()) ?? []
        if let idx = bills.firstIndex(where: { $0.id == id }) {
            bills[idx].deletedAt = nil
            bills[idx].updatedAt = Date()
            try await saveAllRaw(bills)
        }
    }

    func delete(id: UUID) async throws {
        var bills = (try? await loadAllRaw()) ?? []
        bills.removeAll { $0.id == id }
        try await saveAllRaw(bills)
    }

    func deleteAll() async throws {
        storage.remove(forKey: key)
    }
}
