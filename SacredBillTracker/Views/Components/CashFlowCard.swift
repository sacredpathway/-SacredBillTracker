//
//  CashFlowCard.swift
//  SacredBillTracker
//
//  "Cash flow" summary surfaced on the Dashboard. Shows the core monthly
//  picture — total bills, paid, remaining, next 7 days — and what's left over.
//

import SwiftUI

struct CashFlowCard: View {
    let flow: BillStore.CashFlow

    private let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    private func fmt(_ value: Decimal) -> String {
        currency.string(from: value as NSDecimalNumber) ?? "$0"
    }

    /// 0...1 proportion paid this month.
    private var progress: Double {
        let due = (flow.dueThisMonth as NSDecimalNumber).doubleValue
        let paid = (flow.paidThisMonth as NSDecimalNumber).doubleValue
        guard due > 0 else { return 0 }
        return min(1, max(0, paid / due))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(Color.appAccent)
                Text("Cash flow")
                    .font(.headline)
                Spacer()
                Text("This month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appAccent.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [Color.appLime, Color.appAccent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
                HStack(spacing: 6) {
                    Text("\(Int(progress * 100))% covered")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.appAccent)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(flow.unpaidCount) unpaid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Grid of 4 metrics
            let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: cols, spacing: 10) {
                metric(label: "Total Bills", value: fmt(flow.dueThisMonth),     tint: .appAccent)
                metric(label: "Paid",      value: fmt(flow.paidThisMonth),      tint: .appLime)
                metric(label: "Remaining", value: fmt(flow.remainingThisMonth), tint: .appAmber)
                metric(label: "Next 7d",   value: fmt(flow.nextSevenDays),      tint: .appHousehold)
            }
        }
        .padding(16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    CashFlowCard(flow: .init(
        dueThisMonth: 4607.16,
        paidThisMonth: 30,
        remainingThisMonth: 4577.16,
        nextSevenDays: 2534.99,
        projectedLeftover: -4577.16,
        unpaidCount: 9
    ))
    .padding()
    .background(Color(.systemGroupedBackground))
}
