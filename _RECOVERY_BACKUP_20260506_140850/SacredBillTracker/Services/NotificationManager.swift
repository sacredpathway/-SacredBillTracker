//
//  NotificationManager.swift
//  SacredBillTracker
//
//  Schedules local notifications for upcoming bill due dates.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {

    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var leadTimeDays: Int = 2 {
        didSet { UserDefaults.standard.set(leadTimeDays, forKey: "sacred.lead.time.days") }
    }

    private init() {
        let stored = UserDefaults.standard.integer(forKey: "sacred.lead.time.days")
        self.leadTimeDays = stored == 0 ? 2 : stored
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshStatus()
            return granted
        } catch {
            return false
        }
    }

    /// Reschedules notifications for every unpaid, future-dated bill.
    func rescheduleAll(for bills: [Bill]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        for bill in bills where bill.status != .paid {
            await scheduleReminder(for: bill)
        }
    }

    func scheduleReminder(for bill: Bill) async {
        let center = UNUserNotificationCenter.current()

        // Build trigger date: X days before due, at 9:00 AM local.
        let calendar = Calendar.current
        guard
            let base = calendar.date(byAdding: .day, value: -leadTimeDays, to: bill.dueDate),
            var components = Optional(calendar.dateComponents([.year, .month, .day], from: base))
        else { return }
        components.hour = 9
        components.minute = 0

        guard
            let triggerDate = calendar.date(from: components),
            triggerDate > Date()
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming Bill: \(bill.name)"
        content.body  = "\(bill.formattedAmount) due \(Self.relativeFormatter.localizedString(for: bill.dueDate, relativeTo: Date()))."
        content.sound = .default
        content.userInfo = ["billId": bill.id.uuidString]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: bill.id.uuidString, content: content, trigger: trigger)

        try? await center.add(request)
    }

    func cancelReminder(for billId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [billId.uuidString])
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
