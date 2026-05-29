//
//  LoadStore.swift
//  SacredBillTracker
//
//  Central ObservableObject for the load-submission pipeline.
//  Handles driver load submissions, admin review, and paystub generation.
//
//  Persistence: UserDefaults (mirrors LocalBillRepository pattern).
//  Supabase sync can be layered in later via a CachingLoadRepository.
//

import Foundation
import SwiftUI

// MARK: - Repository protocol

protocol LoadRepository {
    func loadAll() async throws -> [SubmittedLoad]
    func saveAll(_ loads: [SubmittedLoad]) async throws
    func loadPaystubs() async throws -> [Paystub]
    func savePaystubs(_ stubs: [Paystub]) async throws
}

// MARK: - Local persistence

final class LocalLoadRepository: LoadRepository {

    private let loadsKey    = "sacred.bill.tracker.submitted_loads.v1"
    private let paystubsKey = "sacred.bill.tracker.paystubs.v1"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Cloud-backed storage so submitted loads + paystubs survive
    // app delete/reinstall and sync across the user's devices.
    private let storage: CloudBackedDefaults = .shared

    func loadAll() async throws -> [SubmittedLoad] {
        guard let data = storage.data(forKey: loadsKey) else { return [] }
        return try decoder.decode([SubmittedLoad].self, from: data)
    }

    func saveAll(_ loads: [SubmittedLoad]) async throws {
        let data = try encoder.encode(loads)
        storage.set(data, forKey: loadsKey)
    }

    func loadPaystubs() async throws -> [Paystub] {
        guard let data = storage.data(forKey: paystubsKey) else { return [] }
        return try decoder.decode([Paystub].self, from: data)
    }

    func savePaystubs(_ stubs: [Paystub]) async throws {
        let data = try encoder.encode(stubs)
        storage.set(data, forKey: paystubsKey)
    }
}

// MARK: - Store

