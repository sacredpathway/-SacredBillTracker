//
//  PrioritySection.swift
//  SacredBillTracker
//
//  "Pay this first" — the top bills needing attention right now.
//

import SwiftUI

struct PrioritySection: View {
    let bills: [Bill]
    let maxUnpaidAmount: Decimal
    /// v1.0.9 — Parent-provided tap handler. When supplied the row uses
    /// `Button { onSelect(bill) }` (so the parent can present an Edit
    /// sheet via `sheet(item:)` and avoid the legacy two-screen flow).
    /// When nil, falls back to the legacy `NavigationLink(value: bill)`
    /// so callers that haven't migrated still work.
    var onSelect: ((Bill) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.appAccentText)
                Text("Pay this first")
                    .font(.headline)
                Spacer()
                Text("Priority")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(Color.appAccentText)
                    .background(Color.appAccent.opacity(0.15), in: Capsule())
            }
            .padding(.horizontal)

            if bills.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal.fill",
                    title: "You're caught up",
                    message: "No bills urgently need attention."
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bills.enumerated()), id: \.element.id) { idx, bill in
                        Group {
                            if let onSelect {
                                Button {
                                    onSelect(bill)
                                } label: {
                                    PriorityRow(
                                        bill: bill,
                                        rank: idx + 1,
                                        isHighest: bill.amount >= maxUnpaidAmount
                                    )
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                            } else {
                                NavigationLink(value: bill) {
                                    PriorityRow(
                                        bill: bill,
                                        rank: idx + 1,
                                        isHighest: bill.amount >= maxUnpaidAmount
                                    )
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        if bill.id != bills.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }
}

private struct PriorityRow: View {
    let bill: Bill
    let rank: Int
    let isHighest: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                Text("\(rank)")
                    .font(.subheadline.bold())
                    .foregroundStyle(rankColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(dueCopy)
                        .font(.caption)
                        .foregroundStyle(dueColor)
                    if bill.autoPay {
                        Text("• Autopay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isHighest {
                        Text("• Highest amount")
                            .font(.caption)
                            .foregroundStyle(Color.appAmber)
                    }
                }
            }

            Spacer()

            Text(bill.formattedAmount)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(.primary)
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .appDangerText
        case 2: return Color.appAmber
        default: return Color.appAccent
        }
    }

    private var dueCopy: String {
        if bill.isOverdue {
            return "\(bill.daysOverdue) day\(bill.daysOverdue == 1 ? "" : "s") overdue"
        } else if bill.isDueToday {
            return "Due today"
        } else if bill.daysUntilDue == 1 {
            return "Due tomorrow"
        } else {
            return "Due in \(bill.daysUntilDue) days"
        }
    }

    private var dueColor: Color {
        if bill.isOverdue { return .appDangerText }
        if bill.daysUntilDue <= 3 { return Color.appAmber }
        return .secondary
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PrioritySection(
            bills: Array(SampleData.bills().prefix(3)),
            maxUnpaidAmount: 1850
        )
        .padding(.vertical)
        .background(Color(.systemGroupedBackground))
    }
}
#endif
