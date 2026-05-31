//
//  SacredBillTrackerWidget.swift
//  SacredBillTrackerWidgets
//
//  A single static-configuration widget with three families:
//   • .systemSmall  → next bill due
//   • .systemMedium → next 3 upcoming bills
//   • .systemLarge  → dashboard summary (overdue / today / this week / monthly total)
//
//  Data source: WidgetSnapshotStore (App Group JSON written by the app).
//  No fake numbers — when the snapshot is empty, the widget shows
//  "No bills yet — open Sacred Bill Tracker to add one."
//

import SwiftUI
import WidgetKit

// MARK: - Sacred palette (mirrors the main app's accent colors —
//         duplicated here because Theme.swift isn't a member of the
//         widget target by default)

enum SacredWidgetPalette {
    static let accentGreen = Color(red: 0.16, green: 0.55, blue: 0.36)
    static let accentGold  = Color(red: 0.83, green: 0.69, blue: 0.32)
    static let card        = Color(.systemBackground)
    static let secondary   = Color.secondary
    static let danger      = Color(red: 0.83, green: 0.21, blue: 0.21)
    static let success     = Color(red: 0.16, green: 0.66, blue: 0.40)
}

// MARK: - Timeline

struct SacredBillEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetBillSnapshot
}

struct SacredBillTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> SacredBillEntry {
        SacredBillEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SacredBillEntry) -> Void) {
        completion(SacredBillEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SacredBillEntry>) -> Void) {
        let snap = WidgetSnapshotStore.load()
        let entry = SacredBillEntry(date: Date(), snapshot: snap)
        // Refresh hourly. The main app also calls
        // `WidgetCenter.shared.reloadAllTimelines()` on every mutation,
        // so this is just a safety net for time-of-day rollover.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget configuration

struct SacredBillTrackerWidget: Widget {
    let kind: String = "SacredBillTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SacredBillTimelineProvider()) { entry in
            SacredBillWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SacredWidgetPalette.card
                }
        }
        .configurationDisplayName("Sacred Bill Tracker")
        .description("Your next bill, upcoming bills, and dashboard at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Router

struct SacredBillWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SacredBillEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallBillWidgetView(snapshot: entry.snapshot)
        case .systemMedium: MediumBillWidgetView(snapshot: entry.snapshot)
        case .systemLarge:  LargeBillWidgetView(snapshot: entry.snapshot)
        default:            SmallBillWidgetView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Shared subviews

private struct LeafBadge: View {
    var size: CGFloat = 14
    var body: some View {
        ZStack {
            Circle()
                .fill(SacredWidgetPalette.accentGreen.opacity(0.15))
                .frame(width: size + 8, height: size + 8)
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.85, weight: .semibold))
                .foregroundStyle(SacredWidgetPalette.accentGreen)
        }
    }
}

private func formatMoney(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = .current
    f.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    return f.string(from: NSNumber(value: value)) ?? "$\(value)"
}

private func relativeDue(_ date: Date, now: Date = Date()) -> String {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    let due   = cal.startOfDay(for: date)
    let days  = cal.dateComponents([.day], from: today, to: due).day ?? 0
    switch days {
    case ..<0:  return "\(abs(days))d overdue"
    case 0:     return "Due today"
    case 1:     return "Due tomorrow"
    case 2...7: return "Due in \(days) days"
    default:
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Due " + f.string(from: date)
    }
}

