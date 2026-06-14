//
//  ReportsView.swift
//  SacredBillTracker
//
//  Monthly totals and category breakdown with simple horizontal bars.
//

import SwiftUI

struct ReportsView: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var subs: SubscriptionManager
    @State private var displayedMonth: Date = Date()
    @State private var selectedType: BillType = .household
    @State private var showPaywall = false

    private let calendar = Calendar.current

    private var currency: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if subs.isPro || FreeTierLimits.allowReports {
                    VStack(alignment: .leading, spacing: 20) {
                        ProfileSwitcherBar()
                            .padding(.horizontal)
                        monthPicker
                        totalsRow
                        typeSelector
                        categoryBreakdown
                    }
                    .padding(.vertical)
                } else {
                    ProLockCard(
                        icon: "chart.pie.fill",
                        title: "Reports are a Pro feature",
                        message: "Unlock monthly totals, category breakdowns, and cash-flow insights for household and business.",
                        onUpgrade: { showPaywall = true }
                    )
                    .padding()
                }
            }
            .background(Theme.Color.background)
            .navigationTitle("Reports")
            .navigationDestination(for: Bill.self) { bill in
                BillDetailView(bill: bill)
            }
            .paywallSheet(isPresented: $showPaywall,
                          reason: "Reports are a Pro feature. Upgrade to see monthly breakdowns.")
        }
    }

    // MARK: - Month Picker

    private var monthPicker: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayedMonth.longMonthYear)
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Totals Row

    private var totalsRow: some View {
        HStack(spacing: 12) {
            totalCard(
                title: "Personal",
                total: totalForMonth(.household),
                unpaid: unpaidForMonth(.household),
                count: countForMonth(.household),
                tint: .appHousehold,
                icon: "house.fill"
            )
            totalCard(
                title: "Business",
                total: totalForMonth(.business),
                unpaid: unpaidForMonth(.business),
                count: countForMonth(.business),
                tint: .appBusiness,
                icon: "briefcase.fill"
            )
        }
        .padding(.horizontal)
    }

    private func totalCard(title: String, total: Decimal, unpaid: Decimal,
                           count: Int, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                .font(.title2.bold().monospacedDigit())
            Text("\(count) bill\(count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if unpaid > 0 {
                Text("Unpaid: \(currency.string(from: unpaid as NSDecimalNumber) ?? "$0")")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("All paid")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Type Selector

    private var typeSelector: some View {
        Picker("Type", selection: $selectedType) {
            ForEach(BillType.allCases) { t in
                Text(t.title).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdown: some View {
        let rows = store.categoryBreakdown(for: selectedType, in: displayedMonth)
        let maxValue = rows.map(\.total).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            Text("\(selectedType.title) by Category")
                .font(.headline)
                .padding(.horizontal)

            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "chart.pie",
                    title: "No data",
                    message: "No \(selectedType.title.lowercased()) bills for \(displayedMonth.longMonthYear)."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.category) { idx, row in
                        NavigationLink {
                            CategoryDetailView(
                                category: row.category,
                                month: displayedMonth,
                                typeFilter: selectedType
                            )
                            .environmentObject(store)
                        } label: {
                            categoryBar(
                                category: row.category,
                                value: row.total,
                                max: maxValue,
                                tint: selectedType.accentColor
                            )
                            .contentShape(Rectangle())
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Show all \(row.category.title.lowercased()) bills")
                        if idx < rows.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(8)
                .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    private func categoryBar(category: BillCategory, value: Decimal, max: Decimal, tint: Color) -> some View {
        let ratio: CGFloat = {
            let d = (value as NSDecimalNumber).doubleValue
            let m = (max   as NSDecimalNumber).doubleValue
            guard m > 0 else { return 0 }
            return CGFloat(d / m)
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(category.title, systemImage: category.systemImage)
                    .font(.subheadline)
                Spacer()
                Text(currency.string(from: value as NSDecimalNumber) ?? "$0")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Computation helpers

    private func totalForMonth(_ type: BillType) -> Decimal {
        store.bills(in: displayedMonth)
            .filter { $0.type == type }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func unpaidForMonth(_ type: BillType) -> Decimal {
        store.bills(in: displayedMonth)
            .filter { $0.type == type && !$0.isPaid }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func countForMonth(_ type: BillType) -> Int {
        store.bills(in: displayedMonth).filter { $0.type == type }.count
    }

    private func shiftMonth(by months: Int) {
        if let new = calendar.date(byAdding: .month, value: months, to: displayedMonth) {
            displayedMonth = new
        }
    }
}

#Preview {
    ReportsView()
        .environmentObject(BillStore())
        .environmentObject(ManagedProfileStore.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(SubscriptionManager())
}
