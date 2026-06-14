//
//  ManagedProfile.swift
//  SacredBillTracker
//
//  Account-owned financial profiles. These are not separate auth accounts:
//  every profile belongs to the signed-in subscriber and is scoped by
//  owner_id in Supabase RLS.
//

import Foundation

enum ManagedProfileKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case personal
    case spouse
    case parent
    case child
    case business
    case rentalProperty = "rental_property"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal:       return "Personal"
        case .spouse:         return "Spouse"
        case .parent:         return "Parent"
        case .child:          return "Child"
        case .business:       return "Business"
        case .rentalProperty: return "Rental Property"
        case .other:          return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .personal:       return "person.crop.circle.fill"
        case .spouse:         return "heart.circle.fill"
        case .parent:         return "person.2.circle.fill"
        case .child:          return "figure.and.child.holdinghands"
        case .business:       return "briefcase.fill"
        case .rentalProperty: return "house.and.flag.fill"
        case .other:          return "folder.fill"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .personal:       return "#2F7D5A"
        case .spouse:         return "#9B5A7A"
        case .parent:         return "#5F6FA8"
        case .child:          return "#C48A2C"
        case .business:       return "#B5892B"
        case .rentalProperty: return "#3F7F93"
        case .other:          return "#6B7280"
        }
    }
}

struct ManagedProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var ownerID: UUID?
    var name: String
    var kind: ManagedProfileKind
    var iconSystemName: String
    var colorHex: String
    var isDefault: Bool
    var archivedAt: Date?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerID: UUID? = nil,
        name: String,
        kind: ManagedProfileKind = .personal,
        iconSystemName: String? = nil,
        colorHex: String? = nil,
        isDefault: Bool = false,
        archivedAt: Date? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.kind = kind
        self.iconSystemName = iconSystemName ?? kind.systemImage
        self.colorHex = colorHex ?? kind.defaultColorHex
        self.isDefault = isDefault
        self.archivedAt = archivedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, ownerID, name, kind, iconSystemName, colorHex
        case isDefault, archivedAt, sortOrder, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.ownerID = try c.decodeIfPresent(UUID.self, forKey: .ownerID)
        self.name = try c.decode(String.self, forKey: .name)
        self.kind = try c.decodeIfPresent(ManagedProfileKind.self, forKey: .kind) ?? .personal
        self.iconSystemName = try c.decodeIfPresent(String.self, forKey: .iconSystemName) ?? kind.systemImage
        self.colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? kind.defaultColorHex
        self.isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        self.archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

enum ManagedProfileSelection: Equatable, Hashable {
    case allProfiles
    case profile(UUID)

    var selectedProfileID: UUID? {
        if case .profile(let id) = self { return id }
        return nil
    }

    var storageValue: String {
        switch self {
        case .allProfiles:
            return "all"
        case .profile(let id):
            return id.uuidString
        }
    }

    static func from(storageValue: String?, fallbackProfileID: UUID) -> ManagedProfileSelection {
        guard let storageValue, !storageValue.isEmpty else {
            return .profile(fallbackProfileID)
        }
        if storageValue == "all" {
            return .allProfiles
        }
        if let id = UUID(uuidString: storageValue) {
            return .profile(id)
        }
        return .profile(fallbackProfileID)
    }
}

struct ManagedProfileContext: Equatable {
    var ownerID: UUID?
    var selection: ManagedProfileSelection
    var defaultProfileID: UUID?

    var selectedProfileID: UUID? { selection.selectedProfileID }

    var writeProfileID: UUID? {
        selectedProfileID ?? defaultProfileID
    }

    func owns(ownerID rowOwnerID: UUID?) -> Bool {
        guard let ownerID else { return false }
        return rowOwnerID == ownerID || rowOwnerID == nil
    }

    func includes(profileID: UUID?) -> Bool {
        switch selection {
        case .allProfiles:
            return true
        case .profile(let selectedID):
            if profileID == selectedID { return true }
            return profileID == nil && defaultProfileID == selectedID
        }
    }
}
