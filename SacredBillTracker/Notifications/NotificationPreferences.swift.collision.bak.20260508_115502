//
//  NotificationPreferences.swift
//  Sacred Pathway Driver Hub — P5
//
//  UserDefaults-backed user preferences for notifications.
//  Per-category toggle, lock-screen privacy, quiet hours.
//

import Foundation
import Combine

@MainActor
final class NotificationPreferences: ObservableObject {

    static let shared = NotificationPreferences()

    private static let defaultsKey = "sph.notif.prefs.v1"

    @Published var enabledCategories: Set<NotificationCategory> {
        didSet { persist() }
    }

    /// When true, body of notifications containing sensitive data is redacted on lock screen.
    @Published var lockScreenPrivacy: Bool {
        didSet { persist() }
    }

    /// Quiet hours — local time. While inside this window, non-time-sensitive notifications are suppressed.
    @Published var quietHoursEnabled: Bool { didSet { persist() } }
    @Published var quietHoursStartHour: Int { didSet { persist() } }   // 0-23
    @Published var quietHoursEndHour: Int   { didSet { persist() } }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(StoredPrefs.self, from: data) {
            enabledCategories  = saved.enabled
            lockScreenPrivacy  = saved.lockScreenPrivacy
            quietHoursEnabled  = saved.quietHoursEnabled
            quietHoursStartHour = saved.quietHoursStart
            quietHoursEndHour   = saved.quietHoursEnd
        } else {
            enabledCategories  = Set(NotificationCategory.allCases.filter(\.defaultEnabled))
            lockScreenPrivacy  = true   // privacy by default
            quietHoursEnabled  = false
            quietHoursStartHour = 22
            quietHoursEndHour   = 7
        }
    }

    func isEnabled(_ category: NotificationCategory) -> Bool {
        enabledCategories.contains(category)
    }

    func set(_ category: NotificationCategory, enabled: Bool) {
        if enabled { enabledCategories.insert(category) }
        else       { enabledCategories.remove(category) }
    }

    /// True if the OS is currently inside the user-configured quiet window.
    /// Returns false if quiet hours are disabled.
    func isInQuietHours(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = calendar.component(.hour, from: now)
        let s = quietHoursStartHour
        let e = quietHoursEndHour
        // Window can wrap midnight (e.g. 22 → 7 means 22, 23, 0, 1, 2, 3, 4, 5, 6 are quiet)
        if s == e { return false }
        if s < e { return hour >= s && hour < e }
        return hour >= s || hour < e
    }

    /// The single gate function. Returns false → caller should NOT post the notification.
    /// Time-sensitive notifications bypass quiet hours.
    func shouldPost(_ category: NotificationCategory, now: Date = Date()) -> Bool {
        guard isEnabled(category) else { return false }
        if category.interruptionLevel == .timeSensitive { return true }
        return !isInQuietHours(now: now)
    }

    // MARK: - Persistence
    private struct StoredPrefs: Codable {
        let enabled: Set<NotificationCategory>
        let lockScreenPrivacy: Bool
        let quietHoursEnabled: Bool
        let quietHoursStart: Int
        let quietHoursEnd: Int
    }

    private func persist() {
        let prefs = StoredPrefs(
            enabled: enabledCategories,
            lockScreenPrivacy: lockScreenPrivacy,
            quietHoursEnabled: quietHoursEnabled,
            quietHoursStart: quietHoursStartHour,
            quietHoursEnd: quietHoursEndHour
        )
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Quick formatter for the settings UI.
    func quietHoursLabel() -> String {
        guard quietHoursEnabled else { return "Off" }
        let f = DateFormatter()
        f.dateFormat = "h a"
        let cal = Calendar.current
        let start = cal.date(bySettingHour: quietHoursStartHour, minute: 0, second: 0, of: Date()) ?? Date()
        let end   = cal.date(bySettingHour: quietHoursEndHour,   minute: 0, second: 0, of: Date()) ?? Date()
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}
