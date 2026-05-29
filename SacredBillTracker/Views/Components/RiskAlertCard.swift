//
//  RiskAlertCard.swift
//  SacredBillTracker
//
//  A polished, non-alarming warning panel that surfaces risk flags:
//  bills overdue > 3 days, high-dollar unpaid bills, or a cluster of
//  bills due within the next 7 days.
//

import SwiftUI

struct RiskAlertCard: View {
    let flags: BillStore.RiskFlags

    private let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    var body: some View {
        if flags.hasAny {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(Color.appAmber)
                    Text("Heads up")
                        .font(.headline)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !flags.veryOverdueBills.isEmpty {
                        alertRow(
                            icon: "exclamationmark.triangle.fill",
                            tint: .red,
                            title: "\(flags.veryOverdueBills.count) bill\(flags.veryOverdueBills.count == 1 ? "" : "s") more than 3 days overdue",
                            subtitle: topNames(flags.veryOverdueBills)
                        )
                    }
                    if !flags.highAmountUnpaid.isEmpty {
                        let total = flags.highAmountUnpaid.reduce(Decimal(0)) { $0 + $1.amount }
                        alertRow(
                            icon: "dollarsign.circle.fill",
                            tint: Color.appAmber,
                            title: "High-dollar unpaid: \(currency.string(from: total as NSDecimalNumber) ?? "")",
                            subtitle: topNames(flags.highAmountUnpaid)
                        )
                    }
                    if !flags.clusterUpcoming.isEmpty {
                        alertRow(
                            icon: "calendar.badge.clock",
                            tint: Color.appAccent,
                            title: "\(flags.clusterUpcoming.count) bills due in the next 7 days",
                            subtitle: topNames(flags.clusterUpcoming)
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.appAmber.opacity(0.35), lineWidth: 0.75)
                    )
            )
        }
    }

    private func topNames(_ bills: [Bill]) -> String {
        let shown = bills.prefix(3).map(\.name).joined(separator: " · ")
        let extra = bills.count - min(bills.count, 3)
        return extra > 0 ? "\(shown) + \(extra) more" : shown
    }

    private func alertRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }
}
