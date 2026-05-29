//
//  FinancialOverviewSection.swift
//  SacredBillTracker
//
//  v1.0.9 — Replaces the dashboard's older trio (This Month / Income
//  Overview / Total Income) with one compact Financial Overview card.
//  Defaults to a tight 2x2 grid of totals; an inline "Show Details"
//  chevron expands paid/pending/overdue breakdowns, income
//  percentages, the combined income line, the insight, and the
//  Combine Income toggle.
//
//  Numbers are tappable:
//    - Personal Bills  → BillsByTypeListView(type: .household)
//    - Business Bills  → BillsByTypeListView(type: .business)
//    - Personal Income → IncomeListView(typeFilter: .personal)
//    - Business Income → IncomeListView(typeFilter: .business)
//    - Combined Income → IncomeListView()  (toggle ON only)
//

import SwiftUI

struct FinancialOverviewSection: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var incomeStore: IncomeStore

    /// Persisted toggle owned by the Dashboard (sbt.income.combineIncome.v1).
    /// Passed in so this section stays a pure display component.
    @Binding var combineIncome: Bool

    /// Dashboard-wide income filter (week / 30d / month / year / all).
    /// Used for income totals + insight.
    let incomePeriod: IncomeDashboardPeriod
    let weekStartDay: WeekStartDay

    @State private var expanded: Bool = false

    private let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Compact 2x2 grid — always visible.
            compactGrid

            // Expand / collapse chrome.
            detailsChevron

            // Expanded details — only mounted when open so the default
            // dashboard remains tight.
            if expanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.appCard)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.22), value: expanded)
        .animation(.easeInOut(duration: 0.22), value: combineIncome)
    }

    // MARK: - Header

    private var header: some View {
        Text("Financial Overview")
            .font(.system(.title2, design: .rounded).weight(.bold))
            .tracking(-0.2)
            .foregroundStyle(.primary)
    }

    // MARK: - Compact grid (always visible)

    private var compactGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Bills — Personal / Business
                tile(
                    title: "Personal Bills",
                    amount: store.totalThisMonth(for: .household),
                    tint: .appHouseholdText,
                    icon: "house.fill",
                    destination: BillsByTypeListView(type: .household)
                        .environmentObject(store)
                )
                tile(
                    title: "Business Bills",
                    amount: store.totalThisMonth(for: .business),
                    tint: .appBusinessText,
                    icon: "briefcase.fill",
                    destination: BillsByTypeListView(type: .business)
                        .environmentObject(store)
                )
            }

            if combineIncome {
                tile(
                    title: "Combined Income",
                    amount: combinedIncomeTotal,
                    tint: Color.appAccentText,
                    icon: "dollarsign.circle.fill",
                    destination: IncomeListView()
                        .environmentObject(incomeStore),
                    fullWidth: true
                )
            } else {
                HStack(spacing: 10) {
                    tile(
                        title: "Personal Income",
                        amount: incomeTotal(for: .personal),
                        tint: .appHouseholdText,
                        icon: IncomeType.personal.systemImage,
                        destination: IncomeListView(typeFilter: .personal)
                            .environmentObject(incomeStore)
                    )
                    tile(
                        title: "Business Income",
                        amount: incomeTotal(for: .business),
                        tint: .appBusinessText,
                        icon: IncomeType.business.systemImage,
                        destination: IncomeListView(typeFilter: .business)
                            .environmentObject(incomeStore)
                    )
                }
            }
        }
    }

    // MARK: - Expand / collapse

    private var detailsChevron: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(expanded ? "Hide Details" : "Show Details")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                Spacer()
            }
            .foregroundStyle(Color.appAccentText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded
            ? "Collapse Financial Overview details"
            : "Expand Financial Overview details")
    }

    // MARK: - Expanded details

    @ViewBuilder
    private var expandedDetails: some View {

        Divider()
            .padding(.vertical, 2)

        // ── Bill breakdown ──────────────────────────────────────
        subsectionHeader("Bills — This Month")

        HStack(spacing: 8) {
            statTile(label: "Paid",
                     value: currency.string(from: paidThisMonth as NSDecimalNumber) ?? "$0",
                     tint: .green)
            statTile(label: "Pending",
                     value: currency.string(from: pendingThisMonth as NSDecimalNumber) ?? "$0",
                     tint: Color.appAccentText)
            statTile(label: "Overdue",
                     value: currency.string(from: overdueThisMonth as NSDecimalNumber) ?? "$0",
                     tint: .red)
        }

        Text("\(billsThisMonthCount) bill\(billsThisMonthCount == 1 ? "" : "s") this month")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

        Divider()
            .padding(.vertical, 4)

        // ── Income breakdown ───────────────────────────────────
        subsectionHeader("Income — \(incomePeriod.title)")

        if combineIncome {
            HStack {
                Text("Combined Income")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currency.string(from: combinedIncomeTotal as NSDecimalNumber) ?? "$0")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
        } else {
            let bizP = percentage(of: incomeTotal(for: .business),
                                  in: combinedIncomeTotal) ?? 0
            let perP = combinedIncomeTotal > 0 ? 100 - bizP : 0
            HStack {
                Text("Personal").font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appHouseholdText)
                Spacer()
                Text("\(perP)%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                Text(currency.string(from: incomeTotal(for: .personal) as NSDecimalNumber) ?? "$0")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            HStack {
                Text("Business").font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appBusinessText)
                Spacer()
                Text("\(bizP)%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                Text(currency.string(from: incomeTotal(for: .business) as NSDecimalNumber) ?? "$0")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            Divider().padding(.vertical, 2)
            HStack {
                Text("Total Income").font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(currency.string(from: combinedIncomeTotal as NSDecimalNumber) ?? "$0")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
        }

        // Insight line.
        if let line = insightLine {
            Text(line)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appAccent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.appAccent.opacity(0.18), lineWidth: 1)
                )
                .padding(.top, 4)
        }

        Divider().padding(.vertical, 4)

        // ── Combine Income toggle (now lives inside details) ───
        Toggle(isOn: $combineIncome) {
            Label("Combine Income", systemImage: combineIncome
                  ? "rectangle.stack.fill"
                  : "rectangle.split.2x1")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Color.appAccent)
    }

    // MARK: - Tile builders

    /// Tappable totals tile used by the compact grid. Wraps a
    /// NavigationLink so the parent NavigationStack pushes the
    /// drill-in destination.
    private func tile<Destination: View>(
        title: String,
        amount: Decimal,
        tint: Color,
        icon: String,
        destination: Destination,
        fullWidth: Bool = false
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tint)
                        )
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(currency.string(from: amount as NSDecimalNumber) ?? "$0")
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .accessibilityHint("Open \(title.lowercased()) details")
    }

    private func statTile(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func subsectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Calculations

    private var incomeRange: ClosedRange<Date> {
        incomeStore.bounds(for: incomePeriod, weekStartDay: weekStartDay)
    }

    private func incomeTotal(for type: IncomeType) -> Decimal {
        incomeStore.total(in: incomeRange, type: type)
    }

    private var combinedIncomeTotal: Decimal {
        incomeTotal(for: .business) + incomeTotal(for: .personal)
    }

    private var billsThisMonth: [Bill] {
        store.bills.filter { $0.isDueThisMonth }
    }
    private var billsThisMonthCount: Int { billsThisMonth.count }
    private var paidThisMonth: Decimal {
        billsThisMonth.filter { $0.isPaid }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
    private var overdueThisMonth: Decimal {
        billsThisMonth.filter { $0.isOverdue }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
    private var pendingThisMonth: Decimal {
        billsThisMonth.filter { !$0.isPaid && !$0.isOverdue }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func percentage(of part: Decimal, in whole: Decimal) -> Int? {
        guard whole > 0 else { return nil }
        let p = NSDecimalNumber(decimal: part)
            .dividing(by: NSDecimalNumber(decimal: whole))
            .multiplying(by: 100)
        return Int(p.doubleValue.rounded())
    }

    private var insightLine: String? {
        let total = combinedIncomeTotal
        guard total > 0 else { return nil }
        if combineIncome {
            let amount = currency.string(from: total as NSDecimalNumber) ?? "$0"
            return "Your combined income this period is \(amount)."
        }
        let bizP = percentage(of: incomeTotal(for: .business), in: total) ?? 0
        let perP = 100 - bizP
        if incomeTotal(for: .business) >= incomeTotal(for: .personal) {
            return "Business income generated \(bizP)% of your earnings this period."
        } else {
            return "Personal income generated \(perP)% of your earnings this period."
        }
    }
}

#Preview {
    FinancialOverviewSection(
        combineIncome: .constant(false),
        incomePeriod: .last30Days,
        weekStartDay: .monday
    )
    .environmentObject(BillStore())
    .environmentObject(IncomeStore())
}
