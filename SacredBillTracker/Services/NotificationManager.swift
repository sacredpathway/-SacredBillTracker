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

        if let triggerDate = calendar.date(from: components),
           triggerDate > Date() {

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

        // 15/3 Paydown Plan (v1.4) — fire two extra reminders alongside
        // the standard due-date reminder above. Identifiers are
        // suffixed so `cancelReminder(for:)` can clean them up.
        await schedulePaydownReminders(for: bill, calendar: calendar)
    }

    /// Schedule the two 15/3 paydown reminders for a bill if the plan
    /// is active and the dates are in the future. No-op otherwise.
    private func schedulePaydownReminders(for bill: Bill, calendar: Calendar) async {
        guard bill.isUsing153Plan else { return }

        let center = UNUserNotificationCenter.current()

        if let firstDate = bill.firstPaydownDate,
           let firstAmount = bill.firstPaydownAmount {
            await schedulePaydownReminder(
                center: center,
                identifier: PaydownPlanService.NotificationKey.firstID(for: bill.id),
                billName: bill.name,
                title: "First Paydown",
                amount: firstAmount,
                date: firstDate,
                calendar: calendar,
                billID: bill.id
            )
        }

        if let secondDate = bill.secondPaydownDate,
           let secondAmount = bill.secondPaydownAmount {
            await schedulePaydownReminder(
                center: center,
                identifier: PaydownPlanService.NotificationKey.secondID(for: bill.id),
                billName: bill.name,
                title: "Final Paydown",
                amount: secondAmount,
                date: secondDate,
                calendar: calendar,
                billID: bill.id
            )
        }
    }

    private func schedulePaydownReminder(
        center: UNUserNotificationCenter,
        identifier: String,
        billName: String,
        title: String,
        amount: Decimal,
        date: Date,
        calendar: Calendar,
        billID: UUID
    ) async {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = 9
        comps.minute = 0
        guard
            let triggerDate = calendar.date(from: comps),
            triggerDate > Date()
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(title): \(billName)"
        content.body  = "Plan to pay \(PaydownPlanService.currency(amount)) today (15/3 Paydown Plan)."
        content.sound = .default
        content.userInfo = [
            "billId": billID.uuidString,
            "paydown": identifier.hasSuffix(PaydownPlanService.NotificationKey.secondSuffix) ? "second" : "first"
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelReminder(for billId: UUID) {
        // Also clear any 15/3 paydown reminders that may have been
        // scheduled for this bill so toggling the plan off in the
        // editor actually removes them.
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [
                billId.uuidString,
                PaydownPlanService.NotificationKey.firstID(for: billId),
                PaydownPlanService.NotificationKey.secondID(for: billId)
            ])
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
