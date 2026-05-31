//
//  WidgetSharedBillSnapshot.swift
//  Shared between SacredBillTracker (main app) and SacredBillTrackerWidgets.
//
//  The widget process is sandboxed away from the main app's Documents
//  directory, so we exchange a tiny JSON snapshot through the App Group
//  shared container: `group.com.sacredbilltracker.shared`.
//
//  Contract:
//    • The main app writes `bill_snapshot.json` after EVERY mutation
//      (add / edit / delete / mark paid / mark unpaid).
//    • The widget's TimelineProvider reads it on every refresh.
//    • The file is intentionally lossy — only the fields the widget
//      renders, no PII like notes / paymentURL / attachments.
//
//  This file is added to BOTH targets in project.pbxproj.
//

import Foundation

public enum WidgetAppGroup {
    public static let identifier = "group.com.sacredbilltracker.shared"
    public static let snapshotFileName = "bill_snapshot.json"

    /// URL to the snapshot JSON in the shared container, or nil if the
    /// App Group isn't provisioned yet (e.g. on first launch of a build
    /// without the entitlement enabled).
    public static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(snapshotFileName)
    }
}

// MARK: - DTO

public struct WidgetBillSummary: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let amount: Double
    public let dueDate: Date
    public let isPaid: Bool
    public let isOverdue: Bool
    public let categoryTitle: String

    public init(
        id: String,
        name: String,
        amount: Double,
        dueDate: Date,
        isPaid: Bool,
        isOverdue: Bool,
        categoryTitle: String
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.isPaid = isPaid
        self.isOverdue = isOverdue
        self.categoryTitle = categoryTitle
    }
}

public struct WidgetIncomeSummary: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let amount: Double
    public let entryDate: Date
    public let typeTitle: String

    public init(
        id: String,
        name: String,
        amount: Double,
        entryDate: Date,
        typeTitle: String
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.entryDate = entryDate
        self.typeTitle = typeTitle
    }
}

public struct WidgetBillSnapshot: Codable, Hashable {
    public let generatedAt: Date
    public let overdueCount: Int
    public let dueTodayCount: Int
    public let dueThisWeekCount: Int
    public let monthlyTotal: Double
    public let monthlyIncomeTotal: Double
    public let thisWeekIncomeTotal: Double
    public let healthScore: Int
    public let upcoming: [WidgetBillSummary]   // sorted ascending by dueDate, unpaid only
    public let recentIncome: [WidgetIncomeSummary]

    public init(
        generatedAt: Date = Date(),
        overdueCount: Int,
        dueTodayCount: Int,
        dueThisWeekCount: Int,
        monthlyTotal: Double,
        monthlyIncomeTotal: Double = 0,
        thisWeekIncomeTotal: Double = 0,
        healthScore: Int = 100,
        upcoming: [WidgetBillSummary],
        recentIncome: [WidgetIncomeSummary] = []
    ) {
        self.generatedAt = generatedAt
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.dueThisWeekCount = dueThisWeekCount
        self.monthlyTotal = monthlyTotal
        self.monthlyIncomeTotal = monthlyIncomeTotal
        self.thisWeekIncomeTotal = thisWeekIncomeTotal
        self.healthScore = healthScore
        self.upcoming = upcoming
        self.recentIncome = recentIncome
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, overdueCount, dueTodayCount, dueThisWeekCount, monthlyTotal
        case monthlyIncomeTotal, thisWeekIncomeTotal, healthScore, upcoming, recentIncome
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        self.overdueCount = try c.decodeIfPresent(Int.self, forKey: .overdueCount) ?? 0
        self.dueTodayCount = try c.decodeIfPresent(Int.self, forKey: .dueTodayCount) ?? 0
        self.dueThisWeekCount = try c.decodeIfPresent(Int.self, forKey: .dueThisWeekCount) ?? 0
        self.monthlyTotal = try c.decodeIfPresent(Double.self, forKey: .monthlyTotal) ?? 0
        self.monthlyIncomeTotal = try c.decodeIfPresent(Double.self, forKey: .monthlyIncomeTotal) ?? 0
        self.thisWeekIncomeTotal = try c.decodeIfPresent(Double.self, forKey: .thisWeekIncomeTotal) ?? 0
        self.healthScore = try c.decodeIfPresent(Int.self, forKey: .healthScore) ?? 100
        self.upcoming = try c.decodeIfPresent([WidgetBillSummary].self, forKey: .upcoming) ?? []
        self.recentIncome = try c.decodeIfPresent([WidgetIncomeSummary].self, forKey: .recentIncome) ?? []
    }

    /// Placeholder used by the widget when no real snapshot has been
    /// written yet (e.g. before the user opens the app on a fresh install).
    public static let placeholder = WidgetBillSnapshot(
        overdueCount: 0,
        dueTodayCount: 0,
        dueThisWeekCount: 0,
        monthlyTotal: 0,
        monthlyIncomeTotal: 0,
        thisWeekIncomeTotal: 0,
        healthScore: 100,
        upcoming: []
    )
}

// MARK: - I/O

public enum WidgetSnapshotStore {

    /// Reads the latest snapshot from the shared container.
    /// Returns `.placeholder` on any failure so the widget never crashes.
    public static func load() -> WidgetBillSnapshot {
        guard let url = WidgetAppGroup.snapshotURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return .placeholder }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(WidgetBillSnapshot.self, from: data))
            ?? .placeholder
    }

    /// Writes a fresh snapshot. Atomic. Silently no-ops if the App Group
    /// isn't provisioned (don't crash production over a config slip).
    @discardableResult
    public static func save(_ snapshot: WidgetBillSnapshot) -> Bool {
        guard let url = WidgetAppGroup.snapshotURL else { return false }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        do {
            let data = try enc.encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            #if DEBUG
            print("[WidgetSnapshotStore] save failed:", error)
            #endif
            return false
        }
    }

    /// Removes the shared snapshot so widgets fall back to their empty
    /// placeholder instead of displaying another user's private data.
    @discardableResult
    public static func clear() -> Bool {
        guard let url = WidgetAppGroup.snapshotURL else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            #if DEBUG
            print("[WidgetSnapshotStore] clear failed:", error)
            #endif
            return false
        }
    }
}