@MainActor
final class LoadStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var loads: [SubmittedLoad] = []
    @Published private(set) var paystubs: [Paystub] = []
    @Published var isLoading: Bool = false

    /// The active user role. Persisted to UserDefaults.
    @Published var userRole: UserRole {
        didSet { UserDefaults.standard.set(userRole.rawValue, forKey: roleKey) }
    }

    // MARK: - Dependencies

    private let repository: LoadRepository
    private let roleKey = "sacred.bill.tracker.user.role.v1"

    // MARK: - Init

    init(repository: LoadRepository = LocalLoadRepository()) {
        self.repository = repository

        // Restore role from UserDefaults, defaulting to driver.
        if let raw = UserDefaults.standard.string(forKey: roleKey),
           let role = UserRole(rawValue: raw) {
            self.userRole = role
        } else {
            self.userRole = .driver
        }

        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    func reload() async {
        await bootstrap()
    }

    private func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            loads = try await repository.loadAll()
            paystubs = try await repository.loadPaystubs()
        } catch {
            loads = []
            paystubs = []
        }
    }

    // MARK: - Driver actions

    /// Submit a new load. Called by the driver.
    func submitLoad(_ load: SubmittedLoad) {
        var newLoad = load
        newLoad.status = .submitted
        newLoad.createdAt = Date()
        newLoad.updatedAt = Date()
        loads.append(newLoad)
        persistLoads()
    }

    /// Loads belonging to a specific driver, sorted newest first.
    func loads(forDriver driverId: UUID) -> [SubmittedLoad] {
        loads
            .filter { $0.driverId == driverId }
            .sorted { $0.loadDate > $1.loadDate }
    }

    // MARK: - Admin actions

    /// All loads pending review.
    var pendingLoads: [SubmittedLoad] {
        loads
            .filter { $0.status == .submitted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Approved loads not yet rolled into a paystub.
    var approvedLoads: [SubmittedLoad] {
        loads
            .filter { $0.status == .approved }
            .sorted { $0.loadDate < $1.loadDate }
    }

    /// Approve a load. Requires gross amount to be set.
    func approveLoad(_ load: SubmittedLoad) {
        guard load.grossAmount != nil else { return }
        updateStatus(loadId: load.id, to: .approved)
    }

    /// Reject a load with optional notes.
    func rejectLoad(_ load: SubmittedLoad, reason: String = "") {
        guard let idx = loads.firstIndex(where: { $0.id == load.id }) else { return }
        loads[idx].status = .rejected
        if !reason.isEmpty {
            loads[idx].notes = reason
        }
        loads[idx].updatedAt = Date()
        persistLoads()
    }

    /// Update the gross amount on a load (admin editing before approval).
    func updateGrossAmount(loadId: UUID, amount: Decimal) {
        guard let idx = loads.firstIndex(where: { $0.id == loadId }) else { return }
        loads[idx].grossAmount = amount
        loads[idx].updatedAt = Date()
        persistLoads()
    }

    /// Update miles on a load.
    func updateMiles(loadId: UUID, miles: Double) {
        guard let idx = loads.firstIndex(where: { $0.id == loadId }) else { return }
        loads[idx].miles = miles
        loads[idx].updatedAt = Date()
        persistLoads()
    }

    /// Generate a paystub from all approved loads for a specific driver
    /// within a pay period. Marks those loads as rolled_into_paystub.
    func generatePaystub(
        driverId: UUID,
        driverName: String,
        payPeriodStart: Date,
        payPeriodEnd: Date
    ) -> Paystub? {
        let eligible = loads.filter {
            $0.driverId == driverId
            && $0.status == .approved
            && $0.loadDate >= payPeriodStart
            && $0.loadDate <= payPeriodEnd
            && $0.grossAmount != nil
        }

        guard !eligible.isEmpty else { return nil }

        let totalGross = eligible.compactMap(\.grossAmount).reduce(Decimal(0), +)
        let totalMiles = eligible.reduce(0.0) { $0 + $1.miles }
        let loadIds = eligible.map(\.id)

        let stub = Paystub(
            driverId: driverId,
            driverName: driverName,
            payPeriodStart: payPeriodStart,
            payPeriodEnd: payPeriodEnd,
            loadIds: loadIds,
            totalGross: totalGross,
            totalMiles: totalMiles,
            loadCount: eligible.count
        )

        // Mark loads as rolled into paystub
        for loadId in loadIds {
            updateStatus(loadId: loadId, to: .rolledIntoPaystub)
        }

        paystubs.append(stub)
        persistPaystubs()

        return stub
    }

    /// Roll ALL approved loads (across all drivers) into paystubs, grouped by driver.
    func generateAllPaystubs(payPeriodStart: Date, payPeriodEnd: Date) -> [Paystub] {
        let approved = loads.filter {
            $0.status == .approved
            && $0.loadDate >= payPeriodStart
            && $0.loadDate <= payPeriodEnd
            && $0.grossAmount != nil
        }

        let grouped = Dictionary(grouping: approved, by: \.driverId)
        var generated: [Paystub] = []

        for (driverId, driverLoads) in grouped {
            let name = driverLoads.first?.driverName ?? "Unknown"
            if let stub = generatePaystub(
                driverId: driverId,
                driverName: name,
                payPeriodStart: payPeriodStart,
                payPeriodEnd: payPeriodEnd
            ) {
                generated.append(stub)
            }
        }

        return generated
    }

    /// Unique driver IDs from approved loads (for paystub generation UI).
    var driversWithApprovedLoads: [(id: UUID, name: String)] {
        let approved = loads.filter { $0.status == .approved }
        var seen = Set<UUID>()
        var result: [(id: UUID, name: String)] = []
        for load in approved {
            if !seen.contains(load.driverId) {
                seen.insert(load.driverId)
                result.append((id: load.driverId, name: load.driverName))
            }
        }
        return result
    }

    // MARK: - Queries

    /// All loads with a given status.
    func loads(withStatus status: LoadStatus) -> [SubmittedLoad] {
        loads.filter { $0.status == status }
    }

    /// Paystubs for a specific driver.
    func paystubs(forDriver driverId: UUID) -> [Paystub] {
        paystubs
            .filter { $0.driverId == driverId }
            .sorted { $0.generatedAt > $1.generatedAt }
    }

    // MARK: - Private helpers

    private func updateStatus(loadId: UUID, to status: LoadStatus) {
        guard let idx = loads.firstIndex(where: { $0.id == loadId }) else { return }
        loads[idx].status = status
        loads[idx].updatedAt = Date()
        persistLoads()
    }

    private func persistLoads() {
        let snapshot = loads
        Task { try? await repository.saveAll(snapshot) }
    }

    private func persistPaystubs() {
        let snapshot = paystubs
        Task { try? await repository.savePaystubs(snapshot) }
    }

    /// Delete a load (driver can delete their own submitted loads).
    func deleteLoad(_ load: SubmittedLoad) {
        loads.removeAll { $0.id == load.id }
        persistLoads()
    }
}
