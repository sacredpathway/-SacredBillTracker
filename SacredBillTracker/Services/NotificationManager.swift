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
        await cancelPendingBillNotifications(center: center)

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

    // MARK: - Sacred Focus productivity reminders

    func rescheduleScheduleReminders(for items: [ScheduleItem]) async {
        let center = UNUserNotificationCenter.current()
        await cancelPendingRequests(withPrefix: Self.scheduleReminderPrefix, center: center)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        for item in items {
            await scheduleReminder(for: item, requestIfNeeded: false)
        }
    }

    func scheduleReminder(for item: ScheduleItem, requestIfNeeded: Bool = true) async {
        guard
            !item.isComplete,
            let minutesBefore = item.reminderMinutesBefore,
            await ensureNotificationAuthorization(requestIfNeeded: requestIfNeeded)
        else { return }

        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        guard let reminderDate = calendar.date(byAdding: .minute, value: -minutesBefore, to: item.startTime) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Schedule Reminder"
        content.body = item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.title
            : "\(item.title) at \(item.location)"
        content.sound = .default
        content.userInfo = ["scheduleItemId": item.id.uuidString]

        let triggerDate = nextReminderDate(
            for: item.repeatRule,
            reminderDate: reminderDate,
            customWeekdays: item.customWeekdays,
            calendar: calendar
        )
        guard let triggerDate else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(Self.repeatingComponents(for: item.repeatRule), from: triggerDate),
            repeats: item.repeatRule != .oneTime
        )
        let request = UNNotificationRequest(
            identifier: Self.scheduleReminderID(for: item.id),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func cancelScheduleReminders(for id: UUID) async {
        await cancelPendingRequests(withPrefix: Self.scheduleReminderID(for: id), center: UNUserNotificationCenter.current())
    }

    func rescheduleTodoReminders(for items: [FocusTodo]) async {
        let center = UNUserNotificationCenter.current()
        await cancelPendingRequests(withPrefix: Self.todoReminderPrefix, center: center)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        for item in items {
            await scheduleReminder(for: item, requestIfNeeded: false)
        }
    }

    func scheduleReminder(for item: FocusTodo, requestIfNeeded: Bool = true) async {
        guard
            !item.isComplete,
            let reminderDate = item.reminderDate,
            reminderDate > Date(),
            await ensureNotificationAuthorization(requestIfNeeded: requestIfNeeded)
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "To-Do Reminder"
        content.body = item.title
        content.sound = .default
        content.userInfo = ["todoId": item.id.uuidString]

        let calendar = Calendar.current
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.todoReminderID(for: item.id),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelTodoReminder(for id: UUID) async {
        await cancelPendingRequests(withPrefix: Self.todoReminderID(for: id), center: UNUserNotificationCenter.current())
    }

    private func ensureNotificationAuthorization(requestIfNeeded: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined where requestIfNeeded:
            return await requestAuthorization()
        default:
            return false
        }
    }

    private func cancelPendingBillNotifications(center: UNUserNotificationCenter) async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(Self.isBillNotificationIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func cancelPendingRequests(withPrefix prefix: String, center: UNUserNotificationCenter) async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func nextReminderDate(
        for repeatRule: FocusRepeatRule,
        reminderDate: Date,
        customWeekdays: Set<Int>,
        calendar: Calendar
    ) -> Date? {
        if repeatRule == .oneTime {
            return reminderDate > Date() ? reminderDate : nil
        }

        var candidate = reminderDate
        for _ in 0..<400 {
            if candidate > Date(),
               repeatRule.occursOn(candidate, anchorDate: reminderDate, customWeekdays: customWeekdays, calendar: calendar) {
                return candidate
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = nextDay
        }
        return nil
    }

    private static func repeatingComponents(for repeatRule: FocusRepeatRule) -> Set<Calendar.Component> {
        switch repeatRule {
        case .oneTime:
            return [.year, .month, .day, .hour, .minute]
        case .daily:
            return [.hour, .minute]
        case .weekly, .custom:
            return [.weekday, .hour, .minute]
        case .monthly:
            return [.day, .hour, .minute]
        }
    }

    private static func isBillNotificationIdentifier(_ identifier: String) -> Bool {
        let base = identifier
            .replacingOccurrences(of: PaydownPlanService.NotificationKey.firstSuffix, with: "")
            .replacingOccurrences(of: PaydownPlanService.NotificationKey.secondSuffix, with: "")
        return UUID(uuidString: base) != nil
    }

    private static let scheduleReminderPrefix = "sbt.schedule."
    private static let todoReminderPrefix = "sbt.todo."

    private static func scheduleReminderID(for id: UUID) -> String {
        "\(scheduleReminderPrefix)\(id.uuidString)"
    }

    private static func todoReminderID(for id: UUID) -> String {
        "\(todoReminderPrefix)\(id.uuidString)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
