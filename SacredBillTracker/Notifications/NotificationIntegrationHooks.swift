//
//  NotificationIntegrationHooks.swift
//  Sacred Pathway Driver Hub — P5
//
//  Public, callable hooks that other parts of the app call when a notable event happens.
//  Each hook:
//    • is async, fire-and-forget safe
//    • respects user prefs (PushNotificationManager handles gating internally)
//    • uses stable identifiers so we never spam the same event twice
//
//  Wire these in:
//    SettlementRepository → call onSettlementCreated when a new local settlement is saved
//                          → call onSettlementsSynced when refreshFromCloud yields new rows
//                          → call onSyncFailed when network errors persist
//    ShareLinkManager     → call onShareLinkScheduled when a share is created
//                          → call onShareLinkRevoked when revoked
//    CSVExporter / ZIP    → call onExportCompleted when the file is ready
//

import Foundation

@MainActor
enum NotificationHooks {

    // MARK: - Settlements

    /// Fired when a new settlement is generated locally.
    static func onSettlementCreated(settlementId: UUID, payPeriod: String, netAmount: Double) async {
        let amount = Self.formatCurrency(netAmount)
        await PushNotificationManager.shared.notify(
            category: .settlementCreated,
            body: "Pay period \(payPeriod): \(amount) ready to review.",
            privacyBody: "A new settlement is ready to view.",
            identifier: "settlement.created.\(settlementId.uuidString)",
            deepLink: .settlementDetail,
            payload: ["settlementId": settlementId.uuidString]
        )
    }

    /// Fired when refreshFromCloud pulled in N new settlements (from another device).
    static func onSettlementsSynced(newCount: Int) async {
        guard newCount > 0 else { return }
        let body = newCount == 1
            ? "1 new settlement synced from another device."
            : "\(newCount) new settlements synced from another device."
        await PushNotificationManager.shared.notify(
            category: .settlementSynced,
            body: body,
            identifier: "settlement.synced.\(Self.day())",  // dedupe per day
            deepLink: .settlementHistory
        )
    }

    /// Fired when sync has failed N times in a row (debounce upstream — call this after 3 failures).
    static func onSyncFailed(reason: String?) async {
        await PushNotificationManager.shared.notify(
            category: .syncFailed,
            body: reason ?? "We couldn't reach the cloud. Your data is safe locally.",
            identifier: "sync.failed.\(Self.day())",
            deepLink: .settlementHistory
        )
    }

    // MARK: - Share links

    /// Fired right after a share link is created. Schedules expiring-soon + expired alerts.
    static func onShareLinkScheduled(shareId: UUID, documentLabel: String, recipient: String?, expiresAt: Date) async {
        await PushNotificationManager.shared.scheduleShareLinkNotifications(
            shareId: shareId,
            documentLabel: documentLabel,
            recipient: recipient,
            expiresAt: expiresAt
        )
    }

    /// Fired when a share is manually revoked → cancels pending alerts.
    static func onShareLinkRevoked(shareId: UUID) {
        PushNotificationManager.shared.cancelForShare(shareId)
    }

    // MARK: - Exports

    /// Fired when CSV / ZIP export completes.
    static func onExportCompleted(filename: String, fileURL: URL?) async {
        await PushNotificationManager.shared.notify(
            category: .exportCompleted,
            body: "\"\(filename)\" is ready in Files.",
            identifier: "export.\(filename).\(Date().timeIntervalSince1970)",
            deepLink: .settlementHistory
        )
    }

    // MARK: - Helpers

    private static func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    /// Day stamp used to dedupe notifications that should only fire once per day.
    private static func day() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}

// MARK: - Sync failure debouncer
// Drop this into SettlementRepository (or call it from there).
// Counts consecutive failures and only fires onSyncFailed after `threshold` strikes.

@MainActor
final class SyncFailureDebouncer {
    static let shared = SyncFailureDebouncer()
    private var consecutiveFailures = 0
    private let threshold = 3
    private var lastNotifiedAt: Date?
    private let cooldown: TimeInterval = 60 * 60   // 1 hour

    func recordSuccess() { consecutiveFailures = 0 }

    func recordFailure(reason: String? = nil) async {
        consecutiveFailures += 1
        guard consecutiveFailures >= threshold else { return }
        if let last = lastNotifiedAt, Date().timeIntervalSince(last) < cooldown { return }
        lastNotifiedAt = Date()
        await NotificationHooks.onSyncFailed(reason: reason)
    }
}
