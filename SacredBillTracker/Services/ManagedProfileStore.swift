//
//  ManagedProfileStore.swift
//  SacredBillTracker
//
//  Loads and manages account-owned financial profiles. A profile is a
//  data partition inside one account, not a separate auth identity.
//

import Foundation
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class ManagedProfileStore: ObservableObject {

    static let shared = ManagedProfileStore()

    @Published private(set) var profiles: [ManagedProfile]
    @Published var selection: ManagedProfileSelection {
        didSet { persistSelection() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isPremiumUnlocked = false
    @Published var lastError: String?

    private let localDefaultIDKey = "sbt.managedProfiles.localDefaultID.v1"
    private let selectionKeyPrefix = "sbt.managedProfiles.selection.v1"
    private let table = "financial_profiles"
    private var currentOwnerID: UUID?

    private init() {
        let defaultID = Self.localDefaultID(key: localDefaultIDKey)
        let defaultProfile = ManagedProfile(
            id: defaultID,
            ownerID: nil,
            name: "My Bills",
            kind: .personal,
            isDefault: true
        )
        self.profiles = [defaultProfile]
        self.selection = .profile(defaultID)
    }

    var context: ManagedProfileContext {
        ManagedProfileContext(
            ownerID: currentOwnerID,
            selection: normalizedSelection(),
            defaultProfileID: defaultProfile?.id
        )
    }

    var defaultProfile: ManagedProfile? {
        profiles.first(where: \.isDefault) ?? profiles.sortedForDisplay.first
    }

    var selectedProfile: ManagedProfile? {
        guard let id = normalizedSelection().selectedProfileID else { return nil }
        return profiles.first { $0.id == id }
    }

    var selectionTitle: String {
        switch normalizedSelection() {
        case .allProfiles:
            return "All Profiles"
        case .profile:
            return selectedProfile?.name ?? defaultProfile?.name ?? "My Bills"
        }
    }

    var canUseManagedProfiles: Bool {
        isPremiumUnlocked
    }

    var premiumRequiredMessage: String {
        PremiumMessaging.managedProfiles
    }

    func applyPremiumAccess(_ isUnlocked: Bool) {
        isPremiumUnlocked = isUnlocked
        guard !isUnlocked else { return }
        enforceFreeSelection()
    }

    var selectionIcon: String {
        switch normalizedSelection() {
        case .allProfiles:
            return "square.grid.2x2.fill"
        case .profile:
            return selectedProfile?.iconSystemName ?? "person.crop.circle.fill"
        }
    }

    func loadForSignedInUser(userID: UUID, displayName: String? = nil) async {
        currentOwnerID = userID
        isLoading = true
        defer { isLoading = false }

        #if canImport(Supabase)
        do {
            let loaded = try await loadRemoteProfiles()
            if loaded.isEmpty {
                let created = try await createRemoteProfile(
                    name: defaultProfileName(displayName: displayName),
                    kind: .personal,
                    isDefault: true,
                    sortOrder: 0
                )
                profiles = [created]
            } else {
                profiles = normalizedProfiles(loaded)
            }
            restoreSelectionForCurrentOwner()
            enforceFreeSelection()
            lastError = nil
            return
        } catch {
            lastError = error.localizedDescription
        }
        #endif

        ensureLocalProfile(ownerID: userID, displayName: displayName)
        restoreSelectionForCurrentOwner()
        enforceFreeSelection()
    }

    func resetForSignedOutUser() {
        currentOwnerID = nil
        let defaultID = Self.localDefaultID(key: localDefaultIDKey)
        profiles = [
            ManagedProfile(
                id: defaultID,
                ownerID: nil,
                name: "My Bills",
                kind: .personal,
                isDefault: true
            )
        ]
        selection = .profile(defaultID)
        lastError = nil
    }

    func selectAllProfiles() {
        guard canUseManagedProfiles else {
            rejectPremiumOnlyAction()
            return
        }
        selection = .allProfiles
    }

    func select(profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        guard canUseManagedProfiles || profileID == defaultProfile?.id else {
            rejectPremiumOnlyAction()
            return
        }
        selection = .profile(profileID)
    }

    @discardableResult
    func createProfile(name: String, kind: ManagedProfileKind) async -> ManagedProfile? {
        guard canUseManagedProfiles else {
            rejectPremiumOnlyAction()
            return nil
        }

        let trimmed = cleanedName(name)
        guard !trimmed.isEmpty else {
            lastError = "Profile name is required."
            return nil
        }

        let sortOrder = ((profiles.map(\.sortOrder).max() ?? -1) + 1)

        #if canImport(Supabase)
        if currentOwnerID != nil {
            do {
                let created = try await createRemoteProfile(
                    name: trimmed,
                    kind: kind,
                    isDefault: profiles.isEmpty,
                    sortOrder: sortOrder
                )
                profiles = normalizedProfiles(profiles + [created])
                selection = .profile(created.id)
                lastError = nil
                return created
            } catch {
                lastError = error.localizedDescription
                return nil
            }
        }
        #endif

        let created = ManagedProfile(
            ownerID: currentOwnerID,
            name: trimmed,
            kind: kind,
            isDefault: profiles.isEmpty,
            sortOrder: sortOrder
        )
        profiles = normalizedProfiles(profiles + [created])
        selection = .profile(created.id)
        return created
    }

    func updateProfile(_ profile: ManagedProfile, name: String, kind: ManagedProfileKind) async {
        guard canUseManagedProfiles else {
            rejectPremiumOnlyAction()
            return
        }

        let trimmed = cleanedName(name)
        guard !trimmed.isEmpty else {
            lastError = "Profile name is required."
            return
        }

        var updated = profile
        updated.name = trimmed
        updated.kind = kind
        updated.iconSystemName = kind.systemImage
        updated.colorHex = kind.defaultColorHex
        updated.updatedAt = Date()

        #if canImport(Supabase)
        if currentOwnerID != nil {
            do {
                try await updateRemoteProfile(updated)
                replaceLocal(updated)
                lastError = nil
                return
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
        #endif

        replaceLocal(updated)
    }

    func setDefaultProfile(_ profile: ManagedProfile) async {
        guard canUseManagedProfiles else {
            rejectPremiumOnlyAction()
            return
        }

        guard profiles.contains(where: { $0.id == profile.id && $0.archivedAt == nil }) else { return }

        #if canImport(Supabase)
        if currentOwnerID != nil {
            do {
                try await setRemoteDefault(profile.id)
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
        #endif

        profiles = normalizedProfiles(
            profiles.map { existing in
                var out = existing
                out.isDefault = existing.id == profile.id
                out.updatedAt = Date()
                return out
            }
        )
        selection = .profile(profile.id)
        lastError = nil
    }

    func archiveProfile(_ profile: ManagedProfile) async {
        guard canUseManagedProfiles else {
            rejectPremiumOnlyAction()
            return
        }

        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        guard profiles.count > 1 else {
            lastError = "Keep at least one active profile."
            return
        }

        let replacementDefault = profiles.first {
            $0.id != profile.id && $0.archivedAt == nil
        }

        #if canImport(Supabase)
        if currentOwnerID != nil {
            do {
                if profile.isDefault, let replacementDefault {
                    try await setRemoteDefault(replacementDefault.id)
                }
                try await archiveRemoteProfile(profile.id)
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
        #endif

        let now = Date()
        profiles = normalizedProfiles(
            profiles.compactMap { existing in
                guard existing.id != profile.id else { return nil }
                var out = existing
                if profile.isDefault, out.id == replacementDefault?.id {
                    out.isDefault = true
                    out.updatedAt = now
                }
                return out
            }
        )
        if selection.selectedProfileID == profile.id {
            if let fallback = defaultProfile?.id {
                selection = .profile(fallback)
            } else {
                selection = .allProfiles
            }
        }
        lastError = nil
    }

    private func normalizedSelection() -> ManagedProfileSelection {
        if !canUseManagedProfiles, let fallback = defaultProfile?.id {
            return .profile(fallback)
        }

        switch selection {
        case .allProfiles:
            return .allProfiles
        case .profile(let id):
            if profiles.contains(where: { $0.id == id }) {
                return .profile(id)
            }
            if let fallback = defaultProfile?.id {
                return .profile(fallback)
            }
            return .allProfiles
        }
    }

    private func ensureLocalProfile(ownerID: UUID?, displayName: String?) {
        if profiles.isEmpty {
            let defaultID = Self.localDefaultID(key: localDefaultIDKey)
            profiles = [
                ManagedProfile(
                    id: defaultID,
                    ownerID: ownerID,
                    name: defaultProfileName(displayName: displayName),
                    kind: .personal,
                    isDefault: true
                )
            ]
        } else {
            profiles = normalizedProfiles(
                profiles.enumerated().map { idx, profile in
                    var out = profile
                    out.ownerID = ownerID
                    out.isDefault = profile.isDefault || idx == 0 && !profiles.contains(where: \.isDefault)
                    return out
                }
            )
        }
    }

    private func normalizedProfiles(_ input: [ManagedProfile]) -> [ManagedProfile] {
        var sorted = input.filter { $0.archivedAt == nil }.sortedForDisplay
        if !sorted.contains(where: \.isDefault), let first = sorted.first {
            sorted = sorted.map { profile in
                var out = profile
                out.isDefault = profile.id == first.id
                return out
            }
        }
        return sorted
    }

    private func replaceLocal(_ profile: ManagedProfile) {
        profiles = normalizedProfiles(
            profiles.map { $0.id == profile.id ? profile : $0 }
        )
    }

    private func defaultProfileName(displayName: String?) -> String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "My Bills" : "\(trimmed)'s Bills"
    }

    private func cleanedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectionStorageKey() -> String {
        if let owner = currentOwnerID {
            return "\(selectionKeyPrefix).\(owner.uuidString)"
        }
        return "\(selectionKeyPrefix).local"
    }

    private func persistSelection() {
        UserDefaults.standard.set(selection.storageValue, forKey: selectionStorageKey())
    }

    private func restoreSelectionForCurrentOwner() {
        guard let fallback = defaultProfile?.id else {
            selection = .allProfiles
            return
        }
        guard canUseManagedProfiles else {
            selection = .profile(fallback)
            return
        }
        let stored = UserDefaults.standard.string(forKey: selectionStorageKey())
        let restored = ManagedProfileSelection.from(
            storageValue: stored,
            fallbackProfileID: fallback
        )
        switch restored {
        case .allProfiles:
            selection = .allProfiles
        case .profile(let id):
            selection = profiles.contains(where: { $0.id == id })
                ? .profile(id)
                : .profile(fallback)
        }
    }

    private static func localDefaultID(key: String) -> UUID {
        if let raw = UserDefaults.standard.string(forKey: key),
           let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    private func rejectPremiumOnlyAction() {
        lastError = premiumRequiredMessage
        enforceFreeSelection()
    }

    private func enforceFreeSelection() {
        guard !canUseManagedProfiles, let fallback = defaultProfile?.id else { return }
        if selection != .profile(fallback) {
            selection = .profile(fallback)
        }
    }
}

private extension Array where Element == ManagedProfile {
    var sortedForDisplay: [ManagedProfile] {
        sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault && !$1.isDefault }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

#if canImport(Supabase)
private extension ManagedProfileStore {
    struct ProfileRow: Codable {
        let id: UUID
        let owner_id: UUID
        let name: String
        let kind: String
        let icon_system_name: String
        let color_hex: String
        let is_default: Bool
        let archived_at: Date?
        let sort_order: Int
        let created_at: Date
        let updated_at: Date

        func toProfile() -> ManagedProfile {
            let resolvedKind = ManagedProfileKind(rawValue: kind) ?? .personal
            return ManagedProfile(
                id: id,
                ownerID: owner_id,
                name: name,
                kind: resolvedKind,
                iconSystemName: icon_system_name,
                colorHex: color_hex,
                isDefault: is_default,
                archivedAt: archived_at,
                sortOrder: sort_order,
                createdAt: created_at,
                updatedAt: updated_at
            )
        }
    }

    struct ProfileInsert: Encodable {
        let owner_id: UUID
        let name: String
        let kind: String
        let icon_system_name: String
        let color_hex: String
        let is_default: Bool
        let sort_order: Int
    }

    struct ProfileUpdate: Encodable {
        let name: String
        let kind: String
        let icon_system_name: String
        let color_hex: String
        let updated_at: Date
    }

    struct DefaultUpdate: Encodable {
        let is_default: Bool
        let updated_at: Date
    }

    struct ArchiveUpdate: Encodable {
        let is_default: Bool
        let archived_at: Date
        let updated_at: Date
    }

    func loadRemoteProfiles() async throws -> [ManagedProfile] {
        guard let currentOwnerID else { return [] }
        let rows: [ProfileRow] = try await SupabaseConfig.client
            .from(table)
            .select()
            .eq("owner_id", value: currentOwnerID)
            .order("sort_order", ascending: true)
            .order("name", ascending: true)
            .execute()
            .value
        return rows.map { $0.toProfile() }
    }

    func createRemoteProfile(
        name: String,
        kind: ManagedProfileKind,
        isDefault: Bool,
        sortOrder: Int
    ) async throws -> ManagedProfile {
        guard let currentOwnerID else {
            throw NSError(domain: "ManagedProfileStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No signed-in account owner."
            ])
        }
        let payload = ProfileInsert(
            owner_id: currentOwnerID,
            name: name,
            kind: kind.rawValue,
            icon_system_name: kind.systemImage,
            color_hex: kind.defaultColorHex,
            is_default: isDefault,
            sort_order: sortOrder
        )
        let inserted: [ProfileRow] = try await SupabaseConfig.client
            .from(table)
            .insert(payload, returning: .representation)
            .select()
            .execute()
            .value
        guard let first = inserted.first else {
            throw NSError(domain: "ManagedProfileStore", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Supabase did not return the created profile."
            ])
        }
        return first.toProfile()
    }

    func updateRemoteProfile(_ profile: ManagedProfile) async throws {
        guard let currentOwnerID else { return }
        let payload = ProfileUpdate(
            name: profile.name,
            kind: profile.kind.rawValue,
            icon_system_name: profile.kind.systemImage,
            color_hex: profile.kind.defaultColorHex,
            updated_at: Date()
        )
        try await SupabaseConfig.client
            .from(table)
            .update(payload)
            .eq("id", value: profile.id)
            .eq("owner_id", value: currentOwnerID)
            .execute()
    }

    func setRemoteDefault(_ profileID: UUID) async throws {
        guard let currentOwnerID else { return }
        let now = Date()
        try await SupabaseConfig.client
            .from(table)
            .update(DefaultUpdate(is_default: false, updated_at: now))
            .eq("owner_id", value: currentOwnerID)
            .execute()
        try await SupabaseConfig.client
            .from(table)
            .update(DefaultUpdate(is_default: true, updated_at: Date()))
            .eq("id", value: profileID)
            .eq("owner_id", value: currentOwnerID)
            .execute()
    }

    func archiveRemoteProfile(_ profileID: UUID) async throws {
        guard let currentOwnerID else { return }
        let now = Date()
        try await SupabaseConfig.client
            .from(table)
            .update(ArchiveUpdate(is_default: false, archived_at: now, updated_at: now))
            .eq("id", value: profileID)
            .eq("owner_id", value: currentOwnerID)
            .execute()
    }
}
#endif
