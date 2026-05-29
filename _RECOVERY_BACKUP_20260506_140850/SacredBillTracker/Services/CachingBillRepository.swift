//
//  CachingBillRepository.swift
//  SacredBillTracker
//
//  Offline-first decorator: reads return the local cache immediately
//  (instant first paint), then kick off a remote refresh in the
//  background. Writes are duplicated — remote first, local second, so
//  that if the network is down the write still completes locally and
//  can be reconciled on a later successful sync.
//
//  Also handles the one-time **migration** of local-only bills up to
//  Supabase the first time the user signs in. Migration is idempotent
//  and keyed in UserDefaults.
//

import Foundation

final class CachingBillRepository: BillRepository {

    private let local: BillRepository
    private let remote: BillRepository

    /// Keyed in UserDefaults so the migration runs at most once per
    /// Supabase user per device. Reset automatically on sign-out.
    private let migrationKey = "sacred.bill.tracker.migration.v1"
    private let defaults: UserDefaults

    init(local: BillRepository,
         remote: BillRepository,
         defaults: UserDefaults = .standard)
    {
        self.local = local
        self.remote = remote
        self.defaults = defaults
    }

    // MARK: - BillRepository

    /// Returns local cache first; if remote succeeds, replaces local
    /// cache and returns the remote copy on the next call. For an
    /// explicit network refresh, call `refreshFromRemote()`.
    func loadBills() async throws -> [Bill] {
        // Optimistic: serve from local immediately.
        let cached = (try? await local.loadBills()) ?? []

        // Pull remote in the background and overwrite local if it
        // succeeds. We swallow errors here so a network hiccup doesn't
        // blow away the cached view.
        Task.detached { [weak self] in
            guard let self else { return }
            _ = try? await self.refreshFromRemote()
        }

        return cached
    }

    /// Pulls authoritative list from remote, writes to local cache,
    /// returns the fresh list. Throws if remote fails — caller decides
    /// whether to fall back.
    @discardableResult
    func refreshFromRemote() async throws -> [Bill] {
        let remoteBills = try await remote.loadBills()
        try await local.saveBills(remoteBills)
        return remoteBills
    }

    func saveBills(_ bills: [Bill]) async throws {
        // Write local first so the user's own device sees changes
        // immediately even if the network is flaky.
        try? await local.saveBills(bills)
        try await remote.saveBills(bills)
    }

    func upsert(_ bill: Bill) async throws {
        try? await local.upsert(bill)
        try await remote.upsert(bill)
    }

    func delete(id: UUID) async throws {
        try? await local.delete(id: id)
        try await remote.delete(id: id)
    }

    func deleteAll() async throws {
        try? await local.deleteAll()
        try await remote.deleteAll()
    }

    // MARK: - First-sign-in migration

    /// Push any local-only bills up to the remote the first time a given
    /// user signs in on a given device. Call from `AuthService` after a
    /// successful sign-in.
    ///
    /// - Parameter userID: the Supabase-assigned user id (used to key
    ///   the idempotency flag).
    func migrateLocalToRemoteIfNeeded(userID: UUID) async {
        let key = "\(migrationKey).\(userID.uuidString)"
        guard !defaults.bool(forKey: key) else { return }

        do {
            // CRITICAL: strip legacy v1.0 demo bills from local cache BEFORE
            // anything else. If iCloud Backup restored stale demo data into
            // UserDefaults, this prevents them from ever reaching Supabase.
            // A brand-new user must start with ZERO bills.
            let rawLocal = try await local.loadBills()
            let localBills = LegacyDemoBills.filterOut(rawLocal)
            // If filtering removed entries, persist the cleaned set immediately
            // so demo bills can never leak through any other code path.
            if localBills.count != rawLocal.count {
                try? await local.saveBills(localBills)
            }
            // Nothing to migrate — still flip the flag so we don't retry.
            guard !localBills.isEmpty else {
                defaults.set(true, forKey: key)
                return
            }

            // Remote side may already have newer bills from another
            // device — merge by id preferring the newer updatedAt.
            let remoteBills = (try? await remote.loadBills()) ?? []
            let merged = Self.merge(local: localBills, remote: remoteBills)

            try await remote.saveBills(merged.filter { bill in
                // Only push bills that are new or newer than remote.
                guard let remoteMatch = remoteBills.first(where: { $0.id == bill.id }) else { return true }
                return bill.updatedAt > remoteMatch.updatedAt
            })
            // Overwrite local with the merged authoritative set.
            try? await local.saveBills(merged)

            defaults.set(true, forKey: key)
        } catch {
            // Don't set the flag — try again next launch.
        }
    }

    /// Reset the migration flag so a re-sign-in re-runs migration for
    /// that user/device pair. Call on sign-out.
    func resetMigrationFlag(userID: UUID) {
        let key = "\(migrationKey).\(userID.uuidString)"
        defaults.removeObject(forKey: key)
    }

    /// Wipe the local bill cache. Called on sign-out so a different
    /// account signing in on the same device cannot read the previous
    /// user's bills out of UserDefaults before the remote refresh
    /// completes.
    func clearLocalCache() async {
        try? await local.saveBills([])
    }

    // MARK: - Merge policy

    private static func merge(local: [Bill], remote: [Bill]) -> [Bill] {
        var byID: [UUID: Bill] = [:]
        for bill in remote { byID[bill.id] = bill }
        for bill in local {
            if let existing = byID[bill.id] {
                byID[bill.id] = bill.updatedAt > existing.updatedAt ? bill : existing
            } else {
                byID[bill.id] = bill
            }
        }
        return Array(byID.values).sorted { $0.dueDate < $1.dueDate }
    }
}