private struct EmptyHint: View {
    var body: some View {
        VStack(spacing: 6) {
            LeafBadge(size: 18)
            Text("No bills yet")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text("Open Sacred Bill Tracker to add one.")
                .font(.caption2)
                .foregroundStyle(SacredWidgetPalette.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }
}

// MARK: - Small (next bill)

struct SmallBillWidgetView: View {
    let snapshot: WidgetBillSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LeafBadge()
                Text("Next bill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SacredWidgetPalette.secondary)
                Spacer(minLength: 0)
            }
            if let bill = snapshot.upcoming.first {
                Text(bill.name)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(formatMoney(bill.amount))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(SacredWidgetPalette.accentGreen)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: bill.isOverdue ? "exclamationmark.triangle.fill" : "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(bill.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.accentGold)
                    Text(relativeDue(bill.dueDate))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(bill.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.secondary)
                }
            } else {
                Spacer(minLength: 0)
                EmptyHint()
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium (next 3 bills)

struct MediumBillWidgetView: View {
    let snapshot: WidgetBillSnapshot

    private var top3: [WidgetBillSummary] {
        Array(snapshot.upcoming.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                LeafBadge()
                Text("Upcoming bills")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer(minLength: 0)
                Text("\(snapshot.upcoming.count) unpaid")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SacredWidgetPalette.secondary)
            }
            if top3.isEmpty {
                Spacer(minLength: 0)
                EmptyHint()
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 6) {
                    ForEach(top3) { bill in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(bill.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.accentGreen)
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bill.name)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .lineLimit(1)
                                Text(relativeDue(bill.dueDate))
                                    .font(.caption2)
                                    .foregroundStyle(bill.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(formatMoney(bill.amount))
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(SacredWidgetPalette.accentGreen)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large (dashboard summary)

struct LargeBillWidgetView: View {
    let snapshot: WidgetBillSnapshot

    private var top3: [WidgetBillSummary] { Array(snapshot.upcoming.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                LeafBadge(size: 16)
                Text("Sacred Bill Tracker")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8),
                          GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                StatTile(label: "Overdue",
                         value: "\(snapshot.overdueCount)",
                         systemImage: "exclamationmark.triangle.fill",
                         tint: snapshot.overdueCount > 0 ? SacredWidgetPalette.danger : SacredWidgetPalette.accentGreen)
                StatTile(label: "Due today",
                         value: "\(snapshot.dueTodayCount)",
                         systemImage: "clock.fill",
                         tint: snapshot.dueTodayCount > 0 ? SacredWidgetPalette.accentGold : SacredWidgetPalette.accentGreen)
                StatTile(label: "This week",
                         value: "\(snapshot.dueThisWeekCount)",
                         systemImage: "calendar",
                         tint: SacredWidgetPalette.accentGreen)
                StatTile(label: "This month",
                         value: formatMoney(snapshot.monthlyTotal),
                         systemImage: "creditcard.fill",
                         tint: SacredWidgetPalette.accentGold)
            }

            if !top3.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Next up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SacredWidgetPalette.secondary)
                VStack(spacing: 4) {
                    ForEach(top3) { bill in
                        HStack(spacing: 10) {
                            Text(bill.name)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(relativeDue(bill.dueDate))
                                .font(.caption2)
                                .foregroundStyle(bill.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.secondary)
                            Text(formatMoney(bill.amount))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(SacredWidgetPalette.accentGreen)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(SacredWidgetPalette.secondary)
            }
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

// MARK: - Dedicated Home Screen widgets

private enum SacredHomeWidgetMode {
    case billsDueToday
    case upcomingBills
    case billHealthScore
    case monthlySpending
    case incomeTracker

    var title: String {
        switch self {
        case .billsDueToday: return "Bills Due Today"
        case .upcomingBills: return "Upcoming Bills"
        case .billHealthScore: return "Bill Health Score"
        case .monthlySpending: return "Monthly Spending"
        case .incomeTracker: return "Income Tracker"
        }
    }

    var icon: String {
        switch self {
        case .billsDueToday: return "clock.fill"
        case .upcomingBills: return "calendar.badge.clock"
        case .billHealthScore: return "gauge.with.dots.needle.67percent"
        case .monthlySpending: return "creditcard.fill"
        case .incomeTracker: return "banknote.fill"
        }
    }
}

struct BillsDueTodayWidget: Widget {
    let kind = "SacredBillsDueTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SacredBillTimelineProvider()) { entry in
            SacredHomeWidgetView(mode: .billsDueToday, snapshot: entry.snapshot)
                .containerBackground(for: .widget) { SacredWidgetPalette.card }
        }
        .configurationDisplayName("Bills Due Today")
        .description("Bills that need attention today.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct UpcomingBillsWidget: Widget {
    let kind = "SacredUpcomingBillsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SacredBillTimelineProvider()) { entry in
            SacredHomeWidgetView(mode: .upcomingBills, snapshot: entry.snapshot)
                .containerBackground(for: .widget) { SacredWidgetPalette.card }
        }
        .configurationDisplayName("Upcoming Bills")
        .description("Your next unpaid bills.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct BillHealthScoreHomeWidget: Widget {
    let kind = "SacredBillHealthScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SacredBillTimelineProvider()) { entry in
            SacredHomeWidgetView(mode: .billHealthScore, snapshot: entry.snapshot)
                .containerBackground(for: .widget) { SacredWidgetPalette.card }
        }
        .configurationDisplayName("Bill Health Score")
        .description("A quick score for your bill readiness.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct MonthlySpendingWidget: Widget {
    let kind = "SacredMonthlySpendingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SacredBillTimelineProvider()) { entry in
            SacredHomeWidgetView(mode: .monthlySpending, snapshot: entry.snapshot)
                .containerBackground(for: .widget) { SacredWidgetPalette.card }
        }
        .configurationDisplayName("Monthly Spending")
        .description("Bills due this month.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct IncomeTrackerWidget: Widget {
    let kind = "SacredIncomeTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SacredBillTimelineProvider()) { entry in
            SacredHomeWidgetView(mode: .incomeTracker, snapshot: entry.snapshot)
                .containerBackground(for: .widget) { SacredWidgetPalette.card }
        }
        .configurationDisplayName("Income Tracker")
        .description("Weekly and monthly income at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct SacredHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let mode: SacredHomeWidgetMode
    let snapshot: WidgetBillSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            header
            switch mode {
            case .billsDueToday:
                dueTodayContent
            case .upcomingBills:
                upcomingContent
            case .billHealthScore:
                healthContent
            case .monthlySpending:
                monthlySpendingContent
            case .incomeTracker:
                incomeContent
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            LeafBadge()
            Label(mode.title, systemImage: mode.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SacredWidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    private var dueTodayContent: some View {
        let dueToday = snapshot.upcoming.filter { Calendar.current.isDateInToday($0.dueDate) }
        let total = dueToday.reduce(0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(snapshot.dueTodayCount)")
                .font(.system(family == .systemSmall ? .largeTitle : .title, design: .rounded).weight(.heavy))
                .foregroundStyle(snapshot.dueTodayCount > 0 ? SacredWidgetPalette.accentGold : SacredWidgetPalette.accentGreen)
                .monospacedDigit()
            Text(formatMoney(total))
                .font(.system(.headline, design: .rounded).weight(.bold))
            if dueToday.isEmpty {
                Text("Nothing due today.")
                    .font(.caption2)
                    .foregroundStyle(SacredWidgetPalette.secondary)
            } else if family != .systemSmall {
                billRows(Array(dueToday.prefix(3)))
            }
        }
    }

    private var upcomingContent: some View {
        let items = Array(snapshot.upcoming.prefix(family == .systemLarge ? 6 : 3))

        return VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                EmptyHint()
            } else {
                if family == .systemSmall, let first = items.first {
                    Text(first.name)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text(formatMoney(first.amount))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(SacredWidgetPalette.accentGreen)
                    Text(relativeDue(first.dueDate))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(first.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.secondary)
                } else {
                    billRows(items)
                }
            }
        }
    }

    private var healthContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(snapshot.healthScore)")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(healthTint(snapshot.healthScore))
                    .monospacedDigit()
                Text("/100")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SacredWidgetPalette.secondary)
            }
            ProgressView(value: Double(snapshot.healthScore), total: 100)
                .tint(healthTint(snapshot.healthScore))
            if family != .systemSmall {
                HStack {
                    Text("\(snapshot.overdueCount) overdue")
                    Spacer()
                    Text("\(snapshot.dueTodayCount) today")
                    Spacer()
                    Text("\(snapshot.dueThisWeekCount) week")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SacredWidgetPalette.secondary)
            }
        }
    }

    private var monthlySpendingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatMoney(snapshot.monthlyTotal))
                .font(.system(family == .systemSmall ? .title2 : .title, design: .rounded).weight(.heavy))
                .foregroundStyle(SacredWidgetPalette.accentGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text("Bills due this month")
                .font(.caption2.weight(.medium))
                .foregroundStyle(SacredWidgetPalette.secondary)
            if family != .systemSmall {
                StatTile(label: "This week",
                         value: "\(snapshot.dueThisWeekCount)",
                         systemImage: "calendar",
                         tint: SacredWidgetPalette.accentGold)
            }
        }
    }

    private var incomeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatMoney(snapshot.thisWeekIncomeTotal))
                .font(.system(family == .systemSmall ? .title2 : .title, design: .rounded).weight(.heavy))
                .foregroundStyle(SacredWidgetPalette.accentGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text("This week • \(formatMoney(snapshot.monthlyIncomeTotal)) month")
                .font(.caption2.weight(.medium))
                .foregroundStyle(SacredWidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if family != .systemSmall, !snapshot.recentIncome.isEmpty {
                incomeRows(Array(snapshot.recentIncome.prefix(family == .systemLarge ? 5 : 3)))
            }
        }
    }

    private func billRows(_ bills: [WidgetBillSummary]) -> some View {
        VStack(spacing: 6) {
            ForEach(bills) { bill in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bill.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.accentGreen)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bill.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(relativeDue(bill.dueDate))
                            .font(.caption2)
                            .foregroundStyle(bill.isOverdue ? SacredWidgetPalette.danger : SacredWidgetPalette.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(formatMoney(bill.amount))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private func incomeRows(_ entries: [WidgetIncomeSummary]) -> some View {
        VStack(spacing: 6) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .font(.caption2)
                        .foregroundStyle(SacredWidgetPalette.accentGreen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(entry.entryDate, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(SacredWidgetPalette.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(formatMoney(entry.amount))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private func healthTint(_ score: Int) -> Color {
        switch score {
        case 85...100: return SacredWidgetPalette.success
        case 65..<85: return SacredWidgetPalette.accentGold
        default: return SacredWidgetPalette.danger
        }
    }
}
