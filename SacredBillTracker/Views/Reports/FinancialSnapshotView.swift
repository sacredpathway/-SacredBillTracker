//
//  FinancialSnapshotView.swift
//  SacredBillTracker
//
//  Calm, deterministic monthly snapshot screen.
//
//    • Total bills this month
//    • Paid this month
//    • Unpaid this month
//    • Overdue (all-time, unpaid)
//    • Next 7 days (unpaid)
//    • Household vs Business split
//
//  No bank connection. No advice copy. No payment processing.
//  Numbers come from the same `BillStore` the dashboard reads, so
//  totals stay in lockstep with the rest of the app.
//

import SwiftUI

struct FinancialSnapshotView: View {

    @EnvironmentObject private var store: BillStore
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            SacredLeafScrollBackground(scrollOffset: scrollOffset)
                .background(Theme.Color.background.ignoresSafeArea())

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    totalsGrid
                    splitCard

                    Text("Sacred Bill Tracker shows what you've recorded. It doesn't connect to your bank and doesn't move money.")
                        .font(.caption2)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                .padding(16)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SacredScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("sbtSnap")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "sbtSnap")
            .onPreferenceChange(SacredScrollOffsetKey.self) { scrollOffset = $0 }
        }
        .navigationTitle("Snapshot")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Aggregations

    private var liveBills: [Bill] {
        store.bills.filter { $0.deletedAt == nil }
    }

    private var thisMonthBills: [Bill] {
        liveBills.filter { $0.isDueThisMonth }
    }

    private var totalThisMonth:  Decimal { sum(thisMonthBills) }
    private var paidThisMonth:   Decimal { sum(thisMonthBills.filter { $0.isPaid }) }
    private var unpaidThisMonth: Decimal { sum(thisMonthBills.filter { !$0.isPaid }) }

    private var overdueAmount: Decimal {
        sum(liveBills.filter { !$0.isPaid && $0.effectiveStatus == .overdue })
    }

    private var upcoming7Amount: Decimal {
        sum(liveBills.filter {
            !$0.isPaid && $0.daysUntilDue >= 0 && $0.daysUntilDue <= 7
        })
    }

    private var householdThisMonth: Decimal {
        sum(thisMonthBills.filter { $0.type == .household })
    }
    private var businessThisMonth: Decimal {
        sum(thisMonthBills.filter { $0.type == .business })
    }

    private func sum(_ bills: [Bill]) -> Decimal {
        bills.reduce(Decimal(0)) { $0 + $1.amount }
    }

    // MARK: - UI pieces

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Theme.Color.accentGreen)
                Text(monthTitle)
                    .font(Theme.Font.cardTitle)
                Spacer()
            }
            Text("Total bills this month")
                .font(.caption)
                .foregroundStyle(Theme.Color.secondaryText)
            Text(format(totalThisMonth))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.Color.card))
        .shadow(color: Theme.Color.cardShadow, radius: 10, x: 0, y: 4)
    }

    private var totalsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12),
                      GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            SnapshotTile(label: "Paid",
                         value: format(paidThisMonth),
                         tint: Theme.Color.success,
                         systemImage: "checkmark.seal.fill")
            SnapshotTile(label: "Unpaid",
                         value: format(unpaidThisMonth),
                         tint: Theme.Color.accentGreen,
                         systemImage: "tray.fill")
            SnapshotTile(label: "Overdue",
                         value: format(overdueAmount),
                         tint: overdueAmount > 0 ? Theme.Color.danger : Theme.Color.accentGreen,
                         systemImage: "exclamationmark.triangle.fill")
            SnapshotTile(label: "Next 7 days",
                         value: format(upcoming7Amount),
                         tint: Theme.Color.accentGold,
                         systemImage: "calendar")
        }
    }

    private var splitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(Theme.Color.accentGreen)
                Text("Personal vs Business")
                    .font(Theme.Font.cardTitle)
                Spacer()
            }

            SnapshotSplitBar(household: nsd(householdThisMonth),
                             business: nsd(businessThisMonth))

            HStack(spacing: 16) {
                SnapshotLegend(color: Color.appHousehold,
                               label: "Personal",
                               amount: format(householdThisMonth))
                SnapshotLegend(color: Color.appBusiness,
                               label: "Business",
                               amount: format(businessThisMonth))
                Spacer()
            }

            if householdThisMonth == 0 && businessThisMonth == 0 {
                Text("Add bills tagged Personal or Business to see your split.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.Color.card))
        .shadow(color: Theme.Color.cardShadow, radius: 10, x: 0, y: 4)
    }

    // MARK: - Helpers

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: Date())
    }

    private func format(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func nsd(_ d: Decimal) -> Double {
        (d as NSDecimalNumber).doubleValue
    }
}

// MARK: - Subviews

private struct SnapshotTile: View {
    let label: String
    let value: String
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.Color.card))
        .shadow(color: Theme.Color.cardShadow, radius: 10, x: 0, y: 4)
    }
}

private struct SnapshotSplitBar: View {
    let household: Double
    let business: Double

    var body: some View {
        GeometryReader { geo in
            let total = max(household + business, 0.0001)
            let hw = CGFloat(household / total) * geo.size.width
            HStack(spacing: 0) {
                Rectangle().fill(Color.appHousehold).frame(width: hw)
                Rectangle().fill(Color.appBusiness)
            }
            .clipShape(Capsule())
        }
        .frame(height: 14)
    }
}

private struct SnapshotLegend: View {
    let color: Color
    let label: String
    let amount: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption)
                Text(amount).font(.caption.weight(.semibold))
            }
        }
    }
}
