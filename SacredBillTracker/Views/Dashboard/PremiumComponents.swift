//
//  PremiumComponents.swift
//  SacredBillTracker
//
//  v1.0.10 — Premium dashboard primitives. Reusable section header
//  + Today-at-a-Glance quick action cards. Designed to feel like a
//  featured Apple finance app: soft shadows, generous spacing, brand
//  gold + green tints, gentle press animation.
//

import SwiftUI

// MARK: - Section header

struct PremiumSectionHeader: View {
    let title: String
    var accessoryIcon: String? = nil
    var accessoryAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .tracking(-0.2)
            Spacer()
            if let icon = accessoryIcon, let action = accessoryAction {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.appAccentText)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(Color.appAccent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Today at a Glance quick action card

struct DashboardQuickActionCard: View {

    enum Tint {
        case green, gold, lavender
        var bg: Color {
            switch self {
            case .green:    return Color.appHousehold.opacity(0.14)
            case .gold:     return Color.appAccent.opacity(0.16)
            // Retuned from lavender → on-brand lime so the dashboard
            // quick-actions stay within the green + gold palette.
            case .lavender: return Color.appLime.opacity(0.18)
            }
        }
        var iconBg: Color {
            switch self {
            case .green:    return Color.appHousehold.opacity(0.85)
            case .gold:     return Color.appAccentText
            // Deep moss so the white glyph keeps strong contrast.
            case .lavender: return Color(red: 0.30, green: 0.46, blue: 0.10)
            }
        }
    }

    let title: String
    let valueLine: String
    let systemImage: String
    let tint: Tint
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.iconBg)
                        .frame(width: 36, height: 36)
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(valueLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSubtleText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }
}

// MARK: - Premium "Today at a Glance" row

/// Reads ScheduleStore + TodoStore + BillStore for live counts and
/// surfaces tappable Schedule / To-Do / Schedule Buddy cards. Tap on
/// any card triggers the same Focus+ entry as the Sacred Focus hero
/// — subscribed → DailyFocusCenterView, unsubscribed → paywall.
struct TodayAtAGlanceRow: View {

    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var todoStore: TodoStore
    @EnvironmentObject private var billStore: BillStore
    @EnvironmentObject private var subs: SubscriptionManager

    /// Bindings from the parent so taps surface the right sheet without
    /// each card owning its own state (which would stack sheets).
    @Binding var showFocusCenter: Bool
    @Binding var showFocusPaywall: Bool

    private let today = Calendar.current.startOfDay(for: Date())

    var body: some View {
        HStack(spacing: 10) {
            DashboardQuickActionCard(
                title: "Schedule",
                valueLine: scheduleLine,
                systemImage: "calendar",
                tint: .green,
                action: tap
            )
            DashboardQuickActionCard(
                title: "To-Do",
                valueLine: todoLine,
                systemImage: "checklist",
                tint: .gold,
                action: tap
            )
            DashboardQuickActionCard(
                title: "Schedule Buddy",
                valueLine: buddyLine,
                systemImage: "sparkles",
                tint: .lavender,
                action: tap
            )
        }
    }

    private func tap() {
        if subs.hasFocusPlus { showFocusCenter = true }
        else                 { showFocusPaywall = true }
    }

    private var scheduleLine: String {
        let n = scheduleStore.items(on: today).count
        if n == 0 { return "Nothing today" }
        return "\(n) item\(n == 1 ? "" : "s") today"
    }

    private var todoLine: String {
        let tasks = todoStore.items(for: today)
        let open = tasks.filter { !$0.isComplete }.count
        if tasks.isEmpty   { return "No tasks" }
        if open == 0       { return "All done — \(tasks.count) tasks" }
        return "\(open) task\(open == 1 ? "" : "s")"
    }

    private var buddyLine: String {
        var n = 0
        n += billStore.bills.filter { $0.isOverdue }.count
        n += billStore.bills.filter { !$0.isPaid && $0.isDueToday }.count
        if n == 0 { return "On track" }
        return "\(n) suggestion\(n == 1 ? "" : "s")"
    }
}
